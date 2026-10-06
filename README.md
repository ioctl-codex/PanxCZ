# PanxCZ Kernel — Infinix Note 30 (X6833B)

Custom GKI kernel for the **Infinix Note 30 (X6833B)** — MediaTek **Helio G99 (MT6789)** —
running **GKI 5.10 / android12-5.10 / KMI generation 9** (Android 17 + Infinity X ROM).

> **Credit:** the real kernel work belongs to the upstream projects below. PanxCZ is a
> **rebrand + integration + tuning layer only**, not original work.

## Base & components

| Layer | Project | Where |
|---|---|---|
| Kernel base | **MillenniumOSS Chihiro** (`android_kernel_common_android12-5.10`, branch `chihiro-lnx-stable`, 5.10.264) | https://github.com/MillenniumOSS/android_kernel_common_android12-5.10 |
| Base refresh | AOSP `android12-5.10-lts` (5.10.269) merged into Chihiro → branch `panxcz-base-5.10.269`, recreated on demand by `scripts/make-base-269.sh` | https://android.googlesource.com/kernel/common |
| Perf source (ported) | **Aetherium** (`kaminarich/GKI-Kernel`, branch `aetherium`) — BBRv3 | https://github.com/kaminarich/GKI-Kernel |
| Root | **BakaSU** (ex-ReSukiSU) | https://github.com/Baka-SU/BakaSU |
| Hiding | **SUSFS** (gki-android12-5.10) | https://gitlab.com/simonpunk/susfs4ksu |
| Flashable zip | **AnyKernel3** | https://github.com/osm0sis/AnyKernel3 |
| Tooling | AOSP `kernel/manifest` `common-android12-5.10` | https://android.googlesource.com/kernel/manifest |

Priority order: 1) SUSFS hiding, 2) max charging, 3) gaming smoothness,
4) stability on Android 17 + Infinity X, 5) Helio G99 tuning.

## Build

Build on a Linux host (a VPS is used — the source tree is ~1.2 GB and a full
`LTO=thin` build wants ≥ 6 cores / 16 GB RAM + swap).

```bash
# as root, Ubuntu 22.04; the script installs its own deps + swap
VARIANT=A-full-allin BBRV3=yes LTS_MERGE=yes bash scripts/build-panxcz.sh
```

The script is fully self-contained and reproducible: it takes the AOSP manifest
(`build/` + prebuilts), replaces `common/` with the Chihiro base, rebuilds the
**5.10.269** base itself (`LTS_MERGE=yes`, the default), ports BBRv3, clones
BakaSU, applies the SUSFS kernel-side patch, rebrands, injects the defconfig and
builds `LTO=thin`. Nothing has to be prepared by hand, which is why the same
script backs the GitHub Actions workflow.

Outputs land in `/opt/panxcz/out-artifacts/`:

```
Image                              # raw kernel image
PanxCZ-<ver>-AnyKernel3.zip        # flashable via AnyKernel3
summary.txt
```

### Env knobs

`KERNEL_NAME`, `KERNEL_RELEASE`, `VARIANT` (`A-full-allin` | `B-susfs-hiding` |
`C-charging-gaming`), `LTO_MODE`, `BASE_REPO`, `BASE_BRANCH`, `LTS_MERGE`,
`LTS_BASE_BRANCH`, `BBRV3` (`auto` | `yes` | `no`), `SUSFS_BRANCH`, `BAKASU_REF`,
`WORKDIR`, `BUILD_NUM`.

## Build history

