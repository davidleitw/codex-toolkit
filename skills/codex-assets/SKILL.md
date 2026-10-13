---
name: codex-assets
description: Produce or edit image assets through the local Codex CLI. Use when the task needs a new illustration, background, texture, mockup, icon, favicon, social image, or sprite frame; several assets in one consistent style; or an edit, variant, or new version of an existing image. Not for reviewing screenshots (codex-visual-review).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
  - Write
---

# codex-assets

Run `scripts/run-codex-assets.sh` from this skill's directory with the brief on stdin. Codex writes only into a staging job directory (default `${TMPDIR:-/tmp}/codex-toolkit/assets/job-*`), never into the repository; reviewing and integrating the files is your job.

## Prepare

1. Read the repository first: design tokens, existing assets, sizes, naming, formats, framework conventions.
2. Settle intended use, exact dimensions or ratio, theme variants, transparency, exact text, alt/accessibility needs. Ask the user only when a missing choice changes the result materially.
3. Route: raster (illustration, background, texture, mockup, variant, sprite frame) → built-in image generation; scalable icon or production mark → SVG / code-native; UI motion → CSS / SVG / Lottie / framework code, image generation only for source frames.
4. Write the brief: mode, visual goal, placement, project conventions, exact deliverables (file names, sizes, formats, transparency), constraints, avoid-list, role of each attached image.

State the mode in the brief; the script has no mode argument. Changes to files inside the repository (wiring an SVG into a component, editing a repo asset in place) are yours or the codex skill's implement mode, even when the file is an image.

| Mode | Flags | Brief says |
|---|---|---|
| generate | `--reference` optional | new asset(s) from description |
| edit | `--edit-target <img>` | what to change, what must stay identical |
| set | none or `--reference` | list of items plus the shared visual spec |
| revise | `--edit-target <previous output>` | the one change requested; original stays untouched, result is a new version |

## Model and effort

Without flags the script uses `gpt-6.1-sol` / `high`. Use `--effort medium` for a settled, mechanical job such as re-exporting a fixed spec. `gpt-6-astra` (at `high` unless the user names an effort) and `--fast` only when the user explicitly asks, each separately; an effort the user names is used as given. After the first run without fast, tell the user once, in their language and without waiting, that fast mode speeds up later runs but may use more quota.

## Run

```bash
<skill-dir>/scripts/run-codex-assets.sh --repo "<repo-root>" \
  [--reference "<style-or-composition-image>"]... [--edit-target "<image-to-edit>"]... \
  [--model <model> --effort <effort>] [--fast] <<'BRIEF'
<self-contained asset brief>
BRIEF
```

Image generation is slow: launch with the harness's background mechanism (not a shell `&`), send stdout and stderr to files, and read them when it finishes.

The last stdout line is the marker:
- `CODEX_ASSETS_READY status=<complete|partial> job_dir=... manifest=... preview=...`
- `CODEX_ASSETS_FAILED kind=<invalid_arguments|unavailable|rate_limit|authentication|service|execution|invalid_manifest|missing_or_linked_asset|unsafe_asset_path|format_mismatch> ...`

`READY` means every listed asset exists in the job dir as a regular file matching its declared format; it says nothing about visual quality. `partial` is usable: integrate what arrived and report `missing`. No marker means interrupted.

In `manifest.json`, `sha256`, `bytes`, `width`, `height`, `alpha`, and `detected` are measured from the files by the script (null when python3 is missing or the format is unknown); `intended_use`, `notes`, `version_of`, `task_summary`, `warnings`, and `missing` are model-written. `preview.html` shows each asset on light, dark, and checker backgrounds; give the user its path when transparency matters.

No automatic retries. A second run must be a distinct request (a revise with `--edit-target`, or a changed brief). Never rerun `rate_limit`, `authentication`, `unavailable`, or `service`; for the last three, run the codex-setup doctor if available.

## Review and integrate

1. Read `manifest.json`; view every raster with the image reader, inspect SVG/CSS as source and render when practical.
2. Reject anything off-brief or off-convention; request at most one targeted revision (mode revise, `--edit-target` the staged file).
3. Copy accepted files into the repository's source asset location, never into generated build output. Keep original files; new versions get sibling names.
4. Update consumers, add alt text or reduced-motion behavior, run the project's formatting, tests, and build.

On `CODEX_ASSETS_FAILED`: read `codex-stderr.log` and `final-message.txt` in the job dir. Keep valid partial files only after review. Never fabricate a raster; for deterministic vector or code-native work, continue directly.
