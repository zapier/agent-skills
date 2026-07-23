---
name: workflows-modify
description: Modify and republish an existing durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks to fix my Zap, update my Zap, modify my workflow, repair this Zap, or edit a deployed Zapier workflow.
license: MIT
metadata:
  author: zapier
  version: "2.0.0"
  sdk_cli_min: "0.55.0"
  sdk_cli_validated: "0.55.0"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Modify

Modifying a deployed workflow follows a discovery, resolve-draft, fetch, edit, publish, verify pattern. All edits and publishes go through the workflow's **draft** — the server-side working copy shared with the Zapier editor. Publishing writes to the user's Zapier account, so get explicit confirmation before publishing.

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`. Do not use `publish-workflow-version` — every publish goes through the draft.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Step 1: Identify The Workflow

If the user provides a workflow ID, use it directly. Otherwise list workflows and find the matching one by name or description:

```bash
zapier-sdk --experimental list-workflows --json
```

If multiple workflows match, show candidates and ask the user which one to modify.

## Step 2: Resolve The Draft

Every workflow edit happens in a draft. Find the open one:

```bash
zapier-sdk --experimental list-workflow-drafts <workflow-id> --json
```

The list returns open drafts, most recently edited first.

- **An open draft exists:** use the most recently edited one. An open draft always holds unpublished work (publishing consumes drafts, so a leftover one was never published) — your change applies on top of it. If several are open, tell the user and confirm which to use.
- **No open draft:** create one, forked from the workflow's current live version:

```bash
zapier-sdk --experimental create-workflow-draft <workflow-id> --json
```

## Step 3: Fetch The Draft

```bash
zapier-sdk --experimental get-workflow-draft <workflow-id> <draft-id> --json
```

Capture:

- `source_files`, especially `source_files["workflow.ts"]` — this may contain unpublished edits; treat it as the user's in-progress work, not stale data.
- `draft_revision` — needed for optimistic concurrency on every write.
- `dependencies`, `zapier_durable_version`, `trigger`, `connections`, and `app_versions`.

Also fetch the workflow itself for its name, enabled state, and metadata:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
```

**Check for unpublished draft changes.** Publishing the draft publishes *everything* in it, not just your edit — so you must know whether the draft already diverges from what's live. Skip this when you just created the draft in Step 2 (a fresh fork is identical to its base). Otherwise fetch the draft's base version and compare:

```bash
zapier-sdk --experimental get-workflow-version <workflow-id> <base_version_id from the draft> --json
```

If the draft's `source_files`, trigger, connections, or app versions differ from the base version, the draft holds unpublished work. Note a short summary of the differences — you'll surface it at confirmation time in Step 6. Never silently publish it and never silently discard it.

**Check the draft isn't stale.** A draft forks from the live version at creation, but the live version can move past it — another open draft may have published, or someone force-published around the drafts. Publishing a stale draft ships its old base content over everything the newer versions changed. Skip this too when you just created the draft; otherwise list the versions and compare the newest version's `id` to the draft's `base_version_id`:

```bash
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

- **Base is the newest version:** not stale — continue.
- **Stale, with no unpublished changes** (the divergence check above found none): the draft is a leftover shell of an old version. Do not build on it — discard it, fork a fresh draft from live, tell the user you did, and continue Steps 3–4 on the fresh draft:

  ```bash
  zapier-sdk --experimental discard-workflow-draft <workflow-id> <draft-id> --json
  zapier-sdk --experimental create-workflow-draft <workflow-id> --json
  ```

- **Stale, with unpublished changes:** stop and tell the user. Publishing this draft as-is would revert everything in the versions published since it was forked. The safe path is forking a fresh draft from live and porting the draft's unpublished changes (plus your edit) onto it — offer to do that, and get an explicit choice between porting and publishing the stale draft anyway. Never pick for them.

## Step 4: Make The Edit

Prefer editing an existing local workflow file if one exists. Otherwise, write `source_files["workflow.ts"]` into a local `workflow.ts` in a workflow-specific directory and edit that copy.

Apply the requested change narrowly. Preserve existing Zod schemas, `ctx.step` boundaries, connection aliases, dependency pins, durable runtime version, connection bindings, app-version bindings, trigger configuration, and visibility/enabled state unless there is a reason to change them. Preserve any unpublished draft content that isn't part of the requested change.

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
  --dependencies '<deps from the fetched draft>' \
  --zapier-durable-version '<durable version from the fetched draft>' \
  --connections '<connection bindings JSON if needed>' \
  --input '<synthetic input JSON>' \
  --private
```

