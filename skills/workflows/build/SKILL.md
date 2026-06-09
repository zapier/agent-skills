---
name: zapier-workflows-build
description: Build a durable Zapier workflow from natural language using @zapier/zapier-durable and the Zapier SDK CLI. Use when the user wants to build a Zapier workflow, create an automation, write a durable workflow, build me a Zap that, create a durable that, or automate a multi-step process involving Zapier-connected apps.
license: MIT
metadata:
  author: zapier
  version: "1.0.0"
---

# Zapier Workflows Build

Build a complete durable workflow from natural language, test it when appropriate, and deploy it through the Zapier SDK experimental Code Workflows commands.

Use the public SDK CLI path. Do not use `zapier-sdk-code-substrate`.

## Prerequisites

Verify these at the start:

```bash
zapier-sdk --version
zapier-sdk get-profile --json
zapier-sdk --experimental --help
npm view @zapier/zapier-sdk version
npm view @zapier/zapier-durable version
```

Capture:

- The latest `@zapier/zapier-sdk` version as the pinned SDK dependency.
- The latest `@zapier/zapier-durable` version as the durable runtime version.

Use exact versions in commands. Do not pass `latest` to `--dependencies` or `--zapier_durable_version`.

The user must also have app connections configured at https://zapier.com/app/assets/connections for any app actions the workflow will run.

## Phase 1: Understand The Intent

Read the user's natural language request and extract:

1. Steps and ordering.
2. Apps involved.
3. Data passed between steps.
4. Manual input fields or trigger input fields.
5. Conditional logic.
6. Waits, callbacks, or human approval gates.

Summarize the proposed workflow back to the user before discovery. Ask focused clarifying questions for missing details like target channels, folders, recipients, or whether to stop when a search returns no results.

Do not generate code until the user agrees on the workflow shape.

## Phase 2: Discover Apps, Connections, Actions, And Fields

Use the standard Zapier SDK CLI for app/action discovery:

```bash
zapier-sdk list-apps --search "<app name>" --json
zapier-sdk list-connections <appKey> --owner me --json
zapier-sdk list-actions <appKey> --action-type <write|search|read|read_bulk> --json
zapier-sdk list-action-input-fields <appKey> <actionType> <actionKey> --connection <connectionId> --json
zapier-sdk list-action-input-field-choices <appKey> <actionType> <actionKey> <fieldKey> --connection <connectionId> --json
```

If several apps, connections, actions, or field choices are plausible, show the candidates and ask the user to choose.

Assign a short snake_case connection alias for each chosen connection, such as `slack_work` or `gmail_primary`. Track alias to connection ID. The alias goes in workflow code; the connection ID is passed to test/deploy commands through the `--connections` JSON.

For output mapping between steps, run a safe action test only after user confirmation. Use the current SDK command shape:

```bash
zapier-sdk run-action <appKey> <actionType> <actionKey> \
  --connection <connectionId> \
  --inputs '<{"key":"value"}>' \
  --json
```

## Phase 3: Confirm The Build Plan

Before writing code, present:

```text
Workflow: <kebab-case-name>
Input: { field1, field2 }
Connections:
  alias = connectionId (connection title)
Steps:
  1. <step-name> - <AppName>.<actionType>.<actionKey>
  2. <step-name> - <AppName>.<actionType>.<actionKey>
Return: <summary of output>
```

Ask the user to confirm before generating files.

## Phase 4: Generate The Workflow Project

Create a workflow directory:

```text
<working-directory>/
  <kebab-case-workflow-name>/
    package.json
    workflow.ts
```

`package.json` should include exact dependencies:

```json
{
  "type": "module",
  "dependencies": {
    "@zapier/zapier-sdk": "<pinned SDK version>",
    "@zapier/zapier-durable": "<pinned durable version>",
    "zod": "latest"
  },
  "devDependencies": {
    "typescript": "latest"
  }
}
```

If you add a build script, use `--skipLibCheck` for now to avoid type-check failures from SDK/durable transitive type declarations:

```json
{
  "scripts": {
    "build": "tsc --target es2022 --module nodenext --moduleResolution nodenext --skipLibCheck --outDir dist workflow.ts"
  }
}
```

`workflow.ts` should:

- Import `defineDurable` from `@zapier/zapier-durable`.
- Import `createZapierSdk` from `@zapier/zapier-sdk`.
- Use Zod for input validation when the workflow has input.
- Keep external side effects inside `ctx.step` calls.
- Keep deterministic input validation, branching, and data shaping outside `ctx.step` calls.
- Use connection aliases, not raw connection IDs, inside workflow code.
- Normalize manual input before Zod validation. In the current `run-durable` path, input may arrive as a JSON string rather than an already-parsed object.