| # | Base | Result |
|---|---|---|
| v1 | Aetherium `aetherium` (5.10.269) | ✅ Image 33 MB — `5.10.269-PanxCZ-1.0.202610060424` |
| v2 | Millennium `chihiro-rebase` (5.10.257) + BakaSU + SUSFS | ✅ Image 37 MB — `PanxCZ-2.0.202610060510` |
| v3 | same as v2, BBRv3 auto-skipped | ❌ cherry-pick conflicted, rolled back |
| v4 | `chihiro-rebase` + BBRv3 patch | ❌ `tp->plb_rehash` missing — patch wrongly replaced `include/linux/tcp.h` |
| v5 | `chihiro-lnx-stable` (5.10.264) + BBRv3 + BakaSU + SUSFS | ❌ built, but **SUSFS was absent** (`System.map` had 0 `susfs` symbols) |
| v9 | `panxcz-base-5.10.269` + BBRv3 + SUSFS KernelSU patch | ❌ `sucompat.c: assigning to 'int' from incompatible type 'void'` |
| **v10** | `panxcz-base-5.10.269` + BBRv3 + **BakaSU `main`** + SUSFS | ✅ **`5.10.269-PanxCZ-4.0.202610060802`** — Image 37 MB, AnyKernel3 19 MB, 27 `bbr3` + **89 `susfs`** symbols |

### Base selection

`chihiro-rebase` (5.10.257) was replaced by **`chihiro-lnx-stable` (5.10.264, 2026-08-09)** to
move toward the level the ROM runs (5.10.269). It is a drop-in: same
`BRANCH=android12-5.10`, same **`KMI_GENERATION=9`**, same `clang-r416183b`, and all six
files the BBRv3 patch touches are byte-identical between the two branches, so the patch
applies cleanly to both.

MillenniumOSS branch survey (LTS level / heads):

| branch | LTS | date |
|---|---|---|
| `millennium-base` | 5.10.264 | 2026-08-14 |
| `millennium-base-linuxstable` | 5.10.264 | 2026-08-09 |
| **`chihiro-lnx-stable`** | **5.10.264** | 2026-08-09 |
| `chihiro-main` | 5.10.260 | 2026-08-09 |
| `chihiro-rebase` | 5.10.257 | 2026-06-18 |
| `kei-5.10` | 5.10.257 | 2026-06-14 |
| `chihiro-dev` | 5.10.250 | 2026-02-14 |

All of the above ship `CONFIG_CPU_FREQ_GOV_REFLEX`, `CONFIG_MQ_IOSCHED_ADIOS` and DAMON.
**No MillenniumOSS branch is at 5.10.269** — the device's `5.10.269-KagamiChihiro` comes
from elsewhere.

## SUSFS integration (this is where v5/v9 went wrong)

BakaSU ships SUSFS as a **first-class hook method**. `kernel/Kconfig` already
offers `KSU_TRACEPOINT_HOOK` (default) / `KSU_MANUAL_HOOK` / **`KSU_SUSFS`** as a
`choice`, `kernel/core/init.c` already calls `susfs_init()` under
`#ifdef CONFIG_KSU_SUSFS`, and `kernel/Kbuild` selects
`tools/inline_hook_check.mk` + `tools/susfs_compat.mk` and then
**hard-errors** unless `fs/susfs.c` exists:

```
-- You have not integrated susfs in your kernel yet.
*** You should integrate susfs in your kernel.
```

So the only kernel-side work is simonpunk's patch. What must **not** be done is
applying its companion `kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch`:
that patch is generated as *"current KernelSU → SUSFS tree built on an older
KernelSU"*, so alongside the SUSFS additions it also **reverts** the current hook
infrastructure (`ksu_late_loaded`, the x86 indirect-safe guard, `hook/lsm_hook.o`,
`hook/syscall_hook_manager.o`, `infra/symbol_resolver.o`, `hook/arm64/*`) and
rewrites `init.c` back to the pre-hook-manager design. It touches 26 files
(‑1012 lines, including ‑425 lines of `selinux_hide.c`) and fails to compile.

That single mistake explains two failed builds:

* **v5** never enabled `CONFIG_KSU_SUSFS` at all (no Kconfig symbol → every
  `CONFIG_KSU_SUSFS_*` defconfig line silently dropped → 0 `susfs` symbols);
* **v9** applied the KernelSU patch and got
  `drivers/kernelsu/feature/sucompat.c: assigning to 'int' from incompatible type 'void'`.

What the build does now:

1. **Force a real BakaSU checkout.** `git clean -fdx` never removes a directory
   containing its own `.git`, so a `KernelSU/` left over from an earlier run
   survives — and BakaSU's `setup.sh` then only does `git pull` on it. Up to v9
   that meant we were silently building **SukiSU-Ultra**, not BakaSU. The script
   now checks `remote get-url origin` and re-clones unless it is `Baka-SU/BakaSU`.
