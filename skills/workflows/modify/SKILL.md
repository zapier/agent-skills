---
name: workflows-modify
description: Modify and republish an existing durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks to fix my Zap, update my Zap, modify my workflow, repair this Zap, or edit a deployed Zapier workflow.
license: MIT
metadata:
  author: zapier
  version: "2.2.0"
  sdk_cli_min: "0.74.0"  # first @zapier/zapier-sdk-cli with publish-workflow-draft --manual (COSUB-1076)
  sdk_cli_validated: "0.74.0"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Modify

Modifying a deployed workflow follows a discovery, fetch, edit, publish, verify pattern. There are two ways to publish a change, and the user chooses between them:

- **Direct publish** — one `publish-workflow-version` call that creates and activates a new version immediately. Fastest path when the user wants the change live now.
- **Through a draft** — save the change into the workflow's server draft (the working copy shared with the Zapier editor), then either publish the draft or leave it open for the user to review and publish later.

Publishing writes to the user's Zapier account, so get explicit confirmation before publishing either way.

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Step 1: Identify The Workflow

If the user provides a workflow ID, use it directly. Otherwise list workflows and find the matching one by name or description:

```bash
zapier-sdk --experimental list-workflows --json
```

If multiple workflows match, show candidates and ask the user which one to modify.

## Step 2: Check For Open Drafts And Pick The Path

```bash
zapier-sdk --experimental list-workflow-drafts <workflow-id> --json
```

The list returns open drafts, most recently edited first. An open draft always holds unpublished work (publishing consumes drafts, so a leftover one was never published).

- **An open draft exists:** work through the draft. It holds the user's in-progress edits and your change applies on top of it — and a direct publish would be rejected by the server's open-draft guard anyway (see Step 6A). If several are open, tell the user and confirm which to use.
- **No open draft:** both paths are available. If the user's request already implies immediate publish ("fix it and ship it"), direct publish is the shorter path. If they want to review first, work incrementally, or hand off to the editor, use a draft. When the intent is unclear, ask: *publish directly once the change is ready, or stage it as a draft to review/publish later?*

## Step 3: Fetch The Current Source

**Direct-publish path:** fetch the live version's content:

```bash
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
zapier-sdk --experimental get-workflow-version <workflow-id> <newest-version-id> --json
```

