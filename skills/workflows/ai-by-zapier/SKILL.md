---
name: workflows-ai-by-zapier
description: Configure a basic AI by Zapier step with runtime context, outputs, typed integration tools, public web search, and a failure exit. Use when a workflow needs language reasoning or AI-directed app/web lookups, including when nested schema discovery is unavailable.
license: MIT
metadata:
  author: zapier
  version: "0.3.0"
  sdk_cli_min: "0.67.4"
  refresh_source: "zapier/agent-skills"
---

# AI by Zapier Workflow Steps

Use this companion with `workflows-create` or `workflows-modify`; it sets up the bounded AI step but does not replace the workflow lifecycle. If the request involves creating, testing, publishing, or enabling a complete workflow and neither lifecycle skill is loaded, load the appropriate one first.

## SDK CLI discovery

Use the public SDK CLI's live catalog before writing the AI step:

- Find the current implementation: `zapier-sdk list-apps --search "AI by Zapier" --json`.
- Inspect actions: `zapier-sdk list-actions <appKey> --json`.
- Inspect editable fields: `zapier-sdk list-action-input-fields <appKey> <actionType> <actionKey> --json`.
- Prefer the complete contract: `zapier-sdk get-action-input-fields-schema <appKey> <actionType> <actionKey> --json`; retain the whole `data` schema, including nested `contentSchema` and root references. If that discovery is unavailable, use the version-scoped basic fallback below, not an invented nested contract.
- Resolve dependent choices: `zapier-sdk list-action-input-field-choices` with the settled parent inputs.
- Resolve an embedded app's connection: `zapier-sdk list-connections <appKey> --owner me --json`. Match the intended account by its returned name/label, paginate as needed, and ask when ambiguous. If none is usable, use the installed SDK's supported connect/reconnect flow and rediscover after the user finishes; never ask for raw credentials.

Keep three namespaces separate:

- Managed model credentials: `inputs.authentication_id: "0"`; no outer connection lookup is needed for this selector.
- Model BYOK: use the `authentication_id` field choice's returned value after settling its provider dependencies, not a UUID from `list-connections`.
- Embedded app tools: copy the selected connection's public UUID `id` from `list-connections` unchanged into `tools[].connection_id`. Use a version whose live contract or the validated fallback supports this field. A legacy numeric `auth_id` is usable only when discovery supplies that format; never decode or coerce a UUID. For connectionless tools, omit both references.

Outer SDK `connection` aliases do not populate these action inputs. For an embedded tool, put the UUID in that tool object, not in the outer AbZ call's `connection`. Use the same chosen connection and settled parent values for the target action's field/choice discovery. If the selected version does not accept the reference, report that version/contract mismatch instead of inventing another identifier.

Use the exact command signatures shown by the installed CLI's `--help`; command flags may evolve. Record the discovered implementation, action, fields, choices, defaults, and connection metadata so you do not repeat calls or fall back on remembered values.

Configure a basic AI by Zapier step: instructions, runtime context, outputs, integration actions, and public web research. Use the live action schema when available; the shapes below are a bounded fallback for callers whose field discovery omits the nested contract.

## Discover and choose the scope

1. Discover AI by Zapier and its normal `get_completion` action (`write`). Use it for both supplied-context and tool-enabled work, not `get_completion_agentic`.
2. Read editable fields, defaults, and dependent choices using your surface's discovery instructions. If a complete schema is available, retain its `contentSchema`, definitions, references, and annotations; prefer it over these examples.
3. This fallback was checked against `AICLIAPI@4.0.27`. Public UUID tool connections are supported from `4.0.26`. It documents the basic shapes below, not every possible capability or every future version. Do not extrapolate an unsupported shape or override conflicting live metadata.
4. Use the live model default unless the user requests a different supported model. All examples use `authentication_id: "0"`; the tool-enabled examples use `premium/auto`, the checked version's managed default, and the prompt-only example uses `standard/auto`. `standard/auto` is prompt-only and cannot carry tools. For other models, resolve provider, authentication, and model choices in their dependency order; a visible model is not proof of tool support or managed-credential eligibility.

Use language reasoning on supplied data without external lookups when it is sufficient. Add integration tools when the AI needs to choose an action or adapt a lookup. Keep predetermined searches and known final side effects as ordinary durable workflow steps; an embedded write needs an explicitly approved, bounded decision loop. Adding a tool enables a capability; it does not call it.

For this basic recipe, consider only integration actions and the three builtins `fail`, `web_search`, and `web_scrape`. Do not add other builtins, knowledge-source configuration, prompt-scoring helpers, or tier-classification calls. Those are not required to configure this step.

## Typed tool contract

These types describe the decoded entries in AbZ's `inputs.tools` array, not MCP tool definitions. Do not send this TypeScript or a JSON Schema as the value of `tools`.

