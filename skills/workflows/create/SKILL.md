---
name: workflows-create
description: Create a durable Zapier workflow from natural language using @zapier/zapier-durable and the Zapier SDK CLI. Use when the user wants to build a Zapier workflow, create an automation, write a durable workflow, build me a Zap that, create a durable that, or automate a multi-step process involving Zapier-connected apps.
license: MIT
metadata:
  author: zapier
  version: "1.8.0"
  sdk_cli_min: "0.85.0"
  sdk_cli_validated: "0.86.4"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Create

Create a complete durable workflow from natural language, test it when appropriate, and deploy it through the Zapier SDK experimental Code Workflows commands.

Use the public SDK CLI path. Do not use `zapier-sdk-code-substrate`.

## Compatibility gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If it reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Prerequisites

Verify at the start:

```bash
zapier-sdk --version
zapier-sdk get-profile --json
zapier-sdk --stability experimental --help
```

Pass `"latest"` for `@zapier/zapier-sdk`. The server resolves it to the newest release the sandbox can install and stores the exact version on publish; drafts store the supplied value verbatim. You need no registry access and no publish-date arithmetic. This is not npm's `latest` tag: the sandbox installs with `pnpm install --config.minimumReleaseAge=1440` and `@zapier/zapier-sdk` publishes several times a day, so that tag frequently points at a release too new to install.

`--zapier-durable-version` sets the runtime engine version; never put `@zapier/zapier-durable` in `--dependencies`. Omit the flag by default; a new draft gets the server's supported version, and updates preserve its stored pin. Pass it explicitly only when carrying forward a version captured from `get-workflow-version` on a republish, or when deliberately pinning or upgrading. Ranges (`^1.2.3`, `~1.2`) are rejected with a 400 for the durable runtime version, so an explicit value must be an exact version or `latest`.

Only `@zapier/zapier-sdk` is resolved server-side; other dependencies are stored as written and re-resolved on every install, so a floating spec can change between ticks of one run. Declare every dependency the source imports when updating the draft, including a pinned `zod`, so the unpublished test has everything it needs. The sandbox installs from `--dependencies`, not your local `package.json`, so a missing import fails the run with `Cannot find package`.

The user must also have app connections configured at https://zapier.com/app/assets/connections for any app actions the workflow will run.

## Surface toolbox (SDK CLI)

- Discover apps/actions/connections: `zapier-sdk list-apps --search "<name>" --json`, `list-connections <appKey> --owner me --json`, `list-actions <appKey> --action-type <type> --json`, `list-action-input-fields`, `get-action-input-fields-schema`, `list-action-input-field-choices`
- Discover triggers: `zapier-sdk --stability experimental list-triggers <appKey> --json`, `list-trigger-input-fields`, `list-trigger-input-field-choices`
- Test probe: `zapier-sdk run-action <appKey> <actionType> <actionKey> --connection <connectionId> --inputs '<json>' --json`; the Phase 2 trigger sample is `run-action <appKey> read <triggerKey> --connection <connectionId> --inputs '<published params>' --max-items 1 --json`
- Stage: `zapier-sdk --stability experimental create-workflow`, `create-workflow-draft`, `update-workflow-draft`, `get-workflow-draft`
- Test run: `zapier-sdk --stability experimental run-workflow-draft <workflow-id> <draft-id> <draft-revision> --input '<JSON>' --json`, `get-workflow-run <run-id> --json`
- Deploy: `zapier-sdk --stability experimental publish-workflow-draft`, `discard-workflow-draft`
- Verify and run: `zapier-sdk --stability experimental get-workflow`, `list-workflow-versions`, `get-workflow-version`, `trigger-workflow`, `get-trigger-run`, `list-workflow-runs`, `get-workflow-run`

`selected_api` is `implementation_id` on `list-apps`/`get-app`.

For a complete action input contract, call `zapier-sdk get-action-input-fields-schema <appKey> <actionType> <actionKey> --json` alongside field discovery. Its `data` is the schema document, not the editable-field array returned by `list-action-input-fields`. Pass the same settled inputs and connection context; use the installed command's `--help` for supported flags.

For an AI by Zapier step, load the installed `workflows-ai-by-zapier` companion for the SDK-specific discovery handoff. It supplements the action-owned schema, not a second configuration contract. If the companion is not installed, use the discovery flow here rather than blocking a step whose contract is available.

