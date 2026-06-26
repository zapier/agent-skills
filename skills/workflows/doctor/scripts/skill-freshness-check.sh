#!/bin/bash
# ABOUTME: Skill-freshness check for the Zapier Workflows skill bundle.
# ABOUTME: Throttled (~daily) best-effort `npx skills update`; ALWAYS exits 0, never blocks the caller.
#
# Invoked by workflows-doctor "Step 0". Soft and non-blocking by design.
# DELIBERATELY no `set -e` (the repo's usual convention): a failure here must
# never abort the worker skill that ran the doctor. Every path ends with exit 0.
#
# Env hooks:
#   ZAPIER_WORKFLOWS_DEBUG=1                   verbose decision log -> stderr (bundle-wide flag)
#   ZAPIER_WORKFLOWS_DOCTOR_NOW=<epoch>        override the clock (tests)
#   ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD=<cmd>   override the update command (tests)
#   ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT=<dir>  override the fingerprint root (tests)
#   XDG_CACHE_HOME=<dir>                       override cache root (tests / XDG)

DAILY=86400
BURST_COOLDOWN=900
MAX_FAILURES=3
UPDATE_NOTE="Refreshed the Zapier Workflows skills; the updates take full effect the next time you reload this workspace."
DEFAULT_UPDATE_CMD="npx --yes skills update workflows-install workflows-doctor workflows-create workflows-list workflows-history workflows-modify -y"

debug() {
  if [ "${ZAPIER_WORKFLOWS_DEBUG:-}" = "1" ]; then
    printf '[workflows-doctor freshness] %s\n' "$*" >&2
  fi
  return 0
}

now_epoch() {
  if [ -n "${ZAPIER_WORKFLOWS_DOCTOR_NOW:-}" ]; then
    printf '%s' "$ZAPIER_WORKFLOWS_DOCTOR_NOW"
  else
    date +%s
  fi
}

as_int() {
  case "$1" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$1" ;;
  esac
}

# The installed bundle root. Resolved with `pwd -P` so it works through the
# symlinks the skills CLI creates (~/.claude/skills/<skill> -> ~/.agents/skills/<skill>);
# the skill is installed at <root>/<skill>/scripts/skill-freshness-check.sh.
bundle_root() {
  if [ -n "${ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT:-}" ]; then
    printf '%s' "$ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT"
    return
  fi
  ( cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P )
}

# Working directory for the update command. The `skills` CLI resolves *project*
# skills relative to its CWD -- it only finds skills under a `.agents`/`.claude`
# directory that is a direct child of the working directory. This script is invoked
# from inside a skill subdirectory, so running `npx skills update` there discovers
# no project skills and silently refreshes nothing (exit 0, no on-disk change).
# The install root is `<scope>/.agents/skills` (or the `.claude` equivalent), so the
# scope root the CLI needs is two levels up. Fall back to the current directory when
# that can't be resolved or doesn't look like a scope root (e.g. test fixtures),
# which preserves prior behavior.
scope_root() {
  local install_root="$1" candidate
  candidate="$( cd "$install_root/../.." 2>/dev/null && pwd -P )" || candidate=""
  if [ -n "$candidate" ] && { [ -d "$candidate/.agents" ] || [ -d "$candidate/.claude" ]; }; then
    printf '%s' "$candidate"
  else
    printf '%s' "$PWD"
  fi
}

# Aggregate checksum of every installed workflow skill's SKILL.md. Used to detect
# "did an update actually change anything on disk" -- a signal that cannot misfire
# on CLI wording, unlike output parsing. cksum/find/sort only (bash 3.2-safe; no
# jq/stat/shasum). No matches -> a stable constant, so before==after when nothing changed.
bundle_fingerprint() {
  local root="$1"
  [ -d "$root" ] || { printf '0'; return; }
  find "$root" -maxdepth 3 -path '*workflows*/SKILL.md' -type f -exec cksum {} + 2>/dev/null \
    | sort | cksum | awk '{print $1}'
}

