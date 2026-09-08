#!/usr/bin/env bash
# Review UI screenshots with the local Codex CLI (read-only, vision input).
#
# usage: run-codex-visual-review.sh <critique|compare|recheck> --image <png>...
#          [--reference <img>]... [--repo <root>] [--model <m>] [--effort <e>] [--fast]
#          [--staging-root <dir>] < brief.txt
#
# Last stdout line:
#   CODEX_VISUAL_REVIEW_OK mode=<mode> report=<file> job_dir=<dir>
#   CODEX_VISUAL_REVIEW_FAILED kind=<kind> ...

set -uo pipefail
umask 077

fail_arguments() {
  echo "CODEX_VISUAL_REVIEW_FAILED kind=invalid_arguments: $1"
  exit 64
}

mode="${1:-}"
case "$mode" in
  critique|compare|recheck) shift ;;
  *) fail_arguments "mode is required: critique, compare, or recheck" ;;
esac

repo=""
model="gpt-5.6-sol"
effort="high"
fast=0
staging_root="${TMPDIR:-/tmp}/codex-toolkit/visual-review"
images=()
references=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--image requires a value"
      images+=("$2"); shift 2 ;;
    --reference)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--reference requires a value"
      references+=("$2"); shift 2 ;;
    --repo)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--repo requires a value"
      repo="$2"; shift 2 ;;
    --model)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--model requires a value"
      model="$2"; shift 2 ;;
    --effort)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--effort requires a value"
      effort="$2"; shift 2 ;;
    --fast)
      fast=1; shift ;;
    --staging-root)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--staging-root requires a value"
      staging_root="$2"; shift 2 ;;
    *)
      fail_arguments "unknown option: $1" ;;
  esac
done

case "$effort" in
  none|minimal|low|medium|high|xhigh|max) ;;
  *) fail_arguments "unsupported effort: $effort" ;;
esac

