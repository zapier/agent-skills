# Zapier Workflows Skills

Skills for setting up, building, inspecting, and modifying Zapier Workflows from an agent-enabled coding workspace.

## Set Up Zapier Workflows

Copy and paste this into your agent prompt:

> Install the Zapier Workflows setup skill with:
> `npx skills add zapier/agent-skills --skill workflows-install`
>
> Then run the `workflows-install` skill to set up this workspace.

## Skills

| Skill | Purpose |
|---|---|
| `workflows-install` | Set up the Zapier SDK CLI, install companion skills, authenticate, and run a read-only smoke test |
| `workflows-doctor` | Diagnose SDK CLI and workflow skill compatibility, refresh the bundle on SDK drift, and auto-update the workflow skills about once a day to pick up content-only improvements |
| `workflows-create` | Create, test, publish, and manually trigger durable workflows |
| `workflows-list` | List workflows visible to the authenticated Zapier account |
| `workflows-history` | Inspect workflow run history and durable run details |
| `workflows-modify` | Fetch, edit, test, republish, and verify existing workflows |

## Daily Skill-Freshness Auto-Update

`workflows-doctor` runs a soft, throttled freshness check before its SDK compatibility check. About once per day per project it runs `npx skills update` for the workflow bundle so content-only skill improvements — those shipped without an SDK version bump — are picked up automatically. It is non-blocking and silent unless an update is applied; updates take full effect on the next workspace reload.

Throttle state lives in a per-project marker under `${XDG_CACHE_HOME:-$HOME/.cache}/zapier-workflows-doctor/` (never in your repo). On failure it retries every 15 minutes up to 3 times, then falls back to a daily retry; any success resets the budget. Set `ZAPIER_WORKFLOWS_DEBUG=1` to see its decisions on stderr.

## Maintaining SDK Compatibility Metadata

Workflow skills include bundle-level SDK compatibility metadata in `SKILL.md`:

```yaml
metadata:
  sdk_cli_min: "0.54.3"
  sdk_cli_validated: "0.54.3"
  refresh_source: "zapier/agent-skills"
```

Rules:

- When a skill begins using a new SDK command or flag, update `sdk_cli_min` to the first SDK CLI version that supports that command or flag.
- If the first SDK CLI version that supports a command or flag is uncertain, set `sdk_cli_min` to the SDK CLI version used while introducing that skill dependency and note the conservative choice in the change description.
- When validating or republishing skills against a newer SDK CLI, update `sdk_cli_validated` to that version even if `sdk_cli_min` does not change.
- When adding or removing SDK command dependencies, update the `workflows-doctor` bundle compatibility checklist.
- When adding a new workflow skill, add it to `skills.sh.json`, `workflows-install`, `workflows-doctor`, and this README skill table.
- Keep `refresh_source` as `zapier/agent-skills`; do not reintroduce the deleted or archived `tjzap/agent-skills` fork.

`sdk_cli_min` and `sdk_cli_validated` apply to the workflow skill bundle, even though the fields are repeated in each `SKILL.md` for discoverability.

`workflows-doctor` verifies bundle command-surface compatibility only: required SDK CLI operations and flags. It does not prove full workflow correctness or that JSON payload semantics are unchanged.
