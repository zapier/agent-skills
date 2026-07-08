---
name: workflows-create
description: Create a durable Zapier workflow from natural language using @zapier/zapier-durable and the Zapier SDK CLI. Use when the user wants to build a Zapier workflow, create an automation, write a durable workflow, build me a Zap that, create a durable that, or automate a multi-step process involving Zapier-connected apps.
license: MIT
metadata:
  author: zapier
  version: "1.3.6"
  sdk_cli_min: "0.54.3"
  sdk_cli_validated: "0.59.3"
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
```

Pin **aged** versions, not npm-latest. The Vercel sandbox installs dependencies with `pnpm install --config.minimumReleaseAge=1440`, so any direct dependency published less than 24h ago is rejected. `@zapier/zapier-sdk` publishes often (several times a day), so its npm-latest is regularly younger than 24h. `@zapier/zapier-sdk`, `@zapier/zapier-durable`, and `zod` (imported by the generated `workflow.ts`) are all direct dependencies of the sandbox install, so select the latest version of each **published at least 24h ago**. This needs only Node (already required) — no `jq` or other tooling:

```bash
SELECT_AGED_VERSION='
const cp = require("child_process");
const pkg = process.argv[1];
const times = JSON.parse(cp.execSync("npm view " + pkg + " time --json", { encoding: "utf8" }));
const cutoff = Date.now() - 24 * 60 * 60 * 1000;
const eligible = Object.keys(times)
  .filter((v) => /^[0-9]+\.[0-9]+\.[0-9]+$/.test(v))
  .map((v) => ({ v, t: new Date(times[v]).getTime() }))
  .filter((x) => x.t <= cutoff)
  .sort((a, b) => a.t - b.t);
