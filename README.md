# Codex Toolkit

English | [繁體中文](README.zh-TW.md)

![Codex Toolkit](assets/header.jpg)

Hand work to the local Codex CLI from inside the coding agent you already use (Claude Code, Codex CLI, or anything that reads agent skills): ask it for a second opinion, have it review or change code, generate images, review screenshots.

This is a community toolkit. It is not affiliated with OpenAI or Anthropic and is not an official package.

## The four skills

| skill | When it is used | What you get |
|---|---|---|
| `codex` | You want a second opinion, a review of uncommitted changes, or a clearly specified change done by Codex | Codex's analysis, review findings, or diff. Your agent checks them before reporting back |
| `codex-assets` | You need illustrations, backgrounds, mockups, icons, a set of assets in one style, or edits to an existing image | Files in a staging directory, `manifest.json` (dimensions, size, checksum computed from the files), `preview.html` (light/dark/checker toggle for transparency checks) |
| `codex-visual-review` | You have UI screenshots to check, or want a reference design compared with the implemented screen | `report.md`: per-image findings with region, impact, and suggestion, plus what a screenshot cannot verify |
| `codex-setup` | First install, or Codex is not working | A check-by-check readiness report (CLI, login, built-in image skill, jq/python3, ...). Report only; it never edits your config |

Division of labor: code goes to `codex`, making images to `codex-assets`, looking at images to `codex-visual-review`, environment problems to `codex-setup`. When a screenshot review calls for a code change, it goes back to `codex` in implement mode. When an asset needs changes, `codex-assets` runs in revise mode and produces a new version; the original stays untouched.

## Requirements

- Codex CLI (`npm install -g @openai/codex`), logged in with `codex login`. Developed against codex-cli 0.153.4.
- `jq` (needed by `codex-assets`); `sha256sum` or `shasum`.
- `python3`: reads image width, height, and alpha. Optional; without it those fields are `null`.
- Image generation uses Codex's built-in imagegen skill (ships with the CLI, under `~/.codex/skills/.system/imagegen`). No separate API key.

After installing, let the agent run the `codex-setup` doctor once.

## Install

All four skills live under `skills/`. The Claude Code plugin and the Codex plugin read the same directory.

### Claude Code

```bash
claude plugin marketplace add davidleitw/codex-toolkit
claude plugin install codex-toolkit@codex-toolkit
```

From a local clone, replace the first line with `claude plugin marketplace add /path/to/codex-toolkit`.

Remove:

```bash
claude plugin uninstall codex-toolkit
claude plugin marketplace remove codex-toolkit
```

### Codex

```bash
codex plugin marketplace add davidleitw/codex-toolkit
codex plugin add codex-toolkit@codex-toolkit
```

From a local clone, replace the first line with `codex plugin marketplace add /path/to/codex-toolkit`.

Remove:

```bash
codex plugin remove codex-toolkit@codex-toolkit
codex plugin marketplace remove codex-toolkit
```

### Without a plugin: install skills directly

Each skill directory carries its own script, so you can install only the ones you want:

```bash
git clone https://github.com/davidleitw/codex-toolkit.git
# Claude Code
ln -s "$PWD/codex-toolkit/skills/codex" ~/.claude/skills/codex
# Codex
ln -s "$PWD/codex-toolkit/skills/codex" ~/.codex/skills/codex
```

Other tools that read agent skills usually look in `~/.agents/skills/`; symlink there the same way.

## Usage

Plain language is enough; the agent picks the skill:

- "Discuss with Codex which layer this retry logic belongs in. Don't change code yet."
- "Have Codex review my uncommitted changes, focus on error handling."
- "This rename is settled. Hand it to Codex and run the tests afterwards."
- "Use Codex to make a README cover image, Japanese woodblock style, with a terminal in it."
- "Here is a screenshot of the settings page. Ask Codex to check the layout."
- "Codex doesn't seem to work. Check my setup."

## Model and speed policy

Every script passes the model, reasoning effort, and service tier explicitly on every run. Nothing is inherited from `~/.codex/config.toml`. This is deliberate: even if your global config names GPT-6 or fast, neither is used unless you ask.

| Work | Model / effort |
|---|---|
| Discussion, review of any size, debugging, code tracing, anything needing design judgment | `gpt-5.6-sol` / `high` |
| Lightweight changes with settled decisions and clear scope (including mechanical edits) | `gpt-5.6-luna` / `max` |
| Image generation, screenshot review | `gpt-5.6-sol` / `high` |

- `gpt-5.6-terra` is never used; the scripts reject it.
- `gpt-6-astra` only when you explicitly ask for GPT-6 / Astra. A hard task, a failed run, or a config file naming it is not authorization.
- Fast mode (Codex `service_tier="fast"`) is a separate explicit opt-in. Asking for GPT-6 does not imply fast, and the reverse.
- Settings you authorized earlier in the same conversation carry forward; you are not asked again.
- After the first delegated run, the agent reminds you once: "If you want later Codex work to go faster, say 'use fast mode from now on'; it may use more quota." Once only, non-blocking, and no job is re-sent to switch speed.

## Where results go

| skill | Location |
|---|---|
| `codex` | Printed in the agent's command output. The last line is `CODEX_DELEGATION_OK ...` or `CODEX_DELEGATION_FAILED kind=...`; the agent judges by that line, not the exit code |
| `codex-assets` | `$TMPDIR/codex-toolkit/assets/job-XXXXXX/` (`/tmp` when `TMPDIR` is unset): the files, `manifest.json`, `preview.html`, `request.txt`, `codex-stderr.log` |
| `codex-visual-review` | `$TMPDIR/codex-toolkit/visual-review/job-XXXXXX/report.md` |
| `codex-setup` | Printed in the command output |

Assets never land in your repository on their own. The agent reads the manifest and looks at the images first, then copies accepted files into the project's source asset directory.

## Status

Done: SKILL.md and script for each of the four skills, plugin manifests for Claude Code and Codex, this README, the header image.

Checked: script syntax and argument error paths; `claude plugin validate` and the Codex plugin validator both pass; a local `codex plugin marketplace add` + `codex plugin add` installs and removes cleanly; `codex-setup doctor` ran; the header image was produced by the `codex-assets` script itself.

Not done: no automated tests; the four skills have not been exercised end to end on real tasks; the GitHub install commands (`marketplace add davidleitw/codex-toolkit`) could not be tried before the push.

Planned, intentionally left out of this version: job records and session resume, automated browser screenshots, an MCP interface, auto-fix in `codex-setup`.
