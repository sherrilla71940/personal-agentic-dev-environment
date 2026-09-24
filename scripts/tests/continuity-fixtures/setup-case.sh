#!/usr/bin/env bash
# Stage one continuity fixture in a throwaway repository and print how to run it.
#
# Never stage a case in this repository. 03 replaces state and 04 is built to tempt a
# session into destroying it, and both would do that to the real tree.
#
# A case is a directory holding prompt.txt, expected.md, and optionally:
#
#   state.md   fixture continuity state, copied into .task-continuity/. Absent for a
#              case that tests what happens when no continuity exists.
#   parked/    optional parked continuity records, copied into .task-continuity/parked/.
#   setup.sh   repository setup, run inside the throwaway repo. Replaces the default
#              alignment below, for a case that needs a particular shape.
#
# By default the recorded branch, HEAD and working-tree path are rewritten to match the
# throwaway repository. Without that the Stop hook reports drift on every case, and the
# session is then reacting to a drift notice rather than to the situation under test.
set -euo pipefail

case_dir="${1:-}"
if [[ -z "$case_dir" || ! -f "$case_dir/prompt.txt" ]]; then
  printf 'usage: %s <fixture-case-directory>\n' "$0" >&2
  exit 2
fi
case_dir="$(cd "$case_dir" && pwd)"

target="$(mktemp -d)"
cd "$target"
git init -q
git commit -q --allow-empty -m "init"

# Git Bash reports a POSIX path that PowerShell and cmd cannot cd into, and this is a
# manual procedure driven from a Windows terminal as often as from bash. pwd -W is
# MSYS-only, so a failure here just means there is no second path worth printing.
target_windows="$(pwd -W 2>/dev/null || true)"

if [[ -f "$case_dir/state.md" ]]; then
  mkdir -p .task-continuity
  cp "$case_dir/state.md" .task-continuity/state.md
fi
if [[ -d "$case_dir/parked" ]]; then
  mkdir -p .task-continuity/parked
  cp "$case_dir"/parked/*.md .task-continuity/parked/
fi

# A case seeds its repository with setup.sh when the prompt needs something real to work
# on. Alignment runs afterwards, so a seeded case still gets a matching branch and HEAD.
# A case whose whole subject is a mismatch opts out with a skip-align marker file.
if [[ -f "$case_dir/setup.sh" ]]; then
  bash "$case_dir/setup.sh"
fi

if [[ ! -f "$case_dir/skip-align" ]]; then
  recorded_branch=""
  if [[ -f .task-continuity/state.md ]]; then
    recorded_branch="$(sed -n 's/^- Branch: `\(.*\)`$/\1/p' .task-continuity/state.md)"
  fi
  if [[ -z "$recorded_branch" ]]; then
    for parked_file in .task-continuity/parked/*.md; do
      [[ -f "$parked_file" ]] || continue
      recorded_branch="$(sed -n 's/^- Branch: `\(.*\)`$/\1/p' "$parked_file")"
      [[ -n "$recorded_branch" ]] && break
    done
  fi
  if [[ -n "$recorded_branch" && "$(git branch --show-current)" != "$recorded_branch" ]]; then
    git switch -q -c "$recorded_branch"
  fi
  for continuity_file in .task-continuity/state.md .task-continuity/parked/*.md; do
    [[ -f "$continuity_file" ]] || continue
    sed -i "s|^- HEAD: \`.*\`\$|- HEAD: \`$(git rev-parse --short HEAD)\`|" "$continuity_file"
    sed -i "s|^- Base commit: \`.*\`\$|- Base commit: \`$(git rev-parse HEAD)\`|" "$continuity_file"
    sed -i "s|^- Started from: \`.*\`\$|- Started from: \`$(git rev-parse HEAD)\`|" "$continuity_file"
    sed -i "s|^- Working tree: \`.*\`\$|- Working tree: \`$target\`|" "$continuity_file"
  done
fi

printf '\nStaged %s in %s\n' "$(basename "$case_dir")" "$target"
if [[ -n "$target_windows" && "$target_windows" != "$target" ]]; then
  printf 'From PowerShell or cmd: %s\n' "$target_windows"
fi
if [[ -f .task-continuity/state.md ]]; then
  printf 'Continuity state is in place.\n\n'
elif compgen -G '.task-continuity/parked/*.md' >/dev/null; then
  printf 'Parked continuity state is in place; no active state exists by design for this case.\n\n'
else
  printf 'No continuity state, by design for this case.\n\n'
fi
printf 'Paste this as the first message, verbatim, and nothing else:\n\n'
sed 's/^/    /' "$case_dir/prompt.txt"
printf '\nThen score the response against %s/expected.md.\n' "$case_dir"
printf 'Delete %s afterwards; a leftover fixture is fabricated state.\n' "${target_windows:-$target}"
