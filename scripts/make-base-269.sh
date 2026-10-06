#!/usr/bin/env bash
# =============================================================================
#  make-base-269.sh
# =============================================================================
#  Recreates the PanxCZ 5.10.269 base branch:
#
#      chihiro-lnx-stable (MillenniumOSS, 5.10.264)
#          + AOSP android12-5.10-lts (5.10.269)
#      -> panxcz-base-5.10.269
#
#  This is how the ROM's level is matched. No MillenniumOSS branch is at
#  5.10.269, and MillenniumTeam's own kernels are described as "Merge
#  android12-5.10-lts and android12-5.10", so we do the same.
#
#  The merge is deterministic: exactly 6 files conflict, and each has one
#  correct resolution (recorded below, validated by a full build). If a future
#  upstream bump changes that set, this script REFUSES to guess.
#
#  Usage:  bash make-base-269.sh [kernel-common-dir]
#  Env:    BASE_BRANCH (chihiro-lnx-stable), OUT_BRANCH (panxcz-base-5.10.269),
#          EXPECT_LTS (5.10.269), FORCE=yes to rebuild an existing branch
# =============================================================================
set -euo pipefail

REPO_DIR="${1:-$PWD}"
BASE_BRANCH="${BASE_BRANCH:-chihiro-lnx-stable}"
OUT_BRANCH="${OUT_BRANCH:-panxcz-base-5.10.269}"
EXPECT_LTS="${EXPECT_LTS:-5.10.269}"
MILLENNIUM_REPO="${MILLENNIUM_REPO:-https://github.com/MillenniumOSS/android_kernel_common_android12-5.10.git}"
AOSP_REPO="${AOSP_REPO:-https://android.googlesource.com/kernel/common}"
AOSP_LTS_BRANCH="${AOSP_LTS_BRANCH:-android12-5.10-lts}"
FORCE="${FORCE:-no}"

# ---- the 6 conflicting files and their validated resolutions ----------------
TAKE_THEIRS="drivers/pci/setup-bus.c drivers/usb/typec/tcpm/tcpm.c fs/proc/fd.c net/ipv6/mcast.c"
TAKE_OURS="fs/f2fs/compress.c kernel/sched/cpufreq_schedutil.c"
EXPECT_CONFLICTS="6"

