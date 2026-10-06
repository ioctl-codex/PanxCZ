#!/usr/bin/env bash
# =============================================================================
#  gitlab-backup-setup.sh
# =============================================================================
#  Creates the PanxCZ backup structure on GitLab:
#
#     panxcz-group/panxcz-backup            (subgroup = the "backup folder")
#     panxcz-group/panxcz-backup/kernel-src (full kernel source + patches)
#     panxcz-group/panxcz-backup/builds     (built Images + AnyKernel3 zips)
#
#  Requires a GitLab personal access token with the "api" scope in
#  $GITLAB_TOKEN. Nothing here is stored in the repo.
#
#  Usage:  GITLAB_TOKEN=... bash gitlab-backup-setup.sh
# =============================================================================
set -euo pipefail

: "${GITLAB_TOKEN:?set GITLAB_TOKEN to a GitLab personal access token with api scope}"

API="https://gitlab.com/api/v4"
PARENT_GROUP="${PARENT_GROUP:-panxcz-group}"
BACKUP_GROUP="${BACKUP_GROUP:-panxcz-backup}"

api() { curl -sS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$@"; }

# JSON field helper (no jq dependency assumed).
jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$1',''))" 2>/dev/null || true; }

echo "=== 1. verify token ==="
ME="$(api "${API}/user")"
USERNAME="$(printf '%s' "${ME}" | jget username)"
[ -n "${USERNAME}" ] || { echo "[FATAL] token rejected by ${API}/user"; exit 1; }
echo "[OK] authenticated as ${USERNAME}"

echo "=== 2. resolve parent group ==="
PG="$(api "${API}/groups/${PARENT_GROUP}")"
PG_ID="$(printf '%s' "${PG}" | jget id)"
[ -n "${PG_ID}" ] || { echo "[FATAL] parent group ${PARENT_GROUP} not found / no access"; exit 1; }
echo "[OK] ${PARENT_GROUP} id=${PG_ID}"

echo "=== 3. create subgroup (the backup folder) ==="
BG="$(api "${API}/groups/${PG_ID}/subgroups?search=${BACKUP_GROUP}")"
BG_ID="$(printf '%s' "${BG}" | python3 -c "
import sys,json
try:
    for g in json.load(sys.stdin):
        if g.get('path')=='${BACKUP_GROUP}':
            print(g['id']); break
except Exception:
    pass
" 2>/dev/null || true)"
if [ -z "${BG_ID}" ]; then
  CREATED="$(api -X POST "${API}/groups" \
      --data-urlencode "name=${BACKUP_GROUP}" \
      --data-urlencode "path=${BACKUP_GROUP}" \
      --data-urlencode "parent_id=${PG_ID}" \
      --data-urlencode "visibility=private" \
      --data-urlencode "description=PanxCZ kernel backup: sources, patches and build artifacts")"
  BG_ID="$(printf '%s' "${CREATED}" | jget id)"
  printf '%s' "${CREATED}" | grep -q '"message"' && { echo "[FATAL] subgroup create failed:"; printf '%s\n' "${CREATED}"; exit 1; }
  echo "[OK] created subgroup ${BACKUP_GROUP} id=${BG_ID}"
else
  echo "[OK] subgroup ${BACKUP_GROUP} already exists id=${BG_ID}"
fi

# --- create or reuse a project in the backup subgroup ------------------------
# Sets the global PROJECT_ID. Messages go to stdout for the caller to print;
# the id is returned via a global so it is never swallowed by $( ... ).
PROJECT_ID=""
ensure_project() {
  local path="$1" desc="$2" id out
  PROJECT_ID=""
  id="$(api "${API}/groups/${BG_ID}/projects?search=${path}" | python3 -c "
import sys,json
try:
    for p in json.load(sys.stdin):
        if p.get('path')=='${path}':
            print(p['id']); break
except Exception:
    pass
" 2>/dev/null || true)"
  if [ -n "${id}" ]; then
    echo "[OK] project ${path} already exists id=${id}"
    PROJECT_ID="${id}"
    return 0
  fi
  out="$(api -X POST "${API}/projects" \
      --data-urlencode "name=${path}" \
      --data-urlencode "path=${path}" \
      --data-urlencode "namespace_id=${BG_ID}" \
      --data-urlencode "visibility=private" \
      --data-urlencode "description=${desc}" \
      --data-urlencode "initialize_with_readme=false")"
  id="$(printf '%s' "${out}" | jget id)"
  if [ -z "${id}" ]; then
    echo "[FATAL] project '${path}' create failed:"; printf '%s\n' "${out}"
    return 1
  fi
  echo "[OK] created project ${path} id=${id}"
  PROJECT_ID="${id}"
}

echo "=== 4. create projects ==="
# NOTE: 'builds' is a reserved GitLab project path (/<project>/-/builds), so the
# artifacts repo is called 'build-artifacts'.
ensure_project kernel-src     "PanxCZ kernel source tree snapshot + integration patches (credit: MillenniumOSS/Chihiro, Aetherium, BakaSU, SUSFS)"
SRC_ID="${PROJECT_ID}"
ensure_project build-artifacts "PanxCZ successful build artifacts: Image, Image.lz4, AnyKernel3 flashable zips"
BLD_ID="${PROJECT_ID}"

echo
echo "=== summary ==="
echo "backup folder   : https://gitlab.com/groups/${PARENT_GROUP}/${BACKUP_GROUP}"
echo "kernel-src      : https://gitlab.com/${PARENT_GROUP}/${BACKUP_GROUP}/kernel-src        (id=${SRC_ID})"
echo "build-artifacts : https://gitlab.com/${PARENT_GROUP}/${BACKUP_GROUP}/build-artifacts  (id=${BLD_ID})"
echo
echo "push URLs (token substituted at push time, never committed):"
echo "  https://oauth2:<TOKEN>@gitlab.com/${PARENT_GROUP}/${BACKUP_GROUP}/kernel-src.git"
echo "  https://oauth2:<TOKEN>@gitlab.com/${PARENT_GROUP}/${BACKUP_GROUP}/build-artifacts.git"