# Policy: terra is never used; astra must be an explicit user request (passing it is the caller's attestation).
[[ "$model" != "gpt-5.6-terra" ]] || fail_arguments "gpt-5.6-terra is not allowed by policy; use gpt-5.6-sol or gpt-5.6-luna"
[[ ${#images[@]} -gt 0 ]] || fail_arguments "at least one --image is required"
[[ "$mode" != "compare" || ${#references[@]} -gt 0 ]] || fail_arguments "compare mode requires at least one --reference"

command -v codex >/dev/null 2>&1 || {
  echo "CODEX_VISUAL_REVIEW_FAILED kind=unavailable: codex is not installed or not on PATH"
  exit 127
}

canonical_file() {
  local f="$1" d
  [[ -f "$f" ]] || fail_arguments "file does not exist: $f"
  d="$(cd "$(dirname "$f")" && pwd -P)"
  printf '%s/%s' "$d" "$(basename "$f")"
}
for i in "${!images[@]}"; do images[$i]="$(canonical_file "${images[$i]}")"; done
for i in "${!references[@]}"; do references[$i]="$(canonical_file "${references[$i]}")"; done

[[ ! "$staging_root" =~ [[:space:][:cntrl:]] ]] || fail_arguments "--staging-root must not contain whitespace or control characters (marker fields are space-separated)"
mkdir -p "$staging_root" || fail_arguments "cannot create staging root: $staging_root"
staging_root="$(cd "$staging_root" && pwd -P)"
job_dir="$(mktemp -d "$staging_root/job-XXXXXX")"
brief_file="$job_dir/request.txt"
prompt_file="$job_dir/codex-prompt.txt"
error_file="$job_dir/codex-stderr.log"
report_file="$job_dir/report.md"

cat >"$brief_file"
[[ -s "$brief_file" ]] || fail_arguments "review brief on stdin is empty"

if [[ -n "$repo" ]]; then
  [[ -d "$repo" ]] || fail_arguments "repository directory does not exist: $repo"
  workdir="$(cd "$repo" && pwd -P)"
else
  workdir="$job_dir"
fi

if [[ $fast -eq 1 ]]; then service_tier="fast"; else service_tier="default"; fi

{
  cat <<'PROMPT_HEADER'
You are a read-only visual reviewer for UI screenshots supplied by another coding agent.

Rules:
- Review only what is visible in the attached images. Do not modify any file, do not run git commands, do not attempt to take new screenshots or open a browser.
- If a repository is provided, you may read it to understand intent and locate the relevant UI code, but code fixes belong to the caller.
- Report real, specific problems with their visible evidence. Do not pad to a quota; zero findings is a valid result.
- Screenshots cannot prove DOM structure, keyboard behavior, focus order, screen-reader output, or motion. List what still needs manual verification instead of guessing.
PROMPT_HEADER
  case "$mode" in
    critique)
      printf '\nMode: critique. Assess layout, hierarchy, spacing, alignment, typography, color/contrast, states, consistency, and obvious accessibility issues visible in the screenshots.\n' ;;
    compare)
      printf '\nMode: compare. The reference images show the intended design; the screenshots show the implementation. Report every visible deviation that matters (missing elements, spacing/size/color/typography drift, wrong states) and note intentional-looking differences separately.\n' ;;
    recheck)
      printf '\nMode: recheck. The brief lists earlier findings. For each: state resolved, still present, or regressed, with the visible evidence. Then list any new problems.\n' ;;
  esac
  printf '\nScreenshots (attached in this order):\n'
  n=1; for img in "${images[@]}"; do printf -- '- screenshot %d: %s\n' "$n" "$img"; n=$((n + 1)); done
  if [[ ${#references[@]} -gt 0 ]]; then
    printf '\nReference designs (attached after the screenshots, in this order):\n'
    n=1; for ref in "${references[@]}"; do printf -- '- reference %d: %s\n' "$n" "$ref"; n=$((n + 1)); done
  fi
  [[ -n "$repo" ]] && printf '\nRepository (read-only): %s\n' "$workdir"
  cat <<'PROMPT_FORMAT'

Write the final answer as Markdown with exactly these sections:

# Visual review: <mode>
## Summary
<2-4 sentences>
## Findings
### <screenshot file name>
- **Region:** <where in the image>  **Issue:** <what is wrong>  **Impact:** <who/what it affects>  **Suggestion:** <concrete change>
(repeat per finding; write "No findings." if none)
## Recheck status
(recheck mode only: one line per earlier finding: resolved | still present | regressed, with evidence; otherwise "Not applicable.")
## Needs manual verification
- <items a screenshot cannot prove>

Review brief:
PROMPT_FORMAT
  cat "$brief_file"
} >"$prompt_file"

codex_args=(
  exec
  --ephemeral
  --skip-git-repo-check
  --sandbox read-only
  --cd "$workdir"
  --model "$model"
  -c "model_reasoning_effort=\"$effort\""
  -c "service_tier=\"$service_tier\""
  --output-last-message "$report_file"
)
for img in "${images[@]}"; do codex_args+=(--image "$img"); done
for ref in "${references[@]}"; do codex_args+=(--image "$ref"); done
codex_args+=(-)

codex "${codex_args[@]}" <"$prompt_file" 2>"$error_file"
status=$?
cat "$error_file" >&2

if [[ $status -ne 0 ]]; then
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
  echo "CODEX_VISUAL_REVIEW_FAILED kind=$kind exit_code=$status job_dir=$job_dir"
  exit "$status"
fi

for section in '## Summary' '## Findings' '## Recheck status' '## Needs manual verification'; do
  if [[ ! -s "$report_file" ]] || ! grep -qF "$section" "$report_file"; then
    echo "CODEX_VISUAL_REVIEW_FAILED kind=invalid_report missing_section=\"$section\" job_dir=$job_dir report=$report_file"
    exit 65
  fi
done

echo "CODEX_VISUAL_REVIEW_OK mode=$mode report=$report_file job_dir=$job_dir"
