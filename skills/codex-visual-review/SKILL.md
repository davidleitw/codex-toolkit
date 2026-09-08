---
name: codex-visual-review
description: Have the local Codex CLI review UI screenshots supplied by the user or the caller - critique a screen, compare an implementation against reference designs, or recheck earlier findings after a fix. Read-only; returns findings per image (region, issue, impact, suggestion) plus what screenshots cannot verify. Does not take screenshots, drive a browser, generate images (see codex-assets), or fix code (see codex implement).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# codex-visual-review

Script: `scripts/run-codex-visual-review.sh` inside this skill's directory. Brief goes on stdin; screenshots are attached with `--image`.

## Modes

| Mode | Flags | Brief says |
|---|---|---|
| `critique` | `--image`... | what the screen is for, target users, platform, known constraints, what to focus on |
| `compare` | `--image`... `--reference`... | which reference maps to which screenshot, tolerated differences |
| `recheck` | `--image`... | the earlier findings verbatim, what was changed |

The mode is the first script argument. `--repo "<root>"` adds read-only code context (optional). Screenshots come from the user or the caller; this skill does not capture them.

## Model and speed

Default `gpt-5.6-sol` / `high`. Never `gpt-5.6-terra` (the script rejects it). `gpt-6-astra` and `--fast` only on explicit user request, each separately; the script pins the standard tier without `--fast`. Fast reminder policy as in the codex skill: one non-blocking mention after the first delegated run, never repeated.

## Run

```bash
<skill-dir>/scripts/run-codex-visual-review.sh <critique|compare|recheck> \
  --image "<screenshot.png>" [--image ...] [--reference "<design.png>"]... \
  [--repo "<repo-root>"] [--model gpt-5.6-sol --effort high] [--fast] <<'BRIEF'
<self-contained review brief>
BRIEF
```

The script is synchronous: launch it with the harness's own background mechanism (not a shell `&`), capture stdout and stderr to files, read them when done.

The last stdout line is the marker (both kinds go to stdout):
- `CODEX_VISUAL_REVIEW_OK mode=... report=<job_dir>/report.md job_dir=...`
- `CODEX_VISUAL_REVIEW_FAILED kind=<invalid_arguments|unavailable|rate_limit|authentication|service|execution|invalid_report> ...`

`OK` means the CLI returned and `report.md` contains all four required sections: Summary, Findings (per screenshot: Region / Issue / Impact / Suggestion; "No findings." is valid), Recheck status, Needs manual verification. It says nothing about whether the findings are right. No marker means interrupted or unknown.

No automatic retries. One later run only as a distinct request (new screenshots, or a `recheck`). Never rerun `rate_limit`, `authentication`, `unavailable`, `service`; point the user to codex-setup for the last three.

## After the run

1. Read `report.md` and look at the screenshots yourself; drop findings the image does not support.
2. Carry "Needs manual verification" items (DOM, focus order, keyboard, screen reader, motion) into the answer as open checks, not as passes.
3. Fixes go to the caller or to the codex skill in implement mode; after a fix, run `recheck` with the new screenshots and the earlier findings in the brief.
