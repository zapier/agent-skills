#!/bin/bash
# ABOUTME: Writes a fetched source_files map out to a local workflow directory, and rebuilds the complete map from it.
# ABOUTME: The build refuses to drop a file the fetched map has, because publishing replaces source_files wholesale.
#
# Run: bash scripts/source-files.sh write <workflow-dir> --from <json|path|->
#      bash scripts/source-files.sh build <workflow-dir> [--base <json|path|->]
set -eu

PROG="$(basename "$0")"

usage() {
  cat >&2 <<EOF
Usage: bash $PROG write <workflow-dir> --from <json|path|->
       bash $PROG build <workflow-dir> [--base <json|path|->]

write   Writes every entry of a fetched source_files map into <workflow-dir>,
        each at its own key as a relative path, byte for byte. Edit the files in
        place afterwards. Files the map does not have are left alone.

build   Prints the complete source_files map for <workflow-dir> on stdout: a
        JSON object whose keys are paths relative to it, exactly as the platform
        stores them. A one-line summary goes to stderr.

        --base is the map fetched from the version or draft being modified.
        Every file in it must appear in the build with content, or the command
        fails and names the missing ones. Publishing replaces source_files
        wholesale, so an omitted key is a deleted file; this check is what turns
        that into a failed command instead of a broken workflow.

A map argument (--from, --base) takes inline JSON, a file path, or - for stdin.
It is the source_files object itself, not the whole version or draft response:
  zapier-sdk --experimental get-workflow-draft <id> <draft> --json | jq '.source_files'

Excluded from the build's walk: node_modules, dist, coverage, .git, .turbo,
lockfiles, package.json, tsconfig*.json, *.d.ts, *.log. package.json is local
type-checking scaffolding, and the platform rejects it as a reserved filename.
EOF
}

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit 1; }

[ $# -ge 1 ] || { usage; exit 1; }
CMD="$1"; shift
case "$CMD" in
  -h|--help) usage; exit 0 ;;
  write|build) ;;
  *) usage; die "unknown command: $CMD (expected write or build)" ;;
esac

DIR=""
MAP_ARG=""
HAS_MAP=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --from|--base)
      [ $# -ge 2 ] || die "$1 needs a value"
      MAP_ARG="$2"; HAS_MAP=1; shift 2 ;;
    --from=*) MAP_ARG="${1#--from=}"; HAS_MAP=1; shift ;;
    --base=*) MAP_ARG="${1#--base=}"; HAS_MAP=1; shift ;;
    -*) usage; die "unknown option: $1" ;;
    *)
      [ -z "$DIR" ] || die "unexpected argument: $1"
      DIR="$1"; shift ;;
  esac
done

[ -n "$DIR" ] || { usage; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq is required"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Reads a map argument into $WORK/map.json and checks it is a source_files map.
# The common mistake is passing the whole version or draft response, whose
# nested objects would otherwise be read as files.
read_map() {
  if [ "$MAP_ARG" = "-" ]; then
    cat > "$WORK/map.json"
  elif [ -f "$MAP_ARG" ]; then
    cat "$MAP_ARG" > "$WORK/map.json"
  else
    printf '%s' "$MAP_ARG" > "$WORK/map.json"
  fi
  case "$(jq -r '
      if type != "object" then "not_object"
      elif has("source_files") then "wrapped"
      elif length == 0 then "empty"
      elif ([.[] | type] | any(. != "string")) then "not_strings"
      else "ok" end
    ' < "$WORK/map.json" 2>/dev/null || printf 'not_json')" in
    ok) ;;
    wrapped) die "that looks like a whole version or draft response. Pass its source_files map: ... --json | jq '.source_files'" ;;
    empty) die "the map is empty. A published workflow always has at least its entrypoint." ;;
    *) die "not a source_files map (an object of path -> file contents)." ;;
  esac
}

