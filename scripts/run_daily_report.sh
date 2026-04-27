#!/usr/bin/env bash
set -euo pipefail

export TZ="${TZ:-Asia/Seoul}"
export HOME="${HOME:-/Users/luna}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

codex_bin="${CODEX_BIN:-/Applications/Codex.app/Contents/Resources/codex}"
prompt_file="${CODEX_PROMPT_FILE:-${repo_root}/docs/codex_cron_daily_tv_monitor.md}"
model="${CODEX_MODEL:-gpt-5.4}"
codex_sandbox="${CODEX_SANDBOX_MODE:-workspace-write}"
log_dir="${CODEX_LOG_DIR:-${repo_root}/logs/cron}"
lock_dir="${TMPDIR:-/tmp}/daily-tv-monitor-cron.lock"
timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
run_log="${log_dir}/run_${timestamp}.log"
last_message="${log_dir}/last_message_${timestamp}.txt"
remote_url="${REMOTE_URL:-https://github.com/DoramiLab/daily-tv-monitor.git}"
branch="${BRANCH:-main}"
instance_default="$(date +%s)-$$"
git_dir="${TV_AI_DAILY_GIT_DIR:-/tmp/tv-ai-daily-git-${TV_AI_DAILY_INSTANCE:-$instance_default}}"
work_dir="${TV_AI_DAILY_WORK_DIR:-/tmp/tv-ai-daily-worktree-${TV_AI_DAILY_INSTANCE:-$instance_default}}"
auth_file="${GITHUB_AUTH_FILE:-${repo_root}/.github-auth.local}"
askpass_script=""

mkdir -p "${log_dir}"