if (!eligible.length) {
  console.error("No " + pkg + " stable version published >=24h ago");
  process.exit(1);
}
console.log(eligible[eligible.length - 1].v);
'
SDK_VERSION="$(node -e "$SELECT_AGED_VERSION" @zapier/zapier-sdk)"
DURABLE_VERSION="$(node -e "$SELECT_AGED_VERSION" @zapier/zapier-durable)"
ZOD_VERSION="$(node -e "$SELECT_AGED_VERSION" zod)"
echo "SDK_VERSION=$SDK_VERSION  DURABLE_VERSION=$DURABLE_VERSION  ZOD_VERSION=$ZOD_VERSION"
```

Capture:

- `SDK_VERSION` — the latest `@zapier/zapier-sdk` published at least 24h ago. Use it as the pinned SDK dependency.
- `DURABLE_VERSION` — the latest `@zapier/zapier-durable` published at least 24h ago. Use it for the local `package.json` pin and for `--zapier-durable-version`.
- `ZOD_VERSION` — the latest `zod` published at least 24h ago. Use it for the local `package.json` pin and in `--dependencies`, because the generated `workflow.ts` imports `zod`.

Use exact versions in commands. Do not pass `latest`. Pass the aged `SDK_VERSION` and `ZOD_VERSION` to `--dependencies` and the aged `DURABLE_VERSION` to `--zapier-durable-version` (see Phases 5 and 6) — all are subject to the 24h guard. **Every package the generated `workflow.ts` imports must appear in `--dependencies`**, aged-pinned: the sandbox installs from `--dependencies`, not your local `package.json`, so a missing import (such as `zod`) fails the run with `Cannot find package`.

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

### Use "AI by Zapier" For AI Steps

For any AI / "call an LLM" step — summarize, extract, classify, generate, or analyze text — **always use "AI by Zapier"** (app key `AICLIAPI`) as the step and select the model *inside* it: if the user names a provider or model, set that as the `model_id` (see below); otherwise use its default model. It runs on Zapier's built-in AI credentials (no third-party account required) and bills as normal Zapier tasks, so an agent-built workflow does not silently route to a separate raw-provider app the user must connect and pay for. Discover it with `list-apps --search "AI by Zapier"`; its generic completion action is `get_completion` ("Analyze and Return Data"), alongside `extract_content` (from a URL) and `search_content` (confirm the current set with `list-actions AICLIAPI --action-type write --json`).

**Configuring the `get_completion` step.** Inspect its fields with `list-action-input-fields AICLIAPI write get_completion --json`. The ones that matter for a generated step:

- `instructions` (**required**) — the prompt describing what the AI should do.
- `provider_id` (optional) — the AI provider, needed only when the user names one. Choices are `openai`, `anthropic`, `google`, `azure-openai`, `amazon-bedrock` (`list-action-input-field-choices AICLIAPI write get_completion provider_id --json`). Setting it is what makes `model_id`'s choices resolve.
- `model_id` (**required**, default `"advanced/auto"`) — the model. **For a generic step, pass the default `"advanced/auto"`** — auto-pick a model in the Advanced tier (tiers: `standard`/`advanced`/`premium`) on built-in credentials. **When the user names a provider or model,** set `provider_id` first, then resolve the valid model for it with `list-action-input-field-choices AICLIAPI write get_completion model_id --inputs '{"provider_id":"<provider>"}' --json` (the list is empty until `provider_id` is set) and pass the matching `<provider>/<model>` value (for example `anthropic/claude-sonnet-5`, `openai/gpt-4o`). Do not hardcode a model list — resolve it at build time.
- `authentication_id` (**required**, default `"0"`) — `"0"` is Zapier's built-in AI credentials (the models shown with a Zap icon). Keep `"0"` for the default and any built-in model. A model the user names may not be available on built-in credentials — those require the user's own AI provider account (a custom `authentication_id`); if so, tell the user and use their authentication. `model_id` depends on this field.
- `inputFields` (optional, OBJECT) — extra context fields mapped from earlier steps, merged into the prompt.

So a default AI step needs only a prompt. `model_id` and `authentication_id` are required but have working defaults; pass them explicitly with those defaults (`"advanced/auto"` and `"0"`) so the `runAction` inputs are complete, and no connection alias is needed for the built-in path:

```typescript
const summary = await ctx.step("summarize-with-ai", async () =>
  sdk.runAction({
    appKey: "AICLIAPI",
    actionType: "write",
    actionKey: "get_completion",
    inputs: {
      instructions: `Summarize this in one sentence: ${input.text}`,
      model_id: "advanced/auto",
      authentication_id: "0",
    },
  }),
);
```

Naming a provider or model is **not** a reason to leave "AI by Zapier" — set it as the `model_id` above. Reach for a raw-provider AI app (Anthropic, OpenAI, Google AI, and so on) only when the user explicitly asks for that standalone app, or needs a capability "AI by Zapier" does not offer. When you do, tell the user the step uses their own provider connection and billing, not "AI by Zapier."

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

"Webhooks by Zapier" and other apps with a catch-hook trigger (PayPal, Salesforce, Twilio, WordPress, Wufoo, Zillow, and others) are discovered and configured exactly like any other trigger app — nothing about them is special-cased. Search `list-apps --search "webhook"` (or the specific app name) for its `implementation_id` (for example `WebHookCLIAPI@1.1.0` — an illustrative example, not a version to hardcode; confirm the current version via discovery), then `list-triggers <appKey>` for its catch-hook trigger action. "Webhooks by Zapier" itself is no-auth (`authentication_id: null`) with empty `params`, but confirm its action key via `list-triggers WebHookCLIAPI` rather than hardcoding one — as of this writing it exposes both `hook_v2` (parsed payload; the common default) and `hook_raw` (unparsed body and headers, max 2MB), and that pair of action keys is specific to `WebHookCLIAPI`, not a pattern the other apps share. Other catch-hook apps (PayPal, Salesforce, Twilio, ...) commonly require a connection, because claiming their trigger means calling the provider's API to register a subscription. Do not assume no-auth or empty `params` for those — confirm each app's actual action key, auth, and param requirements via `list-triggers`/`list-trigger-input-fields` (see above) rather than generalizing from "Webhooks by Zapier." Configure them through `--trigger` at publish time (Phase 6) like any other trigger — do not treat them as "no trigger" / manual-only workflows.

## Phase 3: Confirm The Build Plan

Before writing code, present:

```text
Workflow: <kebab-case-name>
Input: { field1, field2 }
Connections:
  alias = connectionId (connection title)
Trigger:
  selected_api.action with params (including "Webhooks by Zapier" or other catch-hook apps), or none for a workflow fired only manually via `trigger-workflow`
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
    "zod": "<pinned zod version>"
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
- Create the SDK client once at module level: `const sdk = createZapierSdk()` above `defineDurable`
- Use Zod for input validation when the workflow has input.
- Keep external side effects (app actions, fetches) inside `ctx.step` calls.
- Make each app action exactly **one** `ctx.step` whose body is a single `return sdk.runAction({...})` call — one `runAction` per step.
- Group validation, input normalization, simple guards, data shaping into steps as needed.
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

Generate durable source that can be turned into a meaningful step graph. Avoid overly dynamic construction.

**`defineDurable` call shape — every call must resolve `run` to a function.** Use either the bare form `defineDurable("workflow-name", async (ctx, input) => { ... })` or the object form `defineDurable({ name: "workflow-name", inputSchema, outputSchema, description, run: async (ctx, input) => { ... } })`. `ctx` is always the first parameter of `run`; `input` is the optional second parameter, so `async (ctx) => { ... }` is also valid. These shapes are invalid and make the workflow fail on its first run with `durable.run is not a function`:

