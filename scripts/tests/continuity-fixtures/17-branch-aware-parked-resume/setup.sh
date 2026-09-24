#!/usr/bin/env bash
# Seeds a repository whose current named branch and history match the parked continuity record.
set -euo pipefail

mkdir -p src
printf 'WaterFee FE-04 fixture\n' > src/water-fee.txt

git -c core.autocrlf=false add -A
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "seed WaterFee FE-04"