2. Apply only the kernel-side patch (`fs/`, `include/linux/`, and the
   `ksu_handle_*` hook points) and fail on any reject.
3. Assert **before** the 30-minute compile that all seven hooks BakaSU's own
   `inline_hook_check.mk` looks for are present — `ksu_handle_setresuid`
   (`kernel/sys.c`), `ksu_handle_execveat` (`fs/exec.c`), `ksu_handle_faccessat`
   (`fs/open.c`), `ksu_handle_sys_read` (`fs/read_write.c`), `ksu_handle_stat`
   (`fs/stat.c`), `ksu_handle_sys_reboot` (`kernel/reboot.c`),
   `ksu_handle_input_handle_event` (`drivers/input/input.c`).
4. Select the hook method in the defconfig. Because it is a `choice` whose
   default is the tracepoint hook:

   ```
   # CONFIG_KSU_TRACEPOINT_HOOK is not set
   # CONFIG_KSU_MANUAL_HOOK is not set
   CONFIG_KSU_SUSFS=y
   ```
5. Refuse to publish if `System.map` has no `bbr3`/`susfs` symbols or the
   generated `.config` lost `CONFIG_KSU` / `CONFIG_KSU_SUSFS*`.

## Known integration issues / notes

* **BBRv3 — RESOLVED.** Aetherium's BBRv3 is a single **kitchen-sink commit**: it
  also bundles an entire SUSFS implementation (`fs/*`, `security/selinux/*`,
  `kernel/*`, `mm/*`), which would collide with the official SUSFS patch. It also
  conflicts in 11 files on `chihiro-rebase` because Chihiro already carries the
  **newer mainline-style TCP PLB** (`net->ipv4.sysctl_tcp_plb_*`), while
  Aetherium's BBRv3 bundles the **older PLB** (`tcp_get_plb_ctx()`).

  Fix shipped as a pre-resolved, BBRv3-only patch — `patches/bbrv3-chihiro.patch`
  (8 files, no `fs/`, no `security/`):
  1. keep Chihiro's newer PLB and its `tcp_rate`/`tcp_input` code untouched;
  2. add `net/ipv4/tcp_bbr3.c` with the PLB enable check rewritten to
     `net->ipv4.sysctl_tcp_plb_enabled`;
  3. add `struct bbr3` and take `GSO_LEGACY_MAX_SIZE` from `netdevice.h`;
  4. wire BBRv3's `skb_marked_lost` through Chihiro's existing
     `ca_ops->skb_marked_lost` hook;
  5. map BBRv3's `min_tso_segs(sk)` onto Chihiro's older
     `ca_ops->tso_segs(sk, mss_now)` via a small `bbr3_tso_segs_hook()`.

  Verified: `net/ipv4/tcp_bbr3.o` compiles clean on `chihiro-rebase`, and the
  patch applies cleanly to a pristine `chihiro-rebase` checkout.
* **Charging:** there is no upstream "charging control" patch for MT6789. Max-watt
  charging is a **sysfs/userspace** matter (`charger/*`, `mtk-master-charger/*`),
  not a GKI kernel patch. A separate control script is the right vehicle.
* **BakaSU** must live in a real git checkout (`KernelSU/.git`) — `kernel/Kbuild`
  hard-errors otherwise. `fix-bakasu-version.sh` asserts this and injects a
  `KSU_VERSION` fallback so `supercalls.c` cannot fail with `expected expression`.
