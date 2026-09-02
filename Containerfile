# BC-250 GFX1013 patched Bazzite image — Mesa only (Phase 2)
#
# Takes the compiled patched RADV artifact from the build-mesa CI job
# and layers it onto stock Bazzite stable. The image build itself is
# just COPY operations — the 30-45 min Mesa compile happens once in
# the build-mesa job and is cached there.
#
# Base image is defaulted but overridden by the workflow build-arg so
# it always matches what detect-changes resolved.

FROM ghcr.io/ublue-os/bazzite:stable

# Patched RADV install tree (compiled in build-mesa job)
COPY artifacts/opt/bc250-gfx1013 /opt/bc250-gfx1013

# VK_DRIVER_FILES pin: force the Vulkan loader to use our patched driver.
# Without this, apps may silently take the stock /usr Mesa.
COPY system/usr/lib/environment.d/10-bc250-mesa.conf /usr/lib/environment.d/10-bc250-mesa.conf