Generate the workflow as a local project — `<kebab-case-workflow-name>/` containing `package.json`, `workflow.ts`, and any helper modules the source imports (`lib/format.ts`) — and report where the project lives when finishing, naming its files if there is more than one. `package.json` is for local type-checking only and never ships in `source_files`; later phases build that map by walking this directory, so keep it to this workflow's own files.

If you add a build script to `package.json`, use `--skipLibCheck` for now to avoid type-check failures from SDK/durable transitive type declarations:

```json
{
  "scripts": {
    "build": "tsc --target es2022 --module nodenext --moduleResolution nodenext --skipLibCheck --outDir dist workflow.ts"
  }
}
```

`durable.run is not a function` is a code-shape defect in the `defineDurable` call, not a version mismatch. Do not change the `@zapier/zapier-durable` or `@zapier/zapier-sdk` versions to fix it; correct the call so it passes a name and a `run` function.

The entrypoint may also end `.mts`, `.js`, `.mjs`, `.cjs`, or `.cts` rather than `.ts`, but there must be exactly one. Publish rejects a top-level `index.*`, `package.json`, or `.zapierrc`, and any `_zapier_*` name, as reserved — a nested `lib/index.ts` is fine.

Create a complete durable workflow from natural language, test it, deploy it, and verify it is live.

A workflow is a TypeScript module using `defineDurable` from `@zapier/zapier-durable`. Each `ctx.step()` is journaled: when a run retries or replays, a completed step returns its recorded result instead of repeating the work. Published workflows run on Zapier's infrastructure independently of this conversation.

The surface-specific sections of this skill map each capability used below — action discovery, trigger discovery, connection listing, test probes, publishing, and test runs — to your surface's concrete tools or commands. When this skill says "your discovery tool" or "your publish mechanism", use that mapping.

## Phase 1: Understand the intent

Extract from the user's request:

1. Steps and ordering.
2. Apps involved.
3. Data passed between steps.
4. Manual input fields or trigger input fields.
5. Conditional logic and empty-result behavior.
6. What fires the workflow — an app trigger, a schedule, an external webhook POST, or manual runs only.
7. Waits, callbacks, retries, or human approval gates.
8. Start mode (required — see below).

Summarize the proposed workflow before discovery. Ask focused clarifying questions only for genuinely required intent with no safe default — an unresolved ambiguous destination, a missing recipient, or what to do when a search returns nothing. Do not generate source until the user agrees on the workflow shape.

### Classify the start mode (required)

Every workflow has exactly one start mode, and you must decide it here:

- `trigger` — the workflow starts on its own, on a schedule or in response to an external event. Its final deployed version carries a `trigger` configuration and runs without anyone invoking it.
- `manual` — the workflow has no trigger and runs only on-demand through your surface's workflow-run mechanism. This is a deliberate choice, not the absence of a trigger.

Default to looking for a trigger in the build instruction. Infer from intent cues: recurring or time words ("every morning", "daily", "on a schedule") mean a scheduled `trigger`; "when X happens in `<app>`" or "whenever a new `<record>` is created" mean an event-driven `trigger`; explicit "manually", "on demand", or "when I run it" means `manual`.

If the start mode is ambiguous — no clear trigger cue and no explicit manual cue — ask the user whether to run it manually on-demand or attach a trigger, and which. Never silently assume `manual` just because no trigger was named. A triggerless workflow published on an unconfirmed assumption is the exact failure this classification prevents.

Carry the chosen start mode forward: confirm it in the Phase 3 build plan, and make it the gate for the Phase 5 deployment verification.

### What is not missing intent

- A named resource — a Slack `#channel`, a spreadsheet title, a folder or project name — is supplied intent. Resolve its opaque API identifier during discovery (see Phase 2) before asking the user for anything.
- An optional parameter, a field value returned as the product default, or an implementation preference with a safe default is not missing intent. Use the default and proceed.
- A natural-language scope for a bounded AI search step — such as "active Platform epics" — is supplied intent. Put that scope in the AI step's instructions; do not require the user to translate it into exact query syntax.

### Semantic event subsets

