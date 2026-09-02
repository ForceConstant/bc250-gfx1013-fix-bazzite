#!/usr/bin/env bash
# build-kernel.sh — Apply GFX1013 patches and build patched amdgpu.ko
#
# Usage:
#   ./scripts/build-kernel.sh --kernel-src <dir> --patches <dir> --output <dir>
#
# Requirements:
#   - kernel-devel (matching kernel version) installed
#   - gcc, make, flex, bison, elfutils-libelf-devel
#
# Output:
#   <output>/amdgpu.ko — patched kernel module

set -euo pipefail

KERNEL_SRC=""
PATCHES_DIR=""
OUTPUT_DIR=""

usage() {
    echo "Usage: $0 --kernel-src <dir> --patches <dir> --output <dir>"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-src) KERNEL_SRC="$2"; shift 2 ;;
        --patches)    PATCHES_DIR="$2"; shift 2 ;;
        --output)     OUTPUT_DIR="$2"; shift 2 ;;
        *)            usage ;;
    esac
done

[[ -z "$KERNEL_SRC" || -z "$PATCHES_DIR" || -z "$OUTPUT_DIR" ]] && usage

echo "=== BC-250 GFX1013 Kernel Module Build ==="
echo "Kernel source: $KERNEL_SRC"
echo "Patches dir:   $PATCHES_DIR"
echo "Output dir:    $OUTPUT_DIR"

# Detect kernel version from source
cd "$KERNEL_SRC"
KVER=$(make kernelrelease 2>/dev/null || head -1 Makefile | awk -F= '{print $2}' | tr -d ' ')
echo "Kernel version: $KVER"

# Check kernel-devel is available
KDEVEL="/lib/modules/${KVER}/build"
if [[ ! -d "$KDEVEL" ]]; then
    echo "ERROR: kernel-devel not found at $KDEVEL"
    echo "Install kernel-devel for version $KVER first."
    exit 1
fi

echo "Kernel build dir: $KDEVEL"

# Apply patches
echo ""
echo "--- Applying kernel patches ---"
for p in "$PATCHES_DIR"/*.patch; do
    echo "Applying: $(basename "$p")"
    if ! patch -p1 --forward --dry-run < "$p" > /dev/null 2>&1; then
        echo "WARNING: Patch $(basename "$p") does not apply cleanly to this kernel source."
        echo "Attempting with --force (may produce rejects)..."
        patch -p1 --force < "$p" || {
            echo ""
            echo "ERROR: Patch $(basename "$p") failed. Check rejects in $KERNEL_SRC."
            echo "The ogc kernel may differ from the upstream Fedora vanilla source."
            exit 1
        }
    else
        patch -p1 < "$p"
    fi
done
echo "All patches applied successfully."

# Build only the amdgpu module
echo ""
echo "--- Building amdgpu.ko ---"
AMDGPU_DIR="$KERNEL_SRC/drivers/gpu/drm/amd/amdgpu"
if [[ ! -d "$AMDGPU_DIR" ]]; then
    echo "ERROR: amdgpu source dir not found at $AMDGPU_DIR"
    exit 1
fi

make -C "$KDEVEL" M="$AMDGPU_DIR" -j"$(nproc)" modules

# Copy output
mkdir -p "$OUTPUT_DIR"
cp "$AMDGPU_DIR/amdgpu.ko" "$OUTPUT_DIR/"
echo ""
echo "=== Build complete ==="
echo "Output: $OUTPUT_DIR/amdgpu.ko"
ls -lh "$OUTPUT_DIR/amdgpu.ko"
