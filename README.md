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
| **v10** | `panxcz-base-5.10.269` + BBRv3 + **BakaSU `main`** + SUSFS | ⚠️ **`5.10.269-PanxCZ-4.0.202610060802`** built (27 `bbr3` + **89 `susfs`** symbols) but **bootloops on device** — BBRv3 was the default cc |
| **v11** | v10 with BBRv3 **no longer the default cc** (`westwood`, as the stock base) and `HZ` back to 250 | ❌ also **bootloops** — so the default-cc/HZ theory was *not* the (only) cause |
| v12 | `chihiro-lnx-stable` (legacy repo) with `LTS_MERGE=no` | ⛔ aborted — superseded by the repo discovery below |
| **v13** | **`millennium/chihiro-main` @ `2a6271bf1f5b` (5.10.269)** + BakaSU + SUSFS, `BBRV3=no` | ✅ `5.10.269-PanxCZ-4.0.202610070010`, 89 `susfs` symbols; config **matches the known-good device kernel** (see below) — but `out/` was reused, so it is not trustworthy |
| **v14** | v13 with `CLEAN_OUT=yes` (out/ wiped) | ✅ `5.10.269-PanxCZ-4.0.202610070028`, Image 38,651,708 B md5 `45f98e8dbe04a8631a3092609c7dcebd`, 2859/2859 objects rebuilt from scratch, **zero unexpected config drift** — candidate to flash |

#### v14 booted *recovery* — Android is what fails

v14 was flashed to `boot_b` and the phone then sat in recovery, and that turned
out to be the most useful thing all session: **recovery runs the v14 kernel.**

```
$ adb shell uname -r
5.10.269-PanxCZ-4.0.202610070028
$ adb shell 'wc -l < /proc/modules'      # 201 vendor modules loaded
$ adb shell dmesg | tail                 # rt9471 charger, mt635x-auxadc, mtk_crtc, cmdq all live
$ adb shell id                           # uid=0 — recovery adbd is root
```

So the flash path, the boot-image repack, the AVB relocation, the kernel binary
and the vendor modules are **all fine**. What fails is Android specifically, and
`/proc/bootconfig` says `androidboot.bootreason = "kernel_panic"`.

Both crash stores were checked and neither holds a log from v14:

* `/sys/fs/pstore/console-ramoops-0` (256 KB, `ramoops.console_size=0x40000` from
  the cmdline) still contains the *old* `5.10.260-KagamiChihiro-MillenniumTeam+`
  bbr3 crash. A console record is only written from a `kmsg_dump` (panic/oops),
  so an untouched record means v14 did **not** panic with a dump.
* `/dev/block/by-name/expdb` (128 MB — MTK's AEE exception dumper) contains only
  that same old 5.10.260 log: `bbr3` x27, `KagamiChihiro` x23, `PanxCZ` x0.

=> it is a **hang + watchdog reset**, not a panic. (For the record, that same
old log is also positive evidence: that 5.10.260 kernel — a *different* build —
drove `system_server` and a camera EEPROM probe before dying in `bbr3_main` at
48 s, i.e. the chihiro lineage does fully boot Android here.)

Two theories were checked and **dropped**:

* *module vermagic / uname-derived module path* — `/lib/modules` is a **flat**
directory (no `uname -r` subdir), and 201 modules load, so `uname -r` is
irrelevant here.
* *symbol-version mismatch* — our kernel logs 3653 `disagrees about version of
symbol ..., but ignore...` lines, which looked damning. But the working
5.10.260 log only covers t=22→48 s, so it never covers module load at t≈0.65 s;
the absence there proves nothing. MTK patches the check to warn-and-continue by
design, so this is not evidence of a fault.

#### ReSukiSU *is* BakaSU

Worth stating plainly because it invalidates a whole class of fix: `ReSukiSU/ReSukiSU`
**redirects to `Baka-SU/BakaSU`** — ReSukiSU was renamed, and the project still
ships its manager as `ReSukiSU_v4.2.0-rc3_*.apk`. "Switch to ReSukiSU" therefore
rebuilds the same root solution. The real delta against Aetherium (which boots
here) is only the *revision*: our kernel reports manager version code **35216**
while the newest published APK is **35171**.

Also checked: Aetherium's tree does **not** vendor KernelSU/SUSFS (`fs/susfs.c`
and `drivers/kernelsu` are both absent on `kaminarich/GKI-Kernel@aetherium`), so
they integrate it the same way we do. Their tree *does* add options ours cannot
have, notably `CONFIG_CFI_FORCE_SKIP_CHECK=y` — that symbol exists only in their
tree, so it is a patch there, not a knob we can flip.

