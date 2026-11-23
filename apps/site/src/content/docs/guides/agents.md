---
title: Coding agents
description: Let Claude Code and other agents link, sync and restore your apps for you.
---

dryfit never stops to ask a question, and every command can answer in JSON, so an agent can drive it the
way you do. What an agent lacks is knowing that dryfit exists and how to use it safely, so dryfit ships
that knowledge as a skill.

## Claude Code

```bash
dryfit agent install
```

This writes the skill to `~/.claude/skills/dryfit/SKILL.md`, where Claude Code finds it in every project.
Start a new session and ask for what you want, such as "try my changes to the ui library in the shop app".
Claude Code looks at `dryfit status`, links the app, syncs while you work, and restores it when you are
done.

To share the skill with everyone working on a project, install it into the project instead and commit
it:

```bash
dryfit agent install --project
```

`dryfit agent uninstall` removes it, with the same options.

## Other agents

`--dir` installs the skill into any other folder of skills. For an agent that reads its instructions
from a file, such as `AGENTS.md`, print the skill and copy what you need:

```bash
dryfit agent show
```

## What the skill tells an agent

- Pass `--json` to every command, read the result from stdout and the exit code.
- Look at `dryfit status` before changing anything, and set dryfit up only when it never was.
- Link only the apps you asked for, never commit a linked app, and restore the apps it linked when it
  is done.
- When restoring fails because the app's `package.json` changed, ask you before `restore --force`
  overwrites those changes.

## Errors and exit codes

With `--json`, an error is one line of JSON on stderr:

```json
{
  "error": {
    "code": "library-linked",
    "message": "@acme/ui is still linked into shop.",
    "hint": "Run `dryfit restore` for those consumers first."
  },
  "exitCode": 1
}
```

The exit code is 0 when everything succeeded, 1 when something failed, 2 when the command was used
wrongly, and 130 when it was interrupted. Commands that act on several apps, such as `link` and
`restore`, report each app in their result and exit 1 if any of them failed. A link whose install
failed has `"status": "failed"` and a `message` with the end of the package manager's output, such as
npm's `ERESOLVE` report.
