# Zapier Workflows Skills

Skills for setting up, building, inspecting, and modifying Zapier Workflows from an agent-enabled coding workspace.

Install path once published:

```bash
npx skills add zapier/agent-skills --skill zapier-workflows-install
```

## Skills

| Skill | Purpose |
|---|---|
| `zapier-workflows-install` | Set up the Zapier SDK CLI, install companion skills, authenticate, and run a read-only smoke test |
| `zapier-workflows-build` | Build, test, publish, and manually trigger durable workflows |
| `zapier-workflows-list` | List workflows visible to the authenticated Zapier account |
| `zapier-workflows-history` | Inspect workflow run history and durable run details |
| `zapier-workflows-modify` | Fetch, edit, test, republish, and verify existing workflows |
