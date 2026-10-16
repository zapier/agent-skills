---
name: workflows-modify
description: Modify and republish an existing durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks to fix my Zap, update my Zap, modify my workflow, repair this Zap, or edit a deployed Zapier workflow.
license: MIT
metadata:
  author: zapier
  version: "2.3.0"
  sdk_cli_min: "0.85.0"  # first @zapier/zapier-sdk-cli with --stability (run-workflow-draft since 0.82.0)
  sdk_cli_validated: "0.86.4"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Modify

Modifying a deployed workflow follows a discovery, fetch, edit, test, publish, verify pattern. Every change goes through the workflow's server draft (the working copy shared with the Zapier editor): save the change into the draft, test the unpublished draft when the change warrants it, then either publish the tested draft or leave it open for the user to review and publish later.

Publishing writes to the user's Zapier account, so get explicit confirmation before publishing.

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Step 1: Identify The Workflow

If the user provides a workflow ID, use it directly. Otherwise list workflows and find the matching one by name or description:

```bash
zapier-sdk --stability experimental list-workflows --json
```

If multiple workflows match, show candidates and ask the user which one to modify.

## Step 2: Check For Open Drafts

```bash
zapier-sdk --stability experimental list-workflow-drafts <workflow-id> --json
```

The list returns open drafts, most recently edited first. An open draft always holds unpublished work (publishing consumes drafts, so a leftover one was never published).

- **An open draft exists:** work through it. It holds the user's in-progress edits and your change applies on top of it. If several are open, tell the user and confirm which to use.
- **No open draft:** create one in Step 3.

If the user's request already implies immediate publish ("fix it and ship it"), publish once the change is saved and tested. If they want to review first, work incrementally, or hand off to the editor, leave the draft open. When the intent is unclear, ask: *publish once the change is ready, or leave it as a draft to review/publish later?*

## Step 3: Fetch The Current Source

