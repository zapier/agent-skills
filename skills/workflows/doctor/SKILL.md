---
name: workflows-doctor
description: Diagnose Zapier Workflows skill and SDK CLI compatibility. Use when a workflow skill asks for a compatibility check, when SDK commands or flags are missing, when a workflow skill may be stale, or when updating workflow skills after an SDK CLI change.
license: MIT
metadata:
  author: zapier
  version: "1.2.1"
  sdk_cli_min: "0.54.3"
  sdk_cli_validated: "0.54.3"
  refresh_source: "zapier/agent-skills"
---

# Zapier Workflows Doctor

Diagnose whether the installed Zapier SDK CLI can support the Zapier Workflows skill bundle. Be diagnostic first. Do not refresh skills unless SDK/skill drift is detected or compatibility cannot be confirmed.

## Compatibility Metadata

Workflow skills use these metadata fields:

- `sdk_cli_min`: oldest SDK CLI version the skill is allowed to run against. Set it to the first SDK CLI version that supports the newest command or flag the skill depends on. If that exact first-supported version is uncertain, use the SDK CLI version used when introducing the skill instruction change.
- `sdk_cli_validated`: SDK CLI version used during the latest validation pass. Update it whenever workflow skills are intentionally tested and republished against a newer SDK CLI, even if `sdk_cli_min` does not change.
- `refresh_source`: canonical skill source. For these skills, keep this as `zapier/agent-skills`.

Command-surface checks verify required bundle capabilities only. They do not prove full workflow correctness or that JSON payload semantics are unchanged.

## Step 0: Daily Skill-Freshness Check

Run this before the SDK compatibility steps below. It keeps the workflow skills current with `zapier/agent-skills` even when the SDK CLI has not changed, by occasionally running `npx skills update` for the bundle. It is **soft and non-blocking**: it self-throttles to roughly once per day per project, never stops the calling skill, and prints nothing unless it actually applied an update.

Run it exactly once, then continue to Step 1 regardless of its output. Do **not** parse or branch on the result:

```bash
bash scripts/skill-freshness-check.sh
```

Resolve `scripts/skill-freshness-check.sh` relative to this skill's own directory. The script locates the installed skill bundle from its own path and runs the bundle update from the scope root that contains it (the directory holding `.agents`/`.claude`), so it does not matter which directory you invoke it from.

- If it prints a note that skills were refreshed, pass that note along to the user and keep going; the update takes full effect on the next workspace reload.
- If it prints nothing, say nothing and continue.

This freshness check is independent of the SDK command-surface compatibility check in Steps 1–4 below, which is unchanged and remains a hard gate. For troubleshooting, set `ZAPIER_WORKFLOWS_DEBUG=1` to see the freshness check's decision on stderr.

## Step 1: Check Bundle Compatibility

Check the workflow skill bundle as one unit. Do not maintain separate compatibility checks for `workflows-install`, `workflows-create`, `workflows-list`, `workflows-history`, and `workflows-modify`; users will normally use these skills together, and drift in any core workflow SDK surface should refresh the whole bundle.

Current workflow skills use `sdk_cli_min: "0.54.3"` and `sdk_cli_validated: "0.54.3"` unless the installed skills' metadata says otherwise.

## Step 2: Check SDK CLI Versions

Run:

```bash
which zapier-sdk
zapier-sdk --version
npm view @zapier/zapier-sdk-cli version
```

If `zapier-sdk` is missing or `zapier-sdk --version` is below the bundle's `sdk_cli_min`, update the SDK CLI before continuing:

```bash
npm install -g @zapier/zapier-sdk-cli@latest
zapier-sdk --version
```

If global npm installs fail because of permissions, tell the user to fix their Node/npm setup before retrying. Prefer a user-owned Node install through nvm or Homebrew over `sudo npm install -g`.

If the installed SDK CLI version is newer than the bundle's `sdk_cli_validated`, continue to command-surface discovery. Do not refresh skills solely because the SDK CLI is newer.

## Step 3: Discover Current Command Surface

Start from the SDK help output:

```bash
zapier-sdk --experimental --help
```

Use the help output to discover the current command names and flags for the required bundle capabilities below. Current command names in this skill are examples from the SDK CLI version the workflow skill bundle was validated against; they are not the compatibility contract. If the current help output exposes an equivalent way to perform a required capability, use the current help output.

For each discovered candidate command, inspect command-specific help:

```bash
zapier-sdk --experimental <candidate-command> --help
```

## Required Bundle Capabilities

Confirm that the SDK CLI exposes a clear way to perform these operations for the workflow skill bundle:

- Create a workflow container.
- Publish a workflow version.
- Run a durable workflow locally or synthetically.
- List workflows.
- List workflow runs.
- Inspect a workflow run.
- Discover or list app triggers.
- Trigger a workflow.
- Control workflow visibility, including private workflow creation or the current equivalent.
- Bind app connections for test runs and published workflow versions.
- Bind app implementation/version metadata when required.
- Provide trigger configuration for published workflow versions.
- Pass workflow input when running or triggering workflows.
- Control enabled state when publishing workflow versions.
- Run synthetic durable tests privately or with the current equivalent behavior.

When the current SDK help output is clear, prefer it over the example commands below. If discovery is ambiguous or a required capability appears absent, treat compatibility as unconfirmed and refresh the workflow skill bundle.

Example commands from the validated SDK CLI surface:

```bash
zapier-sdk --experimental create-workflow --help
zapier-sdk --experimental publish-workflow-version --help
zapier-sdk --experimental run-durable --help
zapier-sdk --experimental list-workflows --help
zapier-sdk --experimental list-workflow-runs --help
zapier-sdk --experimental get-workflow-run --help
zapier-sdk --experimental list-triggers --help
zapier-sdk --experimental trigger-workflow --help
zapier-sdk --experimental get-trigger-run --help
zapier-sdk --experimental get-workflow --help
zapier-sdk --experimental get-workflow-version --help
```

Example flags from the validated SDK CLI surface:

- `create-workflow`: `--private`
- `publish-workflow-version`: `--connections`, `--app_versions`, `--trigger`, `--enabled`
- `run-durable`: `--connections`, `--input`, `--private`
- `trigger-workflow`: `--input`

Equivalent current flags or command shapes are acceptable if the help text clearly supports the same required bundle capability.

## Step 4: Decide Whether To Refresh Skills

If all required bundle capabilities are confirmed, tell the calling skill to continue without refreshing.

If any required capability is missing, or compatibility cannot be confirmed, update the entire workflow skill bundle so the skills stay in sync.

Prefer the standard day-2 update path first:

```bash
npx skills update workflows-install workflows-doctor workflows-create workflows-list workflows-history workflows-modify -y
```

If `skills update` cannot find the installed skills, updates the wrong scope, or otherwise fails, fall back to explicit installs from canonical GitHub:

```bash
npx skills add zapier/agent-skills --skill workflows-install --yes
npx skills add zapier/agent-skills --skill workflows-doctor --yes
npx skills add zapier/agent-skills --skill workflows-create --yes
npx skills add zapier/agent-skills --skill workflows-list --yes
npx skills add zapier/agent-skills --skill workflows-history --yes
npx skills add zapier/agent-skills --skill workflows-modify --yes
```

After updating skills, stop the current skill invocation. Tell the user to reload the agent workspace and rerun their original request. Do not promise that the current invocation has changed its already-loaded instructions.
