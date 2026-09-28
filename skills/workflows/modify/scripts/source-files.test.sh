#!/bin/bash
# ABOUTME: Framework-free tests for source-files.sh (fetch/write/edit/build round trip, dropped-file detection, structural gates).
# ABOUTME: Builds throwaway workflow directories under a temp root — no network, no SDK CLI, no Zapier account.
#
# Run:   bash skills/workflows/modify/scripts/source-files.test.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/source-files.sh"
CREATE_COPY="$SCRIPT_DIR/../../create/scripts/source-files.sh"

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  PASS: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }

# A multi-file workflow as it exists locally: entrypoint, nested helper, and the
# local-only package.json the create skill tells the agent to write.
make_workflow() {
  WF="$(mktemp -d)"
  mkdir -p "$WF/lib"
  printf 'import { formatRow } from "./lib/format.ts";\nexport default 1;\n' > "$WF/workflow.ts"
  printf 'export function formatRow(r) { return r; }\n' > "$WF/lib/format.ts"
  printf '{"type":"module"}\n' > "$WF/package.json"
}
drop_workflow() { rm -rf "$WF"; }

# A source_files map as the platform returns it: note lib/format.ts has no
# trailing newline, so a write-out that adds one corrupts it.
FETCHED='{
  "workflow.ts": "import { formatRow } from \"./lib/format.ts\";\nexport default 1;\n",
  "lib/format.ts": "export function formatRow(r) { return r; }",
  "prompts/summarize.md": "Summarise the row.\n"
}'

# run <args...> -> RUN_OUT (stdout), RUN_ERR (stderr), RUN_RC (exit code)
run() {
  local errfile
  errfile="$(mktemp)"
  RUN_OUT="$(bash "$SCRIPT" "$@" 2>"$errfile")"
  RUN_RC=$?
  RUN_ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

want_rc()        { [ "$RUN_RC" -eq "$1" ] && ok "exit $1" || bad "expected exit $1; got $RUN_RC; stderr=[$RUN_ERR]"; }
want_keys()      { local got; got="$(printf '%s' "$RUN_OUT" | jq -cr 'keys')"; [ "$got" = "$1" ] && ok "keys $1" || bad "expected keys $1; got $got"; }
want_err_has()   { case "$RUN_ERR" in *"$1"*) ok "stderr has [$1]";; *) bad "expected stderr to contain [$1]; got [$RUN_ERR]";; esac; }
want_out_empty() { [ -z "$RUN_OUT" ] && ok "stdout empty" || bad "expected empty stdout; got [$RUN_OUT]"; }

echo "Case 1: build a multi-file workflow -> every source file in the map, package.json excluded"
make_workflow
run build "$WF"
want_rc 0
want_keys '["lib/format.ts","workflow.ts"]'
body="$(printf '%s' "$RUN_OUT" | jq -r '."lib/format.ts"')"
[ "$body" = 'export function formatRow(r) { return r; }' ] && ok "helper body round-trips verbatim" || bad "helper body mangled: [$body]"
drop_workflow

echo "Case 2: THE REGRESSION — fetch, write, edit one file, rebuild: helper survives byte-exact"
WF="$(mktemp -d)"
run write "$WF" --from "$FETCHED"
want_rc 0
want_err_has "wrote 3 file(s)"
[ -f "$WF/lib/format.ts" ] && ok "nested helper written to its own path" || bad "lib/format.ts not written"
[ -f "$WF/prompts/summarize.md" ] && ok "non-code source file written too" || bad "prompts/summarize.md not written"
# Edit only the entrypoint, exactly as a modify would.
printf 'import { formatRow } from "./lib/format.ts";\nexport default 2; // fixed\n' > "$WF/workflow.ts"
run build "$WF" --base "$FETCHED"
want_rc 0
want_keys '["lib/format.ts","prompts/summarize.md","workflow.ts"]'
want_err_has "preserved 3 file(s), edited 1"
# The two untouched files must be byte-identical to what was fetched, so a
# round trip through disk is not itself an edit.
for key in "lib/format.ts" "prompts/summarize.md"; do
  before="$(printf '%s' "$FETCHED" | jq -r --arg k "$key" '.[$k]')"
  after="$(printf '%s' "$RUN_OUT" | jq -r --arg k "$key" '.[$k]')"
  [ "$before" = "$after" ] && ok "$key unchanged through the round trip" || bad "$key changed: [$before] -> [$after]"
done
drop_workflow

echo "Case 3: helper deleted locally -> dropped file detected, nothing printed to stdout"
make_workflow
BASE="$(bash "$SCRIPT" build "$WF" 2>/dev/null)"
rm "$WF/lib/format.ts"
run build "$WF" --base "$BASE"
want_rc 1
want_out_empty
want_err_has "leaves out or empties: lib/format.ts"
drop_workflow

echo "Case 4: helper blanked rather than deleted -> still counts as dropped"
make_workflow
BASE="$(bash "$SCRIPT" build "$WF" 2>/dev/null)"
printf '\n  \n' > "$WF/lib/format.ts"
run build "$WF" --base "$BASE"
want_rc 1
want_err_has "leaves out or empties: lib/format.ts"
drop_workflow

echo "Case 5: new helper added -> allowed, and reported at confirmation time"
make_workflow
BASE="$(bash "$SCRIPT" build "$WF" 2>/dev/null)"
printf 'export const RETRIES = 3;\n' > "$WF/lib/config.ts"
run build "$WF" --base "$BASE"
want_rc 0
want_keys '["lib/config.ts","lib/format.ts","workflow.ts"]'
want_err_has "added lib/config.ts"
drop_workflow

