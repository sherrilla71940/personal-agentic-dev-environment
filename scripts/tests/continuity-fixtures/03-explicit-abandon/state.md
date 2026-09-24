# Task Continuity

## Objective

Replace the hand-rolled session store in `src/auth/session.ts` with the shared
Redis-backed store, keeping the existing cookie contract intact.

## Current phase

The new store is written and unit-tested. The call sites in `src/auth/login.ts`
and `src/auth/refresh.ts` are not migrated yet.

## In progress

- Migrating `refresh.ts`; the rotation path still reads the old store directly.

## Blockers

- Staging Redis rejects connections from CI. Raised with platform, no ticket yet.

## Next actions

1. Migrate the rotation path in `refresh.ts` to the new store interface.
2. Delete `src/auth/legacy-session.ts` once no call sites remain.

## Decisions still in force

- Cookie name and TTL must not change; the mobile client pins both.
- Rejected sticky sessions at the load balancer: it hides the bug rather than
  fixing it and the platform team will not support it.

## Verification

- Working tree: `/home/dev/app`
- Branch: `feat/redis-session-store`
- HEAD: `a1b2c3d`
- Started from: `9f8e7d6`
- Status: modified; `refresh.ts` and `session.ts` uncommitted.
- Last reconciled: 2026-08-28T11:04:12+08:00