cleanup() {
  rm -rf "${git_dir}" "${work_dir}"
  if [[ -n "${askpass_script}" ]]; then
    rm -f "${askpass_script}"
  fi
  rmdir "${lock_dir}" >/dev/null 2>&1 || true
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
  local cmd_status=0

  for delay in "${delays[@]}"; do
    if (( delay > 0 )); then
      sleep "${delay}"
    fi

    set +e
    output="$("$@" 2>&1)"
    cmd_status=$?
    set -e

    if (( cmd_status == 0 )); then
      if [[ -n "${output}" ]]; then
        printf '%s\n' "${output}" | tee -a "${run_log}"
      fi
      return 0
    fi

    printf '%s attempt %d failed: %s\n' "${label}" "${attempt}" "${output}" | tee -a "${run_log}" >&2
    if ! is_transient_network_error "${output}"; then
      return "${cmd_status}"
    fi

    attempt=$((attempt + 1))
  done

  return "${cmd_status}"
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
    printf 'GitHub auth file exists but no token was found in %s\n' "${auth_file}" | tee -a "${run_log}" >&2
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

publish_reports() {
  local commit_message="Daily TV monitor: $(date +%F)"
  local -a git_bare=(git "--git-dir=${git_dir}")
  local -a git_common=(git "--git-dir=${git_dir}" "--work-tree=${work_dir}")
  local -a report_files

  mkdir -p "${git_dir}" "${work_dir}"
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
  "${git_bare[@]}" config credential.helper ""

  printf '[%s] Publishing updated reports.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
  run_with_retry "git fetch" "${git_bare[@]}" fetch origin "${branch}" -q

  "${git_bare[@]}" update-ref "refs/heads/${branch}" "refs/remotes/origin/${branch}"
  "${git_bare[@]}" symbolic-ref HEAD "refs/heads/${branch}"
  "${git_common[@]}" reset --hard "origin/${branch}" -q

  mkdir -p "${work_dir}/new_features"
  shopt -s nullglob
  report_files=("${repo_root}"/new_features/*.md)
  shopt -u nullglob

  if (( ${#report_files[@]} == 0 )); then
    printf 'No report files found under %s/new_features.\n' "${repo_root}" | tee -a "${run_log}" >&2
    return 1
  fi

  cp "${report_files[@]}" "${work_dir}/new_features/"

  (
    cd "${work_dir}"
    "${git_common[@]}" add new_features/*.md
  )

  if "${git_common[@]}" diff --cached --quiet; then
    printf '[%s] No report changes to publish.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
    return 0
  fi

  "${git_common[@]}" commit -m "${commit_message}" -q
  run_with_retry "git push" "${git_common[@]}" push origin "${branch}"
  printf '[%s] Publish completed.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
}

sync_local_checkout_if_only_reports_changed() {
  local current_branch=""
  local has_non_report_change=0
  local line path

  if ! git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  current_branch="$(git -C "${repo_root}" branch --show-current 2>/dev/null || true)"
  if [[ "${current_branch}" != "${branch}" ]]; then
    printf '[%s] Skipping local checkout sync; current branch is %s, expected %s.\n' \
      "$(date '+%Y-%m-%d %H:%M:%S %Z')" "${current_branch:-detached}" "${branch}" | tee -a "${run_log}"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    path="${line:3}"
    if [[ "${path}" != new_features/* ]]; then
      has_non_report_change=1
      break
    fi
  done < <(git -C "${repo_root}" status --porcelain=v1 --untracked-files=all)

  if (( has_non_report_change )); then
    printf '[%s] Skipping local checkout sync; non-report changes are present.\n' \
      "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
    return 0
  fi

  if git -C "${repo_root}" diff --quiet && git -C "${repo_root}" diff --cached --quiet &&
    [[ -z "$(git -C "${repo_root}" ls-files --others --exclude-standard -- new_features)" ]]; then
    return 0
  fi

  printf '[%s] Syncing local checkout after report publish.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
  run_with_retry "local git fetch" git -C "${repo_root}" fetch origin "${branch}" -q

  if ! git -C "${repo_root}" merge-base --is-ancestor HEAD "origin/${branch}"; then
    printf '[%s] Skipping local checkout sync; local HEAD is not an ancestor of origin/%s.\n' \
      "$(date '+%Y-%m-%d %H:%M:%S %Z')" "${branch}" | tee -a "${run_log}"
    return 0
  fi

  git -C "${repo_root}" clean -fd -- new_features | tee -a "${run_log}"
  git -C "${repo_root}" reset --hard "origin/${branch}" -q
  printf '[%s] Local checkout synced to origin/%s.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "${branch}" | tee -a "${run_log}"
}

if ! mkdir "${lock_dir}" 2>/dev/null; then
  printf '[%s] Another run is already in progress. Exiting.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
  exit 0
fi

trap cleanup EXIT

if [[ ! -x "${codex_bin}" ]]; then
  printf 'Codex binary not found or not executable: %s\n' "${codex_bin}" | tee -a "${run_log}" >&2
  exit 1
fi

if [[ ! -f "${prompt_file}" ]]; then
  printf 'Prompt file not found: %s\n' "${prompt_file}" | tee -a "${run_log}" >&2
  exit 1
fi

if [[ ! -w "${repo_root}/new_features" ]]; then
  printf 'Report output directory is not writable: %s\n' "${repo_root}/new_features" | tee -a "${run_log}" >&2
  exit 1
fi

printf '[%s] Starting daily TV monitor run.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "${run_log}"
printf 'repo_root=%s\nprompt_file=%s\nmodel=%s\nsandbox=%s\n' "${repo_root}" "${prompt_file}" "${model}" "${codex_sandbox}" | tee -a "${run_log}"

set +e
"${codex_bin}" --search --ask-for-approval never --sandbox "${codex_sandbox}" exec \
  -C "${repo_root}" \
  -m "${model}" \
  --color never \
  -o "${last_message}" \
  - < "${prompt_file}" 2>&1 | tee -a "${run_log}"
cmd_status=${PIPESTATUS[0]}
set -e

printf '[%s] Finished with exit code %s.\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "${cmd_status}" | tee -a "${run_log}"

if (( cmd_status != 0 )); then
  exit "${cmd_status}"
fi

publish_reports
sync_local_checkout_if_only_reports_changed

exit "${cmd_status}"