When the user describes a semantic subset of an app event — "when a vendor asks to integrate", "when a message looks urgent", "when feedback is actionable" — do not force them to invent a label, sender list, or keyword rule before building. Available sender, subject, body, or label filters are not reliable semantic filters unless the user supplied a deterministic rule for them. Configure the broad source event with its optional filters empty, then evaluate and skip non-matching events inside the workflow using a bounded AI step. Ask about a narrower trigger only when the broad event would be unsafe, prohibitively noisy, or the user explicitly requests one.

## Phase 2: Discover apps, actions, connections, triggers, and fields

Use your surface's discovery tools to look up real identifiers. Never invent app keys, action keys, action types, field names, field values, app versions, or connection IDs; training knowledge is stale by construction.

Work one app/action at a time. Record discovered keys, types, fields, choices, connection IDs, and output shapes. If several candidates are plausible, show them and let the user choose. Do not introduce apps discovery did not return.

Respect returned editable fields, choices, schemas, and locks. Resolve dependencies with the same action/version, connection, and settled parent inputs; refresh when those change. Missing nested contract: use only a version-scoped installed companion fallback, else report the limitation. Metadata and fallbacks grant no permissions.

### Resolve named resources before asking

A human-readable destination in the request is supplied intent, not a missing required value. Resolve it to the API identifier the action needs:

1. Prefer the action field's dynamic choices when the field exposes them.
2. Otherwise use a documented read/list action or API for the app with the selected connection to look up the resource.
3. Continue automatically on one exact match.
4. Ask the user only when lookup returns no match, multiple plausible matches, or the available tool surface cannot resolve it.

Do not ask the user to paste an opaque ID before attempting the available lookup. If the action accepts the supplied human-readable name directly, that is the final fallback. For an unspecified posting identity, use the action's default; prefer bot-style posting for unattended workflows when the action requires a choice.

### Use AI by Zapier for AI steps, agentic tool loops, and semantic work

If your surface provides an AI by Zapier companion, load it using that surface's instructions before configuring the step.

Use a bounded AI by Zapier step when the workflow must infer meaning rather than copy or calculate from a complete rule. Summarization, generation, varied-prose extraction/classification, risk analysis, fuzzy matching, and disambiguation qualify even when the user never says “AI.” Direct mapping, exact formatting, arithmetic, supplied regexes/keyword tables, and fully specified conditions stay deterministic. Prefer AI by Zapier unless the user explicitly requests another provider app or needs a capability AbZ lacks; naming a provider/model alone is not a reason to leave AbZ. Honor an explicit Code by Zapier request.

Use prompt-only AbZ when the trigger and previous steps contain all evidence. Embed a read/search tool only when the model must choose, inspect, adapt, or repeat a lookup; predetermined searches and final side effects remain durable workflow steps after the AI returns typed output.

Discover the current `get_completion` action, its editable fields, dependent choices, and complete input schema when available. Metadata owns the contract; if schema is unavailable, use only your surface's documented AbZ fallback, not labels or remembered examples. Use live model defaults unless the user requests another supported choice. `inputs.authentication_id: "0"` is the managed-model credential input, not an outer workflow or nested-tool connection. Do not invoke `get_completion_agentic`.

Pass stable instructions separately from trigger/prior-step context, configure outputs from the discovered contract, and verify the actual result. Default text output is `result.data[0].output`; configured outputs live at their named item fields.

The durable workflow still owns its trigger, branches, destinations, approvals, side effects, and completion behavior; a bounded LLM/tool loop is not a persistent agent automation.

### Map connections

Use connection discovery or server-side binding for each app that needs authentication. Where you choose aliases, use short snake_case names such as `slack_work`; app-key-binding servers supply their own convention. Outer SDK aliases are resolved by test/publish; never embed tokens or raw credentials.

Action-input connection references are separate. Supply a discovered identifier only where the action schema requires one, in its advertised format; do not substitute an outer alias, decode an ID, or assume outer binding rewrites nested inputs. If your surface cannot discover a required reference, report that limitation.

Some built-in apps are no-auth by design — Schedule, Webhooks, Code, Formatter, Filter, Delay by Zapier. They get no alias and do not appear in the connection bindings. An app with schema-owned authentication is the same case, such as AI by Zapier passing its discovered `authentication_id` as an action input.

### Confirm action output shapes

