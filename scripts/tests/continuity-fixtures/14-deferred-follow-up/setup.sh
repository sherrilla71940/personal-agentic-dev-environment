#!/usr/bin/env bash
# Seeds artifact, implementation, and handoff evidence without including product code.
set -euo pipefail

mkdir -p docs/pm docs/handoff implementation

cat > docs/pm/waterfee-phase1-v1.md <<'EOF'
# WaterFee Phase 1 approved artifact v1

## FE-07

The 接管水號清單 view displays `waterNumber`, `areaName`, `meterStatus`, and `lastReading`.
EOF

cat > implementation/fe-07-9f9bf616a.md <<'EOF'
# FE-07 implementation evidence

Commit: `9f9bf616a`

The current API exposes `waterNumber` and `areaName`, but not `meterStatus` or `lastReading`.
Those fields were intentionally omitted until the API provides them.
EOF

cat > docs/handoffs/waterfee-phase1.md <<'EOF'
# WaterFee Phase 1 PM/BE handoff

FE-07 currently renders the fields available from the API. The artifact fields `meterStatus` and
`lastReading` are not implemented because the current API does not provide them.
EOF

git -c core.autocrlf=false add docs/pm/waterfee-phase1-v1.md implementation/fe-07-9f9bf616a.md docs/handoffs/waterfee-phase1.md
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "record FE-07 implementation evidence"
