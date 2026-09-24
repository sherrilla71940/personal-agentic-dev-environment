# Task Continuity

## Objective

Move the invoice PDF renderer off the deprecated `pdfkit` fork and onto the
maintained upstream release.

## Current phase

Renderer is migrated, committed, and verified against the golden-file suite.

## Decisions still in force

- Kept the custom font loader: upstream's loader cannot read the bundled
  subsetted fonts, and replacing those is a separate piece of work.

## Verification

- Working tree: `/home/dev/app`
- Branch: `chore/pdfkit-upstream`
- HEAD: `7c8d9e0`
- Started from: `5b6c7d8`
- Status: clean; golden-file suite passes.
- Cleanup: `declined`
- Last reconciled: 2026-09-01T16:22:07+08:00
