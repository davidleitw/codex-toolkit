---
name: codex-setup
description: Check whether the local Codex CLI is ready for the codex, codex-assets, and codex-visual-review skills - CLI present, logged in, codex doctor clean, plugin support, effective global model and service tier, built-in image generation skill, jq/python3/sha256. Use on first install, or when a codex-toolkit run fails with kind=unavailable, authentication, or service. Reports only; never edits configuration. A quota-spending smoke test runs only when the user explicitly asks.
allowed-tools:
  - Bash
  - Read
---

# codex-setup

Script: `scripts/codex-setup.sh` inside this skill's directory.

## doctor

```bash
<skill-dir>/scripts/codex-setup.sh doctor
```

One line per check: `CHECK <name> <available|unavailable|unknown> <detail>`. Last line `CODEX_SETUP_DOCTOR_OK` or `CODEX_SETUP_DOCTOR_ATTENTION unavailable=<n> unknown=<n>`.

| Check | unavailable means | Tell the user |
|---|---|---|
| codex-cli | `codex` not on PATH | `npm install -g @openai/codex`, then rerun |
| auth | not logged in | run `codex login` themselves (interactive) |
| codex-doctor | Codex's own doctor reports failures | run `codex doctor` for details |
| plugins | this build lacks `codex plugin` | install skills standalone (symlink `skills/*` into `~/.codex/skills/` or `~/.agents/skills/`) |
| imagegen-skill (unknown) | built-in image skill file not found | codex-assets raster output may fail; text modes unaffected |
| jq / python3 / sha256 | missing tool | install via the system package manager |
| config / config-model | never unavailable; informational | values come from the base user config (`$CODEX_HOME/config.toml`) only; profiles, project, and system layers are not inspected. Toolkit scripts pass model, effort, and service tier explicitly, so a configured `gpt-6-astra` or `service_tier="fast"` is not inherited |

`available` for imagegen-skill means the file exists, not that generation works.

## smoke-test

Only when the user explicitly asks for a smoke test; it spends quota.

```bash
<skill-dir>/scripts/codex-setup.sh smoke-test            # one tiny text run: gpt-5.6-luna / low
<skill-dir>/scripts/codex-setup.sh smoke-test --imagegen # plus one small image generation
```

Last line `CODEX_SMOKE_OK workdir=...` or `CODEX_SMOKE_FAILED kind=<unavailable|text|imagegen> ...`. On failure read the stderr tail printed above the marker and map it to the table.

## Rules

- Report findings; never edit `~/.codex/config.toml`, environment, or login state. Give the user the exact command instead.
- Do not run `codex login` for the user.
