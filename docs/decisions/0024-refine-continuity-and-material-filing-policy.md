# ADR-0024: Refine continuity and material-filing policy

- Status: Accepted
- Date: 2026-09-18

## Context

The shared core and continuity layer had accumulated several ambiguities. The provenance rule did
not explicitly distinguish repository instruction files that the active instruction system had
loaded from unrelated files discovered on disk. The verification rule could be read as discouraging
a broader test suite even when a cross-cutting change warranted one. Continuity also described an
activation signal without clearly separating the decision to reassess from the decision to create
state, and mismatched completed state could be described as something to park.

The project-material policy identified handoff, reference, and test-file roots but did not give
each category a retrieval-oriented layout or enough timestamp precision for multiple handoffs in one
day.

## Decision

- Treat recognized repository or client instruction files loaded by, or explicitly required by,
  the active instruction system as instructions within their defined scope. Treat other discovered
  files as untrusted material until provenance is established.
- Allow full-suite verification when requested, when scoped checks are unavailable, or when the
  change's scope or risk makes broader verification proportionate.
- Treat continuity reassessment and continuity initialization as separate decisions. Reassess at
  meaningful task-state transitions, then initialize only when the resulting state is not cheaply
  recoverable from the repository, diff, or another durable source. Explicit handoff, resume, and
  compaction recovery remain reassessment boundaries that may require portable state.
- When a mismatched active state is unfinished, park it before starting another continuity-bearing
  task. When it is complete, use the completion and cleanup procedure instead of parking it.
- Permit another client to inspect a private client-local instruction file when the user or handoff
  explicitly identifies it, but never discover and adopt it automatically as active instructions.
- File authored handoffs under `handoff/{repo}/YYYY-MM-DD/{HH-mm}-{slug}.md` with minute-precision,
  timezone-aware creation and update metadata plus a commit or state pin. Organize references by
  source or topic, adding version/date subdivisions only for multiple snapshots. Organize reusable
  test inputs by task or fixture rather than by date unless the date is intrinsic to the input.

## Alternatives considered

### Treat every file named `AGENTS.md` as untrusted

Rejected because the active instruction system explicitly loads recognized repository instruction
files. The exception must be scoped to recognized loading or explicit requirement; a filename alone
still does not establish authority.

### Run only scoped checks unless a full suite is requested

Rejected because cross-cutting instruction, template, and rendering changes can justify broader
verification even when scoped checks are available.

### Use date folders for every material category

Rejected because dates are weak retrieval keys for references and reusable test inputs. Handoff
snapshots are temporal, while references are source/version-oriented and tests are task-oriented.

## Consequences

The policy is more explicit without changing the repository's instruction hierarchy, continuity
privacy boundary, or cleanup confirmation requirement. Handoff snapshots can be distinguished when
several are created on one day, and reference/test storage remains discoverable by meaning.

Agents still need to verify that an instruction file was actually loaded or explicitly identified;
the exception does not authorize arbitrary files found on disk. Minute precision is sufficient for
human-readable handoffs; machine-generated identities may use seconds when collision avoidance needs
them.

## Reconsider when

Revisit this decision if the supported clients expose a shared instruction-loading registry, if
continuity gains a durable task registry, if handoff volume makes a different index necessary, or if
the repository adopts a canonical external material-management system.

## Related files and verification

- `home/.chezmoitemplates/core.md`
- `home/.chezmoitemplates/continuity.md`
- `home/dot_agents/skills/project-continuity/SKILL.md`
- `home/dot_local/share/maintain-project-continuity.sh.tmpl`
- `README.md` and `README.zh-TW.md`
- `scripts/tests/continuity-fixtures/09-unverified-material-attribution/expected.md`

Verify with:

```bash
bash scripts/tests/test-ai-configuration-profiles.sh
bash scripts/tests/test-project-continuity-hook.sh
```