if [ "$CMD" = "write" ]; then
  [ "$HAS_MAP" -eq 1 ] || { usage; die "write needs --from"; }
  read_map
  mkdir -p "$DIR"
  ABS_DIR="$(cd "$DIR" && pwd -P)"
  jq -r 'keys[]' < "$WORK/map.json" > "$WORK/keys"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "$key" in
      /*|*..*) die "refusing to write a path that escapes the workflow directory: $key" ;;
    esac
    mkdir -p "$ABS_DIR/$(dirname "$key")"
    # -j, not -r: -r appends a newline, which would rewrite every file's content
    # and make untouched files read back as edited.
    jq -j --arg key "$key" '.[$key]' < "$WORK/map.json" > "$ABS_DIR/$key"
  done < "$WORK/keys"
  printf 'wrote %s file(s) to %s: %s\n' \
    "$(grep -c . "$WORK/keys")" "$DIR" "$(tr '\n' ' ' < "$WORK/keys")" >&2
  exit 0
fi

# build
[ -d "$DIR" ] || die "not a directory: $DIR"
ABS_DIR="$(cd "$DIR" && pwd -P)"
KEYS="$WORK/keys"
PARTS="$WORK/parts"
: > "$KEYS"
: > "$PARTS"

# Prune build output and tooling directories, then filter tooling files by name.
# Keys keep their nested relative path (lib/format.ts stays lib/format.ts):
# that path is the storage key and what the source's own imports resolve against.
( cd "$ABS_DIR" && find . \
    \( -name node_modules -o -name dist -o -name coverage -o -name .git -o -name .turbo \) -prune -o \
    -type f -print ) \
  | sed 's|^\./||' \
  | LC_ALL=C sort > "$WORK/all"

while IFS= read -r key; do
  [ -n "$key" ] || continue
  case "$key" in
    package.json|package-lock.json|pnpm-lock.yaml|yarn.lock) continue ;;
    tsconfig.json|tsconfig.*.json) continue ;;
    *.d.ts|*.log) continue ;;
    .DS_Store|*/.DS_Store) continue ;;
  esac
  printf '%s\n' "$key" >> "$KEYS"
done < "$WORK/all"

[ -s "$KEYS" ] || die "no source files found in $DIR"

# The platform reserves these names and rejects the publish outright, so fail
# here with the reason rather than sending a request that 400s. Only top-level
# index.* is reserved; a nested lib/index.ts is a legitimate source file.
RESERVED="$(grep -E '^(index\.[^/]+|\.zapierrc)$|(^|/)_zapier_' "$KEYS" || true)"
if [ -n "$RESERVED" ]; then
  die "reserved filenames the platform rejects: $(printf '%s' "$RESERVED" | tr '\n' ' ')
Rename them. Dependencies travel in --dependencies and the runtime in --zapier-durable-version."
fi

# A workflow has exactly one entrypoint: workflow.{ts,mts,js,mjs,cjs,cts}.
# Zero or several is a 400 at publish, and renaming it retargets the workflow.
ENTRYPOINTS="$(grep -E '^workflow\.(ts|mts|js|mjs|cjs|cts)$' "$KEYS" || true)"
ENTRY_COUNT="$(printf '%s' "$ENTRYPOINTS" | grep -c . || true)"
if [ "$ENTRY_COUNT" -eq 0 ]; then
  die "no workflow entrypoint. Exactly one of workflow.ts, workflow.mts, workflow.js, workflow.mjs, workflow.cjs, workflow.cts must be at the top level of $DIR"
fi
if [ "$ENTRY_COUNT" -gt 1 ]; then
  die "several workflow entrypoints: $(printf '%s' "$ENTRYPOINTS" | tr '\n' ' ')
Only one is allowed; name the others something that is not workflow.<extension>."
fi

# jq -Rs raw-slurps the file into one JSON string. Deliberately not --rawfile,
# which needs jq 1.6+; on an older jq it is unrecognised, the arguments are read
# as input files, and parsing TypeScript as JSON yields an empty map through a
# pipeline that looks like it worked.
while IFS= read -r key; do
  jq -Rs --arg path "$key" '{($path): .}' < "$ABS_DIR/$key" >> "$PARTS"
done < "$KEYS"

jq -s 'add' < "$PARTS" > "$WORK/built.json"

if [ "$HAS_MAP" -eq 1 ]; then
  read_map

  # A key present but blanked counts as dropped: it deletes the same code under
  # the same name.
  DROPPED="$(jq -r --slurpfile built "$WORK/built.json" '
    [ to_entries[]
      | select(
          ($built[0][.key] == null)
          or (($built[0][.key] | test("^\\s*$")) and ((.value | test("^\\s*$")) | not))
        )
      | .key ] | join(", ")
  ' < "$WORK/map.json")"

  if [ -n "$DROPPED" ]; then
    die "the build leaves out or empties: $DROPPED
Publishing replaces source_files wholesale, so those files would be deleted from the workflow.
Write every fetched file into $DIR at its own key and rebuild. If a deletion is intended, drop the file from the map you pass to --base and say so at confirmation time."
  fi

  jq -r --slurpfile b "$WORK/built.json" '
    . as $base | $b[0] as $built
    | [ $built | keys[] | select($base[.] == null) ] as $added
    | [ $base  | keys[] | select($built[.] != null and $built[.] != $base[.]) ] as $edited
    | "preserved \($base | length) file(s), edited \($edited | length)"
      + (if ($added | length) > 0 then ", added \($added | join(", "))" else "" end)
  ' < "$WORK/map.json" >&2
else
  printf 'built %s file(s): %s\n' \
    "$(grep -c . "$KEYS")" "$(tr '\n' ' ' < "$KEYS")" >&2
fi

cat "$WORK/built.json"
