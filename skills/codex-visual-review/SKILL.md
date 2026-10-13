---
name: codex-visual-review
description: Have the local Codex CLI review UI screenshots that already exist as files - critique a screen, compare an implementation against reference designs, or recheck earlier findings after a fix. Use when the user or the task supplies screenshots or design images to evaluate. Not for capturing screenshots or driving a browser, generating images (codex-assets), or fixing code (codex).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# codex-visual-review

Run `scripts/run-codex-visual-review.sh` from this skill's directory with the brief on stdin and screenshots attached via `--image`. The run is read-only.

## Modes

| Mode | Flags | Brief says |
|---|---|---|
| `critique` | `--image`... | what the screen is for, target users, platform, known constraints, what to focus on |
| `compare` | `--image`... `--reference`... | which reference maps to which screenshot, tolerated differences |
| `recheck` | `--image`... | the earlier findings verbatim, what was changed |

The mode is the first script argument. `--repo "<root>"` optionally adds read-only code context.

## Model and effort

Without flags the script uses `gpt-6.1-sol` / `high`. `gpt-6-astra` (at `high` unless the user names an effort) and `--fast` only when the user explicitly asks, each separately; an effort the user names is used as given. After the first run without fast, tell the user once, in their language and without waiting, that fast mode speeds up later runs but may use more quota.

## Run

```bash
<skill-dir>/scripts/run-codex-visual-review.sh <critique|compare|recheck> \
  --image "<screenshot.png>" [--image ...] [--reference "<design.png>"]... \
  [--repo "<repo-root>"] [--model <model> --effort <effort>] [--fast] <<'BRIEF'
<self-contained review brief>
BRIEF
```

Launch with the harness's background mechanism (not a shell `&`), send stdout and stderr to files, and read them when it finishes.

The last stdout line is the marker:
- `CODEX_VISUAL_REVIEW_OK mode=... report=<job_dir>/report.md job_dir=...`
- `CODEX_VISUAL_REVIEW_FAILED kind=<invalid_arguments|unavailable|rate_limit|authentication|service|execution|invalid_report> ...`

`OK` means `report.md` has all four sections: Summary, Findings (per screenshot: Region / Issue / Impact / Suggestion; "No findings." is valid), Recheck status, Needs manual verification. It says nothing about whether the findings are right. No marker means interrupted.

No automatic retries. A second run must be a distinct request (new screenshots, or a `recheck`). Never rerun `rate_limit`, `authentication`, `unavailable`, or `service`; for the last three, run the codex-setup doctor if available.

## After the run

1. Read `report.md` and look at the screenshots yourself; drop findings the image does not support.
2. Carry "Needs manual verification" items (DOM, focus order, keyboard, screen reader, motion) into the answer as open checks, not as passes.
3. Fix issues yourself or with the codex skill's implement mode; after a fix, run `recheck` with the new screenshots and the earlier findings in the brief.
