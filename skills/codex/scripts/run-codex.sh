#!/usr/bin/env bash
# Delegate one discuss | review | implement task to the local Codex CLI.
#
# usage: run-codex.sh <mode> [<repo-root>] --model <model> --effort <effort> [--fast] < brief.txt
#
# The last line of stdout is the terminal marker:
#   CODEX_DELEGATION_OK mode=<mode>
#   CODEX_DELEGATION_FAILED kind=<kind> exit_code=<n>
# Judge completion by the marker, not by the exit code.

set -uo pipefail

fail_arguments() {
  echo "CODEX_DELEGATION_FAILED kind=invalid_arguments: $1"
  exit 64
}

mode="${1:-}"
[[ -n "$mode" ]] || fail_arguments "mode is required: implement, review, or discuss"
shift

repo="$PWD"
if [[ $# -gt 0 && "$1" != --* ]]; then
  repo="$1"
  shift
fi

model=""
effort=""
fast=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--model requires a value"
      model="$2"
      shift 2
      ;;
    --effort)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--effort requires a value"
      effort="$2"
      shift 2
      ;;
    --fast)
      fast=1
      shift
      ;;
    *)
      fail_arguments "unknown option: $1"
      ;;
  esac
done

# Both are mandatory: the user's global config may name a model (for example
# gpt-6-astra) that policy forbids unless explicitly requested. Passing them
# on every run is what stops inherited configuration from choosing silently.
[[ -n "$model" ]] || fail_arguments "--model is required; never inherit the model from config"
[[ -n "$effort" ]] || fail_arguments "--effort is required; never inherit the effort from config"

case "$effort" in
  none|minimal|low|medium|high|xhigh|max) ;;
  *) fail_arguments "unsupported effort: $effort" ;;
esac

# Policy: terra is never used; astra must be an explicit user request (passing it is the caller's attestation).
[[ "$model" != "gpt-5.6-terra" ]] || fail_arguments "gpt-5.6-terra is not allowed by policy; use gpt-5.6-sol or gpt-5.6-luna"

case "$mode" in
  implement) sandbox="workspace-write" ;;
  review|discuss) sandbox="read-only" ;;
  *) fail_arguments "unknown mode: $mode (expected implement, review, or discuss)" ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  echo "CODEX_DELEGATION_FAILED kind=unavailable: codex is not installed or not on PATH"
  exit 127
fi

[[ -d "$repo" ]] || fail_arguments "repository directory does not exist: $repo"
repo="$(cd "$repo" && pwd -P)"

prompt_file="$(mktemp -t codex-toolkit-prompt.XXXXXX)"
error_file="$(mktemp -t codex-toolkit-error.XXXXXX)"
trap 'rm -f "$prompt_file" "$error_file"' EXIT

cat >"$prompt_file"
[[ -s "$prompt_file" ]] || fail_arguments "delegation brief on stdin is empty"

if [[ $fast -eq 1 ]]; then
  service_tier="fast"
else
  # Explicit standard tier on every run so a global service_tier="fast"
  # cannot be inherited without opt-in.
  service_tier="default"
fi

codex_args=(
  exec
  --ephemeral
  --sandbox "$sandbox"
  --cd "$repo"
  --model "$model"
  -c "model_reasoning_effort=\"$effort\""
  -c "service_tier=\"$service_tier\""
  -
)

codex "${codex_args[@]}" <"$prompt_file" 2>"$error_file"
status=$?

cat "$error_file" >&2

if [[ $status -eq 0 ]]; then
  echo "CODEX_DELEGATION_OK mode=$mode model=$model effort=$effort service_tier=$service_tier"
  exit 0
fi

diagnostic="$(tail -n 40 "$error_file")"

if grep -Eiq 'rate[ _-]?limit|usage[ _-]?limit|quota|too many requests|limit (has been )?reached|exhausted|reset.*limit' <<<"$diagnostic"; then
  kind="rate_limit"
elif grep -Eiq 'unauthenticated|authentication failed|not logged in|please log in|login required|unauthorized|invalid credential' <<<"$diagnostic"; then
  kind="authentication"
elif grep -Eiq 'timed out|timeout|temporarily unavailable|service unavailable|connection (failed|refused)|network error' <<<"$diagnostic"; then
  kind="service"
else
  kind="execution"
fi

echo "CODEX_DELEGATION_FAILED kind=$kind exit_code=$status"
exit "$status"
