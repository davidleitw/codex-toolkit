---
name: codex-assets
description: Produce visual assets through the local Codex CLI - illustrations, backgrounds, textures, mockups, icons, favicons, social images, sprite frames, and edits or variants of existing images. Modes generate, edit, set (several assets sharing one spec), revise (new version of an earlier output). Raster output uses Codex's built-in image generation; scalable icons and marks are produced as SVG or code-native assets. Output is staged outside the repository for the caller to review and integrate. Not for reviewing screenshots (see codex-visual-review).
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
  - Write
---

# codex-assets

Script: `scripts/run-codex-assets.sh` inside this skill's directory. Brief goes on stdin. Codex works in a staging directory (default `${TMPDIR:-/tmp}/codex-toolkit/assets/job-*`), never in the repository.

## Prepare

1. Read the repository first: design tokens, existing assets, sizes, naming, formats, framework conventions.
2. Settle intended use, exact dimensions or ratio, theme variants, transparency, exact text, alt/accessibility needs. Ask the user only when a missing choice changes the result materially.
3. Route: raster (illustration, background, texture, mockup, variant, sprite frame) → built-in image generation; scalable icon or production mark → SVG / code-native; UI motion → CSS / SVG / Lottie / framework code, image generation only for source frames.
4. Write the brief: mode, visual goal, placement, project conventions, exact deliverables (file names, sizes, formats, transparency), constraints, avoid-list, role of each attached image.

The mode is stated in the brief text; the script has no mode argument. The deliverable is always staged files. Anything that changes files inside the repository (wiring an SVG into a component, editing a repo asset in place) is the caller's job or the codex skill in implement mode, even when the file is an image.

| Mode | Flags | Brief says |
|---|---|---|
| generate | `--reference` optional | new asset(s) from description |
| edit | `--edit-target <img>` | what to change, what must stay identical |
| set | none or `--reference` | list of items plus the shared visual spec |
| revise | `--edit-target <previous output>` | the one change requested; original stays untouched, result is a new version |

## Model and speed

Defaults `gpt-5.6-sol` / `high` (asset work involves design judgment). Pass `--model gpt-5.6-luna --effort max` only for a settled, mechanical job such as re-exporting a fixed spec. Never `gpt-5.6-terra` (the script rejects it). `gpt-6-astra` and `--fast` only on explicit user request, each separately; the script pins the standard tier without `--fast`. Fast reminder policy as in the codex skill: one non-blocking mention after the first delegated run, never repeated.

## Run

```bash
<skill-dir>/scripts/run-codex-assets.sh --repo "<repo-root>" \
  [--reference "<style-or-composition-image>"]... [--edit-target "<image-to-edit>"]... \
  [--model gpt-5.6-sol --effort high] [--fast] <<'BRIEF'
<self-contained asset brief>
BRIEF
```

The script is synchronous and image generation is slow: launch it with the harness's own background mechanism (not a shell `&`), capture stdout and stderr to files, read them when done.

The last stdout line is the marker (both kinds go to stdout):
- `CODEX_ASSETS_READY status=<complete|partial> job_dir=... manifest=... preview=...`
- `CODEX_ASSETS_FAILED kind=<invalid_arguments|unavailable|rate_limit|authentication|service|execution|invalid_manifest|missing_or_linked_asset|unsafe_asset_path|format_mismatch> ...`

`READY` means the CLI returned and every listed asset exists inside the job dir, is a regular file, and matches its declared format; it says nothing about visual quality. No marker means interrupted or unknown.

The script rewrites every asset entry in `manifest.json` with values read from the file itself: `sha256`, `bytes`, `width`, `height`, `alpha`, `detected` (PNG incl. tRNS, JPEG, GIF, WebP, SVG headers; null when python3 is missing or the format is unknown). Model-written text stays in `intended_use`, `notes`, `version_of`, `task_summary`, `warnings`, `missing`. `preview.html` shows every asset over light, dark, and checker backgrounds.

No automatic retries. One later run only as a distinct request (a revise with `--edit-target`, or changed brief). Never rerun `rate_limit`, `authentication`, `unavailable`, `service`; point the user to codex-setup for the last three. A `partial` result is usable: integrate the delivered items, report `missing`.

## Review and integrate

1. Read `manifest.json`; view every raster with the image reader, inspect SVG/CSS as source and render when practical.
2. Reject anything off-brief or off-convention; request at most one targeted revision (mode revise, `--edit-target` the staged file).
3. Copy accepted files into the repository's source asset location, never into generated build output. Keep original files; new versions get sibling names.
4. Update consumers, add alt text or reduced-motion behavior, run the project's formatting, tests, and build.

On `CODEX_ASSETS_FAILED`: read `codex-stderr.log` and `final-message.txt` in the job dir. Keep valid partial files only after review. Never fabricate a raster; for deterministic vector or code-native work, continue directly.
