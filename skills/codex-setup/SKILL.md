---
name: codex-setup
description: Check whether the local Codex CLI is ready for the codex, codex-assets, and codex-visual-review skills. Use on first install, when the user asks to check or troubleshoot their Codex setup, or when one of those skills fails with kind=unavailable, authentication, or service.
allowed-tools:
  - Bash
  - Read
---

# codex-setup

Run `scripts/codex-setup.sh` from this skill's directory. Report findings and give the user exact commands; never edit `~/.codex/config.toml`, the environment, or login state, and never run `codex login` for the user.

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
| config / config-model | never unavailable | informational only. Read from `$CODEX_HOME/config.toml` alone; the toolkit scripts pass model, effort, and service tier explicitly, so configured values do not affect them |

`available` for imagegen-skill means the file exists, not that generation works.

## smoke-test

Only when the user explicitly asks; it spends quota.

```bash
<skill-dir>/scripts/codex-setup.sh smoke-test            # one tiny text run: gpt-6-luna / low
<skill-dir>/scripts/codex-setup.sh smoke-test --imagegen # plus one small image generation
```

Last line `CODEX_SMOKE_OK workdir=...` or `CODEX_SMOKE_FAILED kind=<unavailable|text|imagegen> ...`. On failure read the stderr tail printed above the marker and map it to the table.