Test any action whose output feeds a later step rather than guessing its fields, using your surface's read-probe mechanism. When a probe result is too large to read in full, look at one record with its values shortened rather than at its key names alone, which hide whether a value is a string or an object. A write probe can create or change real data, so explain the side effect and wait for confirmation before running one.

Inside a workflow, `sdk.runAction` returns `{ data, nextCursor }`. Workflow source reads the first item as `result.data[0]`, or the full item list as `result.data`. Do not invent fallback chains such as `value.results || value.items` for action output.

### Discover triggers

For a triggered workflow, discover the trigger, its configuration fields, and its field choices with your surface's trigger-discovery tools. Build the trigger configuration from discovered values:

```json
{
  "selected_api": "ExampleCLIAPI@1.2.0",
  "action": "new_row",
  "authentication_id": "connection-id-or-null",
  "params": {}
}
```

`selected_api` is the implementation identifier from the discovered trigger result, never a display name. Send it bare, `@latest`-suffixed, or version-pinned (`<app_key>@<app_version>`); publish resolves it, and the version the publish call returns — and any later version read-back — carries the pinned value. Reuse that pinned value on republishes, so a later publish does not move to a newer app version unnoticed.

Match each trigger parameter's discovered type: array fields must be JSON arrays (`"dow": ["1"]`), string fields plain strings (`"hod": "9:00 AM"`) — a scalar where an array is expected is rejected at publish time with an explicit error. Use `null` or omit `authentication_id` for no-auth triggers; otherwise use the selected trigger connection ID.

Webhooks by Zapier and other catch-hook apps are real triggers. Discover and configure them like any other trigger. Confirm their action key, authentication, and parameters instead of assuming every catch hook is unauthenticated — apps whose claim registers a subscription with the provider commonly require a connection. Webhooks by Zapier itself is no-auth (`authentication_id: null`) with empty `params` and exposes `hook_v2` (parsed payload, the common default) and `hook_raw` (raw body and headers, 2MB max); confirm the key via discovery — that pair is specific to it, not a shared pattern. A catch hook has no record to sample: type the fields the request says the sender will post.

### Sample the trigger

1. Run the read action whose key is the trigger's own key — never a look-alike action — with your surface's read probe and exactly the `params` you will publish.
2. Read one whole record. Never cut the output by lines.
3. Type only what the record showed (Phase 4); a field you did not see gets no fixed type.

### Learn from an existing workflow when useful

If a similar working workflow exists, it can provide realistic source, connection bindings, and trigger configuration. This is optional, not a required first step. Read it with your surface's workflow-inspection tools and borrow only the patterns relevant to the new workflow.

## Phase 3: Confirm the build plan

Present this plan:

```text
Workflow: <kebab-case-name>
Input: { field1, field2 }
Connections:
  alias = connectionId (connection title)
Start mode: trigger (<selected_api.action with typed params>)
Trigger sample: <trigger key> with <params> → <keys seen> — or — none, fields read untyped
  — or —
Start mode: manual — on-demand only
Steps:
  1. <step-name> - <AppName>.<actionType>.<actionKey>
  2. <step-name> - <AppName>.<actionType>.<actionKey>
Return: <summary of output>
```

The Start mode line is required and must state exactly one of the two modes classified in Phase 1.

If required details are missing or ambiguous, stop here and ask a focused question. If everything was supplied or resolved unambiguously through discovery, the user's request to create the workflow is already approval: present the plan briefly and proceed in the same turn.

## Phase 4: Write the workflow source

Source is a `{ path: contents }` map. Every source submission replaces the whole map with no server-side merge: a file left out is deleted, so always send the complete set.

Exactly one top-level entrypoint, normally `workflow.ts`. Keep a small workflow in it; when it grows, move pure helpers, long schemas, or prompt text into relative-path modules with the extension (`./lib/format.ts`, stored under that key), keeping `defineDurable` and every `ctx.step` in the entrypoint so the editor can read the step graph.

The entrypoint must:

