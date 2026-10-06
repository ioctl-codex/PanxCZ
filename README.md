# PanxCZ Kernel — Infinix Note 30 (X6833B)

Custom GKI kernel for the **Infinix Note 30 (X6833B)** — MediaTek **Helio G99 (MT6789)** —
running **GKI 5.10 / android12-5.10 / KMI generation 9** (Android 17 + Infinity X ROM).

> **Credit:** the real kernel work belongs to the upstream projects below. PanxCZ is a
> **rebrand + integration + tuning layer only**, not original work.

## Base & components

| Layer | Project | Where |
|---|---|---|
| Kernel base | **MillenniumOSS Chihiro** (`android_kernel_common_android12-5.10`, branch `chihiro-lnx-stable`, 5.10.264) | https://github.com/MillenniumOSS/android_kernel_common_android12-5.10 |
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
# as root, Ubuntu 22.04
VARIANT=A-full-allin \
BASE_BRANCH=chihiro-rebase \
BBRV3=yes \
bash scripts/build-panxcz.sh
```

Outputs land in `/opt/panxcz/out-artifacts/`:

```
Image                              # raw kernel image
PanxCZ-<ver>-AnyKernel3.zip        # flashable via AnyKernel3
summary.txt
```

### Env knobs

`KERNEL_NAME`, `KERNEL_RELEASE`, `VARIANT` (`A-full-allin` | `B-susfs-hiding` |
`C-charging-gaming`), `LTO_MODE`, `BASE_REPO`, `BASE_BRANCH`, `BBRV3`
(`auto` | `yes` | `no`), `SUSFS_BRANCH`, `BAKASU_REF`, `WORKDIR`, `BUILD_NUM`.

## Build history

| # | Base | Result |
|---|---|---|
| v1 | Aetherium `aetherium` (5.10.269) | ✅ Image 33 MB — `5.10.269-PanxCZ-1.0.202610060424` |
| v2 | Millennium `chihiro-rebase` (5.10.257) + BakaSU + SUSFS | ✅ Image 37 MB — `PanxCZ-2.0.202610060510` |
| v3 | same as v2, BBRv3 auto-skipped | ❌ cherry-pick conflicted, rolled back |
| v4 | `chihiro-rebase` + BBRv3 patch | ❌ `tp->plb_rehash` missing — patch wrongly replaced `include/linux/tcp.h` |
| v5 | `chihiro-lnx-stable` (5.10.264) + BBRv3 + BakaSU + SUSFS | 🔄 building |

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
  ROM builds. The v5 base refresh (5.10.264) narrows the gap to the ROM's 5.10.269.
  Verifying on-device (both ROM builds) is the only way to actually prove it.

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
