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
| `workflows-doctor` | Diagnose SDK CLI and workflow skill compatibility, then refresh the workflow skill bundle when drift is detected |
| `workflows-create` | Create, test, publish, and manually trigger durable workflows |
| `workflows-list` | List workflows visible to the authenticated Zapier account |
| `workflows-history` | Inspect workflow run history and durable run details |
| `workflows-modify` | Fetch, edit, test, republish, and verify existing workflows |

## Maintaining SDK Compatibility Metadata

Workflow skills include SDK compatibility metadata in `SKILL.md`:

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
- When adding or removing SDK command dependencies, update the corresponding `workflows-doctor` command-check profile.
- When adding a new workflow skill, add it to `skills.sh.json`, `workflows-install`, `workflows-doctor`, and this README skill table.
- Keep `refresh_source` as `zapier/agent-skills`; do not reintroduce the deleted or archived `tjzap/agent-skills` fork.

`workflows-doctor` verifies command-surface compatibility only: required SDK CLI commands and flags. It does not prove full workflow correctness or that JSON payload semantics are unchanged.
