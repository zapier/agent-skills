---
name: workflows-create
description: Create a durable Zapier workflow from natural language using @zapier/zapier-durable and the Zapier SDK CLI. Use when the user wants to build a Zapier workflow, create an automation, write a durable workflow, build me a Zap that, create a durable that, or automate a multi-step process involving Zapier-connected apps.
license: MIT
metadata:
  author: zapier
  version: "1.3.0"
  sdk_cli_min: "0.54.3"
  sdk_cli_validated: "0.54.3"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Create

Create a complete durable workflow from natural language, test it when appropriate, and deploy it through the Zapier SDK experimental Code Workflows commands.

Use the public SDK CLI path. Do not use `zapier-sdk-code-substrate`.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

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
  "selected_api": "GoogleSheetsAPI@2.3.0",
  "action": "new_row",
  "authentication_id": "connection-id-or-null",
  "params": {}
}
```

Use the version-pinned app/API identifier for `selected_api`, the trigger action key for `action`, the trigger source connection ID for `authentication_id` when the trigger requires auth, and trigger input values for `params`. Omit optional fields only when the trigger does not need them.

For `selected_api`, use the **version-pinned implementation identifier** — the `implementation_id` returned by SDK discovery (`list-apps`/`get-app`), such as `GoogleSheetsAPI@2.3.0`. Do not use the bare app key (`GoogleSheetsAPI`) and do not substitute a display name. A bare, unversioned `selected_api` makes the trigger claim **fail silently at publish**: the publish call returns success with no errors, but the workflow stays disabled and nothing surfaces the cause. If discovery only exposes a bare app slug and not a versioned `implementation_id`, treat that as a blocker and record it in the build plan before publishing — do not publish a trigger with an unversioned identifier.

For `params`, match each field's `value_type` from `list-trigger-input-fields <app> <action>`. ARRAY fields must be JSON arrays (for example `"dow": ["1"]`); STRING fields must be plain strings (for example `"hod": "9:00 AM"`). Passing a scalar where an array is expected (or vice versa) fails the trigger claim the same silent way.

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
- Create the SDK client **once at module level** — `const sdk = createZapierSdk()` above `defineDurable`. Do not call `createZapierSdk()` inside a `ctx.step` callback; an `sdk` created inside the callback is not the shape the editor recognizes as an app action (see **App-Action Step Shape (Editor Recognition)** below).
- Use Zod for input validation when the workflow has input.
- Keep external side effects (app actions, fetches) inside `ctx.step` calls.
- Make each app action exactly **one** `ctx.step` whose body is a single `return sdk.runAction({...})` call — one `runAction` per step.
- Keep validation, input normalization, simple guards, data shaping, and final return object construction **outside** `ctx.step` calls.
- Use connection aliases, not raw connection IDs, inside workflow code.
- Reference a prior step's output with `stepVar.data[0].field` for the first result, or `stepVar.data` for the whole array.
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

### Visualizer-Friendly Structure

Generate durable source the editor can turn into a meaningful step graph. An app action becomes an app-action step (with the app icon) only when it is a pure, single-`runAction` step (see **App-Action Step Shape (Editor Recognition)** below). Everything else — validation, input normalization, data shaping, guards, and the final return object — stays as plain code.

You may still expose a user-meaningful non-app stage (for example a record check, or a prepared payload) as a named `ctx.step`. Such a step has no `sdk.runAction` call, so the editor renders it as a **code step** by design — that is the correct rendering for a non-app stage, not a regression. Use a visible non-app step only when the box genuinely helps the reader; otherwise keep that logic in plain code.

Prefer the starter-workflow-compatible `defineDurable(name, run)` form as the default. Object-form `defineDurable({ name, description, run })` is acceptable when the workflow needs object-form metadata.

Default to this parser-friendly shape — note the **module-level** `sdk`, the hoisted app-key/connection constants, and the bare `runAction` body of the app-action step:

```typescript
import { defineDurable } from "@zapier/zapier-durable";
import { createZapierSdk } from "@zapier/zapier-sdk";
import { z } from "zod";

const sdk = createZapierSdk();

const InputSchema = z.object({ reaction: z.string() });
type Input = z.infer<typeof InputSchema>;

const TODOIST_APP_KEY = "TodoistV2CLIAPI";
const TODOIST_CONNECTION = "todoist_primary";