```typescript
type ToolInput =
  | { type: "guess" | "default" | "ignore" }
  | { type: "locked"; value: string | string[] | Record<string, string> }
  | { type: "guess-locked"; value: string[] };

type IntegrationTool = {
  type: "integration";
  id: string;
  selected_api: string;
  action_key: string;
  action_type: "read" | "search" | "write";
  display_name: string;
  description: string;
  app_needs_auth: boolean | null;
  connection_id?: string | null;
  auth_id?: number | null;
  inputs?: Record<string, ToolInput> | null;
  input_labels?: Record<string, string | string[]> | null;
  approval_policy?: "always_allow" | "require_approval" | "deny" | "auto";
};

type BuiltinTool = {
  type: "builtin";
  id: string;
  builtin_tool_name: "fail" | "web_search" | "web_scrape";
};

type BasicTool = IntegrationTool | BuiltinTool;
```

- Generate `id` locally, unique across the entire tools list, and keep it stable when editing. It is not a connection UUID, app/action identifier, or MCP `tool_name`.
- Copy `selected_api`, `action_key`, and `action_type` from discovery, retaining an app version when supplied. Do not substitute display names, an MCP wrapper name, or a synthetic trigger alias. Use the discovered capability for `display_name` and `description`.
- `app_needs_auth` describes the target app: true for an authenticated app, false only when known to be connectionless, null if unspecified. Null does not remove an authentication requirement.
- For authenticated tools, copy a discovered public connection UUID unchanged into `connection_id`. A discovered legacy numeric `auth_id` remains supported; at most one reference may be non-null. For a connectionless action, omit both. Never invent an ID, decode a UUID, substitute an account/user ID, or put an outer connection alias here.
- `input_labels` is optional display metadata, not a substitute for the values in `inputs`.

### Tool input policies

Discover the target action's fields and choices with the selected connection. Settle parent values before discovering dependent fields, and refresh affected discovery when a parent changes. Respect configured locks and restrictions. Store policies under the actual app field keys, not under MCP's `params` or `dynamic_properties` wrapper.

| Intent | Entry in the integration tool's `inputs` |
| --- | --- |
| Determine a value from instructions/context at execution time | `{"type":"guess"}` |
| Pin a fixed value | `{"type":"locked","value":"<actual value or choice ID>"}` |
| Let the agent choose among discovered candidates | `{"type":"guess-locked","value":["<choice ID 1>","<choice ID 2>"]}` |
| Leave normal field/default resolution in control | `{"type":"default"}` |
| Intentionally exclude a field when omission is valid | `{"type":"ignore"}` |

Do not use bare values such as `"channel": "C123"`. A fixed value belongs inside a `locked` entry. Scalar values use strings, including the selected action's numeric/boolean representations; dictionaries contain string values. Include `value` even when it is `""`. An omitted entry is unpinned, not ignored; `default` neither forces a particular default nor prevents runtime resolution.

Array values in both `locked` and `guess-locked` are candidates, not literal multi-value app inputs: one item is locked, multiple items guide selection, and an empty array allows guessing. Use nonempty candidate lists for new configurations. Candidate lists guide resolution; they are not an authorization boundary. Do not infer support for arbitrary nested objects or literal line-item arrays from these types.

### Approval policy

Choose the policy deliberately. `require_approval` is the default when omitted; `always_allow` permits execution without per-tool approval; `deny` excludes the tool; `auto` follows runtime policy and becomes `require_approval` during step tests. Omit rather than send null.

Only use `always_allow` after the user authorizes the bounded behavior, especially writes. If review is required, confirm the execution surface supports that review/resume flow before running. Do not silently change the policy to get past a halt. Permissions and other execution limits still apply.

## Include fail in tool-enabled configs

A prompt-only step omits `tools` entirely. Adding `fail` alone makes the step tool-enabled and requires a tool-capable model, so do not add it just to create a failure path; AbZ manages the failure channel at execution.

Every tool-enabled configuration includes exactly one explicit failure exit in its `tools` list:

```json
{
  "type": "builtin",
  "id": "tool_fail",
  "builtin_tool_name": "fail"
}
```

Tell the step to use it when required external work cannot be completed rather than fabricate a result or claim success. AbZ also adds this builtin automatically and deduplicates builtin names; one explicit entry makes the intended failure path visible in the authored configuration. Tool availability still depends on the model and account.

## Complete basic step

These are decoded `get_completion` inputs: put them in `sdk.runAction(...).inputs`, or the selected step-authoring interface's equivalent. Supply native object/array literals where supported; serialize only when the interface requires it, not again inside each tool. Do not invent platform-owned Zap/run IDs.

```json
{
  "model_id": "standard/auto",
  "authentication_id": "0",
  "instructions": "Summarize the supplied note in one sentence. Do not claim to read external data or send any messages. If the task cannot be completed, return a clear failure rather than inventing a result.",
  "inputFields": {
    "note": "The launch moved to Friday after final testing."
  },
  "includeWorkflowData": false,
  "outputFields": [
    { "name": "summary", "type": "text", "isRequired": true }
  ]
}
```

