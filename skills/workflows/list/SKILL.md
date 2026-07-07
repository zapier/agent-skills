---
name: workflows-list
description: List durable workflows in the authenticated Zapier account using the Zapier SDK experimental Code Workflows commands. Use when the user asks to list my Zaps, show my durable workflows, what workflows do I have, or see what Zapier workflows are deployed.
license: MIT
metadata:
  author: zapier
  version: "1.1.1"
  sdk_cli_min: "0.54.3"
  sdk_cli_validated: "0.54.3"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows List

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Check Prerequisites

```bash
zapier-sdk --version
zapier-sdk get-profile --json
zapier-sdk --experimental --help
```

If auth fails, ask the user to run `zapier-sdk login` in an interactive terminal and retry.

## List Workflows

```bash
zapier-sdk --experimental list-workflows --json
```

Parse the JSON output and format what the user asked for. Common useful fields may include `id`, `name`, `enabled`, `is_private`, `created_by_user_id`, `created_at`, `updated_at`, `description`, `current_version`, and trigger-related metadata if present.

For each workflow with an `id`, include the Zapier editor link:

```text
https://zapier.com/durables-editor/<workflow-id>
```

Treat `trigger_url` as account-sensitive: firing it invokes the workflow as the authenticated account, so while the token in the URL is no longer a standalone credential, it is still not something to print gratuitously. Do not print `trigger_url` unless the user explicitly asks for it.

Check each entry in `triggers[]` for `details.webhook_url`, regardless of trigger type — its presence alone tells you there's a catch URL. Unlike `trigger_url`, `webhook_url` is meant to be shared — it's the URL the user pastes into the external service — so surface it plainly when present. Most triggers have no `webhook_url`, and that is normal; do not flag its absence unless the user specifically expects one (for example they mention "Webhooks by Zapier"), in which case the installed SDK may predate this field.

## Ownership Scoping

`list-workflows` may return every workflow the authenticated user can see, including team workflows. If the user asks for "my workflows," first show the likely matches and explain any uncertainty rather than silently filtering by the wrong ID.

Known quirk: `zapier-sdk get-profile` may return a UUID that does not match `list-workflows[].created_by_user_id`, which may be a separate numeric user ID. If you cannot confidently map those IDs, say so and present the unfiltered list with enough context for the user to choose.

## Last Run Time

If the user asks for recent activity, fetch runs for each relevant workflow:

```bash
zapier-sdk --experimental list-workflow-runs <workflow-id> --json
```

Use the most recent run. Be mindful of API volume for large accounts.