log()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[WARN] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[FATAL] %s\033[0m\n' "$*"; exit 1; }

ver() { awk '/^(VERSION|PATCHLEVEL|SUBLEVEL) =/{printf "%s.",$3}END{print ""}' "$1"Makefile; }

log "make-base-269: ${REPO_DIR}"
cd "${REPO_DIR}"
[ -d .git ] || die "${REPO_DIR} is not a git repo"

if git rev-parse --verify --quiet "refs/heads/${OUT_BRANCH}" >/dev/null && [ "${FORCE}" != "yes" ]; then
  echo "OK: ${OUT_BRANCH} already exists ($(ver ''))"
  exit 0
fi

# A shallow tree cannot compute a merge base (that is exactly how this bit us
# the first time), so make sure the shared history is actually present.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  warn "tree is shallow - unshallowing so the merge base can be computed"
  git fetch --unshallow 2>/dev/null || git fetch --depth=200000 2>/dev/null || true
fi

log "1/4 fetch ${BASE_BRANCH}"
if git remote | grep -qx millennium; then git remote set-url millennium "${MILLENNIUM_REPO}"; else git remote add millennium "${MILLENNIUM_REPO}"; fi
git fetch --filter=blob:none millennium "${BASE_BRANCH}"
BASE_SHA="$(git rev-parse FETCH_HEAD)"
echo "  base       : $(git log -1 --format='%h %cs %s' "${BASE_SHA}")"
echo "  base LTS   : $(git show "${BASE_SHA}:Makefile" | awk '/^(VERSION|PATCHLEVEL|SUBLEVEL) =/{printf "%s.",$3}')"

log "2/4 fetch AOSP ${AOSP_LTS_BRANCH}"
if git remote | grep -qx aosp; then git remote set-url aosp "${AOSP_REPO}"; else git remote add aosp "${AOSP_REPO}"; fi
git fetch --filter=blob:none aosp "${AOSP_LTS_BRANCH}"
LTS_SHA="$(git rev-parse FETCH_HEAD)"
LTS_VER="$(git show "${LTS_SHA}:Makefile" | awk '/^(VERSION|PATCHLEVEL|SUBLEVEL) =/{printf "%s.",$3}')"
echo "  lts        : $(git log -1 --format='%h %cs %s' "${LTS_SHA}")"
echo "  lts level  : ${LTS_VER}"

MB="$(git merge-base "${BASE_SHA}" "${LTS_SHA}" 2>/dev/null || true)"
[ -n "${MB}" ] || die "no merge base between ${BASE_BRANCH} and ${AOSP_LTS_BRANCH} - history is still truncated"
echo "  merge base : $(git log -1 --format='%h %cs %s' "${MB}")"

log "3/4 merge"
git checkout -f "${BASE_SHA}"
git checkout -B "${OUT_BRANCH}"
set +e
git merge --no-commit --no-ff "${LTS_SHA}" >/dev/null 2>&1
set -e
CONF="$(git diff --name-only --diff-filter=U | sort)"
N="$(printf '%s\n' "${CONF}" | grep -c . || true)"
echo "  conflicts: ${N}"
[ "${N}" = "${EXPECT_CONFLICTS}" ] || {
  printf '%s\n' "${CONF}"
  warn "expected ${EXPECT_CONFLICTS} conflicts, got ${N} - upstream moved."
  warn "Aborting rather than guessing a resolution."
  git merge --abort || true
  git checkout -f "${BASE_SHA}"
  git branch -D "${OUT_BRANCH}" 2>/dev/null || true
  die "conflict set changed - review and update this script"
}

# Resolution (validated by a full build):
#   AOSP side for the newer upstream fixes, Chihiro side for its own tuning and
#   for the zstd_* wrapper API present in this tree.
for f in ${TAKE_THEIRS}; do git checkout --theirs -- "$f"; done
for f in ${TAKE_OURS};   do git checkout --ours   -- "$f"; done

# Fix-up for one merge artefact: the merged fs/proc/fd.c kept a 3-argument
# proc_fd_link() while fs/proc/internal.h's ->proc_get_link hook is 2-argument,
# which fails to build. Drop the extra argument (it is derivable in-function).
python3 - fs/proc/fd.c <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
start = "static int proc_fd_link(struct dentry *dentry, struct path *path"
i = s.find(start)
if i == -1:
    print("[skip] proc_fd_link already has the 2-arg signature"); sys.exit(0)
if "struct task_struct *task)" not in s[i:i+140]:
    print("[skip] proc_fd_link not in the 3-arg form"); sys.exit(0)
j = s.find("\n}\n", i)
if j == -1:
    print("[FAIL] could not find end of proc_fd_link"); sys.exit(1)
j += len("\n}\n")
new = (
"static int proc_fd_link(struct dentry *dentry, struct path *path)\n"
"{\n"
"\tstruct task_struct *task = get_proc_task(d_inode(dentry));\n"
"\tint ret = -ENOENT;\n"
"\tunsigned int fd = proc_fd(d_inode(dentry));\n"
"\tstruct file *fd_file;\n"
"\n"
"\tif (!task)\n"
"\t\treturn ret;\n"
"\n"
"\tfd_file = fget_task(task, fd);\n"
"\tif (fd_file) {\n"
"\t\t*path = fd_file->f_path;\n"
"\t\tpath_get(&fd_file->f_path);\n"
"\t\tret = 0;\n"
"\t\tfput(fd_file);\n"
"\t}\n"
"\n"
"\tput_task_struct(task);\n"
"\treturn ret;\n"
"}\n"
)
open(p, "w").write(s[:i] + new + s[j:])
print("[OK] proc_fd_link reduced to the 2-arg hook signature")
PYEOF

git add -A
[ -z "$(git diff --name-only --diff-filter=U)" ] || die "unresolved conflicts remain"

log "4/4 commit"
git -c user.name="PanxCZ Builder" -c user.email="builder@panxcz.local" commit -q -m \
"Merge AOSP ${AOSP_LTS_BRANCH} (${LTS_VER}) into ${BASE_BRANCH}

PanxCZ base merge: ${BASE_BRANCH} -> ${LTS_VER} to match the level the
Infinity X ROM runs (5.10.269-KagamiChihiro).

Conflicts (${N}) resolved as:
  ${TAKE_THEIRS// /, } : AOSP (newer upstream fixes; fget_task() race fix in
    proc/fd.c, in6_addr by value in mcast.c)
  ${TAKE_OURS// /, } : Chihiro (custom schedutil rate-limit tuning; uses the
    exported zstd_* wrapper API present in this tree)
Plus a fix-up reducing proc_fd_link() to the 2-arg ->proc_get_link hook."

echo
echo "OK: ${OUT_BRANCH} = $(git rev-parse --short HEAD)  LTS $(ver '')"
[ "$(ver '')" = "${EXPECT_LTS}." ] || warn "expected ${EXPECT_LTS}, got $(ver '')"