#### Bisecting: `ROOT_KSU` / `SUSFS`

A hang that spares recovery but breaks Android points at the `execveat` /
path / stat hooks, which Android hammers constantly and recovery barely touches.
Builds are only ~10 min, so `scripts/build-panxcz.sh` now takes `ROOT_KSU=` and
`SUSFS=` knobs to split that in one build each:

| build | `ROOT_KSU` | `SUSFS` | Image size | identity | purpose |
|---|---|---|---|---|---|
| v15 | yes | **no** | 38,389,588 | `5.10.269-PanxCZ-4.0.202610070309` md5 `b2d09ce8db210451702eaef57cf821f6` | is SUSFS' hiding (path/stat/mount) the culprit? |
| v16 | **no** | no | **38,323,860** | `5.10.269-PanxCZ-4.0.202610070318` md5 `9fef438bd04f45c17b68e62beb05ba21` | control — must boot; proves tree + pipeline |

(`OUTDIR` is now overridable too, because the zip name does not encode these
knobs and a shared output dir silently overwrites the previous candidate.)

**v16 lands the control perfectly.** Its `Image` is 38,323,860 bytes — *the same
size as the MillenniumOSS prebuilt* `chihiro/Image.gz` — and its config differs
from the known-good device config by **2 lines, both cosmetic** (the version
banner, and the `UNUSED_KSYMS_WHITELIST` build path). v16 therefore *is* the
kernel the phone runs, rebuilt by our pipeline with only the branding changed.

The sizes tell the whole story:

```
stock / v16    38,323,860        
v15 (+KSU)     38,389,588   (+65,728 = 64 KiB + 1 KiB)
v14 (+KSU+SUSFS) 38,651,708  (+327,848)
```

So the bisect reads directly: v16 must boot (nothing but branding changed from a
kernel that already boots), **v15 then isolates root from hiding** — if v15
boots, SUSFS is the culprit; if it also hangs, KernelSU itself is, and the
remaining lever is the BakaSU revision (our manager version code is 35216, the
newest published APK is 35171).

#### v13 config check (and why v14 exists)

`scripts/extract-kernel-config.py` pulls the config back out of a built `Image`
(handling both raw Images and full boot images). Diffing v13's against
`patches/config-reference-kagamichihiro-5.10.269.txt` — the config of the kernel
currently sitting in `boot_b`, identical to MillenniumOSS's prebuilt — gave:

```
config diff: 2 removed, 31 added
```

and **every** line is expected: the `# Linux/arm64 …` banner, the
`CONFIG_UNUSED_KSYMS_WHITELIST` build-machine path, the KSU/SUSFS comment blocks,
and the `CONFIG_KSU*` symbols themselves. No `CONFIG_HZ`, no
`CONFIG_DEFAULT_TCP_CONG`, no BBRv3, no `CONFIG_LLVM_POLLY` — i.e. the kernel is
now config-identical to the one that boots, plus root and hiding. That check is
built into the build as **step 12b** and warns on any unexpected drift, because
`CONFIG_HZ=300` and `CONFIG_DEFAULT_TCP_CONG="bbr3"` are both perfectly valid
Kconfig values and nothing else flagged them in v10.

