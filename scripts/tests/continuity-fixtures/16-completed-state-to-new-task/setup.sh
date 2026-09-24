#!/usr/bin/env bash
# Seeds a small repository whose completed Task A state is true of the checkout. The prompt then
# asks for a fresh continuity state for Task B while preserving Task A in parked history.
set -euo pipefail

mkdir -p src
printf 'Task A output\n' > src/task-a.txt

git -c core.autocrlf=false add -A
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "complete task A"
