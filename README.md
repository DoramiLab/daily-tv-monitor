# Daily TV SW/HW Monitor

This workspace is for a recurring agent that runs every day at 07:00 Asia/Seoul.

## Mission

Investigate whether major global TV software and hardware companies announced:

- new TV products
- new display hardware
- new TV platform features
- new OS, UX, AI, gaming, smart-home, ad-tech, or content features tied to TV products

The agent should search broadly across:

- official company newsrooms and blogs
- YouTube channels and launch videos
- major news coverage
- developer blogs
- patents and patent databases
- research papers and preprints
- conference materials
- investor relations pages
- social and official brand channels when relevant

## Suggested company set

Prioritize coverage across the biggest TV-related vendors and platform players, including:

- Samsung
- LG
- Sony
- TCL
- Hisense
- Panasonic
- Philips / TP Vision
- Sharp
- Xiaomi
- Amazon Fire TV
- Google TV / Android TV
- Roku
- Apple TV

Add other globally relevant TV SW/HW companies when they appear material.

## Time window

Each run should focus on the period from the **last report execution timestamp** to the current run time.
When a prior report exists, use that execution timestamp as the next run's start time and use it to avoid duplicate coverage.
Do not use a fixed 24-hour window.

## Output

For each run, create or update:

- `new_features/YYYY-MM-DD.md`
- `new_features/latest.md`

Each report should include:

1. Executive summary
2. New announcements found
3. Source list with links
4. Items checked with no meaningful update
5. Notes on uncertainty or verification gaps

If no new announcement qualifies, keep report format but set `신규 발표 확인 사항` to exactly `해당 없음`.

## Git

Commit and push the daily report changes to the configured GitHub remote when available.
If the repository is not initialized or no authenticated remote is configured, document the blocker in the report instead of failing silently.

## Codex Cloud

This repository is now prepared for Codex cloud tasks.

- Repo-level instructions live in [`AGENTS.md`](/Users/luna/Documents/Codex/2026-04-17-24-top-tv-sw-hw-7/AGENTS.md).
- A ready-to-run cloud task prompt lives in [`docs/codex_cloud_daily_tv_monitor.md`](/Users/luna/Documents/Codex/2026-04-17-24-top-tv-sw-hw-7/docs/codex_cloud_daily_tv_monitor.md).
- The publish helper remains [`scripts/publish_report.sh`](/Users/luna/Documents/Codex/2026-04-17-24-top-tv-sw-hw-7/scripts/publish_report.sh).

If you run this repo from Codex on the web with a GitHub-connected environment, Codex should pick up `AGENTS.md` automatically and can use the prompt file as the task brief.
