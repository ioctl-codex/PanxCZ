#!/usr/bin/env bash
# =============================================================================
#  fix-bakasu-version.sh
# =============================================================================
#  BakaSU (the renamed ReSukiSU) computes its build version from the git repo it
#  lives in, and refuses to build unless it is present as a real checkout:
#
#     kernel/Kbuild:
#        LOCAL_GIT_EXISTS := $(shell test -e $(KSU_SRC)/../.git && echo 1 || echo 0)
#        ifeq ($(LOCAL_GIT_EXISTS),0)
#        $(error You should use BakaSU as a git submodule instead of copying code)
#        endif
#        KSU_LOCAL_VERSION := $(shell cd $(KSU_SRC); git rev-list --count HEAD)
#        KSU_VERSION := $(shell expr 30000 + $(KSU_LOCAL_VERSION) + 700)
#
#  Two ways this still breaks a CI/VPS build:
#    1) the checkout has no .git (someone copied the sources) -> hard $(error)
#    2) git history is unusable, so `expr` yields an empty KSU_VERSION, and
#       supercalls.c then fails with:
#           error: expected expression
#           struct ksu_get_info_cmd cmd = {.version = KERNEL_SU_VERSION, ...};
#
#  This script verifies (1) and hard-guards (2) by injecting a fallback.
#
#  Usage: bash fix-bakasu-version.sh [kernel-common-dir]
# =============================================================================
set -euo pipefail

COMMON_DIR="${1:-$PWD}"
KSU_DIR="${COMMON_DIR}/KernelSU"
KBUILD="${KSU_DIR}/kernel/Kbuild"

echo "=== fix-bakasu-version: ${COMMON_DIR} ==="

if [ ! -d "${KSU_DIR}" ]; then
  echo "[SKIP] ${KSU_DIR} not found (root solution not integrated)"
  exit 0
fi

# --- 1) BakaSU must live in a real git checkout ------------------------------
if [ ! -d "${KSU_DIR}/.git" ]; then
  echo "[FATAL] ${KSU_DIR}/.git is missing."
  echo "        BakaSU's Kbuild raises a hard \$(error) without it."
  echo "        Re-run the integration step (setup.sh clones, it does not copy)."
  exit 1
fi
echo "[OK] .git present"

if [ -f "${KSU_DIR}/.git/shallow" ]; then
  echo "[..] shallow checkout detected - fetching full history for a real version"
  git -C "${KSU_DIR}" fetch --unshallow 2>/dev/null || echo "[WARN] unshallow failed; version count will be approximate"
fi

COUNT="$(git -C "${KSU_DIR}" rev-list --count HEAD 2>/dev/null || echo 0)"
BRANCH="$(git -C "${KSU_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
echo "     branch=${BRANCH} commits=${COUNT}"
if [ "${COUNT}" -gt 0 ] 2>/dev/null; then
  echo "     expected KSU_VERSION = $((30000 + COUNT + 700))"
fi

# --- 2) never allow an empty KSU_VERSION ------------------------------------
if [ ! -f "${KBUILD}" ]; then
  echo "[FATAL] ${KBUILD} not found"
  exit 1
fi

python3 - "${KBUILD}" <<'PYEOF'
import sys

path = sys.argv[1]
src = open(path).read()
marker = "ccflags-y += -DKSU_VERSION=$(KSU_VERSION)"
guard = (
    "# PanxCZ: KSU_VERSION fallback. BakaSU derives the version from the git\n"
    "# history of its own checkout; if that is unavailable the macro expands\n"
    "# to nothing and supercalls.c fails with 'expected expression'.\n"
    "ifeq ($(strip $(KSU_VERSION)),)\n"
    "KSU_VERSION := 41185\n"
    "endif\n"
)

if "PanxCZ: KSU_VERSION fallback" in src:
    print("[OK] Kbuild already patched")
    sys.exit(0)

if marker not in src:
    print("[WARN] marker not found in Kbuild; nothing changed")
    sys.exit(0)

open(path, "w").write(src.replace(marker, guard + marker, 1))
print("[OK] KSU_VERSION fallback inserted into Kbuild")
PYEOF

grep -n "PanxCZ: KSU_VERSION fallback" "${KBUILD}" | head -3
echo "=== fix-bakasu-version: done ==="
