---
name: handoff-writing
description: "Write a human-facing handoff, gap list, or blocker document for a PM, tech lead, another team, ticket, or chat. Use when the document lists work blocked on someone else or items owed by BE/PM. Do not use for ordinary PR descriptions, READMEs, or agent continuity state."
user-invocable: true
---

# Handoff writing

Write a concise, actionable document for a human stakeholder who must route or resolve gaps that
affect the writer's own delivery. This skill is for handoffs, gap lists, and "blocked on someone
else" notes. It is not a general code-review skill and does not replace `technical-writing` for
ordinary PR descriptions or READMEs.

## Choose the output

Use Markdown by default. It is portable, reviewable, and the canonical copy for a handoff.

- Create an Artifact only when the user explicitly requests one or the active client documents
  support for it and the user wants that presentation.
- Keep the reviewed Markdown as the source of truth. If an Artifact is created, derive it from
  the final Markdown, verify that the user can open it, and treat its URL as supplemental.
- Codex follows the same policy but must not claim Artifact support merely because another client
  has it. Never make an inaccessible Artifact the only copy.
- Post or deliver the final document verbatim. If the canonical destination is a ticket or chat,
  delete the local draft only after delivery succeeds. Otherwise keep a timestamped local copy.

If no canonical destination is specified, use the repository's handoff convention: a Markdown file
under `~/Documents/handoffs/{repo}/YYYY-MM-DD/{HH-mm}-{slug}.md` with timezone-aware `Created` and
`Last updated` metadata and a commit or continuity-state pin when one exists. Do not use the
worktree directory name as `{repo}`.

## Scope each item to the writer's delivery

Start by identifying the recipient and the executor. A PM may receive the note while a developer
acts on it. Say that distinction in the introduction so technical locators are intentional.

Include an item only when it blocks delivery or makes something users see in the writer's own work
wrong. Do not turn a handoff into an unsolicited review of another team's code. Inspect enough code,
data, history, or API behavior to substantiate the writer-facing symptom and its apparent cause,
but omit unrelated defects and design opinions.

Before listing an item, test whether the writer can solve it. Record the attempted workaround or
check. If a workaround exists but would be incorrect, say why it was rejected rather than calling
the item impossible. State the outcome needed, not an implementation prescription for the other
owner.

Do not assign priority, severity, effort, schedule, or ticketing process. The recipient decides
those. Identify an owner only when the user, repository, or evidence establishes one; never guess.

## Use one structure for every item

Put locators first, then use this order:

1. **Current state** — what the writer's feature or deliverable shows or cannot do.
2. **Cause** — the verified dependency or observed boundary, with the confidence level stated.
3. **Requested action** — the outcome another person must provide.
4. **Our status** — what the writer tried, what is complete, and what remains blocked.
5. **Owner** — the evidenced team or person, or `Unassigned` when unknown.
6. **Additional context** — investigation details that help the executor without delaying the action.

For a Traditional Chinese document, use the natural Taiwan Chinese equivalents:
`現況 → 原因 → 需要 X 處理 → 我方狀態 → Owner → 補充`. Load `natural-zhtw` for the
deliverable; keep chat replies in the requested chat language. Do not add a priority or severity
column.

Give the executor enough locators to act without rediscovering the issue. Include the fields that
apply:

- screen or feature name and page URL;
- API endpoint and HTTP verb;
- source file and line or symbol;
- database table or column when schema work is involved;
- originating ticket and checklist item; and
- owner or owning component, when evidenced.

## Keep the document alive without duplicating it

Treat the handoff as one living file while the task is in progress. Update that file as facts are
verified. Do not copy its full contents into `.task-continuity/state.md`; continuity should hold
the path, recipient, purpose, and format constraints so the next client can reopen the same file.

Add an appendix such as **Investigated and closed — no action** for concerns that were checked and
ruled out. This prevents the recipient or the next agent from repeating the investigation.

When the document is ready, re-read the exact file that will be delivered. Post that copy verbatim,
then verify delivery before removing the local copy when the destination is canonical. Never claim
that a handoff was sent, posted, or deleted unless that action actually happened.

## Short worked example

```markdown
### FE-03 export total does not match the requested whole-set count

- Locator: `收费明细查詢` / `/fees/detail`; `GET /api/fees/detail`; `FeeDetail.ts:118`;
  ticket FE-03 checklist item 2.
- Current state: The screen can display only the current page, so the export total differs from
  the design when more than 500 records exist.
- Cause: The API returns page rows but no whole-set total, and `MaxPageSize = 500` rules out a
  correct client-only workaround.
- Requested action: Provide the whole-set total in the API response.
- Our status: The client-side formatter and paging behavior were tested; the missing contract is
  the remaining blocker.
- Owner: BE, based on the endpoint ownership.
- Additional context: The export and screen must use the same total definition.
```

The example reports the symptom visible through the writer's feature, the evidence that rules out
solving it locally, and the required outcome. It does not rank the work or prescribe the backend's
implementation.
