---
name: zapier-workflows-modify
description: Modify and republish an existing durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks to fix my Zap, update my Zap, modify my workflow, repair this Zap, or edit a deployed Zapier workflow.
license: MIT
metadata:
  author: zapier
  version: "1.0.0"
---

# Zapier Workflows Modify

Modifying a deployed workflow follows a discovery, fetch, edit, republish, verify pattern. Publishing a workflow version writes to the user's Zapier account, so get explicit confirmation before publishing.

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

## Step 1: Identify The Workflow

If the user provides a workflow ID, use it directly. Otherwise list workflows and find the matching one by name or description:

```bash
zapier-sdk --experimental list-workflows --json
```

If multiple workflows match, show candidates and ask the user which one to modify.

## Step 2: Fetch Current Metadata And Version

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
- Any connection, app version, trigger, or workflow metadata present in the response.

The current SDK publish command takes `source_files` as a JSON object. Do not pass a raw `workflow.ts` path to `publish-workflow-version`.

## Step 3: Make The Edit

Prefer editing an existing local workflow file if one exists. Otherwise, write `source_files["workflow.ts"]` into a local `workflow.ts` in a workflow-specific directory and edit that copy.

Apply the requested change narrowly. Preserve existing Zod schemas, `ctx.step` boundaries, connection aliases, dependency pins, and durable runtime version unless there is a reason to change them.

## Step 4: Optional Synthetic Test

For non-trivial changes, propose a test run before publishing. This may run real downstream actions, so summarize side effects and wait for confirmation.

Build `source_files` from the local file:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

Run the workflow:

```bash
zapier-sdk --experimental run-durable "$SOURCE_FILES" \
  --dependencies '<deps from fetched version>' \
  --zapier_durable_version '<durable version from fetched version>' \
  --connections '<connections JSON if needed>' \
  --input '<synthetic input JSON>'
```

If the run returns a run ID, inspect it when needed:

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

## Step 5: Confirm, Then Republish

Before publishing, summarize for the user:

1. The diagnosis.
2. The code or config change.
3. The workflow ID being updated.
4. The publish command shape and any values that will be preserved from the old version.

Wait for explicit confirmation before publishing.

Build `source_files`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

Publish:

```bash
zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '<deps from fetched version>' \
  --zapier_durable_version '<durable version from fetched version>' \
  --enabled
```

Current v1 caution: the old trigger republish flags (`--trigger-app`, `--trigger-action`, `--trigger-auth`, `--trigger-params`) are not part of the verified SDK CLI surface. Do not promise trigger preservation through those flags. If the fetched metadata shows trigger configuration that cannot be republished with the current command, stop and tell the user this requires SDK confirmation before changing that workflow.

## Step 6: Verify

Read back the workflow and versions:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

Confirm the newest version reflects the publish and that the workflow is still enabled if it should be. If the change is hard to validate without a live trigger fire, tell the user exactly what test event to send and what result to expect.

## Reverting

Previous versions remain available. To revert, fetch the prior version's source and republish it with the same `publish-workflow-version` pattern above, preserving dependency and durable version pins.