v13 still reuses `out/android12-5.10/common` from earlier builds — `git clean
-fdx` only cleans the *source* tree — and only 3462 `CC` lines were logged, so
most objects came from the older legacy-repo tree. Mixing objects and generated
headers from two different kernels on one link line is not a supported
configuration, so **v14 rebuilds with `CLEAN_OUT=yes`** (now the default) rather
than flashing a binary with that doubt attached.

### Base selection — the legacy repo was the bootloop

**The single most important thing on this page.** There are *two* MillenniumOSS
kernel repos, and only one of them is current:

| repo | branch used | LTS | head date |
|---|---|---|---|
| `android_kernel_common_android12-5.10` *(legacy)* | `chihiro-lnx-stable` | 5.10.264 | 2026-08-14 |
| **`android_kernel_common_millennium_android12-5.10`** | **`chihiro-main`** | **5.10.269** | **2026-10-03** |

Everything up to v12 was built from the **legacy** repo. That was wrong. The
proof is a prebuilt: MillenniumOSS publishes the device's own kernel in
`android_device_millennium_common-kernel` (`chihiro/Image.gz`, branch
`seventeen`), and that binary reports

```
Linux version 5.10.269-KagamiChihiro-MillenniumTeam-android12-9+
  (build-user@build-host) ... clang version 12.0.5 ... #1 SMP PREEMPT Sat Oct 3 22:58:56 UTC 2026
```

`Sat Oct 3 22:58:56 UTC 2026` is the timestamp of `chihiro-main` tip
`2a6271bf1f5b` (*"Merge branch 'millennium-dev' into chihiro-main"*), so the
kernel this phone runs is built from that exact commit. Two further checks
agree: the prebuilt's embedded `IKCFG_ST` config is **byte-identical (0 diff
lines)** to the config of the kernel currently sitting in `boot_b`, and the
prebuilt's decompressed `Image` is the same size as `boot_a`'s (38,323,860 B).

So the reference for "what boots on this device" is exactly
**`millennium/chihiro-main` + stock `gki_defconfig`, with no KSU, no SUSFS and
no BBRv3.** The v10/v11 builds instead hand-merged AOSP LTS 5.10.269 onto the
legacy 5.10.264 branch through six manual conflict resolutions — an entirely
different tree, and the natural place for a boot hang to hide.

Legacy-repo branch survey (kept for reference only — do not build from these):

| branch | LTS | date |
|---|---|---|
| `millennium-base` | 5.10.264 | 2026-08-14 |
| `millennium-base-linuxstable` | 5.10.264 | 2026-08-09 |
| **`chihiro-lnx-stable`** | **5.10.264** | 2026-08-09 |
| `chihiro-main` | 5.10.260 | 2026-08-09 |
| `chihiro-rebase` | 5.10.257 | 2026-06-18 |
| `kei-5.10` | 5.10.257 | 2026-06-14 |
| `chihiro-dev` | 5.10.250 | 2026-02-14 |

Those ship `CONFIG_CPU_FREQ_GOV_REFLEX` and DAMON; `CONFIG_MQ_IOSCHED_ADIOS` is in the
legacy `chihiro-rebase` lineage but **not** in the live `chihiro-main`.

**Correction to an earlier claim on this page:** *"no MillenniumOSS branch is at
5.10.269, so the device's `5.10.269-KagamiChihiro` comes from elsewhere"* was wrong. It
came from not looking in the second repo. `millennium/chihiro-main` **is** 5.10.269, and
that is where the device kernel comes from — so no AOSP LTS merge is needed at all
(`LTS_MERGE=no` is now the default; `scripts/make-base-269.sh` is kept only for the
legacy path).

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

