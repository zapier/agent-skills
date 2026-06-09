# Zapier Agent Skills

A collection of skills for AI coding agents (Claude Code, Cursor, Copilot, etc.), maintained by Zapier teams. Skills are packaged instructions and scripts that extend an agent's capabilities.

Skills follow the [Agent Skills](https://agentskills.io/) format and are indexed by [skills.sh](https://skills.sh).

## Layout

Skills live under `skills/`, grouped into a subfolder per team or project, with one folder per skill:

```
skills/
  <team-or-project>/      # category: one subfolder per team or project
    <skill-name>/         # kebab-case, one folder per skill
      SKILL.md            # required
```

See [AGENTS.md](AGENTS.md) for the authoring contract (naming, frontmatter, scripts).

## Categories

Skills are grouped by team or project. Each category's README lists its skills; the full, always-current index of every skill is on [skills.sh](https://skills.sh/zapier/agent-skills).

<!-- One row per category. Add a row when a team adds its first skill. -->

| Category | Description |
| -------- | ----------- |
| [workflows](skills/workflows) | Skills for setting up, building, inspecting, and modifying Zapier Workflows |

## Installation

Install every skill in the repo:

```bash
npx skills add zapier/agent-skills
```

Or install a single skill by its `name`:

```bash
npx skills add zapier/agent-skills --skill <skill-name>
```

This drops the skill into your local agent configuration (e.g. `.claude/skills/` or `.cursor/skills/`).

### Testing without publishing

To install locally without triggering the public skills.sh marketplace listing:

```bash
DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx skills add zapier/agent-skills --skill <skill-name>
```

## Usage

Skills are available to your agent automatically once installed — the agent invokes them when a relevant task is detected.

## Other Zapier skill sources

Not all Zapier skills live in this repo. This repo is the home for **non-connector** skills. Other sources have their own distribution:

- **Connectors** — per-app connector skills (one per integration). These are **not** installed from this repo; they are distributed through the connectors download API rather than skills.sh. The public GitHub home for connectors is still being set up — a direct link will be added here once it is live.

If you are an agent looking for a connector-specific skill, do not expect to find it under `skills/` in this repo; use the connectors distribution channel instead.

## License

MIT