- Import `defineDurable` from `@zapier/zapier-durable` and `createZapierSdk` from `@zapier/zapier-sdk` as static top-of-module `import` statements — every package any source file needs, declared the same way. Never import inside a function or through a dynamic `import()`.
- Pin every dependency you declare to an exact version you've verified is real and at least 24 hours old — never invent or guess one. The registry document at `https://registry.npmjs.org/<name>` (scoped: `@scope%2Fname`) lists each version's publish time under `time`. `@zapier/zapier-sdk` is the exception: an exact pin or the literal `"latest"` both work, since the platform resolves `"latest"` to the version it actually installs. `@zapier/zapier-durable` is the runtime engine itself: its version is set by the publish step, never declared as a dependency.
- Create one SDK client at module scope: `const sdk = createZapierSdk()`.
- Use Zod to validate workflow input when it exists, pass the schema as `inputSchema`, and normalize stringified input before validation. Require only what the run cannot proceed without; mark every field a trigger delivers `.nullable().optional()` — `.optional()` or `.default()` alone still throws on `null`, which trigger payloads send routinely — and read it with a `??` fallback at the use site.
- Put every external call in a named `ctx.step`. Each app-action step contains exactly one `sdk.runAction`; an authenticated HTTP step contains one `sdk.fetch`.
- Keep deterministic validation, branching, guards, and data shaping outside steps.
- Put replay-variant values such as `new Date()`, `Date.now()`, and `Math.random()` inside steps so they are journaled once.
- Use the exact discovered `read`, `search`, or `write` action type.
- Use aliases for outer SDK connections; follow "Map connections" for schema-owned action-input references.
- Use unique, descriptive kebab-case verb-noun step names — `find-jira-issue`, `send-approval-email` — and preserve them when modifying a published workflow. Renaming a step loses its journal identity. Avoid generic names like `step-1`.

A sampled record maps to its schema key by key: `"user": { "id": "U0…", "name": "alice" }` becomes `user: z.object({ id: z.string(), name: z.string() }).loose().nullable().optional()`; a key the sample never showed becomes `z.unknown()`, narrowed where it is used (`typeof v === "string" ? v : v?.id`).

Input may arrive as a JSON string:

```typescript
function normalizeInput(rawInput: unknown): unknown {
  if (typeof rawInput === "string") {
    return JSON.parse(rawInput);
  }
  return rawInput;
}
```

### Use a valid, editor-friendly module shape

Every `defineDurable` call must resolve `run` to a function. Prefer the object form `defineDurable({ name, inputSchema, run })`; `defineDurable("name", run)` also works. Do not pass a bare function without a workflow name or an object without `run`; those fail with `durable.run is not a function`.

Default to module-level SDK and constants, a named durable, and a direct `runAction` body for each app step:

```typescript
import { defineDurable } from "@zapier/zapier-durable";
import { createZapierSdk } from "@zapier/zapier-sdk";
import { z } from "zod";

const sdk = createZapierSdk();

const InputSchema = z.object({
  ticketId: z.string(),
  label: z.string().nullable().optional(),
});

const JIRA_APP_KEY = "JiraSoftwareCloudCLIAPI";
const JIRA_CONNECTION = "jira_work";
const SLACK_APP_KEY = "SlackCLIAPI";
const SLACK_CONNECTION = "slack_work";
const SLACK_CHANNEL = "C0123456";

const workflow = defineDurable({
  name: "notify-about-jira-issue",
  inputSchema: InputSchema,
  run: async (ctx, rawInput) => {
    const input = InputSchema.parse(normalizeInput(rawInput));

    const issuePage = await ctx.step("find-jira-issue", async () =>
      sdk.runAction({
        appKey: JIRA_APP_KEY,
        actionType: "search",
        actionKey: "search_issues",
        connection: JIRA_CONNECTION,
        inputs: { query: input.ticketId },
      }),
    );

    const issue = issuePage.data[0];
    if (!issue) {
      return { skipped: true, reason: "issue-not-found" };
    }

    const label = input.label ?? "Jira";
    const message = `${label} ${issue.key}: ${issue.summary}`;

    const notification = await ctx.step("notify-slack-channel", async () =>
      sdk.runAction({
        appKey: SLACK_APP_KEY,
        actionType: "write",
        actionKey: "send_channel_message",
        connection: SLACK_CONNECTION,
        inputs: { channel: SLACK_CHANNEL, text: message },
      }),
    );

    return { notification };
  },
});
```

A missing or renamed optional trigger field is never a reason to stop: resolve it with a fallback — `input.label ?? "Jira"` above — and run the action; never `throw` or `return` early because an optional value did not arrive. Spell optional fields `.nullable().optional()`, not `.nullish()` — other product surfaces read only that spelling.

