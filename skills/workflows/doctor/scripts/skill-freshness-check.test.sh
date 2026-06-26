#!/bin/bash
# ABOUTME: Framework-free tests for skill-freshness-check.sh (throttle + outcome logic).
# ABOUTME: Uses env hooks (fake clock, stub update cmd, temp bundle root + XDG_CACHE_HOME) — no network, no real time.
#
# Run:   bash skills/workflows/doctor/scripts/skill-freshness-check.test.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/skill-freshness-check.sh"
NOW=2000000000
NOTE_SUBSTR="Refreshed the Zapier Workflows skills"

pass=0
fail=0

setup() {
  XDG_CACHE_HOME="$(mktemp -d)"
  export XDG_CACHE_HOME
  EMPTY_ROOT="$(mktemp -d)"          # an empty bundle root -> fingerprint never changes
  CACHE_DIR="$XDG_CACHE_HOME/zapier-workflows-doctor"
  KEY="$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" | cksum | awk '{print $1}')"
  MARKER="$CACHE_DIR/$KEY"
}
teardown() { rm -rf "$XDG_CACHE_HOME" "$EMPTY_ROOT"; }

put_marker() { # last_success last_attempt failures
  mkdir -p "$CACHE_DIR"
  printf '%s\n%s\n%s\n' "$1" "$2" "$3" > "$MARKER"
}

# run STUB -> sets RUN_OUT (stdout), RUN_ERR (stderr), RUN_RC (exit code).
# Pins the bundle root to an empty dir so fingerprint stays constant and these
# cases exercise the prose/exit fallback path. The on-disk-change path is Case 12.
run() {
  local stub="$1" errfile
  errfile="$(mktemp)"
  RUN_OUT="$(ZAPIER_WORKFLOWS_DEBUG=1 ZAPIER_WORKFLOWS_DOCTOR_NOW="$NOW" \
             ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT="$EMPTY_ROOT" \
             ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD="$stub" bash "$SCRIPT" 2>"$errfile")"
  RUN_RC=$?
  RUN_ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

ok()  { pass=$((pass+1)); printf '  PASS: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }

want_state()    { case "$RUN_ERR" in *"state=$1"*) ok "state=$1";; *) bad "expected state=$1; stderr=[$RUN_ERR]";; esac; }
want_stdout_has(){ case "$RUN_OUT" in *"$1"*) ok "stdout has [$1]";; *) bad "expected stdout to contain [$1]; got [$RUN_OUT]";; esac; }
want_stdout_empty(){ [ -z "$RUN_OUT" ] && ok "stdout empty" || bad "expected empty stdout; got [$RUN_OUT]"; }
want_rc0()      { [ "$RUN_RC" -eq 0 ] && ok "exit 0" || bad "expected exit 0; got $RUN_RC"; }
want_marker_line(){ local n="$1" exp="$2" got; got="$(sed -n "${n}p" "$MARKER")"; [ "$got" = "$exp" ] && ok "marker L$n=$exp" || bad "marker L$n expected [$exp] got [$got]"; }

STUB_CHANGED='printf "Updated workflows-doctor 1.2.0 -> 1.3.0\n"'
STUB_UNCHANGED='printf "Checking skills from source: zapier/agent-skills\nAll global skills are up to date\n"'
STUB_FAIL='exit 1'
STUB_FAIL_EXIT0='printf "error: network unreachable\n"'

echo "Case 1: missing marker -> prose shows update -> updated + note"
setup; run "$STUB_CHANGED"; want_state updated; want_stdout_has "$NOTE_SUBSTR"; want_rc0; want_marker_line 1 "$NOW"; want_marker_line 3 "0"; teardown

echo "Case 2: missing marker -> update unchanged -> noop, silent"
setup; run "$STUB_UNCHANGED"; want_state noop; want_stdout_empty; want_rc0; want_marker_line 1 "$NOW"; teardown

echo "Case 3: fresh (success 1h ago) -> skipped, no update"
setup; put_marker $((NOW-3600)) $((NOW-3600)) 0; run "$STUB_CHANGED"; want_state skipped; want_stdout_empty; want_rc0; teardown

echo "Case 4: bursting, attempt 10m ago -> skipped (cooldown)"
setup; put_marker $((NOW-90000)) $((NOW-600)) 1; run "$STUB_CHANGED"; want_state skipped; want_stdout_empty; teardown

