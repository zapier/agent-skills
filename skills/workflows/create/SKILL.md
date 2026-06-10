---
name: workflows-create
description: Create a durable Zapier workflow from natural language using @zapier/zapier-durable and the Zapier SDK CLI. Use when the user wants to build a Zapier workflow, create an automation, write a durable workflow, build me a Zap that, create a durable that, or automate a multi-step process involving Zapier-connected apps.
license: MIT
metadata:
  author: zapier
  version: "1.0.0"
---

# Zapier Workflows Create

Create a complete durable workflow from natural language, test it when appropriate, and deploy it through the Zapier SDK experimental Code Workflows commands.

Use the public SDK CLI path. Do not use `zapier-sdk-code-substrate`.

## Prerequisites

Verify these at the start:

```bash
zapier-sdk --version
zapier-sdk get-profile --json
zapier-sdk --experimental --help
zapier-sdk --experimental create-workflow --help
zapier-sdk --experimental publish-workflow-version --help
zapier-sdk --experimental run-durable --help
zapier-sdk --experimental list-triggers --help
zapier-sdk --experimental trigger-workflow --help
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

## Phase 2: Discover Apps, Connections, Actions, Triggers, And Fields

Use the standard Zapier SDK CLI for app/action discovery:

```bash
zapier-sdk list-apps --search "<app name>" --json
zapier-sdk list-connections <appKey> --owner me --json
zapier-sdk list-actions <appKey> --action-type <write|search|read|read_bulk> --json
zapier-sdk list-action-input-fields <appKey> <actionType> <actionKey> --connection <connectionId> --json
zapier-sdk list-action-input-field-choices <appKey> <actionType> <actionKey> <fieldKey> --connection <connectionId> --json
```

For workflows that should subscribe to a Zapier app trigger, use the experimental trigger discovery commands:

```bash
zapier-sdk --experimental list-triggers <appKey> --json
zapier-sdk --experimental list-trigger-input-fields <appKey> <triggerKey> --connection <connectionId> --json
zapier-sdk --experimental list-trigger-input-field-choices <appKey> <triggerKey> <fieldKey> --connection <connectionId> --json
```

If several apps, connections, actions, triggers, or field choices are plausible, show the candidates and ask the user to choose.

Assign a short snake_case connection alias for each chosen connection, such as `slack_work` or `gmail_primary`. Track alias to connection ID. The alias goes in workflow code; the connection ID is passed to test/deploy commands through the `--connections` JSON.

For output mapping between steps, run a safe action test only after user confirmation. Use the current SDK command shape:

```bash
zapier-sdk run-action <appKey> <actionType> <actionKey> \
  --connection <connectionId> \
  --inputs '<{"key":"value"}>' \
  --json
```

For trigger-backed workflows, capture the trigger configuration for publish:

```json
{
  "selected_api": "GoogleSheetsAPI",
  "action": "new_row",
  "authentication_id": "connection-id-or-null",
  "params": {}
}
```

Use the selected app/API identifier for `selected_api`, the trigger action key for `action`, the trigger source connection ID for `authentication_id` when the trigger requires auth, and trigger input values for `params`. Omit optional fields only when the trigger does not need them.

For `selected_api`, use the app/API or implementation identifier returned by SDK discovery, such as `GoogleSheetsAPI`; do not substitute a display name. If discovery only exposes an app slug and not an implementation/API identifier, use the value accepted by the trigger discovery command and record the uncertainty in the build plan before publishing.

Capture app implementation/version information from SDK discovery output when available, such as `list-apps`, `get-app`, `list-actions`, or trigger/action result metadata. Do not invent app versions. If no implementation/version binding is exposed, omit `--app_versions` rather than guessing.

## Phase 3: Confirm The Build Plan

Before writing code, present:

```text
Workflow: <kebab-case-name>
Input: { field1, field2 }
Connections:
  alias = connectionId (connection title)
Trigger:
  selected_api.action with params, or none for webhook/manual-only workflow
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