Create the draft if none exists (it forks from the workflow's current live version), then fetch it:

```bash
zapier-sdk --stability experimental create-workflow-draft <workflow-id> --json
zapier-sdk --stability experimental get-workflow-draft <workflow-id> <draft-id> --json
```

Capture from the fetched draft:

- `source_files`, especially `source_files["workflow.ts"]` — this may contain unpublished edits; treat it as the user's in-progress work, not stale data.
- `draft_revision` — needed for optimistic concurrency on every write.
- `dependencies`, `zapier_durable_version`, `trigger`, `connections`, and `app_versions`.

Also fetch the workflow itself for its name, enabled state, and metadata:

```bash
zapier-sdk --stability experimental get-workflow <workflow-id> --json
```

**Determine the current start mode from this read-back — a modify must never silently change it.** A workflow has one of two start modes, and re-publishing without carrying it forward is exactly how a triggered workflow silently becomes triggerless:

- **`trigger`** — **either** signal shows a trigger: the fetched version/draft source carries a `trigger` object, **or** `get-workflow`'s `triggers[]` is non-empty. Capture the full `trigger` config verbatim; the draft must still carry it when you publish (Step 6) or the new version drops the trigger.
- **`manual`** — **both** signals are absent: no `trigger` object in the fetched source **and** an empty `triggers[]`. It runs on-demand only.

If the two signals disagree — most importantly a saved `trigger` config but an empty or stale live `triggers[]` (a claim that failed, is pending, or was disabled) — do **not** label it manual. Preserve the trigger and stop to reconcile with the user: dropping a saved trigger is the silent-triggerless regression this determination guards against.

`triggers[]` and the fetched trigger config are the authority for the current mode — the platform's start-mode input (the write-only `manual` flag) is never surfaced on any read-back, so do not look for it. Unless the user's request is explicitly to change the start mode (add a trigger to a manual workflow, or remove one), the modify preserves it — carry the captured mode through the edit, publish, and verification.

The remaining checks in this step apply only when building on a **pre-existing** draft (skip them for a draft you just created — a fresh fork is identical to its base):

**Check for unpublished draft changes.** Publishing the draft publishes *everything* in it, not just your edit — so you must know whether the draft already diverges from what's live. Fetch the draft's base version and compare:

```bash
zapier-sdk --stability experimental get-workflow-version <workflow-id> <base_version_id from the draft> --json
```

If the draft's `source_files`, trigger, connections, or app versions differ from the base version, the draft holds unpublished work. Note a short summary of the differences — you'll surface it at confirmation time in Step 6. Never silently publish it and never silently discard it.

**Check the draft isn't stale.** A draft forks from the live version at creation, but the live version can move past it — another draft may have published since. Publishing a stale draft ships its old base content over everything the newer versions changed. Compare the newest version's `id` to the draft's `base_version_id`:

```bash
zapier-sdk --stability experimental list-workflow-versions <workflow-id> --json
```

- **Base is the newest version:** not stale — continue.
- **Stale, with no unpublished changes** (the divergence check above found none): the draft is a leftover shell of an old version. Do not build on it — discard it, fork a fresh draft from live, tell the user you did, and continue on the fresh draft:

  ```bash
  zapier-sdk --stability experimental discard-workflow-draft <workflow-id> <draft-id> --json
  zapier-sdk --stability experimental create-workflow-draft <workflow-id> --json
  ```

- **Stale, with unpublished changes:** stop and tell the user. Publishing this draft as-is would revert everything in the versions published since it was forked. The safe path is forking a fresh draft from live and porting the draft's unpublished changes (plus your edit) onto it — offer to do that, and get an explicit choice between porting and publishing the stale draft anyway. Never pick for them.

## Step 4: Make The Edit

Prefer editing an existing local workflow file if one exists. Otherwise, write `source_files["workflow.ts"]` into a local `workflow.ts` in a workflow-specific directory and edit that copy.

Apply the requested change narrowly. Preserve existing Zod schemas, `ctx.step` boundaries, connection aliases, dependency pins, durable runtime version, connection bindings, app-version bindings, trigger configuration, and visibility/enabled state unless there is a reason to change them. Preserve any unpublished draft content that isn't part of the requested change.

Put replay-variant values such as `new Date()`, `Date.now()`, and `Math.random()` inside steps so they are journaled once. A value computed outside a step changes on replay and fails the run with `DeterminismViolation`.

When the edit adds a new AI/LLM step, follow the AI by Zapier guidance in `workflows-create` Phase 2.

## Step 5: Plan The Draft Test

For non-trivial changes, propose a test run before publishing. The test runs the saved draft, so it happens in Step 6 after the edit is saved and before the draft is published. It may run real downstream actions, so summarize side effects and wait for confirmation.

## Step 6: Confirm, Then Publish

Before writing anything, summarize for the user:

1. The diagnosis.
2. The code or config change.
3. The workflow ID and draft being updated.
4. The values being preserved, including dependencies, durable version, enabled state, connections, app versions, and trigger configuration.
5. The **start mode** captured in Step 3 (`trigger` or `manual`) and that it is unchanged by this edit — or, if the request is to change it, state the change explicitly (adding a trigger to a manual workflow, or removing one). A modify never changes the start mode as a side effect.
6. Whether to publish now or leave the draft for review (Step 2), and **any unpublished draft changes found in Step 3** (publishing the draft ships those too).

Wait for explicit confirmation, then build `source_files` as the complete map: every key from the draft's fetched `source_files`, with the files you edited replaced. An update replaces the whole map, so a file left out is deleted. With the fetched map in `FETCHED_SOURCE_FILES`, add one `--rawfile` per edited file:

```bash
SOURCE_FILES="$(jq -n --argjson base "$FETCHED_SOURCE_FILES" --rawfile workflow workflow.ts '$base + {"workflow.ts": $workflow}')"
```

**Before publishing, confirm the version you are about to publish matches the start mode captured in Step 3:** a `trigger`-mode workflow's draft must carry its trigger and be published **without** `--manual`; a `manual`-mode workflow's must carry no trigger and be published **with** `--manual` (unless the request is explicitly to change the mode, in which case match the intended new mode). Pass **exactly one** of trigger / `--manual` — the platform contract is a discriminated union and rejects both together as a contradiction. A `trigger`-mode republish that loses its trigger is a silent-triggerless regression. The trigger lives in the stored draft; see the start-mode check below.

### Save, Test, And Publish The Draft

If Step 3 found unpublished draft changes, resolve them first — ask the user explicitly: include them in this change, or start clean?

- **Include:** proceed as written — the draft content plus your edit ships together.
- **Start clean:** discard the draft and fork a fresh one from the live version, then re-apply your edit on the fresh draft (re-run Steps 3–4 against it):

  ```bash
  zapier-sdk --stability experimental discard-workflow-draft <workflow-id> <draft-id> --json
  zapier-sdk --stability experimental create-workflow-draft <workflow-id> --json
  ```

  Discard-and-refork is the only sanctioned way to drop unpublished work — never overwrite draft content in place to get rid of it.

Save the edit into the draft, passing the `draft_revision` from your read:

```bash
zapier-sdk --stability experimental update-workflow-draft <workflow-id> <draft-id> "$SOURCE_FILES" \
  --draft-revision <draft_revision from Step 3> \
  --json
```

Omitted fields keep their stored draft values, so only pass `--trigger`, `--connections`, `--app-versions`, `--dependencies`, or `--zapier-durable-version` when the edit changes them. Passing `null` for `--trigger`, `--connections`, or `--app-versions` clears the stored value — never do that to "skip" a field.

**Start-mode check:** the trigger lives in the stored draft and `publish-workflow-draft` takes no `--trigger` flag — it publishes whatever the draft holds. So a correct `trigger`-mode draft publish has *no* `--trigger` at publish time; that is expected, not a dropped trigger. First confirm, immediately before `publish-workflow-draft`, that the draft's stored `trigger` still matches the captured (or intended) start mode — a `trigger`-mode draft still carries its trigger, a `manual`-mode draft none (read it back with `get-workflow-draft` if unsure). Then declare the start mode at publish: a `manual`-mode workflow passes `--manual` on `publish-workflow-draft` (below); a `trigger`-mode workflow's draft already holds its trigger, so publish **without** `--manual`. Never combine a stored trigger with `--manual` — the platform contract rejects both together. Clearing the trigger with `--trigger null` on the `update-workflow-draft` above is exactly how a `trigger`-mode workflow silently becomes manual.

**Test the saved revision** when Step 5 called for a test. Read the draft for its current `draft_revision` (the update response also returns it), then run that revision:

```bash
zapier-sdk --stability experimental run-workflow-draft <workflow-id> <draft-id> <draft-revision> \
  --input '<JSON matching input schema>' \
  --json
```

Omit `--input` when the workflow takes no input. The run uses the draft's stored dependencies, connections, and app versions. Capture the returned `id` and poll `get-workflow-run <run-id> --json`. The test passes when `status` is `"finished"`, `output` is what the change should produce, `error` is `null`, top-level `errors` is empty, `kind` is `"draft"`, and `workflow_id`, `workflow_draft_id`, and `draft_revision` match the draft you tested. If it fails, fix the source, update the draft again, and test the new revision.

**If the user chose to publish later,** stop here: report the draft ID and the draft's editor link — `https://zapier.com/workflow/<workflow-id>/draft/<draft-slug>/workflow.ts`, using the `slug` from the draft response — so they can review and publish from the editor, or ask you to publish in a follow-up. The final segment is one of the draft's `source_files` keys (`workflow.ts` in this skill's flow).

**Otherwise publish now**, passing the tested `draft_revision` (or, with no test, the one from the update response) so concurrent edits cannot go live untested. Publish the variant matching the start mode (the draft already holds the trigger — the difference is only whether you pass `--manual`):

**`trigger`-mode** — the stored trigger is the signal, omit `--manual`:

```bash
zapier-sdk --stability experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <tested draft_revision> \
  --json
```

**`manual`-mode** — the draft holds no trigger, declare `--manual`:

```bash
zapier-sdk --stability experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <tested draft_revision> \
  --manual \
  --json
```

Publishing the draft creates a new immutable version, advances the live pointer, and **discards the draft** — publish consumes it, so an open draft always means unpublished work. The response contains both the new `version` and the consumed `draft` (`status: "discarded"`). Any further modification starts back at Step 2.

Publish preserves the workflow's current enabled state when `--enabled` is omitted. Omit it unless the user asked to change the enabled state.

**On a conflict (revision mismatch):** someone edited the draft between your read and your write — likely the user, in the editor. Never blind-overwrite. Re-read the draft (`get-workflow-draft`), re-apply your change on top of the fresh `source_files`, and retry with the new `draft_revision`. If the fresh content conflicts materially with your change, stop and ask the user.

## Step 7: Verify

If the change was published, read back the workflow and versions:

```bash
zapier-sdk --stability experimental get-workflow <workflow-id> --json
zapier-sdk --stability experimental list-workflow-versions <workflow-id> --json
```

Confirm the newest version reflects the publish, the workflow is still enabled if it should be, and trigger/connection/app-version metadata was preserved.

**Gate on start-mode preservation.** Compare the deployed start mode against the one captured in Step 3. The `enabled` state and the trigger's presence are independent — an `enabled` check alone will not catch a dropped trigger, so inspect `triggers[]` directly:

- Captured mode **`trigger`** (and the edit was not meant to remove it) → require the read-back to still show a non-empty `triggers[]`, and `enabled` to match the workflow's **preserved** enabled state (captured in Step 3), not `enabled: true` unconditionally. A workflow that was disabled before the edit stays disabled and still passes this gate; only require `enabled: true` when the workflow was enabled before the edit (or the user asked to enable it). An empty `triggers[]` means the published draft no longer carried the trigger (most often an `update-workflow-draft` call passed `--trigger null` or a changed config) — do **not** report the change as done; restore the captured config with `update-workflow-draft --trigger '<captured trigger JSON>'`, test the new draft revision, publish it, and re-check. The `triggers[]` check, not the `enabled` state, is what proves the trigger survived: a triggered workflow can be legitimately disabled, and a disabled workflow that lost its trigger would still read back `enabled: false`.
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
- The Zapier editor link: `https://zapier.com/workflow/<workflow-id>` — or, when the change was staged as a draft, the draft link `https://zapier.com/workflow/<workflow-id>/draft/<draft-slug>/workflow.ts`.

## Reverting

Previous versions remain available as read-only history. To revert, fetch the prior version's source:

```bash
zapier-sdk --stability experimental list-workflow-versions <workflow-id> --json
zapier-sdk --stability experimental get-workflow-version <workflow-id> <version-id> --json
```

Then publish it like any other change through Step 6: load the prior version's `source_files` and metadata into the draft with `update-workflow-draft`, test, and publish the draft. Same confirmation and conflict handling as Step 6.
