---
name: workflows-modify
description: Modify and republish an existing durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks to fix my Zap, update my Zap, modify my workflow, repair this Zap, or edit a deployed Zapier workflow.
license: MIT
metadata:
  author: zapier
  version: "1.2.0"
  sdk_cli_min: "0.55.0"
  sdk_cli_validated: "0.55.0"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Modify

Modifying a deployed workflow follows a discovery, resolve, fetch, edit, publish, verify pattern. Publishing writes to the user's Zapier account, so get explicit confirmation before publishing.

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

**Core invariant: never publish past an open draft.** A workflow may have an open server draft holding the user's unpublished editor work. Publishing a version directly while a draft is open orphans that work — the draft is not rebased, so the editor later resolves the stale draft *over* the new version and the user's or agent's change appears to revert. Always resolve drafts first (Step 2) and publish through the draft when one exists.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Step 1: Identify The Workflow

If the user provides a workflow ID, use it directly. Otherwise list workflows and find the matching one by name or description:

```bash
zapier-sdk --experimental list-workflows --json
```

If multiple workflows match, show candidates and ask the user which one to modify.

## Step 2: Resolve The Working Copy (Drafts First)

Check for open drafts before reading any version. This is the same resolution the Zapier editor uses:

```bash
zapier-sdk --experimental list-workflow-drafts <workflow-id> --json
```

The list returns open drafts, most recently edited first.

- **One or more open drafts → use the draft path** (Steps 3A/5A). Work in the most recently edited draft. If several are open, tell the user the others exist and confirm which one to use.
- **No open drafts → use the version path** (Steps 3B/5B). Publishing a version directly is legitimate only in this case, and only because you checked first. Do not assume the server enforces this for you.

## Step 3A: Fetch The Draft (Draft Path)

```bash
zapier-sdk --experimental get-workflow-draft <workflow-id> <draft-id> --json
```

Capture:

- `source_files`, especially `source_files["workflow.ts"]` — this may contain the user's unpublished edits. Your change applies **on top of** this content, not on top of the published version.
- `draft_revision` — needed for optimistic concurrency on every write.
- `dependencies`, `zapier_durable_version`, `trigger`, `connections`, `app_versions`, and the draft's `base_version_id`.

Also fetch the workflow itself for `enabled` state and metadata:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
```

## Step 3B: Fetch The Current Version (Version Path)

Run these reads, then preserve the current metadata before changing anything:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

From the versions list, pick the current or newest version ID, then fetch it:

```bash
zapier-sdk --experimental get-workflow-version <workflow-id> <version-id> --json
```

Capture:

- `source_files`, especially `source_files["workflow.ts"]`.
- `dependencies`.
- `zapier_durable_version`.
- `enabled`.
- Any `connections`, `app_versions`, `trigger`, or workflow metadata present in the workflow or version response.

## Step 4: Make The Edit

Prefer editing an existing local workflow file if one exists. Otherwise, write `source_files["workflow.ts"]` into a local `workflow.ts` in a workflow-specific directory and edit that copy.

Apply the requested change narrowly. Preserve existing Zod schemas, `ctx.step` boundaries, connection aliases, dependency pins, durable runtime version, publish connection bindings, app-version bindings, trigger configuration, and visibility/enabled state unless there is a reason to change them. On the draft path, also preserve any unpublished draft content that isn't part of the requested change — it is the user's in-progress work, not stale data.

When the edit adds a new AI/LLM step, follow `workflows-create` Phase 2: always use "AI by Zapier" (`AICLIAPI`, action `get_completion`) and select the model with `model_id` — the user's named provider/model if they gave one, otherwise the default `"advanced/auto"` with built-in credentials (`authentication_id: "0"`). Only use a raw-provider AI app if the user explicitly asks for that standalone app or needs a capability AI by Zapier lacks.

## Step 5: Optional Synthetic Test

For non-trivial changes, propose a test run before publishing. This may run real downstream actions, so summarize side effects and wait for confirmation.

Build `source_files` from the local file:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

Run the workflow:

```bash
zapier-sdk --experimental run-durable "$SOURCE_FILES" \
  --dependencies '<deps from fetched draft or version>' \
  --zapier-durable-version '<durable version from fetched draft or version>' \
  --connections '<connection bindings JSON if needed>' \
  --input '<synthetic input JSON>' \
  --private
