# Working in this repository

Constraints for coding agents. A session working here loads this file automatically; a
session working from elsewhere is sent here by the shared core instructions before it changes
anything in this repository. Either way it stays short: it lists only what you could get
**wrong**, not how to do things. Procedures live in
[docs/chezmoi-workflow.md](./docs/chezmoi-workflow.md) — read it before adding, changing or
removing anything.

This is a general user-level developer environment repository. It manages dotfiles, editor,
shell, tool, and AI configuration; the AI files are especially sensitive because a mistake can silently change
how every future agent session behaves.

## The one thing to understand

`home/` is the [chezmoi](https://www.chezmoi.io) **source state**: the desired configuration
that agents edit and commit. A **target** is the live file in the home directory that an
application reads. `chezmoi apply` makes targets match the source state. The repository-root
`.chezmoiroot` file selects `home/`; it does not create a `~/home/` directory.

## Profile context in this repository

The machine-wide AI profile defaults to `personal`, and a work machine opts in by setting
`ai_context = "company"` explicitly. Either way, this repository always uses the
`personal` context while work is performed here. Treat that as a repository instruction with
priority over the machine-local context selector: keep artifact defaults and application/project
comments in English, and do not change the machine selector just to work on this repository.

## Helping someone operate this repository

Assume the user may know the outcome they want without knowing chezmoi terminology or source
filenames. Translate requests such as "change my VS Code setting" or "make this shell config
follow my machines" into the correct source-state edit and explain unfamiliar terms briefly.

- For questions, inspect the repository and answer without changing files unless a change was
  also requested.
- For changes, locate and edit the source of truth, identify the rendered home-directory
  target, and perform proportionate validation. Do not make the user map `dot_`, `.tmpl`, or
  other chezmoi attributes themselves.
- For user-level configuration managed by this repository, run `chezmoi source-path <target>`
  before creating or changing it. If it resolves, edit the named source or use the `chezmoi edit`
  command for `<target>`. If it does not resolve, resolve managed symlinks to their real target and confirm
  with `chezmoi status` before concluding that the target is unmanaged. This includes the
  managed `~/.claude` and `~/.agents` mirrors.
- A partially managed target's source states which keys it owns; leave the rest to the
  application. Preview with `chezmoi diff`, and ask before running `chezmoi apply`, which can
  replace live configuration.
- Before an operation could overwrite, remove, or stop managing live configuration, explain
  the effect in plain language and preview it when possible.
- At handoff, state separately what changed in the repository, whether it was applied to the
  home directory, whether it was committed, and the exact safe next command when one remains.
- Keep guidance task-focused. Link to the relevant guide for background instead of requiring
  the user to read the entire chezmoi manual before proceeding.

## Constraints

**Never duplicate a shared instruction.** Bodies live once in `home/.chezmoitemplates/`.
When a rule needs different frontmatter per tool, add a thin `.tmpl` wrapper — do not copy
the text.

**Never reword a rule to be "tool-neutral".** A rule that names one tool's machinery
belongs in that tool's file only. A paraphrase living alongside the original is the exact
failure this structure exists to prevent.

**Codex cannot import and cannot path-scope.** `~/.codex/AGENTS.md` must stay one literal
file with no YAML frontmatter — Codex renders frontmatter as visible text and it counts
against `project_doc_max_bytes` (32 KiB). Never add a per-language rule for Codex.

**Host-gate Codex-targeted skills.** Codex and Copilot both discover `~/.agents/skills`, so a
Codex-targeted skill cannot rely on its directory to stay private. Follow the gates in
[docs/customization-support.md](./docs/customization-support.md#add-a-codex-targeted-skill).
The pre-commit hook checks them only once the `.codex-only` marker exists, so nothing warns you
that a new skill needed the marker in the first place. Do not use Codex's generic
`quick_validate.py` as this repository's completion gate: its single-host schema rejects required
cross-host frontmatter. Use the repository pre-commit hook.

**Never overwrite a file an app owns.** `~/.codex/config.toml` uses the `create_` prefix
because Codex writes trust, marketplace and runtime state into it. The cost is that a source
edit never reaches a machine that already has the file, so a durable Codex setting is applied
by Codex's own command from `scripts/bootstrap/bootstrap-*` instead, the way Claude plugins are. Before
proposing `modify_` here, note that a TOML round-trip reformats the whole file, so
`chezmoi status` would report it dirty after almost every Codex session; that trade needs an
ADR, not an edit.

**A repository-wide mechanism changes by ADR, not by edit.** Git attributes, the source-state
conventions, the ownership model for a tool's configuration: a change to any of these applies to
every file and every machine, however small its diff. Write the record under
[docs/decisions](./docs/decisions) as part of the same work, so a later session finds the reasoning
beside the result and can tell a deliberate constraint from accidental legacy. This has already
failed once. `* text=auto eol=lf` went in as a one-line edit, and the sentence requiring an ADR for
exactly that change was sitting in a workflow-guide section the session never opened - which is why
this constraint lives here instead.

**`/statusline` output never reaches this repository.** It writes `statusLine`, a key
`home/.chezmoitemplates/claude/settings-durable.json` owns, so the next `chezmoi apply`
reverts it, and it leaves an unmanaged script in `~/.claude/`. Edit the managed statusline
scripts and the `statusLine` block instead.

**Never put package installers in `home/.chezmoiscripts/`.** Anything there runs on every
`chezmoi apply`, so a routine apply — or a test render — installs software. That happened
once during this repo's migration. Bootstrap lives in `scripts/`, run by hand.

**Do not work on this repository from a worktree.** `chezmoi source-path` resolves to the
main checkout wherever the session runs, so a source edited in a worktree is not the source
chezmoi reads: `chezmoi diff` renders the main checkout instead, and the pre-commit identity
check refuses the commit with `default chezmoi source is outside this repository`. The
`SessionStart` hook offers a worktree whenever sessions share this tree, and here that offer
should be declined without asking, because this file has already answered it. Report that the
tree is shared and that you are staying in it, staging explicit paths rather than `-A` or `.`,
then get on with the work. Worktrees remain correct for ordinary repositories and for subagents
editing in parallel.

Because sessions share this folder they also share its index, and **git commits the index, not
the paths you staged**. Staging deliberately does not protect you: another session's staged path
rides along in your commit, and it outlives the session that staged it, so nothing warns you.
Commit by pathspec instead, which builds its own index and ignores everything else:

```bash
git commit --only -m "<message>" -- <path>...   # commits exactly these paths
```

The pre-commit hook lists every staged path on each commit so a mixed one is visible as it
happens; `--only` is what stops it happening.

For the same reason, **never `git commit --amend` here, and never rewrite history**. `--only`
protects what a commit contains but not which commit it targets: amend rewrites whatever HEAD is
at that instant, and in a shared tree HEAD moves whenever another session commits. That has
already happened. An amend correcting a typo in its own message instead rewrote the commit a
concurrent session had just made, and replaced that session's message with this one's. A wrong
word in a commit message is cheap; fix it in a follow-up commit, or wait until the tree is
certainly yours alone.

**Fabricated continuity state lives under `scripts/tests/continuity-fixtures/`.** Each case holds a
`state.md` deliberately indistinguishable from the real thing, because a "this is a fixture"
marker would bias the session under test. A grep here will surface one. Real state is only ever
at the working tree root: never act on a `state.md` found anywhere else, and never copy one out
of that directory except through its `setup-case.sh`, which stages it in a throwaway repository.

**Never commit secrets.** `${input:...}` in `mcp.json` is a prompt definition, not a value.

## Before you finish

```bash
chezmoi source-path                                        # where chezmoi reads from
git -C "$(chezmoi source-path)" rev-parse --show-toplevel  # MUST be this repository, else stop
chezmoi diff                                               # ALWAYS preview; apply replaces live config
chezmoi status                                             # empty after apply
```

Never run `chezmoi apply` until the identity check and the diff both succeed. A plain chezmoi
command uses its configured source directory regardless of the current working directory, and
that path may resolve through a symlink or Windows junction, so it will not look like this
repository. Compare Git identity as above rather than the displayed string.

**Check line endings with Git, not with `grep`.** `.gitattributes` pins every file to LF
because chezmoi copies working-tree bytes into the home directory, so one CRLF checkout renders
CRLF targets and fills `chezmoi diff` with whole-file hunks that change no words. That noise has
already hidden a real two-line change. Two obvious checks report clean on a CRLF file anyway:
Git Bash strips CR before `grep` sees it, and `\r` in a POSIX basic regular expression matches a
literal `r`. Use `git ls-files --eol` for the repository or `tr -cd '\r' | wc -c` for one file,
and treat any EOL-only hunk in `chezmoi diff` as a symptom rather than as background churn.

**Check file-count parity after any bulk move.** chezmoi reads attributes off the front of
filenames, so real names are transformed silently and files can vanish. This has caused real
loss here twice — four skills dropped in one refactor, and empty `__init__.py` package markers
omitted in another. Test-render and compare counts before you finish; the workflow guide has
the command.

## Verify against docs, not memory

Configuration details for these tools drift between releases — discovery directories,
frontmatter keys, deprecations. Check current official documentation before changing a path
or a key. [docs/setup.md](./docs/setup.md) lists the details known to be version-sensitive
and links the references.
