#!/usr/bin/env bash
# Produce visual assets through the local Codex CLI (built-in imagegen for
# raster, code-native SVG/CSS when that fits). Output is staged outside the
# repository; the caller reviews and integrates.
#
# usage: run-codex-assets.sh --repo <root> [--reference <img>]... [--edit-target <img>]...
#          [--model <m>] [--effort <e>] [--fast] [--staging-root <dir>] < brief.txt
#
# Last stdout line:
#   CODEX_ASSETS_READY status=<complete|partial> job_dir=<dir> manifest=<file>
#   CODEX_ASSETS_FAILED kind=<kind> ...

set -uo pipefail
umask 077

repo="$PWD"
model="gpt-5.6-sol"
effort="high"
fast=0
staging_root="${TMPDIR:-/tmp}/codex-toolkit/assets"
references=()
edit_targets=()

fail_arguments() {
  echo "CODEX_ASSETS_FAILED kind=invalid_arguments: $1"
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --reference)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--reference requires a value"
      references+=("$2"); shift 2 ;;
    --edit-target)
      [[ $# -ge 2 && -n "$2" ]] || fail_arguments "--edit-target requires a value"
      edit_targets+=("$2"); shift 2 ;;
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

command -v codex >/dev/null 2>&1 || {
  echo "CODEX_ASSETS_FAILED kind=unavailable: codex is not installed or not on PATH"
  exit 127
}
command -v jq >/dev/null 2>&1 || {
  echo "CODEX_ASSETS_FAILED kind=unavailable: jq is required to validate the asset manifest"
  exit 127
}
if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_of() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
else
  echo "CODEX_ASSETS_FAILED kind=unavailable: sha256sum or shasum is required"
  exit 127
fi
bytes_of() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }
have_python=0
command -v python3 >/dev/null 2>&1 && have_python=1

[[ -d "$repo" ]] || fail_arguments "repository directory does not exist: $repo"
repo="$(cd "$repo" && pwd -P)"

canonical_file() {
  local f="$1" d
  [[ -f "$f" ]] || fail_arguments "file does not exist: $f"
  d="$(cd "$(dirname "$f")" && pwd -P)"
  printf '%s/%s' "$d" "$(basename "$f")"
}
for i in "${!references[@]}"; do references[$i]="$(canonical_file "${references[$i]}")"; done
for i in "${!edit_targets[@]}"; do edit_targets[$i]="$(canonical_file "${edit_targets[$i]}")"; done

[[ ! "$staging_root" =~ [[:space:][:cntrl:]] ]] || fail_arguments "--staging-root must not contain whitespace or control characters (marker fields are space-separated)"
mkdir -p "$staging_root" || fail_arguments "cannot create staging root: $staging_root"
staging_root="$(cd "$staging_root" && pwd -P)"
job_dir="$(mktemp -d "$staging_root/job-XXXXXX")"
job_id="$(basename "$job_dir")"
brief_file="$job_dir/request.txt"
prompt_file="$job_dir/codex-prompt.txt"
error_file="$job_dir/codex-stderr.log"
final_file="$job_dir/final-message.txt"
manifest_file="$job_dir/manifest.json"
preview_file="$job_dir/preview.html"

cat >"$brief_file"
[[ -s "$brief_file" ]] || fail_arguments "asset brief on stdin is empty"

if [[ $fast -eq 1 ]]; then service_tier="fast"; else service_tier="default"; fi

{
  cat <<'PROMPT_HEADER'
Produce visual assets for another coding agent. Work as an isolated asset producer.

Rules:
- The repository is read-only context: inspect it for visual conventions (colors, existing assets, sizes, naming, formats) but never modify it and never run git commands there.
- Write every deliverable under the staging directory. Never copy files into the repository.
- Raster images: use the built-in image generation tool ($imagegen, default built-in mode). Do not use the API/CLI fallback. Generate first, then copy the selected result into the staging directory with a descriptive filename.
- Scalable icons, marks, and UI motion: prefer project-compatible SVG / CSS / code-native formats. Do not ship a raster approximation where the project needs a maintainable vector.
- Edit targets: never overwrite them. Write the edited result as a new versioned file in staging and record `version_of` with the source path.
- Reference images are style or composition guidance only unless the brief says otherwise; do not reproduce them.
- A set of assets shares one visual spec; state it in `task_summary` and apply it to every item.
- Do not ask follow-up questions. If a design decision is missing, choose the safest reviewable option and record it in `warnings`.
- If some requested items cannot be produced, deliver the valid ones with status "partial" and list each missing item in `missing`.
- Do not retry persistent usage, authentication, capability, or service failures.
PROMPT_HEADER
  printf '\nRepository (read-only): %s\n' "$repo"
  printf 'Staging directory (write here): %s\n' "$job_dir"
  printf 'Job id: %s\n' "$job_id"
  if [[ ${#references[@]} -gt 0 ]]; then
    printf '\nReference images (style/composition guidance), attached in this order:\n'
    for r in "${references[@]}"; do printf -- '- %s\n' "$r"; done
  fi
  if [[ ${#edit_targets[@]} -gt 0 ]]; then
    printf '\nEdit targets (modify into a new versioned file; keep the original untouched), attached after the references:\n'
    for t in "${edit_targets[@]}"; do printf -- '- %s\n' "$t"; done
  fi
  cat <<'PROMPT_SCHEMA'

Before finishing, write `manifest.json` in the staging directory with exactly this shape:

{
  "schema_version": 2,
  "job_id": "<job id>",
  "status": "complete | partial",
  "task_summary": "<what was produced and the shared visual spec>",
  "generation_mode": "built-in-imagegen | code-native | mixed",
  "assets": [
    {
      "path": "<absolute path inside the staging directory>",
      "kind": "raster | vector | animation-source | other",
      "format": "<file extension without dot>",
      "intended_use": "<where or how it should be used>",
      "version_of": null,
      "notes": "<design notes, integration notes>"
    }
  ],
  "missing": [],
  "warnings": []
}

`version_of` is the absolute path of the edit target this asset revises, or null. `missing` lists requested items not delivered (required when status is "partial"). List only real deliverables: not logs, prompts, the manifest, or intermediate generations. Technical fields (checksum, size, dimensions, alpha) are computed by the caller; do not add them.

Task brief:
PROMPT_SCHEMA
  cat "$brief_file"
} >"$prompt_file"

codex_args=(
  exec
  --ephemeral
  --skip-git-repo-check
  --sandbox workspace-write
  --cd "$job_dir"
  --model "$model"
  -c "model_reasoning_effort=\"$effort\""
  -c "service_tier=\"$service_tier\""
  --output-last-message "$final_file"
)
for r in "${references[@]}"; do codex_args+=(--image "$r"); done
for t in "${edit_targets[@]}"; do codex_args+=(--image "$t"); done
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
  echo "CODEX_ASSETS_FAILED kind=$kind exit_code=$status job_dir=$job_dir"
  exit "$status"
fi

if ! jq -e '
  .schema_version == 2 and
  .job_id == $job_id and
  (.status == "complete" or .status == "partial") and
  (.assets | type == "array" and length > 0) and
  (.missing | type == "array") and
  (.status == "complete" or (.missing | length > 0)) and
  all(.assets[]; (.path | type == "string") and (.kind | type == "string") and (.format | type == "string"))
' --arg job_id "$job_id" "$manifest_file" >/dev/null 2>&1; then
  echo "CODEX_ASSETS_FAILED kind=invalid_manifest job_dir=$job_dir manifest=$manifest_file"
  exit 65
fi

# Compute technical fields from the files themselves; never trust model-written values.
probe_image() {
  # prints JSON {"width":..,"height":..,"alpha":..,"detected":..} ; nulls when unknown
  if [[ $have_python -eq 0 ]]; then echo '{"width":null,"height":null,"alpha":null,"detected":null}'; return; fi
  python3 - "$1" <<'PY'
import json, struct, sys
p = sys.argv[1]
w = h = alpha = detected = None
try:
    with open(p, 'rb') as f:
        d = f.read(32)
        if d[:8] == b'\x89PNG\r\n\x1a\n':
            detected = 'png'
            w, h = struct.unpack('>II', d[16:24])
            alpha = d[25] in (4, 6)
            if not alpha:
                # indexed / gray / rgb PNGs can still carry transparency via a tRNS chunk before IDAT
                f.seek(33)
                while True:
                    hdr = f.read(8)
                    if len(hdr) < 8:
                        break
                    ln, typ = struct.unpack('>I4s', hdr)
                    if typ == b'tRNS':
                        alpha = True
                        break
                    if typ == b'IDAT':
                        break
                    f.seek(ln + 4, 1)
        elif d[:6] in (b'GIF87a', b'GIF89a'):
            detected = 'gif'
            w, h = struct.unpack('<HH', d[6:10])
        elif d[:2] == b'\xff\xd8':
            detected = 'jpeg'
            f.seek(2)
            while True:
                b = f.read(1)
                if not b:
                    break
                if b != b'\xff':
                    continue
                m = f.read(1)
                while m == b'\xff':
                    m = f.read(1)
                if not m:
                    break
                m = m[0]
                if m in (0xd8, 0x01) or 0xd0 <= m <= 0xd7:
                    continue
                seg = f.read(2)
                if len(seg) < 2:
                    break
                ln = struct.unpack('>H', seg)[0]
                if m in (0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf):
                    f.read(1)
                    h, w = struct.unpack('>HH', f.read(4))
                    alpha = False
                    break
                f.seek(ln - 2, 1)
        elif d[:4] == b'RIFF' and d[8:12] == b'WEBP':
            detected = 'webp'
            if d[12:16] == b'VP8X':
                f.seek(24)
                b = f.read(6)
                w = 1 + (b[0] | b[1] << 8 | b[2] << 16)
                h = 1 + (b[3] | b[4] << 8 | b[5] << 16)
                alpha = bool(d[20] & 0x10)
        elif d[:5] == b'<?xml' or d[:4] == b'<svg':
            detected = 'svg'
except Exception:
    pass
print(json.dumps({"width": w, "height": h, "alpha": alpha, "detected": detected}))
PY
}

normalize_format() { case "$(tr '[:upper:]' '[:lower:]' <<<"$1")" in jpg) echo jpeg ;; *) tr '[:upper:]' '[:lower:]' <<<"$1" ;; esac; }

tmp_manifest="$job_dir/.manifest.tmp"
cp "$manifest_file" "$tmp_manifest"
index=0
while IFS= read -r asset_path; do
  if [[ ! -f "$asset_path" || -L "$asset_path" ]]; then
    echo "CODEX_ASSETS_FAILED kind=missing_or_linked_asset path=$asset_path job_dir=$job_dir"
    exit 66
  fi
  asset_dir="$(cd "$(dirname "$asset_path")" && pwd -P)"
  canonical="$asset_dir/$(basename "$asset_path")"
  case "$canonical" in
    "$job_dir"/*) ;;
    *)
      echo "CODEX_ASSETS_FAILED kind=unsafe_asset_path path=$asset_path job_dir=$job_dir"
      exit 65 ;;
  esac
  if [[ "$canonical" =~ [[:space:][:cntrl:]] ]]; then
    echo "CODEX_ASSETS_FAILED kind=unsafe_asset_path reason=whitespace_or_control_char path=$canonical job_dir=$job_dir"
    exit 65
  fi
  sha="$(sha256_of "$canonical")"
  size="$(bytes_of "$canonical")"
  probe="$(probe_image "$canonical")"
  detected="$(jq -r '.detected // empty' <<<"$probe")"
  declared="$(normalize_format "$(jq -r --argjson i "$index" '.assets[$i].format' "$manifest_file")")"
  if [[ -n "$detected" && "$detected" != "$declared" ]]; then
    echo "CODEX_ASSETS_FAILED kind=format_mismatch declared=$declared detected=$detected path=$canonical job_dir=$job_dir"
    exit 65
  fi
  jq --argjson i "$index" --arg path "$canonical" --arg sha "$sha" --argjson bytes "$size" --argjson probe "$probe" \
    '.assets[$i] |= (. + {path: $path, sha256: $sha, bytes: $bytes} + $probe)' \
    "$tmp_manifest" >"$tmp_manifest.next" && mv "$tmp_manifest.next" "$tmp_manifest"
  index=$((index + 1))
done < <(jq -r '.assets[].path' "$manifest_file")
jq '. + {verified_by: "run-codex-assets.sh"}' "$tmp_manifest" >"$manifest_file" && rm -f "$tmp_manifest"

# Local preview page: light / dark / checker background toggle for transparency checks.
{
  cat <<'HTML_HEAD'
<!doctype html><meta charset="utf-8"><title>codex-assets preview</title>
<style>
body{font:14px system-ui;margin:0;padding:16px;background:#f4f4f2;color:#222}
body.dark{background:#1b1b1f;color:#eee}
body.checker{background:repeating-conic-gradient(#ccc 0 25%,#fff 0 50%) 0 0/24px 24px}
.bar{position:sticky;top:0;background:inherit;padding:8px 0;display:flex;gap:8px;align-items:center}
.card{margin:16px 0;padding:12px;border:1px solid #8884;border-radius:8px}
img{max-width:100%;display:block}
code{font-size:12px;word-break:break-all}
</style>
<div class="bar"><strong>codex-assets preview</strong>
<button onclick="document.body.className=''">light</button>
<button onclick="document.body.className='dark'">dark</button>
<button onclick="document.body.className='checker'">checker</button></div>
HTML_HEAD
  # model-written strings are HTML-escaped; paths are URL-encoded per segment
  jq -r '.assets[] | "<div class=\"card\"><code>\(.path | @html)</code><br><small>\(.kind | @html) · \(.format | @html) · \(.width // "?")x\(.height // "?") · \(.bytes) bytes · alpha=\(.alpha)</small>" + (if .kind == "raster" or .format == "svg" then "<img src=\"file://\(.path | split("/") | map(@uri) | join("/"))\" alt=\"\(.intended_use | @html)\">" else "" end) + "<p>\(.intended_use | @html)</p><p>\(.notes | @html)</p></div>"' "$manifest_file"
} >"$preview_file" || echo "warning: preview.html could not be written" >&2

final_status="$(jq -r '.status' "$manifest_file")"
echo "CODEX_ASSETS_READY status=$final_status job_dir=$job_dir manifest=$manifest_file preview=$preview_file"
