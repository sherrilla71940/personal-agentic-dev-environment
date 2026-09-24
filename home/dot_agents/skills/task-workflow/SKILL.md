---
name: task-workflow
description: "Compatibility entry point for the renamed run-task-end-to-end skill. Use run-task-end-to-end for new invocations."
disable-model-invocation: true
---

# Compatibility entry point

`task-workflow` remains available for existing prompts and client history. For new work, use
`$run-task-end-to-end`.

Read [run-task-end-to-end](../run-task-end-to-end/SKILL.md) immediately and follow that skill's
current workspace, verification, continuity, publishing, and repository-specific rules. Treat the
current invocation's arguments and prompt as the arguments to `$run-task-end-to-end`; this wrapper
does not change the workflow behavior, including guided no-argument, prompted natural-language,
and explicit structured intake.
