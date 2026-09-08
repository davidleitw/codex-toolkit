---
name: codex
description: Delegate code work to the local Codex CLI in one of three modes - discuss (read-only second opinion on an unsettled problem), review (read-only findings on uncommitted changes, a base ref, or a commit), implement (a settled, scoped change). Use when the user names Codex, wants an independent opinion or review, or hands over a clearly specified change. Not for images or screenshots (see codex-assets, codex-visual-review). The caller keeps ownership of decisions, verification, and the final answer.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# codex

Script: `scripts/run-codex.sh` inside this skill's directory. Brief goes on stdin.

## Modes

| Mode | Sandbox | Use when | Brief must contain |
|---|---|---|---|
| `discuss` | read-only | problem is unsettled; want assumptions challenged | question, known facts, current assumptions, locked decisions, options considered, what a good answer looks like |
| `review` | read-only | independent findings on existing work | what to review (uncommitted / base ref / commit / paths), review focus, known constraints; say zero findings is acceptable |
| `implement` | workspace-write | decisions, scope, acceptance criteria are settled | scope, acceptance criteria, verification commands, working-tree changes to preserve, out-of-scope list |

Always: repository root, relevant project instructions, "stay in scope, preserve unrelated changes, report what you changed or verified". Keep the brief self-contained; never forward the whole conversation, secrets, or an instruction to hand work back.

## Model and speed

`--model` and `--effort` are mandatory; the script refuses to inherit them from config.

| Task | Model / effort |
|---|---|
| discuss, review (any size), debugging, code tracing, any design judgment | `gpt-5.6-sol` / `high` |
| implement with settled decisions and light scope (including mechanical edits) | `gpt-5.6-luna` / `max` |
| user explicitly asks for deeper thinking on discuss | `gpt-5.6-sol` / `xhigh`, then `max` |

- Never `gpt-5.6-terra` (the script rejects it).
- `gpt-6-astra` only when the user explicitly asks for GPT-6 / Astra in this conversation. Difficulty, a failed run, or config naming it are not authorization.
- `--fast` (Codex `service_tier="fast"`) only when the user explicitly asks for fast mode. GPT-6 and fast do not imply each other. Without `--fast` the script pins the standard tier.
- Authorization given earlier in the conversation carries forward; do not re-ask.
- After the first delegated run in a conversation, if fast was not requested, tell the user once, without waiting: 「若想加快後續 Codex 工作，可以說『接下來用 fast mode』；可能增加額度消耗。」 Never repeat, never re-send a job to switch.

## Run

```bash
<skill-dir>/scripts/run-codex.sh <discuss|review|implement> "<repo-root>" \
  --model gpt-5.6-sol --effort high [--fast] <<'BRIEF'
<self-contained brief>
BRIEF
```

The script is synchronous. Runs at `high` or above usually exceed a ten-minute foreground limit: launch them with the harness's own background mechanism (not a shell `&`), capture stdout and stderr to files, read the files when done.

The last stdout line is the marker (both kinds go to stdout; Codex's own stderr is passed through):
- `CODEX_DELEGATION_OK mode=... model=... effort=... service_tier=...`
- `CODEX_DELEGATION_FAILED kind=<invalid_arguments|unavailable|rate_limit|authentication|service|execution> exit_code=<n>`

Judge by the marker, not the exit code: a detached run may report exit -1 or unknown after finishing. `OK` means the CLI returned successfully; it says nothing about acceptance criteria, so read the output. No marker means interrupted or unknown, not failure.

No automatic retries. One later run is allowed only as a distinct request with changed inputs, evidence, or scope. Never rerun `rate_limit`, `authentication`, `unavailable`, or `service`; for the last three, point the user to the codex-setup skill.

Linked git worktree: Codex's sandbox cannot write the worktree's git index. Tell Codex to leave changes uncommitted; never say "leave the tree clean on failure" (it reverts its own work). The caller commits.

## After the run

discuss: weigh the reasoning against repository evidence, separate supported conclusions from new assumptions, and answer in your own words. Codex's confidence is not proof; do not start implementing before decisions are settled.

review / implement:
1. Read the diff or findings yourself.
2. Run the verification the task calls for.
3. Fix small leftovers directly, or make one justified follow-up run.
4. Report the combined result; do not call Codex's output verified until you checked it.

Failure: read the marker and stderr; after a failed implement, inspect the working tree for partial changes; keep valid unrelated edits (no blanket reset); continue the task yourself from the current state and mention the fallback only when it changes expectations.
