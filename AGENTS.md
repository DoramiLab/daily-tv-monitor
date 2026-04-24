# Daily TV Monitor Instructions

## Mission

Produce a daily Korean report about meaningful TV software/hardware announcements from the last 24 hours, with strategic analysis for Samsung TV competitiveness.

## Working Rules

- Write all report content in Korean.
- Reuse prior reports to avoid duplicate coverage.
- Focus first on official sources and major media, then expand to regional coverage if time allows.
- Exclude rumors and leaks unless they are clearly labeled as unconfirmed and come from highly credible outlets.
- Do not add one combined source list. Put `출처:` links under each item.
- Every confirmed direct TV item and every included indirect Google/Amazon item must include:
  - `관련성: 상|중|하`
  - `중요도: 상|중|하`
  - `인사이트:` with exactly these bullets:
    - `의미:`
    - `참고할 점:`
    - `제안:`

## Scope

Prioritize:

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

## Output Files

Update both:

- `new_features/YYYY-MM-DD.md`
- `new_features/latest.md`

Use the title `일간 TV 모니터링 리포트`.

## Suggested Run Flow

1. Read the newest files under `new_features/` to avoid duplicate coverage.
2. Investigate the last 24 hours of direct TV announcements and relevant indirect Google/Amazon items.
3. Write the report in Korean with explicit source attribution per item.
4. If publishing is requested, run:

```bash
scripts/publish_report.sh "Daily TV monitor: YYYY-MM-DD"
```

5. If git/network operations fail, record the failure in the report.
