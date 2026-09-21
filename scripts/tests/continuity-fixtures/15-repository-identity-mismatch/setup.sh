#!/usr/bin/env bash
set -euo pipefail

mkdir -p src

cat > README.md <<'MD'
# Fixture workspace

This file belongs to the execution workspace, not the separately named IDE repository.
MD

cat > src/example.ts <<'TS'
export const fixtureValue = 'workspace'
TS

git -c core.autocrlf=false add -A
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "seed identity fixture"
