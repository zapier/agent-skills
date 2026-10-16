# Zapier Workflows Skills

Skills for setting up, building, inspecting, and modifying Zapier Workflows from an agent-enabled coding workspace.

These skills are generated from an internal Zapier repository. Pull requests that edit them here are not merged; see the [root README](../../README.md#contributing).

## Set Up Zapier Workflows

Copy and paste this into your agent prompt:

> Install the Zapier Workflows setup skill with:
> `npx skills add zapier/agent-skills --skill workflows-install`
>
> Then run the `workflows-install` skill to set up this workspace.

## Skills

<!-- skills-table:start (generated from each skill's name and description; do not edit by hand) -->
| Skill | Purpose |
|---|---|
| `workflows-ai-by-zapier` | Configure a basic AI by Zapier step with runtime context, outputs, typed integration tools, public web search, and a failure exit |
| `workflows-create` | Create a durable Zapier workflow from natural language using @zapier/zapier-durable and the Zapier SDK CLI |
| `workflows-doctor` | Diagnose Zapier Workflows skill and SDK CLI compatibility |
| `workflows-history` | Show run history for a specific durable workflow using the Zapier SDK experimental Code Workflows commands |
| `workflows-install` | Install the Zapier SDK CLI for Zapier Workflows Early Access and bootstrap the workflows companion skills |
| `workflows-list` | List durable workflows in the authenticated Zapier account using the Zapier SDK experimental Code Workflows commands |
| `workflows-modify` | Modify and republish an existing durable workflow using the Zapier SDK experimental Code Workflows commands |
<!-- skills-table:end -->

## Daily Skill-Freshness Auto-Update

`workflows-doctor` runs a soft, throttled freshness check before its SDK compatibility check. About once per day per project it runs `npx skills update` for the workflow bundle so content-only skill improvements — those shipped without an SDK version bump — are picked up automatically. It is non-blocking and silent unless an update is applied; updates take full effect on the next workspace reload.

Throttle state lives in a per-project marker under `${XDG_CACHE_HOME:-$HOME/.cache}/zapier-workflows-doctor/` (never in your repo). On failure it retries every 15 minutes up to 3 times, then falls back to a daily retry; any success resets the budget. Set `ZAPIER_WORKFLOWS_DEBUG=1` to see its decisions on stderr.

## Maintaining SDK Compatibility Metadata

Workflow skills include bundle-level SDK compatibility metadata in `SKILL.md`:

```yaml
metadata:
  sdk_cli_min: "0.85.0"
  sdk_cli_validated: "0.86.4"
  refresh_source: "zapier/agent-skills"
```

Rules:

- When a skill begins using a new SDK command or flag, update `sdk_cli_min` to the first SDK CLI version that supports that command or flag.
- If the first SDK CLI version that supports a command or flag is uncertain, set `sdk_cli_min` to the SDK CLI version used while introducing that skill dependency and note the conservative choice in the change description.
- When validating or republishing skills against a newer SDK CLI, update `sdk_cli_validated` to that version even if `sdk_cli_min` does not change.
- When adding or removing SDK command dependencies, update the `workflows-doctor` bundle compatibility checklist.
- When adding a new workflow skill, add its folder under `skills/workflows/` in the source repository, then run `node scripts/compose.mjs` and `node scripts/generate-github-skills.mjs`. The generator adds the skill to `skills.sh.json` and this README skill table; do not edit those by hand. Then add the skill by hand to the bundle lists in `workflows-install` and `workflows-doctor`.
- Keep `refresh_source` as `zapier/agent-skills`; do not reintroduce the deleted or archived `tjzap/agent-skills` fork.

`sdk_cli_min` and `sdk_cli_validated` apply to the workflow skill bundle, even though the fields are repeated in each `SKILL.md` for discoverability.

`workflows-doctor` verifies bundle command-surface compatibility only: required SDK CLI operations and flags. It does not prove full workflow correctness or that JSON payload semantics are unchanged.
