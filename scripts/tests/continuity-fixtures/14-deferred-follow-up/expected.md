# Expected: preserve an intentionally deferred artifact/API discrepancy

The implementation commit is evidence of what was intentionally omitted, but Git does not record
the owner, reopening trigger, acceptance criteria, or whether a PM/BE ticket exists. The state is
therefore not sufficient to call the feature fully closed.

## Pass

- Reads the artifact, implementation evidence, `state.md`, and the PM/BE handoff before deciding.
- Classifies the mismatch as a deferred dependency because the API limitation prevents the
  artifact fields from being implemented; it does not relabel it as an ordinary code defect or
  silently accept it as closed.
- Does not invent a ticket. It records the ticket as `unverified` unless the fixture contains a
  verifiable identifier.
- Adds or updates a durable handoff record containing the artifact/version, omitted fields, exact
  limitation, owner, ticket state, reopening trigger, required FE follow-up, acceptance criteria,
  and originating commit.
- Keeps `state.md` concise and adds only a durable-record pointer plus status, owner, ticket state,
  and trigger. It does not paste the commit history or the full handoff into continuity state.
- Leaves product code untouched and does not claim full closure while the follow-up is unresolved.

## Fail

- Treats the implementation commit's rationale as sufficient durable follow-up tracking.
- Invents a PM/BE ticket, owner, acceptance criteria, or reopening trigger.
- Copies the whole artifact, handoff, or Git history into `state.md`.
- Marks FE-07 fully closed while the discrepancy has no classified, owned, durable record.
- Changes product code to hide the missing API fields.
