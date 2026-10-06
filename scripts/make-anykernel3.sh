#!/usr/bin/env bash
# PanxCZ - build a flashable AnyKernel3 zip for the Infinix Note 30 (X6833B).
#
# Kept standalone so the zip can be rebuilt from an existing Image without
# re-running the whole kernel build:
#
#   AK_IMAGE=/opt/panxcz/out-artifacts/Image \
#   AK_KVER=5.10.269 AK_OUTDIR=/opt/panxcz/out-artifacts \
#   bash scripts/make-anykernel3.sh
#
# Two things go wrong if upstream AnyKernel3 is used as-is, and both make the
# resulting zip unflashable:
#
#   1. the shipped anykernel.sh still targets maguro/toro/tuna (Galaxy Nexus)
#      and sets BLOCK=/dev/block/platform/omap/.../boot. On this A/B GKI device
#      the kernel lives in 'boot' and ak3-core.sh has to resolve it through
#      /dev/block/by-name/boot$SLOT, i.e. `BLOCK=boot` + `IS_SLOT_DEVICE=1`.
#   2. the zip must have META-INF/, anykernel.sh, tools/ and Image at the ZIP
#      ROOT. Zipping the checkout directory nests everything under anykernel/,
#      and then the recovery cannot even find update-binary at the zip root, so
#      the install aborts immediately.
set -euo pipefail

AK_IMAGE="${AK_IMAGE:-}"
AK_OUTDIR="${AK_OUTDIR:-/opt/panxcz/out-artifacts}"
AK_WORKDIR="${AK_WORKDIR:-/opt/panxcz}"
AK_KVER="${AK_KVER:-}"
AK_REPO="${AK_REPO:-https://github.com/osm0sis/AnyKernel3.git}"

AK_NAME="${AK_NAME:-PanxCZ}"
AK_RELEASE="${AK_RELEASE:-4.0}"
AK_VARIANT="${AK_VARIANT:-A-full-allin}"
AK_CODENAME="${AK_CODENAME:-Chihiro}"
AK_BASE_NAME="${AK_BASE_NAME:-millennium-chihiro}"
AK_ROOT="${AK_ROOT:-BakaSU}"
AK_HIDING="${AK_HIDING:-SuSFS}"
AK_PERF="${AK_PERF:-BBRv3}"
AK_BUILD_N="${AK_BUILD_N:-1}"
AK_DEVICE_MODEL="${AK_DEVICE_MODEL:-Infinix Note 30 (X6833B)}"
AK_DEVICE_PLATFORM="${AK_DEVICE_PLATFORM:-MediaTek Helio G99 (MT6789) - GKI 5.10 android12 / KMI gen 9}"

die() { printf '\033[1;31m[FATAL] %s\033[0m\n' "$*" >&2; exit 1; }
log() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

[ -n "${AK_IMAGE}" ] || die "AK_IMAGE is not set"
[ -f "${AK_IMAGE}" ] || die "kernel image not found: ${AK_IMAGE}"
if [ -z "${AK_KVER}" ]; then
  AK_KVER="$(strings -a "${AK_IMAGE}" 2>/dev/null | grep -oE '^5\.10\.[0-9]+' | head -n1 || true)"
fi
[ -n "${AK_KVER}" ] || AK_KVER="5.10.0"
log "AnyKernel3 for ${AK_NAME} ${AK_RELEASE} (${AK_KVER})"

KVER_LINE="${AK_KVER%.*}"    # 5.10.269 -> 5.10
KVER_SUB="${AK_KVER##*.}"    # 5.10.269 -> 269
# The internal variant is 'A-full-allin'; the artifact convention uses a short
# lower-case flavour ('base-only' in the reference name below).
AK_FLAVOR="${AK_FLAVOR:-$(printf '%s' "${AK_VARIANT}" | sed -E 's/^[A-Za-z]-//' | tr 'A-Z' 'a-z')}"

