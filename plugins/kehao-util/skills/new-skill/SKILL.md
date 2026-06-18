---
name: new-skill
description: Scaffold a new skill folder (SKILL.md from a template) into this marketplace repo. Use when adding a new skill to kehao-claude-skills.
disable-model-invocation: true
argument-hint: '<name> "<description>" [plugin]'
arguments: [name, description, plugin]
---

# new-skill — scaffold a new skill in this marketplace

Create a new skill folder from the bundled template. Invoked as
`/kehao-util:new-skill <name> "<description>" [plugin]`.

Arguments (already substituted below):
- name: `$name`
- description: `$description`
- plugin: `$plugin` (defaults to `kehao-util` when empty)

## Steps

1. **If `$description` is empty, STOP and ask the user** for a one-line description of
   what the new skill does. Do not invent a vague placeholder.

2. Run the bundled scaffolder from the **current working directory** (which must be the
   marketplace repo root — the script verifies this and refuses otherwise):

   ```bash
   "${CLAUDE_SKILL_DIR}/scaffold.sh" "$name" "$description" "$plugin"
   ```

   The script will:
   - refuse to run unless the cwd has `.claude-plugin/marketplace.json` and the target
     `plugins/<plugin>/.claude-plugin/plugin.json` exists;
   - refuse to overwrite an existing skill;
   - write `plugins/<plugin>/skills/<name>/SKILL.md` from `templates/SKILL.md.tmpl`.

3. Open the created `SKILL.md`, replace the `TODO` body with real instructions for the
   new skill, then tell the user to run `./scripts/validate.sh` and `/reload-plugins`
   (during development) or bump the version and `/plugin marketplace update`.

If the script exits non-zero, report its message to the user and do not continue.
