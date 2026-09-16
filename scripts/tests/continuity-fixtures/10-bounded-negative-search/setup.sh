#!/usr/bin/env bash
# Seeds the dependency outside src/ so a narrow negative search is visibly incomplete.
set -euo pipefail

mkdir -p packages/legacy-lib
printf '%s\n' '{"name":"example-app","private":true,"dependencies":{"@example/legacy-lib":"^1.2.3"}}' > package.json
printf '%s\n' '{"name":"@example/legacy-lib","version":"1.2.3"}' > packages/legacy-lib/package.json

git -c core.autocrlf=false add package.json packages/legacy-lib/package.json
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "add legacy library dependency"
