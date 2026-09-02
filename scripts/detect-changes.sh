#!/usr/bin/env bash
# detect-changes.sh — Check if base image or upstream patches changed
#
# Usage:
#   ./scripts/detect-changes.sh [--base-image IMAGE] [--upstream-commit-file FILE]
#
# Outputs (to GITHUB_OUTPUT if set, or stdout):
#   kernel_changed=true/false
#   mesa_changed=true/false
#   should_build=true/false

set -euo pipefail

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/ublue-os/bazzite:stable}"
UPSTREAM_COMMIT_FILE="upstream-commit.txt"
PREV_DIR=".base-digests"

usage() {
    echo "Usage: $0 [--base-image IMAGE] [--upstream-commit-file FILE]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-image) BASE_IMAGE="$2"; shift 2 ;;
        --upstream-commit-file) UPSTREAM_COMMIT_FILE="$2"; shift 2 ;;
        *) usage ;;
    esac
done

mkdir -p "$PREV_DIR"

should_build="false"
kernel_changed="false"
mesa_changed="false"

# 1. Check base image versions
echo "--- Base image info ---"
podman pull "$BASE_IMAGE" 2>/dev/null || docker pull "$BASE_IMAGE" 2>/dev/null

CURR_KERNEL=$(podman run --rm "$BASE_IMAGE" uname -r 2>/dev/null || docker run --rm "$BASE_IMAGE" uname -r)
CURR_MESA=$(podman run --rm "$BASE_IMAGE" \
    rpm -q mesa-vulkan-drivers --queryformat '%{VERSION}-%{RELEASE}' 2>/dev/null || \
    docker run --rm "$BASE_IMAGE" \
    rpm -q mesa-vulkan-drivers --queryformat '%{VERSION}-%{RELEASE}')

echo "kernel=$CURR_KERNEL"
echo "mesa=$CURR_MESA"

PREV_KERNEL=""
PREV_MESA=""
[[ -f "$PREV_DIR/previous-kernel.txt" ]] && PREV_KERNEL=$(cat "$PREV_DIR/previous-kernel.txt")
[[ -f "$PREV_DIR/previous-mesa.txt" ]] && PREV_MESA=$(cat "$PREV_DIR/previous-mesa.txt")

if [[ "$PREV_KERNEL" != "$CURR_KERNEL" || "$PREV_MESA" != "$CURR_MESA" ]]; then
    kernel_changed="true"
    mesa_changed="true"
    should_build="true"
    echo "Base image changed."
fi

# 2. Check upstream commit
echo "--- Upstream commit ---"
PINNED=$(head -5 "$UPSTREAM_COMMIT_FILE" | grep -v '^#' | awk '{print $1}')
echo "Pinned: $PINNED"

PREV_PINNED=""
[[ -f "$PREV_DIR/previous-upstream.txt" ]] && PREV_PINNED=$(cat "$PREV_DIR/previous-upstream.txt")

if [[ "$PINNED" != "$PREV_PINNED" ]]; then
    should_build="true"
    kernel_changed="true"
    mesa_changed="true"
    echo "Upstream commit changed (${PREV_PINNED:0:8} → ${PINNED:0:8})."
fi

# 3. Check upstream for newer commits (informational)
LATEST=$(git ls-remote https://github.com/DryhoppedIPA/bc250-gfx1013-fix.git main | awk '{print $1}')
if [[ "$PINNED" != "$LATEST" ]]; then
    echo "⚠️  Upstream has newer commits (pinned: ${PINNED:0:8}, latest: ${LATEST:0:8})"
fi

# 4. Write outputs
echo ""
echo "--- Result ---"
echo "kernel_changed=$kernel_changed"
echo "mesa_changed=$mesa_changed"
echo "should_build=$should_build"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "kernel_changed=$kernel_changed" >> "$GITHUB_OUTPUT"
    echo "mesa_changed=$mesa_changed" >> "$GITHUB_OUTPUT"
    echo "should_build=$should_build" >> "$GITHUB_OUTPUT"
fi