This example is prompt-only: it has no `tools`, so no tool-capable model is needed. Add tools only when the step must choose an action or run external work, as in the integration and web examples below.

Replace sample context with runtime values from the trigger or prior steps; JSON-stringify structured context into a named `inputFields` string when needed. `includeWorkflowData: false` keeps this example independent of automatic Zap history; it does not remove the explicit inputs.

`outputFields` entries use `name`, optional `description`, `type`, and `isRequired`. For an enum, use `type: "category_single"` or `"category_multi"` with nonempty `options`, not `text` plus options. With the example above, read `result.data[0].summary` in the SDK. With no configured output fields, read `result.data[0].output`; `outputFields: []` also requests that default and overrides legacy `outputSchema`. Leave `isOutputArray` false/omitted for this basic recipe. Verify the actual result wrapper on your surface.

## Complete integration-tool example

This example is for a user who explicitly wants the AI to decide whether an urgent note warrants a Slack notification and has approved that bounded send without per-call review. Otherwise, return the decision/message as output and let a normal workflow step send it.

The Slack identifiers, connection UUID, and channel ID are illustrative. Replace them with authorized discovery results before saving or running; never copy the example UUID into a real configuration. The channel is locked, while the runtime agent composes the text.

```json
{
  "model_id": "premium/auto",
  "authentication_id": "0",
  "instructions": "Read the note. Only if it describes an urgent launch blocker, use the configured Slack tool to send one concise notification to its locked channel. Prefix the notification with :robot:. Otherwise, send nothing. Return what actually happened. If a required send fails, use fail rather than claim it was sent.",
  "inputFields": {
    "note": "Launch is blocked: the production health checks are failing."
  },
  "includeWorkflowData": false,
  "outputFields": [
    { "name": "outcome", "type": "text", "isRequired": true }
  ],
  "tools": [
    {
      "type": "integration",
      "id": "tool_notify",
      "selected_api": "SlackCLIAPI",
      "action_key": "channel_message",
      "action_type": "write",
      "display_name": "Slack: Send Channel Message",
      "description": "Send a notification to the configured Slack channel.",
      "app_needs_auth": true,
      "connection_id": "00000000-0000-4000-8000-000000000002",
      "inputs": {
        "channel": { "type": "locked", "value": "C0123456789" },
        "text": { "type": "guess" }
      },
      "approval_policy": "always_allow"
    },
    { "type": "builtin", "id": "tool_fail", "builtin_tool_name": "fail" }
  ]
}
```

Use the same shape for a discovered integration read/search action, with its own action type, field keys, choices, and connection. Do not configure the AI to search or send through a tool whose discovered capability does something else.

## Web requests: include both web tools

When the user asks the step to search the public web or research/read public pages, include both `web_search` and `web_scrape`, plus `fail`. `web_search` finds results and links; `web_scrape` retrieves page content. These are builtin tools, not integration actions: no app identifier, connection, or integration input policies belong on them. The runtime agent supplies queries and URLs from the instructions/context.

```json
{
  "model_id": "premium/auto",
  "authentication_id": "0",
  "instructions": "Search the public web for the requested topic, read relevant pages, and summarize the findings with source URLs. Search snippets alone are not proof that a page was read. If required evidence cannot be retrieved, use fail rather than inventing it.",
  "inputFields": {
    "topic": "Recent public announcements about the user's named company"
  },
  "includeWorkflowData": false,
  "outputFields": [
    { "name": "research", "type": "text", "isRequired": true }
  ],
  "tools": [
    { "type": "builtin", "id": "tool_web_search", "builtin_tool_name": "web_search" },
    { "type": "builtin", "id": "tool_web_scrape", "builtin_tool_name": "web_scrape" },
    { "type": "builtin", "id": "tool_fail", "builtin_tool_name": "fail" }
  ]
}
```

The two explicit web entries are the underlying pair represented by the web-browsing shortcut; do not add a second shorthand entry or other builtins. When combining web and integration actions, merge their arrays with unique IDs and keep only one `fail`. These web tools do not access private app data or replace an authenticated integration tool. Do not add them for ordinary summarization of data already supplied.

## Verify and return

Return to the workflow lifecycle after configuring the AbZ step. Confirm real side effects before tests, use only advertised test/run capabilities, and inspect the actual returned fields and tool outcomes. A processing response, pending approval, or failed tool call is not success. Never claim a message was sent or a page read without execution evidence.

If discovery cannot supply a required authorized app connection, action key, field, or choice, report that specific limitation. This fallback fills in the basic AbZ object contract; it does not grant access, create connections, provide interactive execution controls, or guarantee model quality.

## Return to the workflow lifecycle

After the AI step is configured, return to the loaded workflow skill. Test it inside the complete durable source so runtime `inputFields`, embedded tools, output shape, deterministic continuation, and side effects are exercised together.
