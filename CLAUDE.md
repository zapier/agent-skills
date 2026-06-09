# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, Copilot, etc.) when authoring skills in this repository.

## Repository overview

A collection of skills for AI coding agents, maintained by Zapier teams. Skills are packaged instructions and scripts that extend an agent's capabilities. Skills are indexed by [skills.sh](https://skills.sh) and installable via `npx skills add`.

## Creating a new skill

### Directory structure

Skills are grouped into a subfolder per team or project under `skills/`:

```
skills/
  <team-or-project>/        # kebab-case team/project namespace, e.g. workflows
    <skill-name>/           # kebab-case skill directory
      SKILL.md              # Required: skill definition
      scripts/              # Optional: executable scripts
        <script-name>.sh    # Bash scripts
        <script-name>.mjs   # Node scripts
      references/           # Optional: supporting docs loaded on demand
      lib/                  # Optional: shared code for scripts
```

### Naming conventions

- **Team/project folder**: `kebab-case` (e.g. `workflows`).
- **Skill directory**: `kebab-case` (e.g. `install`, `build`).
- **SKILL.md**: always uppercase, always this exact filename.
- **`name:` field**: prefix with `zapier-<team>-` (e.g. `zapier-workflows-install`). The folder can stay short, but the `name:` is what the agent sees once a skill is installed alongside skills from every other source — keep it unambiguous and collision-proof. Generic names like `install` or `build` **must** be namespaced.
- **Scripts**: `kebab-case.sh` or `kebab-case.mjs`.

### SKILL.md format

```markdown
---
name: zapier-<team>-<skill>
description: One sentence describing when to use this skill. Include trigger phrases like "deploy my workflow", "set up a Zapier script", etc.
license: MIT
metadata:
  author: zapier
  version: "1.0.0"
---

# <Skill Title>

Brief description of what the skill does.

## How it works

Numbered list explaining the skill's workflow.

## Usage

Show 2-3 common usage patterns.

## Output

Show example output users will see.

## Troubleshooting

Common issues and solutions, especially network/permissions errors.
```

### Best practices for context efficiency

Only a skill's `name` and `description` load at startup; the full `SKILL.md` loads only when the agent decides the skill is relevant. To minimize context usage:

- **Keep SKILL.md under 500 lines** — put detailed reference material in separate files.
- **Write specific descriptions** — they help the agent know exactly when to activate the skill.
- **Use progressive disclosure** — reference supporting files that get read only when needed.
- **Prefer scripts over inline code** — script execution doesn't consume context (only output does).
- **File references work one level deep** — link directly from SKILL.md to supporting files.

### Script requirements

- Bash scripts: use `#!/bin/bash` and `set -e`.
- Node scripts: use `#!/usr/bin/env node` and the `.mjs` extension.
- Write status messages to stderr; write machine-readable output (JSON) to stdout.
- Include a cleanup trap for temp files when scripts create them.
- Reference scripts by relative path, e.g. `node scripts/<script>.mjs`.

### Marketplace grouping

Add each new skill's `name` to the appropriate group in `skills.sh.json` so it appears under the right section on skills.sh.

### End-user installation

Document the skills.sh install for public skills:

```bash
npx skills add zapier/agent-skills --skill <skill-name>
```