* **v10/v11 bootloop.** Final verdict: **the base repo was wrong** (see *Base
  selection* above) — v10 and v11 were built from the legacy
  `android_kernel_common_android12-5.10` via a hand-resolved AOSP LTS merge, not from
  the live `millennium/chihiro-main` @ 5.10.269 the device actually runs. v13 is the
  first build on the correct tree. The BBRv3 story below is kept because the crash is
  real and bbr3 is still suspected *in addition* — but be clear that v11 removed
  BBRv3-as-default and **still** bootlooped, so it was never the whole cause.

* **BBRv3 as the default congestion control is a genuine, separate bug.**
  Flashing v10 (both the hand-packed `boot` image and the AnyKernel3 zip) put the
  phone into a reboot loop. There is no log from the v10 kernel itself, but the
  crash is unambiguous — pstore (`/sys/fs/pstore/console-ramoops-0`, dumped as
  root) held an Oops in `bbr3_main`:

  ```
  Unable to handle kernel NULL pointer dereference at virtual address 0000000000000022
  pc : [0x…] bbr3_main+0xec/0xc7c        lr : bbr3_main+0xe8/0xc7c
  Call trace: … tcp_ack+0xe40/0x1378 -> bbr3_main+0xec/0xc7c
  Internal error: Oops: 96000006 [#2] PREEMPT SMP
  ```

  v10 sets `CONFIG_DEFAULT_TCP_CONG="bbr3"`, so **every** TCP socket selects bbr3
  during boot and hits the broken path within a minute of uptime; `mrdump` turns
  the panic into a reboot, which is what a "bootloop" looked like here.

  Confirmed by diffing the **stock** kernel's own config (recovered from the
  `IKCFG_ST` blob embedded in the stock `boot_b` image) against v10's config
  (recovered the same way from v10's `Image`):

  | option | stock (boots) | v10 (bootloop) |
  |---|---|---|
  | `CONFIG_DEFAULT_TCP_CONG` | `"westwood"` | `"bbr3"` |
  | `CONFIG_HZ` | `250` | `300` |
  | `CONFIG_TCP_CONG_BBR3` | *absent* | `y` |

  Nothing else functional differed (only `TCP_CONG_BIC`, `NET_SCH_CAKE` and the
  expected KernelSU/SUSFS additions). **Fix shipped in v11:** bbr3 stays compiled
  in but is no longer the default — `CONFIG_DEFAULT_WESTWOOD=y` +
  `CONFIG_DEFAULT_TCP_CONG="westwood"`, exactly the stock base — and `HZ` goes
  back to 250 (`HZ` is baked into the jiffies conversions the vendor modules use,
  so it is not free to change). bbr3 remains opt-in:
  `sysctl -w net.ipv4.tcp_congestion_control=bbr3`, until the port itself is
  validated. **Aetherium ships a *different, working* BBRv3** (same 5.10.269
  base, `5.10.269-Aetherium4.5`, bbr3 as default) and is the reference to port
  from rather than re-deriving the fix.

  Two theories ruled out, for the record:
  * **module vermagic / localversion** — the device's `/vendor/lib/modules` carry
    `vermagic=5.10.209-android12-9-…` yet load fine on a 5.10.269 kernel, so
    version matching is not enforced here; a custom `LOCALVERSION` is safe.
  * **`TRIM_UNUSED_KSYMS`** — its `UNUSED_KSYMS_WHITELIST`
    (`out/android12-5.10/common/abi_symbollist.raw`) does resolve at build time
    on both the VPS and CI.

  Also worth knowing when diagnosing a non-booting kernel here: the phone's
  stock config **also** has `# CONFIG_PID_NS is not set`, `# CONFIG_USER_NS is not
  set`, `# CONFIG_DEVTMPFS is not set` and `# CONFIG_SYSVIPC is not set` — those
  are *not* required on this device, even though other 5.10.269 kernels (e.g.
  Aetherium) enable them.

* **BBRv3 — ported, but not default-safe yet.** Aetherium's BBRv3 is a single **kitchen-sink commit**: it
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
