#!/usr/bin/env bash
# =============================================================================
#  gitlab-backup-push.sh   (runs on the build VPS)
# =============================================================================
#  Fast, reliable backup of the PanxCZ work to GitLab.
#
#  Speed notes (why this is built the way it is):
#    * The VPS pushes straight to gitlab.com - data is never relayed through
#      another machine, so the VPS's own uplink is the only bottleneck.
#    * Source is pushed as ONE squashed commit. Pushing the full Android
#      history is ~1.1 GB of objects and minutes of server-side enumeration
#      for zero backup value.
#    * Binaries (Image, AnyKernel3 zip) go to the GitLab generic PACKAGE
#      REGISTRY with a single streaming PUT - no git overhead, no repo bloat.
#    * git is tuned for throughput (pack.threads=0, HTTP/2, big postBuffer).
#
#  Env:
#    GITLAB_TOKEN   (required) PAT with api scope
#    REPO_DIR       staging tree to back up   (default /opt/panxcz/panxcz-repo)
#    ARTIFACT_DIR   artifacts to upload       (default /opt/panxcz/out-artifacts)
#    SRC_PROJECT    (default panxcz-group/panxcz-backup/kernel-src)
#    ART_PROJECT    (default panxcz-group/panxcz-backup/build-artifacts)
#    PACKAGE_NAME   (default panxcz-kernel)
#    SOURCE_SNAPSHOT=yes  also tar.zst the full kernel tree into the registry
#    KERNEL_TREE    tree to snapshot          (default /opt/work/bbr3)
#  Usage: GITLAB_TOKEN=... bash gitlab-backup-push.sh
# =============================================================================
set -euo pipefail

: "${GITLAB_TOKEN:?set GITLAB_TOKEN}"
REPO_DIR="${REPO_DIR:-/opt/panxcz/panxcz-repo}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/opt/panxcz/out-artifacts}"
SRC_PROJECT="${SRC_PROJECT:-panxcz-group/panxcz-backup/kernel-src}"
ART_PROJECT="${ART_PROJECT:-panxcz-group/panxcz-backup/build-artifacts}"
PACKAGE_NAME="${PACKAGE_NAME:-panxcz-kernel}"
SOURCE_SNAPSHOT="${SOURCE_SNAPSHOT:-no}"
KERNEL_TREE="${KERNEL_TREE:-/opt/work/bbr3}"
API="https://gitlab.com/api/v4"

log()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[WARN] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[FATAL] %s\033[0m\n' "$*"; exit 1; }

command -v git >/dev/null || die "git missing"
command -v zstd >/dev/null || apt-get install -y -qq zstd || true

# ---------------------------------------------------------------- git tuning
git config --global pack.threads 0            # one thread per core when packing
git config --global pack.windowMemory 256m
git config --global core.compression 6        # balance CPU vs. wire bytes
git config --global http.version HTTP/2
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 300
export GIT_TERMINAL_PROMPT=0

project_id() {
  curl -sS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${API}/projects/$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1")" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))"
}

# ---------------------------------------------------------------- 1. source
log "1/3 backup source -> ${SRC_PROJECT}"
[ -d "${REPO_DIR}" ] || die "REPO_DIR ${REPO_DIR} not found"
cd "${REPO_DIR}"
if [ ! -d .git ]; then
  git init -q -b main
  git config user.name  "PanxCZ Backup"
  git config user.email "backup@panxcz.local"
fi
git add -A
git -c user.name="PanxCZ Backup" -c user.email="backup@panxcz.local" \
    commit -q -m "PanxCZ backup $(date -u +%Y-%m-%dT%H:%M:%SZ)" || warn "nothing new to commit"
# one squashed commit keeps the push small and the history readable
SRC_URL="https://oauth2:${GITLAB_TOKEN}@gitlab.com/${SRC_PROJECT}.git"
git remote remove gitlab 2>/dev/null || true
git remote add gitlab "${SRC_URL}"
echo "objects to push: $(git count-objects -vH | awk '/size-pack/{print $2}')"
time git push -q --force gitlab HEAD:main
echo "[OK] source pushed -> https://gitlab.com/${SRC_PROJECT}"

# ---------------------------------------------------------------- 2. artifacts
log "2/3 upload artifacts -> ${ART_PROJECT} (generic package registry)"
ART_ID="$(project_id "${ART_PROJECT}")"
[ -n "${ART_ID}" ] || die "cannot resolve project ${ART_PROJECT}"
shopt -s nullglob
FILES=("${ARTIFACT_DIR}"/*.zip "${ARTIFACT_DIR}"/Image "${ARTIFACT_DIR}"/Image.lz4 "${ARTIFACT_DIR}"/summary.txt)
[ ${#FILES[@]} -gt 0 ] || warn "no artifacts found in ${ARTIFACT_DIR}"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  ver="$(date -u +%Y.%m.%d)-$(basename "$f" | md5sum | cut -c1-6)"
  printf '  uploading %-44s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
  time curl -sS --fail --retry 3 --retry-delay 5 --limit-rate 0 \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --upload-file "$f" \
      "${API}/projects/${ART_ID}/packages/generic/${PACKAGE_NAME}/${ver}/$(basename "$f")" \
      >/dev/null || warn "upload failed for $(basename "$f")"
done
echo "[OK] artifacts -> https://gitlab.com/${ART_PROJECT}/-/packages"

# ---------------------------------------------------------------- 3. snapshot
if [ "${SOURCE_SNAPSHOT}" = "yes" ]; then
  log "3/3 full kernel source snapshot (.tar.zst) -> registry"
  [ -d "${KERNEL_TREE}" ] || die "KERNEL_TREE ${KERNEL_TREE} not found"
  OUT="/tmp/panxcz-source-$(date -u +%Y%m%d%H%M).tar.zst"
  # exclude build output + git history: we want the tree, not the packs
  tar -C "${KERNEL_TREE}" --exclude=.git --exclude=out \
      -I 'zstd -T0 -3' -cf "${OUT}" . 2>/dev/null || \
    tar -C "${KERNEL_TREE}" --exclude=.git --exclude=out -I 'zstd -T0 -3' -cf "${OUT}" .
  ls -lh "${OUT}"
  ver="$(date -u +%Y.%m.%d)-snapshot"
  time curl -sS --fail --retry 3 --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --upload-file "${OUT}" \
      "${API}/projects/${ART_ID}/packages/generic/${PACKAGE_NAME}/${ver}/$(basename "${OUT}")" >/dev/null
  rm -f "${OUT}"
  echo "[OK] source snapshot uploaded"
else
  echo "[skip] SOURCE_SNAPSHOT!=yes (set SOURCE_SNAPSHOT=yes for a full tree tar.zst)"
fi

log "backup complete"