For synthetic `run-durable` tests, reuse the fetched draft's connection bindings as-is — they're already the nested object shape `{ "alias": { "connectionId": "..." } }` that `run-durable` accepts. Do not flatten to a bare string like `{ "alias": "id" }`; that fails with `expected object, received string`.

If the run returns a run ID, inspect it when needed:

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

## Step 6: Confirm, Then Save And Publish

Before publishing, summarize for the user:

1. The diagnosis.
2. The code or config change.
3. The workflow ID and draft being updated.
4. The values being preserved, including dependencies, durable version, enabled state, connections, app versions, and trigger configuration.
5. **Any unpublished draft changes found in Step 3.** Publishing the draft ships those too. Ask the user explicitly: include them in this publish, or start clean?
   - **Include:** proceed as written — the draft content plus your edit publishes together.
   - **Start clean:** discard the draft and fork a fresh one from the live version, then re-apply your edit on the fresh draft (re-run Steps 3–4 against it):

     ```bash
     zapier-sdk --experimental discard-workflow-draft <workflow-id> <draft-id> --json
     zapier-sdk --experimental create-workflow-draft <workflow-id> --json
     ```

     Discard-and-refork is the only sanctioned way to drop unpublished work — never overwrite draft content in place to get rid of it.

Wait for explicit confirmation before publishing.

Build `source_files`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

Save the edit into the draft, passing the `draft_revision` from your read:

```bash
zapier-sdk --experimental update-workflow-draft <workflow-id> <draft-id> "$SOURCE_FILES" \
  --draft-revision <draft_revision from Step 3> \
  --json
```

Omitted fields keep their stored draft values, so only pass `--trigger`, `--connections`, `--app-versions`, `--dependencies`, or `--zapier-durable-version` when the edit changes them. Passing `null` for `--trigger`, `--connections`, or `--app-versions` clears the stored value — never do that to "skip" a field.

The update response returns the new `draft_revision`. Publish with it:

```bash
zapier-sdk --experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <draft_revision from the update response> \
  --json
```

Publishing the draft creates a new immutable version, advances the live pointer, and **discards the draft** — publish consumes it, so an open draft always means unpublished work. The response contains both the new `version` and the consumed `draft` (`status: "discarded"`). Any further modification starts back at Step 2 and forks a fresh draft from the just-published version.

Publish preserves the workflow's current enabled state when `--enabled` is omitted. Omit it unless the user asked to change the enabled state.

**On a conflict (revision mismatch):** someone edited the draft between your read and your write — likely the user, in the editor. Never blind-overwrite. Re-read the draft (`get-workflow-draft`), re-apply your change on top of the fresh `source_files`, and retry with the new `draft_revision`. If the fresh content conflicts materially with your change, stop and ask the user.

## Step 7: Verify

Read back the workflow and versions:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

Confirm the newest version reflects the publish, the workflow is still enabled if it should be, and trigger/connection/app-version metadata was preserved. The publish response's `draft.status` should be `discarded` — publish consumed the draft, so no open draft is left behind for the editor (or a later agent session) to resurrect stale content from. Check the matching entry in `triggers[]` for `details.webhook_url`, regardless of trigger type — if present, it's the catch URL external services call and is meant to be shared, unlike the workflow-level `trigger_url`; most triggers have none, and that is normal. If the change is hard to validate without a live trigger fire, tell the user exactly what test event to send and what result to expect.

Finish by reporting:

- Workflow name and ID.
- Whether the requested change was published.
- Whether trigger, connection, and app-version metadata were preserved.
- Whether the workflow is enabled.
- The trigger's `webhook_url`, if present.
- The Zapier editor link: `https://zapier.com/durables-editor/<workflow-id>`.

## Reverting

Previous versions remain available as read-only history. To revert, fetch the prior version's source:

```bash
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
zapier-sdk --experimental get-workflow-version <workflow-id> <version-id> --json
```

Then publish it like any other change: load the prior version's `source_files` (and its trigger/connection/app-version/dependency metadata, if it differs from the draft's) into the draft with `update-workflow-draft`, and publish with `publish-workflow-draft` — same confirmation and conflict handling as Step 6.
