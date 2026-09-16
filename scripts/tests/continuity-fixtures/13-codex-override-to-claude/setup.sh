#!/usr/bin/env bash
# Seeds Codex-only local override instructions without copying them into continuity state.
set -euo pipefail

cat > AGENTS.md <<'EOF'
# Repository instructions

Keep the repository's tracked verification instructions authoritative.
EOF

cat > AGENTS.override.md <<'EOF'
# Codex-local run instructions

These private instructions are available to Codex in this working tree. Run the local verification
command selected by the owner before reporting a result.
EOF

printf '/AGENTS.override.md\n' >> "$(git rev-parse --git-path info/exclude)"

git -c core.autocrlf=false add AGENTS.md
git -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m "add repository instructions"
