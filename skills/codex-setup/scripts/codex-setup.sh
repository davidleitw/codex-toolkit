#!/usr/bin/env bash
# Report whether the local Codex CLI is ready for the codex-toolkit skills.
# Never modifies configuration.
#
# usage: codex-setup.sh doctor
#        codex-setup.sh smoke-test [--imagegen]      # spends quota; run only on explicit request
#
# doctor prints one line per check: CHECK <name> <available|unavailable|unknown> <detail>
# and ends with CODEX_SETUP_DOCTOR_OK or CODEX_SETUP_DOCTOR_ATTENTION unavailable=<n> unknown=<n>.
# smoke-test ends with CODEX_SMOKE_OK or CODEX_SMOKE_FAILED kind=<kind>.

set -uo pipefail

codex_home="${CODEX_HOME:-$HOME/.codex}"
config_file="$codex_home/config.toml"

unavailable=0
unknown=0
check() {
  # check <name> <status> <detail>
  case "$2" in
    unavailable) unavailable=$((unavailable + 1)) ;;
    unknown) unknown=$((unknown + 1)) ;;
  esac
  printf 'CHECK %-16s %-12s %s\n' "$1" "$2" "$3"
}

config_value() {
  # top-level key only; stops at the first [table]
  [[ -f "$config_file" ]] || return 1
  awk -v key="$1" '
    /^\[/ { exit }
    $1 == key && $2 == "=" { sub(/^[^=]*=[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }
  ' "$config_file"
}

doctor() {
  if command -v codex >/dev/null 2>&1; then
    check codex-cli available "$(codex --version 2>/dev/null | head -n 1) at $(command -v codex)"
  else
    check codex-cli unavailable "codex not on PATH; install: npm install -g @openai/codex"
    check auth unknown "cannot check without codex"
    check codex-doctor unknown "cannot run without codex"
    check plugins unknown "cannot check without codex"
  fi

  if command -v codex >/dev/null 2>&1; then
    if login_out="$(codex login status 2>&1)"; then
      check auth available "$login_out"
    else
      check auth unavailable "${login_out:-codex login status failed}; run: codex login"
    fi

    if doctor_out="$(codex doctor --summary --ascii --no-color 2>&1)"; then
      summary="$(grep -E '[0-9]+ ok' <<<"$doctor_out" | tail -n 1)"
      if grep -Eq '[[:space:]]0 fail' <<<"$summary"; then
        check codex-doctor available "$summary"
      else
        check codex-doctor unavailable "$summary; run: codex doctor"
      fi
    else
      check codex-doctor unavailable "codex doctor exited non-zero; run: codex doctor"
    fi

    if codex plugin --help >/dev/null 2>&1; then
      check plugins available "codex plugin subcommand present"
    else
      check plugins unavailable "this codex build has no plugin subcommand; install skills standalone"
    fi
  fi

  if [[ -f "$config_file" ]]; then
    check config available "base user config $config_file (profiles, project, and system layers not inspected)"
    m="$(config_value model)"; e="$(config_value model_reasoning_effort)"; t="$(config_value service_tier)"
    check config-model available "base user config: model=${m:-<unset>} effort=${e:-<unset>} service_tier=${t:-<unset>} (scripts always pass model, effort, and service_tier explicitly; these defaults are not inherited)"
    if [[ "$t" == "fast" ]]; then
      check config-fast available "base user config sets service_tier=fast; toolkit scripts override it to default unless --fast is passed"
    fi
  else
    check config unknown "no $config_file; Codex defaults apply"
  fi

  if [[ -f "$codex_home/skills/.system/imagegen/SKILL.md" ]]; then
    check imagegen-skill available "$codex_home/skills/.system/imagegen (presence only; run smoke-test --imagegen to confirm generation works)"
  else
    check imagegen-skill unknown "built-in imagegen skill not found under $codex_home/skills/.system; codex-assets raster output may be unavailable"
  fi

  for tool in jq python3; do
    if command -v "$tool" >/dev/null 2>&1; then
      check "$tool" available "$(command -v "$tool")"
    else
      case "$tool" in
        jq) check jq unavailable "required by codex-assets manifest validation" ;;
        python3) check python3 unavailable "codex-assets image dimensions/alpha will be reported as null" ;;
      esac
    fi
  done
  if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    check sha256 available "$(command -v sha256sum || command -v shasum)"
  else
    check sha256 unavailable "sha256sum or shasum required by codex-assets"
  fi

  if [[ $unavailable -eq 0 && $unknown -eq 0 ]]; then
    echo "CODEX_SETUP_DOCTOR_OK"
  else
    echo "CODEX_SETUP_DOCTOR_ATTENTION unavailable=$unavailable unknown=$unknown"
  fi
}

smoke_test() {
  local with_imagegen=0
  [[ "${1:-}" == "--imagegen" ]] && with_imagegen=1
  command -v codex >/dev/null 2>&1 || { echo "CODEX_SMOKE_FAILED kind=unavailable: codex not on PATH"; exit 127; }

  workdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-toolkit-smoke.XXXXXX")"
  err="$workdir/stderr.log"
  out="$workdir/last-message.txt"

  codex exec --ephemeral --skip-git-repo-check --sandbox read-only --cd "$workdir" \
    --model gpt-5.6-luna -c 'model_reasoning_effort="low"' -c 'service_tier="default"' \
    --output-last-message "$out" \
    'Reply with exactly the text CODEX_SMOKE_REPLY and nothing else.' >/dev/null 2>"$err"
  status=$?
  if [[ $status -ne 0 ]] || ! grep -q 'CODEX_SMOKE_REPLY' "$out" 2>/dev/null; then
    tail -n 20 "$err" >&2
    echo "CODEX_SMOKE_FAILED kind=text exit_code=$status workdir=$workdir"
    exit 1
  fi
  echo "smoke text: ok (gpt-5.6-luna low)"

  if [[ $with_imagegen -eq 1 ]]; then
    codex exec --ephemeral --skip-git-repo-check --sandbox workspace-write --cd "$workdir" \
      --model gpt-5.6-luna -c 'model_reasoning_effort="low"' -c 'service_tier="default"' \
      --output-last-message "$out" \
      "Use the built-in image generation tool (\$imagegen, built-in mode, no API fallback) to generate one small 1024x1024 flat solid indigo square, then copy the result to $workdir/smoke.png. Reply with the final path only." >/dev/null 2>"$err"
    status=$?
    if [[ $status -ne 0 || ! -s "$workdir/smoke.png" ]]; then
      tail -n 20 "$err" >&2
      echo "CODEX_SMOKE_FAILED kind=imagegen exit_code=$status workdir=$workdir"
      exit 1
    fi
    echo "smoke imagegen: ok ($workdir/smoke.png)"
  fi
  echo "CODEX_SMOKE_OK workdir=$workdir"
}

case "${1:-}" in
  doctor) doctor ;;
  smoke-test) shift; smoke_test "$@" ;;
  *) echo "usage: codex-setup.sh doctor | smoke-test [--imagegen]" >&2; exit 64 ;;
esac