# Primary signal is the fingerprint diff; prose is only a fallback for the rare
# case fingerprinting can't see the change.
decide_outcome() {
  local before="$1" after="$2" rc="$3" out="$4" lc
  if [ "$before" != "$after" ]; then printf 'updated'; return; fi
  if [ "$rc" -ne 0 ]; then printf 'failed'; return; fi
  lc="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
  # `skills update` exits 0 even on its own errors (e.g. "No installed skills
  # found"), so scan output too. The substrings can overlap benign text like
  # "0 errors"; because the fingerprint check ran first, that only flips a silent
  # noop to a (silent) failed -> retry sooner, never suppresses a real update.
  case "$lc" in
    *error*|*"not found"*|*enotfound*|*etimedout*|*network*|*failed*) printf 'failed'; return ;;
  esac
  case "$lc" in
    *updated*|*upgraded*|*added*|*"->"*|*"→"*) printf 'updated'; return ;;
  esac
  printf 'noop'
}

write_marker() {
  printf '%s\n%s\n%s\n' "$2" "$3" "$4" > "$1" 2>/dev/null || true
}

main() {
  local now scope_root key cache_dir marker
  now="$(now_epoch)"
  scope_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  key="$(printf '%s' "$scope_root" | cksum | awk '{print $1}')"
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zapier-workflows-doctor"
  marker="$cache_dir/$key"
  debug "scope_root=$scope_root key=$key marker=$marker now=$now"

  local last_success last_attempt failures l1 l2 l3
  last_success=0; last_attempt=0; failures=0
  if [ -f "$marker" ]; then
    l1=""; l2=""; l3=""
    { IFS= read -r l1; IFS= read -r l2; IFS= read -r l3; } < "$marker"
    last_success="$(as_int "$l1")"
    last_attempt="$(as_int "$l2")"
    failures="$(as_int "$l3")"
  else
    debug "marker missing -> treat as due"
  fi

  local since_success since_attempt due
  since_success=$(( now - last_success ))
  since_attempt=$(( now - last_attempt ))
  due=0
  if [ "$since_success" -lt "$DAILY" ]; then
    due=0
  elif [ "$failures" -ge "$MAX_FAILURES" ]; then
    if [ "$since_attempt" -ge "$DAILY" ]; then due=1; fi
  else
    if [ "$since_attempt" -ge "$BURST_COOLDOWN" ]; then due=1; fi
  fi

  if [ "$due" -ne 1 ]; then
    debug "state=skipped since_success=$since_success since_attempt=$since_attempt failures=$failures"
    exit 0
  fi

  local root run_dir before_fp after_fp update_cmd out rc outcome
  root="$(bundle_root)"
  run_dir="$(scope_root "$root")"
  before_fp="$(bundle_fingerprint "$root")"
  update_cmd="${ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD:-$DEFAULT_UPDATE_CMD}"
  debug "due -> root=$root run_dir=$run_dir before_fp=$before_fp running update: $update_cmd"
  out="$( cd "$run_dir" 2>/dev/null && eval "$update_cmd" 2>&1 )"
  rc=$?
  after_fp="$(bundle_fingerprint "$root")"
  outcome="$(decide_outcome "$before_fp" "$after_fp" "$rc" "$out")"
  debug "state=$outcome rc=$rc after_fp=$after_fp"

  mkdir -p "$cache_dir" 2>/dev/null
  if [ "$outcome" = "failed" ]; then
    failures=$(( failures + 1 ))
    write_marker "$marker" "$last_success" "$now" "$failures"
  else
    write_marker "$marker" "$now" "$now" "0"
  fi

  if [ "$outcome" = "updated" ]; then
    printf '%s\n' "$UPDATE_NOTE"
  fi
  exit 0
}

main "$@"
exit 0
