# Daily TV SW/HW Monitor

This repository is set up for a local daily Codex run that generates report markdown files and then publishes the updated report files to GitHub.

## Mission

Investigate meaningful TV software and hardware announcements with strategic analysis for Samsung TV competitiveness.

Prioritized scope:

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

Also include indirect but relevant Google/Amazon launches when they could extend to TV, living-room commerce/media, or smart-home control.

## Output

Each run updates:

- `new_features/YYYY-MM-DD.md`
- `new_features/latest.md`

All report content must be in Korean and follow the format rules in `AGENTS.md`.

## Run Policy

- Use the newest report's execution timestamp as the next search window start.
- Do not use a fixed 24-hour window.
- Reuse prior reports to avoid duplicate coverage.
- Let Codex handle report generation only.
- After Codex finishes, the local cron runner commits and pushes `new_features/*.md`.

## Local Cron Entry

The repository includes a cron-friendly runner:

- `scripts/run_daily_report.sh`

It calls Codex non-interactively with web search enabled, updates the report files locally, then commits and pushes `new_features/*.md`. Run logs are written under `logs/cron/`.

Example crontab entry:

```cron
46 15 * * * /Users/luna/dev/daily-tv-monitor/scripts/run_daily_report.sh >> /Users/luna/dev/daily-tv-monitor/logs/cron/cron_runner.log 2>&1
```

## Prompt Source

The non-interactive prompt used by the cron runner lives in:

- `docs/codex_cron_daily_tv_monitor.md`
