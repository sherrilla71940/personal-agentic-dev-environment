#!/usr/bin/env bash
# Seeds Claude-only local instructions without copying them into continuity state.
set -euo pipefail

cat > CLAUDE.local.md <<'EOF'
# Claude-local run instructions

These private instructions are available to Claude Code in this working tree. Run the local
verification command selected by the owner before reporting a result.
EOF

printf '/CLAUDE.local.md\n' >> "$(git rev-parse --git-path info/exclude)"
