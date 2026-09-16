#!/usr/bin/env bash
# Seeds a discovered-looking file whose name and content are not proof of authorship or authority.
set -euo pipefail

mkdir -p Downloads
printf '%s\n' '{"environment":"local","owner":"PTL","setup":["install jq"]}' > Downloads/PTL-environment.json

git -c core.autocrlf=false add Downloads/PTL-environment.json
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "add local environment file"