echo "Case 5: bursting, attempt 20m ago -> due -> failure, count=2, silent"
setup; put_marker $((NOW-90000)) $((NOW-1200)) 1; run "$STUB_FAIL"; want_state failed; want_stdout_empty; want_rc0; want_marker_line 2 "$NOW"; want_marker_line 3 "2"; teardown

echo "Case 6: exhausted, attempt 2h ago -> skipped (daily fallback)"
setup; put_marker $((NOW-200000)) $((NOW-7200)) 3; run "$STUB_CHANGED"; want_state skipped; want_stdout_empty; teardown

echo "Case 7: exhausted, attempt 25h ago -> due -> success resets count"
setup; put_marker $((NOW-200000)) $((NOW-90000)) 3; run "$STUB_UNCHANGED"; want_state noop; want_rc0; want_marker_line 1 "$NOW"; want_marker_line 3 "0"; teardown

echo "Case 8: corrupt marker -> treated as due"
setup; mkdir -p "$CACHE_DIR"; printf 'garbage\n\nxyz\n' > "$MARKER"; run "$STUB_UNCHANGED"; want_state noop; want_rc0; teardown

echo "Case 9: not in a git repo -> pwd fallback, exits 0"
setup; nonrepo="$(mktemp -d)"; ( cd "$nonrepo" && ZAPIER_WORKFLOWS_DEBUG=1 ZAPIER_WORKFLOWS_DOCTOR_NOW="$NOW" ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT="$EMPTY_ROOT" ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD="$STUB_UNCHANGED" bash "$SCRIPT" >/dev/null 2>&1 ); rc=$?; [ "$rc" -eq 0 ] && ok "non-repo exit 0" || bad "non-repo exit $rc"; rm -rf "$nonrepo"; teardown

echo "Case 10: update fails -> still exit 0"
setup; run "$STUB_FAIL"; want_rc0; teardown

echo "Case 11: exit 0 but output shows an error -> failed (output-based detection)"
setup; run "$STUB_FAIL_EXIT0"; want_state failed; want_stdout_empty; want_rc0; want_marker_line 3 "1"; teardown

echo "Case 12: bundle files change on disk -> updated, even with '0 errors' in output (fingerprint beats prose)"
setup; fproot="$(mktemp -d)"; mkdir -p "$fproot/workflows-doctor"; printf 'version: 1\n' > "$fproot/workflows-doctor/SKILL.md"
stub="printf 'syncing skills, 0 errors\n'; printf 'version: 2\n' > '$fproot/workflows-doctor/SKILL.md'"
errfile="$(mktemp)"
RUN_OUT="$(ZAPIER_WORKFLOWS_DEBUG=1 ZAPIER_WORKFLOWS_DOCTOR_NOW="$NOW" ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT="$fproot" ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD="$stub" bash "$SCRIPT" 2>"$errfile")"
RUN_RC=$?; RUN_ERR="$(cat "$errfile")"; rm -f "$errfile"
want_state updated; want_stdout_has "$NOTE_SUBSTR"; want_rc0; want_marker_line 1 "$NOW"; want_marker_line 3 "0"
rm -rf "$fproot"; teardown

echo "Case 13: update runs from the scope root containing the install dir (not the invocation dir)"
setup
scope="$(mktemp -d)"
mkdir -p "$scope/.agents/skills/workflows-doctor"   # install root = $scope/.agents/skills
cwdfile="$(mktemp)"
stub="pwd -P > '$cwdfile'"
( cd / && ZAPIER_WORKFLOWS_DEBUG=1 ZAPIER_WORKFLOWS_DOCTOR_NOW="$NOW" \
    ZAPIER_WORKFLOWS_DOCTOR_BUNDLE_ROOT="$scope/.agents/skills" \
    ZAPIER_WORKFLOWS_DOCTOR_UPDATE_CMD="$stub" bash "$SCRIPT" >/dev/null 2>&1 )
got="$(cat "$cwdfile")"
want="$(cd "$scope" && pwd -P)"
[ "$got" = "$want" ] && ok "update cwd = scope root ($want)" || bad "expected update cwd [$want]; got [$got]"
rm -rf "$scope" "$cwdfile"; teardown

echo ""
echo "TOTAL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