echo "Case 6: a map argument accepts a file path and stdin, not just inline JSON"
make_workflow
basefile="$(mktemp)"
bash "$SCRIPT" build "$WF" 2>/dev/null > "$basefile"
run build "$WF" --base "$basefile"
want_rc 0
errfile="$(mktemp)"
RUN_OUT="$(bash "$SCRIPT" build "$WF" --base - < "$basefile" 2>"$errfile")"; RUN_RC=$?; RUN_ERR="$(cat "$errfile")"; rm -f "$errfile"
want_rc 0
want_keys '["lib/format.ts","workflow.ts"]'
rm -f "$basefile"; drop_workflow

echo "Case 7: whole version response passed as the map -> rejected by shape"
make_workflow
run build "$WF" --base '{"id":"v1","source_files":{"workflow.ts":"x"}}'
want_rc 1
want_err_has "whole version or draft response"
run build "$WF" --base '["workflow.ts"]'
want_rc 1
want_err_has "not a source_files map"
run write "$WF" --from '{}'
want_rc 1
want_err_has "map is empty"
drop_workflow

echo "Case 8: nested path depth preserved exactly"
WF="$(mktemp -d)"; mkdir -p "$WF/lib/util"
printf 'export default 1;\n' > "$WF/workflow.ts"
printf 'export const a = 1;\n' > "$WF/lib/util/deep.ts"
run build "$WF"
want_rc 0
want_keys '["lib/util/deep.ts","workflow.ts"]'
drop_workflow

echo "Case 9: node_modules and dist pruned, *.d.ts and lockfiles skipped"
WF="$(mktemp -d)"; mkdir -p "$WF/node_modules/zod" "$WF/dist"
printf 'export default 1;\n' > "$WF/workflow.ts"
printf 'module.exports = {};\n' > "$WF/node_modules/zod/index.js"
printf 'export default 1;\n' > "$WF/dist/workflow.js"
printf 'declare const x: number;\n' > "$WF/types.d.ts"
printf 'lockfileVersion: 9\n' > "$WF/pnpm-lock.yaml"
run build "$WF"
want_rc 0
want_keys '["workflow.ts"]'
drop_workflow

echo "Case 10: no entrypoint -> refused before any publish attempt"
WF="$(mktemp -d)"
printf 'export const a = 1;\n' > "$WF/main.ts"
run build "$WF"
want_rc 1
want_err_has "no workflow entrypoint"
drop_workflow

echo "Case 11: two entrypoints -> refused (the platform allows exactly one)"
WF="$(mktemp -d)"
printf 'export default 1;\n' > "$WF/workflow.ts"
printf 'export default 1;\n' > "$WF/workflow.mjs"
run build "$WF"
want_rc 1
want_err_has "several workflow entrypoints"
drop_workflow

echo "Case 12: a .mjs entrypoint is a valid entrypoint (not every workflow is workflow.ts)"
WF="$(mktemp -d)"; mkdir -p "$WF/lib"
printf 'export default 1;\n' > "$WF/workflow.mjs"
printf 'export const a = 1;\n' > "$WF/lib/helper.mjs"
run build "$WF"
want_rc 0
want_keys '["lib/helper.mjs","workflow.mjs"]'
drop_workflow

echo "Case 13: reserved root index.* refused, nested lib/index.ts allowed"
WF="$(mktemp -d)"
printf 'export default 1;\n' > "$WF/workflow.ts"
printf 'export const a = 1;\n' > "$WF/index.ts"
run build "$WF"
want_rc 1
want_err_has "reserved filenames"
drop_workflow
WF="$(mktemp -d)"; mkdir -p "$WF/lib"
printf 'export default 1;\n' > "$WF/workflow.ts"
printf 'export const a = 1;\n' > "$WF/lib/index.ts"
run build "$WF"
want_rc 0
want_keys '["lib/index.ts","workflow.ts"]'
drop_workflow

echo "Case 14: paths with spaces survive the walk and the map build"
WF="$(mktemp -d)"; mkdir -p "$WF/my lib"
printf 'export default 1;\n' > "$WF/workflow.ts"
printf 'export const a = 1;\n' > "$WF/my lib/two words.ts"
run build "$WF"
want_rc 0
want_keys '["my lib/two words.ts","workflow.ts"]'
drop_workflow

echo "Case 15: empty directory and a missing directory both fail loudly"
WF="$(mktemp -d)"
run build "$WF"
want_rc 1
want_err_has "no source files found"
drop_workflow
run build "/nonexistent-$$-workflow-dir"
want_rc 1
want_err_has "not a directory"

echo "Case 16: write refuses a key that escapes the workflow directory"
WF="$(mktemp -d)"
run write "$WF" --from '{"workflow.ts":"x","../escape.ts":"y"}'
want_rc 1
want_err_has "escapes the workflow directory"
[ -f "$WF/../escape.ts" ] && bad "wrote outside the workflow directory" || ok "nothing written outside the directory"
drop_workflow

echo "Case 17: a bad command or missing argument prints usage"
run frobnicate "$SCRIPT_DIR"
want_rc 1
want_err_has "unknown command"
run write "/tmp/whatever-$$"
want_rc 1
want_err_has "write needs --from"

echo "Case 18: workflows-create ships a byte-identical copy of the script"
if [ -f "$CREATE_COPY" ]; then
  cmp -s "$SCRIPT" "$CREATE_COPY" && ok "create/scripts copy is identical" \
    || bad "create/scripts/source-files.sh has drifted from modify/scripts/source-files.sh"
else
  bad "missing create/scripts/source-files.sh (each skill must ship the script it tells the agent to run)"
fi

echo ""
echo "TOTAL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
