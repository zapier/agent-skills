---
name: workflows-history
description: Show run history for a specific durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks for run history, execution history, what happened with this Zap, or how a workflow fired.
license: MIT
metadata:
  author: zapier
  version: "1.1.0"
  sdk_cli_min: "0.54.3"
  sdk_cli_validated: "0.54.3"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows History

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

## Compatibility Gate

Before using this skill, run the `workflows-doctor` bundle compatibility check. If `workflows-doctor` is not installed or cannot be loaded, run `workflows-install` or install `workflows-doctor` from `zapier/agent-skills` before continuing. If `workflows-doctor` reports SDK/skill drift, follow its refresh instructions, stop this skill invocation, reload the agent workspace if needed, and ask the user to rerun the original request.

## Identify The Workflow

If the user provides a workflow ID, use it directly.

If the user refers to the workflow by name or description, list workflows first and find the matching ID:

```bash
zapier-sdk --experimental list-workflows --json
```

If multiple workflows match, show the candidates and ask the user which one they mean.

## Fetch Run History

```bash
zapier-sdk --experimental list-workflow-runs <workflow-id> --json
```

Parse the JSON output. Useful fields may include `id`, `status`, `started_at`, `finished_at`, `input`, and `output`.

When the workflow ID is known, include the Zapier editor link:

```text
https://zapier.com/durables-editor/<workflow-id>
```

## Drill Into A Run

If a single deployed workflow run failed or the user wants step-level detail:

```bash
zapier-sdk --experimental get-workflow-run <run-id> --json
```

Use `get-durable-run <run-id>` only for one-off synthetic runs created by `zapier-sdk --experimental run-durable`, not for deployed workflow runs returned by `list-workflow-runs`.

If a manual trigger response returns a trigger ID before a workflow run ID is available, bridge from trigger to run:

```bash
zapier-sdk --experimental get-trigger-run <trigger-id> --json
```

Summarize the failure, status, timing, input, output, and any step error details that appear in the response. Avoid dumping raw JSON unless the user asks for it.
