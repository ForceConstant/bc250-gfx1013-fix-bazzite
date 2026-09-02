# BC-250 GFX1013 Compute Queue — Bazzite Custom Images

Patched Bazzite images for the ASRock BC-250 that enable the GPU's dedicated async compute queues, delivering ~20-25% FPS in compute-heavy games.

## What This Does

The BC-250's GFX1013 GPU has dedicated compute queues (ACE hardware), but Linux hard-disables them due to known issues:

1. **Kernel:** Stock compute-queue lifecycle is broken — repeated teardown wedges the GPU
2. **Mesa/RADV:** The compute queue is hidden; plus a dispatch corruption bug (one-line fix)
3. **RDNA1 misclassification:** GFX1013 is detected as RDNA2 instead of RDNA1

This project patches both the kernel module (`amdgpu.ko`) and Mesa/RADV to fix all three, then packages them into Bazzite OCI images for easy rebase.

## Performance

Cyberpunk 2077 benchmark, 1440p Medium, native (no upscaling/frame gen), 40-CU unlock:

| CPU config | Without fix | With fix | Delta |
|---|---|---|---|
| 6 cores | 46.4 | 58.0 | **+25.0%** |
| 8 cores | 47.8 | 57.7 | **+20.8%** |

Vulkan CTS: 81,617 synchronization2 tests, 0 regressions, 7,384 compute-queue cases all pass.

## Status

- [x] Phase 0 — Validation: patches apply, builds compile
- [ ] Phase 1 — Repo scaffold + CI workflow
- [ ] Phase 2 — Image assembly, verification gate, `:testing` tag
- [ ] Phase 3 — On-box test (rebase, GravityMark, game soak)
- [ ] Phase 4 — Publish `:stable`, README with install instructions
- [ ] Phase 5 — Steady state (digest-watch cron, patch rebase process)

## Upstream

- **Patches:** [DryhoppedIPA/bc250-gfx1013-fix](https://github.com/DryhoppedIPA/bc250-gfx1013-fix) — cloned at build time from pinned commit (see `upstream-commit.txt`)
- **Kernel source:** [hhd-dev/kernel-bazzite](https://github.com/hhd-dev/kernel-bazzite) (Bazzite's ogc kernel)
- **Mesa disable MR:** [mesa!33116](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/33116) (what upstream did instead)

## How It Works

### Kernel Module (`amdgpu.ko`)

Built from Bazzite's kernel source with 2 patches applied:
1. **0001-gfx1013-pasid-tlb-invalidation.patch** — Fixes PASID TLB invalidation via MMIO instead of KIQ
2. **0002-gfx1013-compute-gfxoff-guard.patch** — Adds GFX1013 to the GFXOFF guard for compute idle

### Mesa/RADV

Built from Mesa 26.2.x with 1 patch applied:
1. **0001-gfx1013-compute-queue-fix.patch** — Enables compute queue exposure, fixes RDNA1 detection, adds async-compute threadgroup workaround

Installs to `/opt/bc250-gfx1013/` with `VK_DRIVER_FILES` env pin to avoid stock Mesa interference.

## Architecture

```
Workflow triggers (push/schedule/dispatch)
  │
  ├─ detect-changes   — check base image digest + upstream commit
  │
  ├─ build-kernel     — clone upstream fix repo → clone ogc kernel → apply patches → build amdgpu.ko
  │
  ├─ build-mesa       — clone upstream fix repo → download Mesa source → apply patches → build RADV
  │
  ├─ verify           — check artifacts exist
  │
  └─ save-digests     — cache for next run's change detection
```

## End-User Install (Phase 4+)

```bash
# One-time rebase
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/forceconstant/bazzite-bc250-patched-kde:stable
systemctl reboot

# Updates are automatic via rpm-ostree upgrade
```

### Flatpak Overrides

Flatpak apps use their own bundled Mesa. To point them at the patched driver:

```bash
sudo flatpak override --filesystem=/opt/bc250-gfx1013:ro \
  --env=VK_DRIVER_FILES=/opt/bc250-gfx1013/share/vulkan/icd.d/radeon_icd.x86_64.json \
  <app-id>
```

## Important Notes

- **Never run Mesa without the kernel patch** — it will hang
- **Suspend doesn't work** on BC-250, patched or not — keep suspend targets masked
- **CU unlock is separate** — we use `bc250-cu-live-manager` for the 38-CU unlock, orthogonal to this
- **Mesh/task shader patches exist but are DISABLED** — they can hang the GPU unrecoverably

## Upstream Patch Tracking

Patches are cloned at build time from [DryhoppedIPA/bc250-gfx1013-fix](https://github.com/DryhoppedIPA/bc250-gfx1013-fix) at a pinned commit stored in `upstream-commit.txt`.

**To update patches:**
1. Edit `upstream-commit.txt` with the new commit hash
2. Push to `main` — CI rebuilds automatically

**How it works:**
- `detect-changes` checks if `upstream-commit.txt` changed since last build
- Build jobs clone the upstream repo at the pinned commit
- No vendored patch files in this repo
