---
name: zapier-workflows-history
description: Show run history for a specific durable workflow using the Zapier SDK experimental Code Workflows commands. Use when the user asks for run history, execution history, what happened with this Zap, or how a workflow fired.
license: MIT
metadata:
  author: zapier
  version: "1.0.0"
---

# Zapier Workflows History

Use the public SDK CLI experimental command surface. Do not use `zapier-sdk-code-substrate`.

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

## Drill Into A Run

If a single run failed or the user wants step-level detail:

```bash
zapier-sdk --experimental get-durable-run <run-id> --json
```

Summarize the failure, status, timing, input, output, and any step error details that appear in the response. Avoid dumping raw JSON unless the user asks for it.
