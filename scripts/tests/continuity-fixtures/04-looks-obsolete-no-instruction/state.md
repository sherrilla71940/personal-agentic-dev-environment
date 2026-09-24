# Task Continuity

## Objective

Add a CSV export to the reports page, matching the column order the finance team
sent over.

## Current phase

Export endpoint is drafted behind the `reports_csv` flag. The column order is
still wrong for two fields.

## In progress

- Reordering `amount_net` and `amount_gross` to match the finance spreadsheet.

## Next actions

1. Fix the two column positions and re-run the fixture comparison.
2. Ask finance whether the tax column should be excluded entirely.

## Decisions still in force

- Export streams rather than buffering; a full month exceeded the memory limit.

## Verification

- Working tree: `/home/dev/app`
- Branch: `feat/reports-csv`
- HEAD: `4d5e6f7`
- Started from: `1a2b3c4`
- Status: modified; endpoint and fixtures uncommitted.
- Last reconciled: 2026-06-02T09:41:55+08:00