Use this helper pattern for workflows with input:

```typescript
function normalizeInput(rawInput: unknown): unknown {
  if (typeof rawInput === "string") {
    return JSON.parse(rawInput);
  }
  return rawInput;
}
```

Then parse the normalized value:

```typescript
const input = InputSchema.parse(normalizeInput(rawInput));
```

## Phase 5: Test The Workflow

Build `source_files` from `workflow.ts`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

Build `connections` JSON from the selected aliases:

```json
{
  "slack_work": "12345678",
  "gmail_primary": "87654321"
}
```

Before running, tell the user what actions may happen in connected apps and wait for confirmation if there are side effects.

Run the durable:

```bash
zapier-sdk --experimental run-durable "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>"}' \
  --zapier_durable_version '<pinned durable version>' \
  --connections '<connections JSON>' \
  --input '<JSON matching input schema>'
```

`run-durable` returns a run immediately, often before the workflow is complete. Capture the returned run ID, then poll until terminal status. Do not assume the first response contains final output.

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

Terminal success means the run has `status: "finished"`, an expected `output`, `error: null`, and top-level `errors: []`. Terminal failure means `status: "failed"` or a non-null `error`. Continue polling while the run is initialized or started.

Fix code and retest until the behavior matches the confirmed plan.

## Phase 6: Deploy The Workflow

Create a workflow container:

```bash
zapier-sdk --experimental create-workflow "<workflow-name>" \
  --description "<brief description>" \
  --json
```

Current v1 caution: the verified `create-workflow` command does not expose a `--private` flag. Do not promise workflow visibility control from this skill until engineering confirms the supported visibility path.

Capture the returned workflow ID. Then publish the version. The current SDK CLI expects `source_files` as a JSON object, not a path to `workflow.ts`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"

zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>"}' \
  --zapier_durable_version '<pinned durable version>' \
  --enabled \
  --json
```

Current v1 caution: do not promise app-trigger wiring through the old `--trigger-app`, `--trigger-action`, `--trigger-auth`, or `--trigger-params` flags. Those flags are stale relative to the verified SDK CLI surface. For EA v1, prefer manual trigger or durable-run workflows unless engineering confirms the current trigger path.

## Phase 7: Verify Deployment

Read back the workflow and versions:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
```

If manual triggering is supported for the workflow, test it only after confirming side effects with the user:

```bash
zapier-sdk --experimental trigger-workflow <workflow-id> --input '<JSON>'
```

Then inspect run history:

```bash
zapier-sdk --experimental list-workflow-runs <workflow-id> --json
```

Finish by reporting:

- Workflow name and ID.
- Where `workflow.ts` lives locally.
- Whether testing passed.
- Whether the deployed workflow is enabled.
- Any known v1 caveats, especially trigger wiring limitations.

## Durable Patterns

### Waits

```typescript
await ctx.wait("wait-before-followup", 3600);
```

Place waits at top-level workflow scope, not inside `ctx.step`.

### Callbacks

```typescript
const [approvalPromise, callbackUrl] = await ctx.createCallback({
  name: "wait-for-approval",
  payloadSchema: z.object({ approved: z.boolean() }),
  timeoutSeconds: 86400,
});

await ctx.step("send-approval-request", async () => {
  const sdk = createZapierSdk();
  // Send callbackUrl via Slack, email, or another action.
});

const approval = await approvalPromise;
if (!approval.approved) {
  throw new Error("Approval denied");
}
```

### Parallel Or Repeated Work

Use `Promise.all()` outside `ctx.step`; each iteration creates its own step:

```typescript
const results = await Promise.all(
  items.map((item, index) =>
    ctx.step(`process-item-${index}`, async () => {
      const sdk = createZapierSdk();
      return sdk.runAction({
        appKey: "ExampleCLIAPI",
        actionType: "write",
        actionKey: "do_something",
        connection: "example_connection",
        inputs: { item },
      });
    }),
  ),
);
```

### Error Handling

Use step-level retries for flaky external calls:

```typescript
const result = await ctx.step({
  name: "flaky-api-call",
  maxAttempts: 3,
  retryDelaySeconds: 5,
  run: async () => {
    const sdk = createZapierSdk();
    return sdk.runAction({
      appKey: "ExampleCLIAPI",
      actionType: "write",
      actionKey: "do_something",
      connection: "example_connection",
      inputs: {},
    });
  },
});
```

Prefer `sdk.runAction` when a Zapier action exists. Use `sdk.fetch` only when the app action cannot provide the needed behavior or data.