To keep keys the schema does not name, add `.loose()` to the object schema. Use `z.record(z.string(), z.unknown())` or `z.looseObject({})` only when a payload has no known fields at all, and never single-argument `z.record(z.unknown())` — it crashes at parse on the platform's zod.

The Zapier editor renders a `ctx.step` as an app-action step (with the app icon) when a string-literal step id has an inline callback whose body is a single direct `sdk.runAction` call with `appKey`, `actionType`, and `actionKey`. Steps with no action, multiple actions, or dynamic loop ids render as code steps; that is expected for those patterns — loops and fan-out legitimately need dynamic ids.

### Reach apps only through the SDK

Use `createZapierSdk()` with published aliases for outer connections, or schema-owned action-input references as described in "Map connections". There is no global Zapier client, no connection object on `ctx`, and no connection token in `process.env`.

```typescript
await ctx.step("send-slack-message", async () =>
  sdk.runAction({
    appKey: "SlackCLIAPI",
    actionType: "write",
    actionKey: "direct_message",
    connection: "slack_work",
    inputs,
  }),
);

const gitlabUser = await ctx.step("fetch-gitlab-user", async () => {
  const response = await sdk.fetch("https://gitlab.com/api/v4/user", {
    connection: "gitlab_work",
    method: "GET",
  });
  if (!response.ok) {
    throw new Error(`GitLab returned ${response.status}`);
  }
  return response.json();
});

// Wrong: ctx.zapier and ctx.connections are undefined.
await ctx.zapier.fetch(url, { connection: ctx.connections.slack });
```

Prefer `sdk.runAction` when a Zapier action exists — it handles dynamic and dependent fields, app-specific auth schemes, and normalized responses. Use authenticated `sdk.fetch` only when no action provides the required behavior. Consume the `Response` inside the step and return serializable JSON or text; never return the raw response or body stream as step output.

### Filter pattern

Use an early return to filter out runs that don't meet a condition, and keep the side-effect-free condition logic outside `ctx.step` — filters add no value to the step graph. For complex multi-condition filters, use named const bindings:

```typescript
const tags = input.tags ?? [];
const isActiveAndUrgent = input.status === "active" && tags.includes("urgent");
const isHighPriority = (input.priority ?? 0) > 8;
const shouldRun = isActiveAndUrgent || isHighPriority;

if (!shouldRun) {
  return { skipped: true, reason: "filter-did-not-match" };
}
```

### Durable patterns

Keep waits at workflow scope, not inside a step:

```typescript
await ctx.wait("wait-before-followup", 3600);
```

Journal replay-variant values once:

```typescript
const createdAt = await ctx.step("capture-created-at", async () =>
  new Date().toISOString(),
);
```

