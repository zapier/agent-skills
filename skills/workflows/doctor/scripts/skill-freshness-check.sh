#!/bin/bash
# ABOUTME: Track B "skill freshness" check for the Zapier Workflows skill bundle.
# ABOUTME: Throttled (~daily) best-effort `npx skills update`; ALWAYS exits 0, never blocks the caller.
#
# Invoked by workflows-doctor "Step 0". Soft and non-blocking by design.
# DELIBERATELY no `set -e` (the repo's usual convention): a failure here must
# never abort the worker skill that ran the doctor. Every path ends with exit 0.
#
# Env hooks:
#   ZAPIER_WORKFLOWS_DEBUG=1                  verbose decision log -> stderr (bundle-wide flag)
#   ZAPIER_WORKFLOWS_DOCTOR_NOW=<epoch>       override the clock (tests)
#   ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD=<cmd>  override the update command (tests)
#   XDG_CACHE_HOME=<dir>                      override cache root (tests / XDG)

DAILY=86400
BURST_COOLDOWN=900
MAX_FAILURES=3
UPDATE_NOTE="Refreshed the Zapier Workflows skills in the background; the updates take full effect the next time you reload this workspace."
DEFAULT_UPDATE_CMD="npx skills update workflows-install workflows-doctor workflows-create workflows-list workflows-history workflows-modify -y"

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

# Grounded on real `skills update` output (verified against the CLI):
#   noop:     "... All global skills are up to date"   (exit 0)
#   no-match: "No installed skills found matching: X"   (exit 0!) -> exit code is NOT a
#             reliable failure signal, so we also scan output for error markers.
# Biased to silence: only a STRONG positive signal counts as "updated"; ambiguous -> noop.
# 'installed' is deliberately NOT a positive marker -- "No installed skills found"
# contains it and would false-positive.
classify_outcome() {
  local rc="$1" out="$2" lc
  if [ "$rc" -ne 0 ]; then printf 'failed'; return; fi
  lc="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    *error*|*"not found"*|*enotfound*|*etimedout*|*network*|*failed*) printf 'failed'; return ;;
  esac
  case "$lc" in
    *updated*|*upgraded*|*added*|*"->"*|*"→"*) printf 'updated'; return ;;
  esac
  printf 'noop'
}

write_marker() {
  printf '%s\n%s\n%s\n%s\n' "$2" "$3" "$4" "$5" > "$1" 2>/dev/null || true
}

main() {
  local now scope_root key cache_dir marker
  now="$(now_epoch)"
  scope_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  key="$(printf '%s' "$scope_root" | cksum | awk '{print $1}')"
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zapier-workflows-doctor"
  marker="$cache_dir/$key"
  debug "scope_root=$scope_root key=$key marker=$marker now=$now"

  local last_success last_attempt failures version l1 l2 l3 l4
  last_success=0; last_attempt=0; failures=0; version=""
  if [ -f "$marker" ]; then
    l1=""; l2=""; l3=""; l4=""
    { IFS= read -r l1; IFS= read -r l2; IFS= read -r l3; IFS= read -r l4; } < "$marker"
    last_success="$(as_int "$l1")"
    last_attempt="$(as_int "$l2")"
    failures="$(as_int "$l3")"
    version="$l4"
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

  local update_cmd out rc outcome
  update_cmd="${ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD:-$DEFAULT_UPDATE_CMD}"
  debug "due -> running update: $update_cmd"
  out="$(eval "$update_cmd" 2>&1)"
  rc=$?
  outcome="$(classify_outcome "$rc" "$out")"
  debug "state=$outcome rc=$rc"

  mkdir -p "$cache_dir" 2>/dev/null
  if [ "$outcome" = "failed" ]; then
    failures=$(( failures + 1 ))
    write_marker "$marker" "$last_success" "$now" "$failures" "$version"
  else
    write_marker "$marker" "$now" "$now" "0" "$version"
  fi

  if [ "$outcome" = "updated" ]; then
    printf '%s\n' "$UPDATE_NOTE"
  fi
  exit 0
}

main "$@"
exit 0