Build the run-only `connections` JSON from the selected aliases. For `run-durable`, aliases map directly to connection IDs:

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
  --input '<JSON matching input schema>' \
  --private
```

`run-durable` returns a run immediately, often before the workflow is complete. Capture the returned run ID, then poll until terminal status. Do not assume the first response contains final output.

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

Terminal success means the run has `status: "finished"`, an expected `output`, `error: null`, and top-level `errors: []`. Terminal failure means `status: "failed"` or a non-null `error`. Continue polling while the run is initialized or started.

Fix code and retest until the behavior matches the confirmed plan.

## Phase 6: Deploy The Workflow

Decide whether the workflow should be private before creating it. For EA users, default to private unless the user explicitly wants an account-visible workflow.

Create a private workflow container:

```bash
zapier-sdk --experimental create-workflow "<workflow-name>" \
  --description "<brief description>" \
  --is_private \
  --json
```

Omit `--is_private` only if the user explicitly wants the workflow visible to the broader account.

Capture the returned workflow ID. Then publish the version. The current SDK CLI expects `source_files` as a JSON object, not a path to `workflow.ts`.

For publish, build connection bindings with the nested shape expected by `publish-workflow-version`:

```json
{
  "slack_work": { "connection_id": "123-or-uuid" },
  "gmail_primary": { "connection_id": "456-or-uuid" }
}
```

If app implementation/version information is known, build `app_versions`:

```json
{
  "slack": { "implementation_name": "SlackCLIAPI", "version": "optional" }
}
```

Omit the entire `--app_versions` flag when no app implementation/version binding is needed. Likewise, omit `--connections` when the workflow has no connection bindings. Do not pass placeholder text like "if needed" to the CLI.

For trigger-backed workflows, build the `trigger` JSON from Phase 2:

```json
{
  "selected_api": "GoogleSheetsAPI",
  "action": "new_row",
  "authentication_id": "connection-id-or-null",
  "params": {}
}
```

Publish a webhook/manual-only workflow by omitting `--trigger`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"

zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>"}' \
  --zapier_durable_version '<pinned durable version>' \
  --connections '<publish connection bindings JSON>' \
  --app_versions '<app versions JSON if needed>' \
  --enabled \
  --json
```

Publish a trigger-backed workflow by adding `--trigger`:

```bash
zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>"}' \
  --zapier_durable_version '<pinned durable version>' \
  --connections '<publish connection bindings JSON>' \
  --app_versions '<app versions JSON if needed>' \
  --trigger '<trigger config JSON>' \
  --enabled \
  --json
```

Do not use the old `--trigger-app`, `--trigger-action`, `--trigger-auth`, or `--trigger-params` flags. The current trigger publish path is the single JSON `--trigger` object.

## Phase 7: Verify Deployment

Read back the workflow and versions:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
zapier-sdk --experimental list-workflow-versions <workflow-id> --json
zapier-sdk --experimental get-workflow-version <workflow-id> <version-id> --json
```

If manual triggering is supported for the workflow, test it only after confirming side effects with the user:

```bash
zapier-sdk --experimental trigger-workflow <workflow-id> --input '<JSON>' --json
```

If `trigger-workflow` returns a trigger ID before a workflow run ID is available, bridge from trigger to run:

```bash
zapier-sdk --experimental get-trigger-run <trigger-id> --json
```

Then inspect run history and, if needed, a deployed workflow run:

```bash
zapier-sdk --experimental list-workflow-runs <workflow-id> --json
zapier-sdk --experimental get-workflow-run <run-id> --json
```

Finish by reporting:

- Workflow name and ID.
- Where `workflow.ts` lives locally.
- Whether testing passed.
- Whether the deployed workflow is enabled.
- Whether the workflow is private or account-visible.
- Whether the workflow uses a Zapier app trigger or webhook/manual triggering.
- The Zapier editor link: `https://zapier.com/durables-editor/<workflow-id>`.

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