const workflow = defineDurable<Input, unknown>(
  "example-workflow",
  async (ctx, input) => {
    // Plain code: guard outside any step.
    if (input.reaction !== "todo") {
      return { skipped: true };
    }

    // Plain code: shape the action input outside the step.
    const taskInput = buildTaskInput(input);

    // App action: one runAction, object literal, module-level sdk.
    const createdTask = await ctx.step("create-todoist-task", async () =>
      sdk.runAction({
        appKey: TODOIST_APP_KEY,
        actionType: "write",
        actionKey: "new_task",
        connection: TODOIST_CONNECTION,
        inputs: taskInput,
      }),
    );

    return { createdTask };
  },
);
```

Do not wrap every helper in a step, and do not put data shaping inside an app-action step. The goal is a useful diagram where each app action carries its app icon — not a box for every line of code.

### App-Action Step Shape (Editor Recognition)

The editor parses each `ctx.step` to decide whether it renders as an **app-action step** (with the app icon) or a generic **code step**. To render as an app action, a step must satisfy **all** of these:

- **String-literal step id** — `ctx.step("create-todoist-task", ...)`. Object form `ctx.step({ name: "create-todoist-task", run })` is also recognized.
- **Inline callback** — an `async () => ...` arrow or `async function () { ... }` written in place, never a named function reference.
- **Exactly one `sdk.runAction(...)` call** in the body, on the **module-level** `sdk` client.
- **Object-literal argument** to `runAction` (or a `const` that resolves to one) providing `appKey`, `actionType`, and `actionKey`. (The `app` / `action` spellings are also accepted.)

A step is **demoted to a code step** (no app icon) when any of these is true:

- The step id is not a string literal (a variable, a function call, or a template such as `` `process-item-${index}` ``).
- The callback is a named reference instead of an inline function.
- The body has **zero** `sdk.runAction` calls — a pure transform/prep step. This renders as a code step by design; it is not an app action.
- The body has **more than one** `sdk.runAction` call.
- `runAction` is called on something other than the module-level `sdk` (for example an `sdk` created inside the callback).
- `appKey`, `actionType`, or `actionKey` is missing.

When in doubt, keep the app-action step to a single `return sdk.runAction({ appKey, actionType, actionKey, connection, inputs })` and move everything else out of the step.

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

For trigger-backed workflows, build the `trigger` JSON from Phase 2. Keep `selected_api` version-pinned to the `implementation_id` (for example `GoogleSheetsAPI@2.3.0`) and keep each `params` field shaped to its `value_type` (see Phase 2) — a bare app key or a wrong param shape makes the trigger claim fail silently at publish:

```json
{
  "selected_api": "GoogleSheetsAPI@2.3.0",
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

For trigger-backed workflows, verify the trigger actually claimed. The claim is asynchronous and can fail silently, so re-read the workflow (allow a few seconds; poll if needed) and confirm it is enabled:

```bash
zapier-sdk --experimental get-workflow <workflow-id> --json
```

If `enabled` is `false` even though you published with `--enabled`, the trigger claim failed. The most common cause is a `selected_api` that is not version-pinned to the `implementation_id`, or a `params` field with the wrong shape (see Phase 2). Re-publish with a corrected `--trigger` and re-check. Do not report the workflow as deployed until `get-workflow` shows `enabled: true`.

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

await ctx.step("send-approval-request", async () =>
  sdk.runAction({
    appKey: "ExampleCLIAPI",
    actionType: "write",
    actionKey: "send_message",
    connection: "example_connection",
    inputs: { callbackUrl },
  }),
);

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
    ctx.step(`process-item-${index}`, async () =>
      sdk.runAction({
        appKey: "ExampleCLIAPI",
        actionType: "write",
        actionKey: "do_something",
        connection: "example_connection",
        inputs: { item },
      }),
    ),
  ),
);
```

The template-literal step id (`` `process-item-${index}` ``) is not a string literal, so the editor renders these fan-out steps as code steps rather than app-action steps (see **App-Action Step Shape (Editor Recognition)**). Use this pattern for runtime fan-out; when you need each app action to show its app icon, write separate steps with string-literal ids instead.

### Error Handling

Use step-level retries for flaky external calls:

```typescript
const result = await ctx.step({
  name: "flaky-api-call",
  maxAttempts: 3,
  retryDelaySeconds: 5,
  run: async () =>
    sdk.runAction({
      appKey: "ExampleCLIAPI",
      actionType: "write",
      actionKey: "do_something",
      connection: "example_connection",
      inputs: {},
    }),
});
```

Prefer `sdk.runAction` when a Zapier action exists. Use `sdk.fetch` only when the app action cannot provide the needed behavior or data.