* **QPR2 / QPR3 — findings.** There is **no** `android12-5.10-qpr2` / `-qpr3` branch in
  `kernel/common`; every QPR ref is Pixel-only (`android-gs-*`). For a frozen GKI 5.10
  kernel, QPR compatibility is a *KMI contract*, not a branch:
  * the base already declares **`KMI_GENERATION=9`** (same as v1/v2/v5), so the module
    interface is unchanged across QPR releases;
  * the tree already carries the per-release symbol lists under `android/`
    (`abi_gki_aarch64`, `_core`, `_generic`, **`_mtk`** — the MediaTek one that matters
    for MT6789 — plus `_qcom`/`_exynos`/`_xiaomi`/…), and `gki_aarch64_modules`;
  * there is no separate per-QPR ABI file to add for 5.10.

  Practical consequence: one Image built this way is meant to boot both QPR2 and QPR3
  ROM builds. Since v10 the base is merged all the way to **5.10.269**, i.e. exactly
  the level the ROM itself runs, so there is no LTS gap left. Verifying on-device
  (both ROM builds) is still the only way to actually prove it.

## Packaging (AnyKernel3)

The zip is assembled by `scripts/make-anykernel3.sh`, which can be re-run on its
own against an existing `Image` — no kernel rebuild needed:

```bash
AK_IMAGE=/opt/panxcz/out-artifacts/Image AK_KVER=5.10.269 \
AK_OUTDIR=/opt/panxcz/out-artifacts bash scripts/make-anykernel3.sh
```

Artifact name follows the Aetherium convention:

```
<Name><release>-<kernel>-<flavor>-<root>-<hiding>-<perf>-<date>-<n>.zip
PanxCZ4.0-5.10-269-full-allin-BakaSU-SuSFS-BBRv3-20261006-1.zip
```

Two upstream-AnyKernel3 traps the script exists to avoid, both of which produce
a zip that cannot be flashed at all:

1. **The zip must have `META-INF/`, `anykernel.sh`, `tools/` and `Image` at the
   zip root.** Zipping the checkout directory nests them under `anykernel/`, and
the recovery then cannot find `META-INF/com/google/android/update-binary`, so
the install aborts before it starts. (v10 shipped exactly like this — the first
zip had to be rebuilt and replaced.)
2. **`anykernel.sh` must be rewritten for the device.** Upstream's copy still
   targets maguro/toro/tuna (Galaxy Nexus) with
`BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot`. The X6833B is GKI
with A/B slots, so it needs `BLOCK=boot` + `IS_SLOT_DEVICE=1` for `ak3-core.sh`
to resolve `/dev/block/by-name/boot$SLOT`. The kernel goes in `boot`; the generic
ramdisk lives in `init_boot`, which is left alone.

Both `Image` and `Image.gz` are shipped — this device's boot partition holds a
gzip-compressed kernel and magiskboot picks whichever it finds.

## Where the builds live

* Build system + CI: **https://github.com/ioctl-codex/PanxCZ**
  (payload only — scripts, patches, workflow; the kernel source is fetched by the
  script). Pushing to `main` runs the **PanxCZ Kernel Build** workflow, which
  reproduces a complete build on a stock `ubuntu-22.04` runner.
* Verified release: **https://github.com/ioctl-codex/PanxCZ/releases/tag/panxcz-4.0-v10**
  (`Image`, `PanxCZ-4.0.202610060802-AnyKernel3.zip`, `System.map`, `config.txt`, `summary.txt`).
* Kernel-source fork: **https://github.com/ioctl-codex/GKI-Kernel** (branch `panxcz`).

## Backup layout (GitLab)

```
panxcz-group/panxcz-backup/            <- the backup folder
├── kernel-src                         artifacts/patches/scripts/docs (branch: main)
└── build-artifacts                    Images / AnyKernel3 zips (package registry)
```

* `kernel-src` → https://gitlab.com/panxcz-group/panxcz-backup/kernel-src
* `build-artifacts` → https://gitlab.com/panxcz-group/panxcz-backup/build-artifacts/-/packages
* Full-tree snapshot (v2, `tar.zst`, ~194 MB) lives in the registry under
  `panxcz-kernel/*-snapshot/`.

Measured from the build VPS: the Image (37 MB) uploads in ~2.5 s and the 194 MB
source snapshot in ~9 s (~175 Mbit/s).

Backup is pushed **from the build VPS directly to GitLab** (never relayed through
a workstation), artifacts go to the generic package registry rather than git, and
each repo gets one squashed commit — pushing full Android history is 10x slower
for no benefit.
