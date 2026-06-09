# Zapier Workflows Skills

Skills for setting up, building, inspecting, and modifying Zapier Workflows from an agent-enabled coding workspace.

## Set Up Zapier Workflows

Copy and paste this into your Cursor agent prompt:

> Install the Zapier Workflows setup skill with:
> `npx skills add zapier/agent-skills --skill workflows-install`
>
> Then run the `workflows-install` skill to set up this workspace.

## Skills

| Skill | Purpose |
|---|---|
| `workflows-install` | Set up the Zapier SDK CLI, install companion skills, authenticate, and run a read-only smoke test |
| `workflows-create` | Create, test, publish, and manually trigger durable workflows |
| `workflows-list` | List workflows visible to the authenticated Zapier account |
| `workflows-history` | Inspect workflow run history and durable run details |
| `workflows-modify` | Fetch, edit, test, republish, and verify existing workflows |
