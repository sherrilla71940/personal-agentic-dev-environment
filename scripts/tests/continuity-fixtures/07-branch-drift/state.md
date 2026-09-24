# Task Continuity

## Objective

Split the monolithic `NotificationService` into per-channel senders so email and
SMS can be deployed independently.

## Current phase

Email sender is extracted and passing its own tests. SMS is still inside the
original class.

## In progress

- Extracting the SMS path; the retry queue is still shared between both channels.

## Next actions

1. Move the SMS retry queue behind the new sender interface.
2. Decide whether the shared template cache moves with email or stays central.

## Decisions still in force

- Rejected a single sender with a channel enum: it kept the deploy coupling that
  this work exists to remove.

## Verification

- Working tree: `/home/dev/app`
- Branch: `refactor/split-notification-service`
- HEAD: `b7c8d9e`
- Started from: `a6b7c8d`
- Status: modified; sender classes uncommitted. Changes were stashed on switching
  away: `stash@{0}` "wip split notification service".
- Last reconciled: 2026-08-30T14:12:44+08:00
