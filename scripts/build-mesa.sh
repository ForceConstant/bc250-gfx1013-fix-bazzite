#!/usr/bin/env bash
# build-mesa.sh — Apply GFX1013 patch and build patched RADV
#
# Usage:
#   ./scripts/build-mesa.sh --mesa-src <dir> --patches <dir> --output <dir>
#
# Requirements:
#   - meson, ninja, gcc/g++, python3
#   - vulkan headers, drm-devel, llvm-devel (for full build; minimal with -Dllvm=disabled)
#
# Output:
#   <output>/opt/bc250-gfx1013/ — patched RADV install tree
#   <output>/radeon_icd.x86_64.json — Vulkan ICD manifest

set -euo pipefail

MESA_SRC=""
PATCHES_DIR=""
OUTPUT_DIR=""

usage() {
    echo "Usage: $0 --mesa-src <dir> --patches <dir> --output <dir>"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mesa-src) MESA_SRC="$2"; shift 2 ;;
        --patches)  PATCHES_DIR="$2"; shift 2 ;;
        --output)   OUTPUT_DIR="$2"; shift 2 ;;
        *)          usage ;;
    esac
done

[[ -z "$MESA_SRC" || -z "$PATCHES_DIR" || -z "$OUTPUT_DIR" ]] && usage

echo "=== BC-250 GFX1013 Mesa/RADV Build ==="
echo "Mesa source:  $MESA_SRC"
echo "Patches dir:  $PATCHES_DIR"
echo "Output dir:   $OUTPUT_DIR"

cd "$MESA_SRC"

# Determine Mesa version
MESA_VERSION=$(meson --version 2>/dev/null || echo "unknown")
echo "Mesa version: $MESA_VERSION"

# Apply patches from series file
echo ""
echo "--- Applying Mesa patches ---"
SERIES="$PATCHES_DIR/series"
if [[ ! -f "$SERIES" ]]; then
    echo "ERROR: series file not found at $SERIES"
    exit 1
fi

while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    
    patch_file="$PATCHES_DIR/$(echo "$line" | xargs)"
    echo "Applying: $(basename "$patch_file")"
    
    if ! patch -p1 --forward --dry-run < "$patch_file" > /dev/null 2>&1; then
        echo "WARNING: Patch $(basename "$patch_file") does not apply cleanly."
        echo "Attempting with --force..."
        patch -p1 --force < "$patch_file" || {
            echo ""
            echo "ERROR: Patch $(basename "$patch_file") failed."
            echo "Mesa version may have changed — rebase the patch."
            exit 1
        }
    else
        patch -p1 < "$patch_file"
    fi
done < "$SERIES"
echo "All patches applied successfully."

# Build RADV only (minimal build — no Gallium, no GLX, no LLVM)
echo ""
echo "--- Configuring Mesa build (RADV only) ---"
DESTDIR="$OUTPUT_DIR"
PREFIX="/opt/bc250-gfx1013"

meson setup build \
    -Dvulkan-drivers=amd \
    -Dgallium-drivers= \
    -Dglx=disabled \
    -Dllvm=disabled \
    -Dbuildtype=release \
    -Dprefix="$PREFIX" \
    -Dwrapper=false

echo ""
echo "--- Building RADV ---"
ninja -C build

echo ""
echo "--- Installing to DESTDIR ---"
DESTDIR="$DESTDIR" ninja -C build install

# Copy the Vulkan ICD manifest to a known location
ICD_SRC="$DESTDIR/$PREFIX/share/vulkan/icd.d/radeon_icd.x86_64.json"
ICD_DST="$OUTPUT_DIR/radeon_icd.x86_64.json"
if [[ -f "$ICD_SRC" ]]; then
    cp "$ICD_SRC" "$ICD_DST"
    echo "ICD manifest: $ICD_DST"
fi

echo ""
echo "=== Build complete ==="
echo "Install tree: $DESTDIR/$PREFIX/"
du -sh "$DESTDIR/$PREFIX/" 2>/dev/null || true