- `defineDurable(async (ctx, input) => { ... })` — a bare function with no name. The function is treated as an options object, so `run` is never set. This is the most common mistake.
- `defineDurable({ name: "workflow-name" })` — object missing `run`.
- `defineDurable({ name: "workflow-name", run: someNonFunction })` — `run` is not a function.

`durable.run is not a function` is a code-shape defect in your `defineDurable` call, not a version mismatch. Do not change the pinned `@zapier/zapier-durable` or `@zapier/zapier-sdk` versions to fix it — correct the call so it passes a `name` and a `run` function.

Default to this parser-friendly shape — module-level `sdk`, hoisted app-key/connection constants, and a bare `runAction` body for each app action:

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

### App-Action Step Shape (Editor Recognition)

The editor renders a `ctx.step` as an **app-action step** (with the app icon) when its body is a single `sdk.runAction({...})` call with `appKey`, `actionType`, and `actionKey` (object literal, or a `const` that resolves to one; the `app` / `action` spellings also work). A string-literal step id (`ctx.step("create-todoist-task", ...)`) and an inline `async () => ...` callback are the recognized form; object form `ctx.step({ name, run })` works too.

Other steps render as plain **code steps** — for example a step with no `runAction`, or with more than one, or one created in a loop with a dynamic id (`` `process-item-${index}` ``). That is expected, not a regression; loops and fan-out legitimately need dynamic ids.

## Phase 5: Test The Workflow

Build `source_files` from `workflow.ts`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"
```

Build the `connections` JSON from the selected aliases. It's a nested object — each alias maps to an object holding a `connectionId` (never a bare string). The same shape is used for `publish-workflow-version` in Phase 6:

```json
{
  "slack_work": { "connectionId": "12345678" },
  "gmail_primary": { "connectionId": "87654321" }
}
```

Before running, tell the user what actions may happen in connected apps and wait for confirmation if there are side effects.

Run the durable:

```bash
zapier-sdk --experimental run-durable "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>","zod":"<pinned zod version>"}' \
  --zapier-durable-version '<pinned durable version>' \
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
  --private \
  --json
```

Omit `--private` only if the user explicitly wants the workflow visible to the broader account.

Capture the returned workflow ID. Then publish the version. The current SDK CLI expects `source_files` as a JSON object, not a path to `workflow.ts`.

For publish, use the same nested `connections` shape as `run-durable` — each alias maps to an object holding a `connectionId`:

```json
{
  "slack_work": { "connectionId": "123-or-uuid" },
  "gmail_primary": { "connectionId": "456-or-uuid" }
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

A "Webhooks by Zapier" or other catch-hook trigger is a real trigger — publish it with `--trigger` using the config captured in Phase 2, the same as any other app trigger.

Publish a workflow with no trigger at all — invoked only manually via `trigger-workflow` — by omitting `--trigger`:

```bash
SOURCE_FILES="$(jq -n --rawfile workflow workflow.ts '{"workflow.ts": $workflow}')"

zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>","zod":"<pinned zod version>"}' \
  --zapier-durable-version '<pinned durable version>' \
  --connections '<publish connection bindings JSON>' \
  --app_versions '<app versions JSON if needed>' \
  --enabled \
  --json
```

Publish a trigger-backed workflow by adding `--trigger`:

```bash
zapier-sdk --experimental publish-workflow-version <workflow-id> "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"<pinned SDK version>","zod":"<pinned zod version>"}' \
  --zapier-durable-version '<pinned durable version>' \
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

Regardless of trigger type, check the matching entry in `triggers[]` from the `get-workflow --json` read-back above for `details.webhook_url` (re-run the same command if enough time has passed since that read that the claim state could have changed). If present, it is the catch URL external services call — show it to the user plainly; unlike the workflow-level `trigger_url`, it is meant to be shared. Most triggers have no `webhook_url`, and that is normal — do not flag its absence.

If you configured a catch-hook trigger in Phase 2 (a "Webhooks by Zapier" or similar catch-hook app/action) and `details.webhook_url` is still absent once the trigger is active, the installed `@zapier/zapier-sdk` may predate this field — run `workflows-doctor` to check for an update, and in the meantime tell the user to copy the URL from the trigger step in the Zapier editor (`https://zapier.com/durables-editor/<workflow-id>`).

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
- Whether the workflow uses a Zapier app trigger, a catch-hook trigger (report its `webhook_url` if available), or no trigger (manual-only via `trigger-workflow`).
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

Loop/fan-out steps use a dynamic id (`` `process-item-${index}` ``), so the editor renders them as code steps — expected for this pattern (see **App-Action Step Shape (Editor Recognition)**).

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