**Draft path:** create the draft if none exists (it forks from the workflow's current live version), then fetch it:

```bash
zapier-sdk --experimental create-workflow-draft <workflow-id> --json
zapier-sdk --experimental get-workflow-draft <workflow-id> <draft-id> --json
```

Capture from the fetched draft:

- `source_files`, especially `source_files["workflow.ts"]` — this may contain unpublished edits; treat it as the user's in-progress work, not stale data.
- `draft_revision` — needed for optimistic concurrency on every write.
- `dependencies`, `zapier_durable_version`, `trigger`, `connections`, and `app_versions`.

On either path, also fetch the workflow itself for its name, enabled state, and metadata:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
```

**Determine the current start mode from this read-back — a modify must never silently change it.** A workflow has one of two start modes, and re-publishing without carrying it forward is exactly how a triggered workflow silently becomes triggerless:

- **`trigger`** — **either** signal shows a trigger: the fetched version/draft source carries a `trigger` object, **or** `get-workflow`'s `triggers[]` is non-empty. Capture the full `trigger` config verbatim; it must be re-passed on publish (Step 6) or the new version drops the trigger.
- **`manual`** — **both** signals are absent: no `trigger` object in the fetched source **and** an empty `triggers[]`. It runs on-demand only.

If the two signals disagree — most importantly a saved `trigger` config but an empty or stale live `triggers[]` (a claim that failed, is pending, or was disabled) — do **not** label it manual. Preserve the trigger and stop to reconcile with the user: dropping a saved trigger is the silent-triggerless regression this determination guards against.

`triggers[]` and the fetched trigger config are the authority for the current mode — the platform's start-mode input (the write-only `manual` flag) is never surfaced on any read-back, so do not look for it. Unless the user's request is explicitly to change the start mode (add a trigger to a manual workflow, or remove one), the modify preserves it — carry the captured mode through the edit, publish, and verification.

The remaining checks in this step apply only when building on a **pre-existing** draft (skip them for the direct path or a draft you just created — a fresh fork is identical to its base):

**Check for unpublished draft changes.** Publishing the draft publishes *everything* in it, not just your edit — so you must know whether the draft already diverges from what's live. Fetch the draft's base version and compare:

```bash
zapier-sdk --experimental get-workflow-version <workflow-id> <base_version_id from the draft> --json
```

If the draft's `source_files`, trigger, connections, or app versions differ from the base version, the draft holds unpublished work. Note a short summary of the differences — you'll surface it at confirmation time in Step 6. Never silently publish it and never silently discard it.

**Check the draft isn't stale.** A draft forks from the live version at creation, but the live version can move past it — another draft may have published, or a direct publish went through. Publishing a stale draft ships its old base content over everything the newer versions changed. Compare the newest version's `id` (from `list-workflow-versions`) to the draft's `base_version_id`:

- **Base is the newest version:** not stale — continue.
- **Stale, with no unpublished changes** (the divergence check above found none): the draft is a leftover shell of an old version. Do not build on it — discard it, fork a fresh draft from live, tell the user you did, and continue on the fresh draft:

  ```bash
  zapier-sdk --experimental discard-workflow-draft <workflow-id> <draft-id> --json
  zapier-sdk --experimental create-workflow-draft <workflow-id> --json
  ```

- **Stale, with unpublished changes:** stop and tell the user. Publishing this draft as-is would revert everything in the versions published since it was forked. The safe path is forking a fresh draft from live and porting the draft's unpublished changes (plus your edit) onto it — offer to do that, and get an explicit choice between porting and publishing the stale draft anyway. Never pick for them.

## Step 4: Make The Edit

Prefer editing an existing local workflow file if one exists. Otherwise, write `source_files["workflow.ts"]` into a local `workflow.ts` in a workflow-specific directory and edit that copy.

Apply the requested change narrowly. Preserve existing Zod schemas, `ctx.step` boundaries, connection aliases, dependency pins, durable runtime version, connection bindings, app-version bindings, trigger configuration, and visibility/enabled state unless there is a reason to change them. On the draft path, preserve any unpublished draft content that isn't part of the requested change.

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
  --dependencies '<deps from the fetched source>' \
  --zapier-durable-version '<durable version from the fetched source>' \
  --connections '<connection bindings JSON if needed>' \
  --input '<synthetic input JSON>' \
  --private
```

For synthetic `run-durable` tests, reuse the fetched connection bindings as-is — they're already the nested object shape `{ "alias": { "connectionId": "..." } }` that `run-durable` accepts. Do not flatten to a bare string like `{ "alias": "id" }`; that fails with `expected object, received string`.

If the run returns a run ID, inspect it when needed:

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

## Step 6: Confirm, Then Publish

Before writing anything, summarize for the user:

1. The diagnosis.
2. The code or config change.
3. The workflow ID (and draft, on the draft path) being updated.
4. The values being preserved, including dependencies, durable version, enabled state, connections, app versions, and trigger configuration.
5. The **start mode** captured in Step 3 (`trigger` or `manual`) and that it is unchanged by this edit — or, if the request is to change it, state the change explicitly (adding a trigger to a manual workflow, or removing one). A modify never changes the start mode as a side effect.
6. The publish path chosen in Step 2, and — on the draft path — **any unpublished draft changes found in Step 3** (publishing the draft ships those too; see 6B).

Wait for explicit confirmation, then build `source_files`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

**Before publishing on either path, confirm the version you are about to publish matches the start mode captured in Step 3:** a `trigger`-mode workflow's published version must carry its trigger and be published **without** `--manual`; a `manual`-mode workflow's must carry no trigger and be published **with** `--manual` (unless the request is explicitly to change the mode, in which case match the intended new mode). Pass **exactly one** of trigger / `--manual` — the platform contract is a discriminated union and rejects both together as a contradiction. A `trigger`-mode republish that loses its trigger is a silent-triggerless regression. *How* you pass this differs by path — the trigger is a `--trigger` flag on a direct publish but lives in the stored draft on the draft path — so see the path-specific check in 6A and 6B below.

### Step 6A: Direct Publish

Publish the variant matching the start mode from Step 3. Pass **exactly one** of `--trigger` / `--manual`.

**`trigger`-mode** — carry the trigger, omit `--manual`:

```bash
zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '<deps from fetched version>' \
  --zapier-durable-version '<durable version from fetched version>' \
  --connections '<connection bindings from fetched version>' \
  --app-versions '<app version bindings from fetched version>' \
  --trigger '<trigger config from fetched version>' \
  --json
```

**`manual`-mode** — omit `--trigger`, declare `--manual`:

```bash
zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '<deps from fetched version>' \
  --zapier-durable-version '<durable version from fetched version>' \
  --connections '<connection bindings from fetched version>' \
  --app-versions '<app version bindings from fetched version>' \
  --manual \
  --json
```

Use the fetched workflow's enabled state when publishing. If the workflow was enabled before the edit, either omit `--enabled` or pass bare `--enabled` because publish defaults to enabled. If the workflow was disabled before the edit, add `--enabled false`; do not use `--enabled=false` or `--no-enabled`. Do not accidentally re-enable a disabled workflow.

Omit `--connections`, `--app-versions`, or `--trigger` only when the fetched metadata confirms the workflow version does not use that field. If the fetched metadata includes trigger, connection, or app-version configuration but the shape cannot be mapped to the current publish flags, stop before publishing and tell the user the workflow needs SDK confirmation rather than silently dropping metadata.

**Start-mode check (direct publish):** a `trigger`-mode workflow must include `--trigger` (and **not** `--manual`) in this call — omitting `--trigger` publishes a triggerless version and silently drops the trigger. A `manual`-mode workflow must omit `--trigger` and pass `--manual` instead. Never pass both `--trigger` and `--manual`; the platform contract rejects the combination. (When the request is to change the mode, match the intended new mode instead.)

**On a 409 open-draft conflict:** the server rejects direct publishes when the workflow has open draft(s) — publishing past a draft would let the draft's later publish silently revert your change. The error lists the blocking drafts (`meta.open_drafts`). A draft appearing here after Step 2 found none means someone (likely the user, in the editor) opened one mid-flight. Tell the user and offer:

- **Fold the change into the draft** — switch to the draft path: fetch the draft, run the Step 3 divergence/staleness checks, re-apply your edit on top of its content, and continue at 6B.
- **Discard the draft and retry** — only with explicit confirmation, since this drops the draft's unpublished work: `discard-workflow-draft`, then retry the direct publish.

Never pick for them, and never discard a draft silently.

### Step 6B: Through The Draft

If Step 3 found unpublished draft changes, resolve them first — ask the user explicitly: include them in this change, or start clean?

- **Include:** proceed as written — the draft content plus your edit ships together.
- **Start clean:** discard the draft and fork a fresh one from the live version, then re-apply your edit on the fresh draft (re-run Steps 3–4 against it):

  ```bash
  zapier-sdk --experimental discard-workflow-draft <workflow-id> <draft-id> --json
  zapier-sdk --experimental create-workflow-draft <workflow-id> --json
  ```

  Discard-and-refork is the only sanctioned way to drop unpublished work — never overwrite draft content in place to get rid of it.

Save the edit into the draft, passing the `draft_revision` from your read:

```bash
zapier-sdk --experimental update-workflow-draft <workflow-id> <draft-id> "$SOURCE_FILES" \
  --draft-revision <draft_revision from Step 3> \
  --json
```

Omitted fields keep their stored draft values, so only pass `--trigger`, `--connections`, `--app-versions`, `--dependencies`, or `--zapier-durable-version` when the edit changes them. Passing `null` for `--trigger`, `--connections`, or `--app-versions` clears the stored value — never do that to "skip" a field.

**Start-mode check (draft path):** the trigger lives in the stored draft and `publish-workflow-draft` takes no `--trigger` flag — it publishes whatever the draft holds. So a correct `trigger`-mode draft publish has *no* `--trigger` at publish time; that is expected, not a dropped trigger. First confirm, immediately before `publish-workflow-draft`, that the draft's stored `trigger` still matches the captured (or intended) start mode — a `trigger`-mode draft still carries its trigger, a `manual`-mode draft none (read it back with `get-workflow-draft` if unsure). Then declare the start mode at publish: a `manual`-mode workflow passes `--manual` on `publish-workflow-draft` (below); a `trigger`-mode workflow's draft already holds its trigger, so publish **without** `--manual`. Never combine a stored trigger with `--manual` — the platform contract rejects both together. Clearing the trigger with `--trigger null` on the `update-workflow-draft` above is exactly how a `trigger`-mode workflow silently becomes manual.

**If the user chose to publish later,** stop here: report the draft ID and the draft's editor link — `https://zapier.com/durables-editor/<workflow-id>/draft/<draft-slug>/workflow.ts`, using the `slug` from the draft response — so they can review and publish from the editor, or ask you to publish in a follow-up. The final segment is one of the draft's `source_files` keys (`workflow.ts` in this skill's flow).

**Otherwise publish now.** The update response returns the new `draft_revision`; publish the variant matching the start mode (the draft already holds the trigger — the difference is only whether you pass `--manual`):

**`trigger`-mode** — the stored trigger is the signal, omit `--manual`:

```bash
zapier-sdk --experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <draft_revision from the update response> \
  --json
```

**`manual`-mode** — the draft holds no trigger, declare `--manual`:

```bash
zapier-sdk --experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <draft_revision from the update response> \
  --manual \
  --json
```

Publishing the draft creates a new immutable version, advances the live pointer, and **discards the draft** — publish consumes it, so an open draft always means unpublished work. The response contains both the new `version` and the consumed `draft` (`status: "discarded"`). Any further modification starts back at Step 2.

Publish preserves the workflow's current enabled state when `--enabled` is omitted. Omit it unless the user asked to change the enabled state.

**On a conflict (revision mismatch):** someone edited the draft between your read and your write — likely the user, in the editor. Never blind-overwrite. Re-read the draft (`get-workflow-draft`), re-apply your change on top of the fresh `source_files`, and retry with the new `draft_revision`. If the fresh content conflicts materially with your change, stop and ask the user.

## Step 7: Verify

If the change was published (either path), read back the workflow and versions:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

Confirm the newest version reflects the publish, the workflow is still enabled if it should be, and trigger/connection/app-version metadata was preserved.

**Gate on start-mode preservation.** Compare the deployed start mode against the one captured in Step 3. The `enabled` state and the trigger's presence are independent — an `enabled` check alone will not catch a dropped trigger, so inspect `triggers[]` directly:

- Captured mode **`trigger`** (and the edit was not meant to remove it) → require the read-back to still show a non-empty `triggers[]`, and `enabled` to match the workflow's **preserved** enabled state (Step 6A), not `enabled: true` unconditionally. A workflow that was disabled before the edit stays disabled and still passes this gate; only require `enabled: true` when the workflow was enabled before the edit (or the user asked to enable it). An empty `triggers[]` means the republish dropped the trigger (most often `--trigger` was not re-passed with the fetched config) — do **not** report the change as done; re-publish with the preserved `--trigger` and re-check. The `triggers[]` check, not the `enabled` state, is what proves the trigger survived: a triggered workflow can be legitimately disabled, and a disabled workflow that lost its trigger would still read back `enabled: false`.
- Captured mode **`manual`** (and the edit was not meant to add a trigger) → require `triggers[]` to remain empty. A trigger appearing unexpectedly is also a mismatch — stop and reconcile with the user.
- If the request was explicitly to change the start mode, verify the read-back matches the **intended new** mode instead. `triggers[]` is the authority for this comparison; the platform's write-only `manual` flag is never surfaced on a read-back, so do not look for it.

Check the matching entry in `triggers[]` for `details.webhook_url`, regardless of trigger type — if present, it's the catch URL external services call and is meant to be shared, unlike the workflow-level `trigger_url`; most triggers have none, and that is normal. If the change is hard to validate without a live trigger fire, tell the user exactly what test event to send and what result to expect.

Finish by reporting:

- Workflow name and ID.
- Whether the requested change was published, or saved to a draft for later publishing (include the draft ID).
- The start mode (`trigger` or `manual`) and that it was preserved (or, if the change was to alter it, its new value), confirmed by the Step 7 gate.
- Whether trigger, connection, and app-version metadata were preserved.
- Whether the workflow is enabled.
- The trigger's `webhook_url`, if present.
- The Zapier editor link: `https://zapier.com/durables-editor/<workflow-id>` — or, when the change was staged as a draft, the draft link `https://zapier.com/durables-editor/<workflow-id>/draft/<draft-slug>/workflow.ts`.

## Reverting

Previous versions remain available as read-only history. To revert, fetch the prior version's source:

```bash
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
zapier-sdk --experimental get-workflow-version <workflow-id> <version-id> --json
```

Then publish it like any other change through Step 6 — either path works: direct publish with the prior version's `source_files` and metadata, or load them into the draft with `update-workflow-draft` and publish the draft. Same confirmation and conflict handling as Step 6.