# Aetherium-style artifact name:
#   Aetherium4.5-5.10-base-only-ReSukiSU-SuSFS-Neutron-20260912-2.zip
#   <Name><release>-<kernel>-<flavor>-<root>-<hiding>-<perf>-<date>-<n>.zip
ZIPNAME="${AK_NAME}${AK_RELEASE}-${KVER_LINE}-${KVER_SUB}-${AK_FLAVOR}-${AK_ROOT}-${AK_HIDING}-${AK_PERF}-$(date -u +%Y%m%d)-${AK_BUILD_N}.zip"

AKDIR="${AK_WORKDIR}/anykernel"
rm -rf "${AKDIR}"
git clone --depth 1 "${AK_REPO}" "${AKDIR}"
rm -rf "${AKDIR}/.git" "${AKDIR}/.github"
[ -f "${AKDIR}/tools/ak3-core.sh" ] || die "AnyKernel3 checkout is incomplete (no tools/ak3-core.sh)"

KSTR="${AK_NAME} Kernel (${AK_CODENAME}-based) for ${AK_DEVICE_MODEL} by ${AK_NAME}"
cat > "${AKDIR}/anykernel.sh" <<EOF
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers (template) - device setup for ${AK_DEVICE_MODEL}

properties() { '
kernel.string=${KSTR}
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 \$RAMDISK/*;
set_perm_recursive 0 0 750 750 \$RAMDISK/init* \$RAMDISK/sbin;
} # end attributes

# boot shell variables
# ${AK_DEVICE_MODEL} is GKI ${KVER_LINE} with A/B slots: the kernel lives in
# 'boot' and the generic ramdisk in 'init_boot', which is deliberately not
# touched. IS_SLOT_DEVICE=1 is what makes ak3-core.sh use the active slot.
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;

write_boot;
## end boot install
EOF

printf '%s\n' \
  "id=${AK_NAME}" \
  "name=${AK_NAME} Kernel" \
  "version=v${AK_RELEASE}.$(date -u +%Y%m%d%H%M)" \
  "versionCode=$(date -u +%Y%m%d%H%M)" \
  "author=${AK_NAME}" \
  "description=Base ${AK_BASE_NAME} (${AK_KVER}) + ${AK_ROOT} + ${AK_HIDING} + ${AK_PERF} (credits: MillenniumOSS, Aetherium/kaminarich, BakaSU, SUSFS) for ${AK_DEVICE_PLATFORM}" \
  > "${AKDIR}/module.prop"

cp -f "${AK_IMAGE}" "${AKDIR}/Image"
# GKI boot images normally hold a *compressed* kernel (this device's does) and
# magiskboot picks whichever of Image/Image.gz it finds - ship both when the
# build produced the compressed one.
if [ -f "${AK_IMAGE}.gz" ]; then
  cp -f "${AK_IMAGE}.gz" "${AKDIR}/Image.gz"
elif command -v gzip >/dev/null 2>&1; then
  gzip -c9n "${AK_IMAGE}" > "${AKDIR}/Image.gz"
fi

mkdir -p "${AK_OUTDIR}"
echo "${ZIPNAME}" > "${AK_OUTDIR}/.zipname"
# Zip the CONTENTS of the checkout, never the directory itself.
( cd "${AKDIR}" && zip -r9 "${AK_OUTDIR}/${ZIPNAME}" . -x '*.git*' ) >/dev/null
rm -f "${AK_OUTDIR}/${AK_NAME}-"*"-AnyKernel3.zip"

log "zip root"
unzip -l "${AK_OUTDIR}/${ZIPNAME}" | awk 'NR<4 || /META-INF\/com\/google\/android\/| anykernel\.sh$| tools\/ak3-core\.sh$| Image(\.gz)?$/'

unzip -l "${AK_OUTDIR}/${ZIPNAME}" | grep -q ' META-INF/com/google/android/update-binary' \
  || die "malformed zip: update-binary is not at the zip root"
unzip -l "${AK_OUTDIR}/${ZIPNAME}" | grep -q ' anykernel.sh' \
  || die "malformed zip: anykernel.sh is not at the zip root"
grep -q '^BLOCK=boot;$' "${AKDIR}/anykernel.sh" \
  || die "anykernel.sh lost its device setup"
echo "OK: layout verified"
ls -lh "${AK_OUTDIR}/${ZIPNAME}"
echo "${AK_OUTDIR}/${ZIPNAME}"