Use callbacks for human approval:

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
  return { skipped: true, reason: "denied" };
}
```

Use `Promise.all` outside steps for independent work, with one step per item:

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

Use step retries for flaky external calls:

```typescript
const result = await ctx.step({
  name: "call-flaky-service",
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

## Phase 5: Test, publish, and verify

The mechanics of testing and publishing are surface-specific — follow your surface's sections. The invariants are not:

- Default to a private workflow unless the user explicitly asks for account-wide visibility.
- Validate the workflow with a real test run before it goes live with its trigger. If your surface can run source directly without creating a workflow, test before creating. If it can execute an unpublished draft (draft test runs), test the draft unpublished and publish only once the test passes. Only when neither exists, publish trigger-less or disabled first, test, and add the trigger only after the test passes.
- Before a test that can change connected apps, explain each likely side effect and wait for confirmation. Prefer a harmless representative input in the sampled record's shape — when the workflow filters events before an external write, a clearly non-matching sample exercises the safe skip path. This warning is not a second approval gate when the user already asked to create the workflow; ask first only for destructive, costly, sensitive, or otherwise unexpected test effects.
- Fix the source and retest until the test result matches the confirmed plan. Publish only the tested source. Never leave an untested version live.
- Trigger claiming is asynchronous and can fail silently. After publishing a triggered workflow, poll your surface's workflow read-back until the trigger is active and the workflow has the intended enabled state. Treat a failed claim as a failed deployment even if the workflow remains enabled. Do not report success until both are verified from tool results — never infer or claim activation. Transitional read-back states (`unclaimed` / `pending`) may just need more polling.
- Verify the deployment against the confirmed start mode, not merely against `enabled` — a triggerless workflow reads back as `enabled: true`, so an `enabled` check alone silently passes a workflow that was supposed to have a trigger and doesn't. The trigger's actual presence on the workflow read-back is the authority: a `trigger`-mode workflow must read back with its trigger present, a `manual`-mode workflow with none. Reconcile a mismatch with the user rather than reporting success.
- If the trigger exposes a `webhook_url`, show it to the user — it is the catch URL intended for external services, and unlike a workflow-level trigger/invoke URL it is meant to be shared. Most triggers have no `webhook_url`; that is normal. If a catch-hook trigger is active but no `webhook_url` is surfaced, point the user to the trigger step in the editor link rather than inventing a URL. Do not print a workflow-level trigger URL that invokes the workflow as the authenticated account unless the user explicitly asks.

Finish by reporting:

- Workflow name and ID.
- Whether testing passed.
- Whether it is enabled.
- Whether it is private or account-visible.
- The confirmed start mode: `trigger` (an app trigger or catch-hook trigger) or `manual` (on-demand only), and that the start-mode gate confirmed the deployment matches it.
- The trigger's `webhook_url`, when present.
- The editor link: `https://zapier.com/workflow/<workflow-id>`.

## Failure signatures

- An existing action reports action-not-found: the workflow likely used the wrong `actionType`; inspect the action and use the exact discovered `read`, `search`, or `write` type.
- A call fails while reading `fetch` or a connection from `undefined`: the source used `ctx.zapier`, `ctx.connection`, or `ctx.connections`; replace it with the module-scope `createZapierSdk()` client and a connection alias.
- A triggered workflow becomes disabled after publish: the asynchronous trigger claim failed; verify that `selected_api`, the action key, `params`, and `authentication_id` all come from one discovered trigger result, then republish.

## Constraints

- Never embed credentials, tokens, or secrets in source. Use outer connection aliases and only schema-advertised, discovered references inside action inputs.
- Never invent app keys, action keys, action types, field names, trigger values, versions, or connection IDs.
- Confirm before any run, write probe, or publish that may cause side effects.
- Read and fix publish errors rather than guessing around them.

## SDK CLI mechanics: test, deploy, verify

### Phase 5 (CLI): create the workflow, stage a draft, and test

Create a private workflow container first, then create its draft. The container starts disabled with no published version. Capture the workflow ID and draft ID from the responses:

```bash
zapier-sdk --stability experimental create-workflow "<workflow-name>" --description "<brief>" --private --json
zapier-sdk --stability experimental create-workflow-draft <workflow-id> --json
```

Build `source_files` by walking the project directory, so every file it holds is carried and none is silently dropped:

```bash
WF_DIR="<working-directory>/<kebab-case-workflow-name>"

SOURCE_FILES="$(cd "$WF_DIR" && find . -type f ! -name package.json ! -path './node_modules/*' -print \
  | sed 's|^\./||' \
  | while IFS= read -r f; do jq -n --arg k "$f" --argjson v "$(jq -Rs . < "$f")" '{($k): $v}'; done \
  | jq -s 'add')"
```

This keys each file by its path relative to the project (`lib/format.ts` stays `lib/format.ts`) and reproduces its bytes exactly, trailing newline included. Do not hand-roll a one-key `{"workflow.ts": …}` map: a map that lost a file looks exactly like one that worked, and the publish that follows deletes that file from the workflow.

```bash
zapier-sdk --stability experimental update-workflow-draft <workflow-id> <draft-id> "$SOURCE_FILES" \
  --dependencies '{"@zapier/zapier-sdk":"latest","zod":"4.3.6"}' \
  --connections '{"slack_work":{"connectionId":"12345678"}}' \
  --app-versions '{"SlackCLIAPI":{"implementationName":"SlackCLIAPI","version":"1.42.1"}}' \
  --trigger '<trigger config JSON, for triggered workflows>' \
  --json
```

For a confirmed manual workflow, replace `--trigger` with `--manual`. For a triggered workflow, pass its configuration as one JSON `--trigger` object. Omit unused `--app-versions` and `--connections` options, and replace example values with discovered values. Each connection alias maps to an object containing `connectionId`.

Do not use the old `--trigger-app`, `--trigger-action`, `--trigger-auth`, or `--trigger-params` flags. The current trigger path is the single JSON `--trigger` object.

Take app implementation/version information from SDK discovery output, such as `list-apps`, `get-app`, `list-actions`, or trigger/action result metadata. If no implementation/version binding is exposed, omit `--app-versions` rather than guessing. Do not pass placeholder text like "if needed" to the CLI.

Before updating the draft, confirm its flags match the start mode confirmed in Phase 3: `Start mode: trigger` passes `--trigger` and not `--manual`; `Start mode: manual` passes `--manual` and not `--trigger`. Pass exactly one. A version is either triggered or `manual: true`, never both, and the platform rejects both together. The start-mode decision is required even though the platform treats its `manual` input as optional: that flag is write-only and not a required field, and enforcement is per-account and flag-gated, so the optionality is a staged-rollout artifact, not permission to skip the decision. Marking manual is the deliberate branch, not a fallback for when a trigger was hard to configure: if the user asked for a trigger, a failure to build its config is a blocker to resolve, never a reason to drop to manual.

Read the saved draft and capture its `draft_revision`, then run that revision:

```bash
zapier-sdk --stability experimental get-workflow-draft <workflow-id> <draft-id> --json
zapier-sdk --stability experimental run-workflow-draft <workflow-id> <draft-id> <draft-revision> \
  --input '<JSON matching input schema>' \
  --json
```

Omit `--input` when the workflow takes no input. The command starts an unpublished draft run associated with the workflow and returns before execution finishes.

Capture the returned `id` and poll `get-workflow-run <run-id> --json`. The test passes when:

- `status` is `"finished"`, `output` matches the confirmed plan, `error` is `null`, and top-level `errors` is empty.
- `kind` is `"draft"`, and `workflow_id`, `workflow_draft_id`, and `draft_revision` match the draft you tested.

If the test fails, fix the source, rebuild the complete map, update the same draft, and test its new revision. If a revision conflict occurs, re-read the draft and reconcile the changes before testing again.

### Phase 6 (CLI): publish the tested draft

Publish only after the test passes, using the tested revision so concurrent edits cannot go live untested:

```bash
zapier-sdk --stability experimental publish-workflow-draft <workflow-id> <draft-id> \
  --draft-revision <tested-draft-revision> \
  --enabled \
  --json
```

Publishing consumes the draft and creates an immutable workflow version. If a revision conflict occurs, re-read the draft and test its current revision before publishing. If the user wants to review in the Zapier editor before going live, leave the tested draft unpublished and hand them its editor link; publish on their go-ahead. Discard unpublished work only with explicit confirmation.

### Phase 7 (CLI): verify

Read back with `get-workflow`, `list-workflow-versions`, `get-workflow-version`. For triggered workflows, re-read `get-workflow` (poll; the claim is asynchronous) and confirm `enabled: true` — if it is `false` despite `--enabled`, the trigger claim failed; check that `selected_api`, the action key, `params`, and `authentication_id` all come from one discovered trigger result (a wrongly shaped `params` value would already have failed the publish).

Gate on the start mode confirmed in Phase 3, not on `enabled` alone:

- `Start mode: trigger` requires both `enabled: true` and a non-empty `triggers[]` on `get-workflow`. An empty `triggers[]` means the trigger was dropped or never sent; do not report the workflow as done.
- `Start mode: manual` requires an empty `triggers[]`. A non-empty `triggers[]` is a mismatch; stop and reconcile with the user.

`triggers[]` is the authority for this gate. The write-only `manual` flag never appears on `get-workflow` or a version read-back, so do not look for it there.

If a catch-hook trigger is active but its `triggers[]` entry has no `details.webhook_url`, the installed `@zapier/zapier-sdk` may predate that field. Run `workflows-doctor` to check for an update, and meanwhile point the user to the trigger step in the editor link.

To run manually (after confirming side effects): `trigger-workflow <workflow-id> --input '<JSON>' --json`. If it returns a trigger ID before a run ID is available, bridge with `get-trigger-run <trigger-id> --json`, then inspect `list-workflow-runs` / `get-workflow-run`.
