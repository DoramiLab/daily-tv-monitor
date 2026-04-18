#!/usr/bin/env bash
set -euo pipefail

REMOTE_URL_DEFAULT="https://github.com/DoramiLab/daily-tv-monitor.git"
GIT_DIR_DEFAULT="/tmp/tv-ai-daily-git"
BRANCH_DEFAULT="main"

remote_url="${REMOTE_URL:-$REMOTE_URL_DEFAULT}"
git_dir="${TV_AI_DAILY_GIT_DIR:-$GIT_DIR_DEFAULT}"
branch="${BRANCH:-$BRANCH_DEFAULT}"

msg="${1:-}"
if [[ -z "${msg}" ]]; then
  msg="daily trend sensing: $(date +%F)"
fi

repo_root="$(pwd)"

git_common=(git "--git-dir=${git_dir}" "--work-tree=.")

mkdir -p "${git_dir}"

if [[ ! -f "${git_dir}/HEAD" ]]; then
  git --git-dir="${git_dir}" init -q
fi

if ! git --git-dir="${git_dir}" remote get-url origin >/dev/null 2>&1; then
  git --git-dir="${git_dir}" remote add origin "${remote_url}"
else
  git --git-dir="${git_dir}" remote set-url origin "${remote_url}"
fi

if ! git --git-dir="${git_dir}" config user.name >/dev/null 2>&1; then
  git --git-dir="${git_dir}" config user.name "codex-automation"
fi
if ! git --git-dir="${git_dir}" config user.email >/dev/null 2>&1; then
  git --git-dir="${git_dir}" config user.email "codex-automation@users.noreply.github.com"
fi

cd "${repo_root}"

${git_common[@]} fetch origin "${branch}" -q

${git_common[@]} update-ref "refs/heads/${branch}" "refs/remotes/origin/${branch}"
${git_common[@]} symbolic-ref HEAD "refs/heads/${branch}"
${git_common[@]} reset --mixed "origin/${branch}" -q

${git_common[@]} add data/raw

if ${git_common[@]} diff --cached --quiet; then
  echo "No staged changes; skipping commit/push."
  exit 0
fi

${git_common[@]} commit -m "${msg}" -q

${git_common[@]} fetch origin "${branch}" -q
${git_common[@]} rebase "origin/${branch}" -q || true

${git_common[@]} push origin "${branch}"

