---
name: codex
description: Hand code work to the local Codex CLI. Use when the user asks for Codex by name; when you want a second opinion on an unsettled bug, design, or approach before deciding; when an independent review of uncommitted changes, a branch, or a commit would help; or when a fully specified code change can be delegated. Not for producing images (codex-assets) or reviewing screenshots (codex-visual-review).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# codex

Run `scripts/run-codex.sh` from this skill's directory with the brief on stdin. You keep ownership of decisions, verification, and the final answer.

## Modes

| Mode | Sandbox | Use when | Brief must contain |
|---|---|---|---|
| `discuss` | read-only | problem is unsettled; want assumptions challenged | question, known facts, current assumptions, locked decisions, options considered, what a good answer looks like |
| `review` | read-only | independent findings on existing work | what to review (uncommitted / base ref / commit / paths), review focus, known constraints; say zero findings is acceptable |
| `implement` | workspace-write | decisions, scope, acceptance criteria are settled | scope, acceptance criteria, verification commands, working-tree changes to preserve, out-of-scope list |

Every brief also gives the repository root, relevant project instructions, and "stay in scope, preserve unrelated changes, report what you changed or verified". Keep it self-contained; never include the whole conversation, secrets, or a request to hand work back.

## Model and effort

Always pass `--model` and `--effort`; the script rejects a run without them.

| Task | Model / effort |
|---|---|
| default: discuss, review (any size), debugging, code tracing, any design judgment | `gpt-6.1-sol` / `high` |
| implement with settled decisions and clear scope (pure coding, including mechanical edits) | `gpt-6.1-sol` / `medium` |
| user explicitly asks for deeper thinking | `gpt-6.1-sol` / `xhigh`, then `max` |
| user explicitly asks for Astra | `gpt-6-astra` / `high`, or the effort the user names |

- `gpt-6-astra` only when the user explicitly asks for Astra in this conversation. Difficulty, a failed run, or a config file naming it do not count.
- An effort the user names is used as given (`none` through `ultra`).
- `--fast` only when the user explicitly asks for fast mode. Astra and fast are separate requests; neither implies the other.
- A model, effort, or fast choice the user made earlier in the conversation carries forward; do not re-ask.
- After the first run in a conversation without fast, tell the user once, in their language and without waiting for a reply, that asking for fast mode speeds up later Codex runs but may use more quota. Never repeat it or resend a job to switch.

## Run

```bash
<skill-dir>/scripts/run-codex.sh <discuss|review|implement> "<repo-root>" \
  --model <model> --effort <effort> [--fast] <<'BRIEF'
<self-contained brief>
BRIEF
```

Runs routinely outlast the foreground time limit: launch every run with the harness's background mechanism (not a shell `&`), send stdout and stderr to files, and read them when it finishes.

The last stdout line is the marker:
- `CODEX_DELEGATION_OK mode=... model=... effort=... service_tier=...`
- `CODEX_DELEGATION_FAILED kind=<invalid_arguments|unavailable|rate_limit|authentication|service|execution> exit_code=<n>`

Judge by the marker, not the exit code: a detached run may report exit -1 or unknown after finishing. No marker means interrupted, not failed. `OK` only means the CLI finished; check the output against the task.

No automatic retries. A second run must change the inputs, evidence, or scope. Never rerun `rate_limit`, `authentication`, `unavailable`, or `service`; for the last three, run the codex-setup doctor if available, otherwise ask the user to check their Codex install and login.

In a linked git worktree, Codex cannot write the git index: tell it to leave changes uncommitted, never to "leave the tree clean on failure" (it reverts its own work). Commit yourself.

## After the run

discuss: weigh the reasoning against repository evidence, separate supported conclusions from new assumptions, and answer in your own words. Codex's confidence is not proof; do not start implementing before decisions are settled.

review / implement:
1. Read the diff or findings yourself.
2. Run the verification the task calls for.
3. Fix small leftovers directly, or make one justified follow-up run.
4. Report the combined result; do not call Codex's output verified until you checked it.

Failure: read the marker and stderr; after a failed implement, inspect the working tree for partial changes; keep valid unrelated edits (no blanket reset); continue the task yourself from the current state and mention the fallback only when it changes expectations.