```

For synthetic `run-durable` tests, reuse the fetched connection bindings as-is — they're already the nested object shape `{ "alias": { "connectionId": "..." } }` that `run-durable` and the publish commands accept. Do not flatten to a bare string like `{ "alias": "id" }`; that fails with `expected object, received string`.

If the run returns a run ID, inspect it when needed:

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

## Step 6: Confirm, Then Publish

Before publishing, summarize for the user:

1. The diagnosis.
2. The code or config change.
3. The workflow ID being updated, and whether the change goes through an open draft.
4. The values that will be preserved, including dependencies, durable version, enabled state, connections, app versions, and trigger configuration.

Wait for explicit confirmation before publishing.

Build `source_files`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

### Step 6A: Save And Publish The Draft (Draft Path)

Save the edit into the draft, passing the `draft_revision` from your read:

```bash
zapier-sdk --experimental update-workflow-draft <workflow-id> <draft-id> "$SOURCE_FILES" \
  --draft-revision <draft_revision from Step 3A> \
  --json
```

Only pass `--trigger`, `--connections`, `--app-versions`, `--dependencies`, or `--zapier-durable-version` when the edit changes them — omitted fields keep their stored draft values.

The update response returns the new `draft_revision`. Publish with it:

```bash
zapier-sdk --experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <draft_revision from the update response> \
  --json
```

Publishing a draft creates a new immutable version, advances the live pointer, and rebases the draft onto the new version — the draft stays open and nothing is orphaned. The response contains both the new `version` and the rebased `draft`.

`publish-workflow-draft` preserves the workflow's current enabled state when `--enabled` is omitted. Omit it unless the user asked to change the enabled state.

**On a conflict (revision mismatch):** someone edited the draft between your read and your write — likely the user, in the editor. Never blind-overwrite. Re-read the draft (`get-workflow-draft`), re-apply your change on top of the fresh `source_files`, and retry with the new `draft_revision`. If the fresh content conflicts materially with your change, stop and ask the user.

### Step 6B: Publish A Version (Version Path — No Open Draft Only)

```bash
zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '<deps from fetched version>' \
  --zapier-durable-version '<durable version from fetched version>' \
  --connections '<connection bindings from fetched version>' \
  --app-versions '<app version bindings from fetched version>' \
  --trigger '<trigger config from fetched version>' \
  --json
```

`--enabled` is a no-argument boolean switch, not a flag that takes a value: `--enabled false` is parsed as bare `--enabled` (enabling the workflow) with a stray `false` token that is silently dropped, `--enabled=false` and `--no-enabled` are both rejected as unknown options. There is no way to publish directly into a disabled state.

If the workflow was enabled before the edit, either omit `--enabled` or pass bare `--enabled` — publish defaults to enabled either way. If the workflow was disabled before the edit, publish normally (it will come back enabled) and then immediately call `disable-workflow <workflow-id>` to restore the disabled state:

```bash
zapier-sdk --experimental disable-workflow <workflow-id> --json
```

Do not skip this step — a disabled workflow that gets republished without it will accidentally go live.

Omit `--connections`, `--app-versions`, or `--trigger` only when the fetched metadata confirms the workflow version does not use that field. If the fetched metadata includes trigger, connection, or app-version configuration but the shape cannot be mapped to the current publish flags, stop before publishing and tell the user the workflow needs SDK confirmation rather than silently dropping metadata.

Do not use the old trigger republish flags (`--trigger-app`, `--trigger-action`, `--trigger-auth`, `--trigger-params`). The current trigger publish path is the single JSON `--trigger` object.

**If the publish is rejected with a conflict listing open drafts:** a draft was opened between Step 2 and now. Switch to the draft path (Steps 3A/6A) against the listed draft. Never bypass the rejection (`ignore_open_drafts`) unless the user explicitly confirms they want to publish past their own draft.

## Step 7: Verify

Read back the workflow and versions:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

Confirm the newest version reflects the publish, the workflow is still enabled if it should be, and trigger/connection/app-version metadata was preserved. On the draft path, the publish response's `draft.base_version_id` should equal the new `version.id` — that confirms the draft was rebased and the user's editor won't resurrect stale content. Check the matching entry in `triggers[]` for `details.webhook_url`, regardless of trigger type — if present, it's the catch URL external services call and is meant to be shared, unlike the workflow-level `trigger_url`; most triggers have none, and that is normal. If the change is hard to validate without a live trigger fire, tell the user exactly what test event to send and what result to expect.

Finish by reporting:

- Workflow name and ID.
- Whether the requested change was published, and whether it went through a draft.
- Whether trigger, connection, and app-version metadata were preserved.
- Whether the workflow is enabled.
- The trigger's `webhook_url`, if present.
- The Zapier editor link: `https://zapier.com/durables-editor/<workflow-id>`.

## Reverting

Previous versions remain available. To revert, fetch the prior version's source with `get-workflow-version`, then publish it through the same drafts-first resolution as any other change: if an open draft exists, load the prior version's `source_files` into the draft (`update-workflow-draft`) and publish via `publish-workflow-draft`; otherwise use the `publish-workflow-version` pattern above. Preserve dependency, durable version, connection, app-version, trigger, and enabled-state metadata either way.
