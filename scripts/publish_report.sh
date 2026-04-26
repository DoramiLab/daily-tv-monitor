#!/usr/bin/env bash
set -euo pipefail

REMOTE_URL_DEFAULT="https://github.com/DoramiLab/daily-tv-monitor.git"
INSTANCE_DEFAULT="$(date +%s)-$$"
GIT_DIR_DEFAULT="/tmp/tv-ai-daily-git-${TV_AI_DAILY_INSTANCE:-$INSTANCE_DEFAULT}"
WORK_DIR_DEFAULT="/tmp/tv-ai-daily-worktree-${TV_AI_DAILY_INSTANCE:-$INSTANCE_DEFAULT}"
BRANCH_DEFAULT="main"

remote_url="${REMOTE_URL:-$REMOTE_URL_DEFAULT}"
git_dir="${TV_AI_DAILY_GIT_DIR:-$GIT_DIR_DEFAULT}"
work_dir="${TV_AI_DAILY_WORK_DIR:-$WORK_DIR_DEFAULT}"
branch="${BRANCH:-$BRANCH_DEFAULT}"

msg="${1:-}"
if [[ -z "${msg}" ]]; then
  msg="Daily TV monitor: $(date +%F)"
fi

repo_root="$(pwd)"
auth_file="${GITHUB_AUTH_FILE:-${repo_root}/.github-auth.local}"
askpass_script=""

git_bare=(git "--git-dir=${git_dir}")
git_common=(git "--git-dir=${git_dir}" "--work-tree=${work_dir}")

cleanup() {
  rm -rf "${git_dir}" "${work_dir}"
  if [[ -n "${askpass_script}" ]]; then
    rm -f "${askpass_script}"
  fi
}

is_transient_network_error() {
  local output
  output="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$output" == *"could not resolve host"* ]] ||
    [[ "$output" == *"failed to connect"* ]] ||
    [[ "$output" == *"operation timed out"* ]] ||
    [[ "$output" == *"connection timed out"* ]] ||
    [[ "$output" == *"connection reset"* ]] ||
    [[ "$output" == *"the remote end hung up unexpectedly"* ]] ||
    [[ "$output" == *"http 5"* ]]
}

run_with_retry() {
  local label="$1"
  shift

  local delays=(0 5 15 45 90)
  local attempt=1
  local output=""
  local status=0

  for delay in "${delays[@]}"; do
    if (( delay > 0 )); then
      sleep "${delay}"
    fi

    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e

    if (( status == 0 )); then
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
      fi
      return 0
    fi

    printf '%s attempt %d failed: %s\n' "$label" "$attempt" "$output" >&2
    if ! is_transient_network_error "$output"; then
      return "$status"
    fi

    attempt=$((attempt + 1))
  done

  return "$status"
}

configure_github_auth() {
  local github_id=""
  local github_pat=""

  if [[ ! -f "${auth_file}" ]]; then
    return 0
  fi

  # shellcheck disable=SC1090
  source "${auth_file}"

  github_id="${GITHUB_ID:-${GITHUB_USER:-${GITHUB_USERNAME:-}}}"
  github_pat="${GITHUB_PAT:-${GITHUB_TOKEN:-}}"

  if [[ -z "${github_pat}" ]]; then
    echo "GitHub auth file exists but no token was found in ${auth_file}" >&2
    return 0
  fi

  if [[ -z "${github_id}" ]]; then
    github_id="x-access-token"
  fi

  export GITHUB_ID="${github_id}"
  export GITHUB_PAT="${github_pat}"

  askpass_script="$(mktemp "/tmp/tv-ai-daily-askpass.XXXXXX")"
  chmod 700 "${askpass_script}"
  cat > "${askpass_script}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "${GITHUB_ID:-${GITHUB_USER:-${GITHUB_USERNAME:-}}}" ;;
  *Password*) printf '%s\n' "${GITHUB_PAT:-${GITHUB_TOKEN:-}}" ;;
  *) printf '\n' ;;
esac
EOF

  export GIT_ASKPASS="${askpass_script}"
}

mkdir -p "${git_dir}"
mkdir -p "${work_dir}"
trap cleanup EXIT

export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=Never
configure_github_auth

if [[ ! -f "${git_dir}/HEAD" ]]; then
  "${git_bare[@]}" init -q
fi

if ! "${git_bare[@]}" remote get-url origin >/dev/null 2>&1; then
  "${git_bare[@]}" remote add origin "${remote_url}"
else
  "${git_bare[@]}" remote set-url origin "${remote_url}"
fi

if ! "${git_bare[@]}" config user.name >/dev/null 2>&1; then
  "${git_bare[@]}" config user.name "codex-automation"
fi
if ! "${git_bare[@]}" config user.email >/dev/null 2>&1; then
  "${git_bare[@]}" config user.email "codex-automation@users.noreply.github.com"
fi

run_with_retry "git fetch" "${git_bare[@]}" fetch origin "${branch}" -q

"${git_bare[@]}" update-ref "refs/heads/${branch}" "refs/remotes/origin/${branch}"
"${git_bare[@]}" symbolic-ref HEAD "refs/heads/${branch}"
"${git_common[@]}" reset --hard "origin/${branch}" -q

mkdir -p "${work_dir}/new_features"
shopt -s nullglob
report_files=("${repo_root}"/new_features/*.md)
if (( ${#report_files[@]} == 0 )); then
  echo "No report files found under ${repo_root}/new_features." >&2
  exit 1
fi
cp "${report_files[@]}" "${work_dir}/new_features/"

(
  cd "${work_dir}"
  "${git_common[@]}" add new_features/*.md
)

if "${git_common[@]}" diff --cached --quiet; then
  echo "No staged changes; skipping commit/push."
  exit 0
fi

"${git_common[@]}" commit -m "${msg}" -q
run_with_retry "git push" "${git_common[@]}" push origin "${branch}"
