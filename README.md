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
- After Codex finishes, the local launchd runner commits and pushes `new_features/*.md`.

## Local LaunchAgent

The repository includes a launchd-friendly runner:

- `scripts/run_daily_report.sh`

It calls Codex non-interactively with web search enabled, updates the report files locally, then commits and pushes `new_features/*.md`. Run logs are written under `logs/cron/`, with launchd stdout/stderr under `logs/launchd/`.

Installed LaunchAgent:

```bash
~/Library/LaunchAgents/com.doramilab.daily-tv-monitor.plist
```

It is scheduled with `StartCalendarInterval` for 07:00 local time. To improve reliability while the Mac is asleep, configure a daily wake event shortly before the job:

```bash
sudo pmset repeat wakeorpoweron MTWRFSU 06:59:00
```

LaunchAgents and scheduled wake events do not guarantee execution while a MacBook is fully asleep with the lid closed; behavior depends on power, Power Nap, and clamshell conditions.

## Prompt Source

The non-interactive prompt used by the cron runner lives in:

- `docs/codex_cron_daily_tv_monitor.md`
