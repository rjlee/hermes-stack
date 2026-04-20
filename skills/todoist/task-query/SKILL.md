---
name: task-query
title: Task Query Wrapper
description: >-
  Ensures that any user request about tasks, to‑do items, or daily agenda is answered using the existing `todoist-cli` skill. It abstracts the common queries (list all tasks, tasks due today, high‑priority items) and delegates to `todoist-cli`.
version: 1.0
---

## Purpose
When the user asks for their tasks (e.g., "What do I have to do today?" or "Show me my pending tasks"), this skill defines the procedure to answer using the `todoist-cli` skill rather than ad‑hoc handling.

## Procedure
1. **Interpret the request** – Determine which operation the user wants:
   - *Query*: list tasks, filter by due date, priority, project, label, etc.
   - *Create*: add a new task with content, optional project, label, due date, priority.
   - *Complete*: mark an existing task as completed.
   - *Update*: modify task content, due date, priority, or labels.
2. **Invoke the appropriate `todoist-cli` command** based on the operation:
   - **Query**
     - `todoist-cli list --filter "status:todo"` – all pending tasks.
     - `todoist-cli list --filter "due:today"` – tasks due today.
     - `todoist-cli list --filter "priority:4"` – high‑priority tasks.
     - Append any project/label filters the user mentions.
   - **Create**
     - `todoist-cli add "<content>"` – basic task.
     - Options: `--project <project>` `--label <label>` `--due <date>` `--priority <1|2|3|4>`.
   - **Complete**
     - `todoist-cli complete <task_id>` – marks the task as done.
   - **Update**
     - `todoist-cli update <task_id> --content "<new content>"` – change description.
     - Additional flags: `--due <new date>`, `--priority <level>`, `--label <add|remove>`.
3. **Capture the output** and format it for the user:
   - For queries: show a numbered list with task ID, content, due date, priority.
   - For mutations: confirm success with a concise message (e.g., "Task created with ID 12345" or "Task 12345 marked complete").
4. **Return the formatted response** as the final answer.

## Edge Cases
- If any `todoist-cli` command returns an error (e.g., invalid task ID, missing fields), reply with a clear error explanation and suggest corrective action.
- When creating a task, if the user omits optional details, use sensible defaults (no project/label, no due date, priority 1).
- When updating, only change fields the user explicitly mentioned.

## Verification
After each `todoist-cli` invocation, verify that the command succeeded (exit code 0) and that the output reflects the expected change. For queries, ensure the list is not empty before presenting; if empty, inform the user accordingly.

## Example Usage

**User:** "Add a new task to buy groceries tomorrow with priority 2."
**Skill Action:** Run `todoist-cli add "buy groceries" --due tomorrow --priority 2` and confirm creation.

**User:** "Mark task 12345 as done."
**Skill Action:** Run `todoist-cli complete 12345` and confirm completion.

**User:** "What do I have to do today?"
**Skill Action:** Run `todoist-cli list --filter "due:today"` and present the result.

**User:** "Show me my pending tasks."
**Skill Action:** Run `todoist-cli list --filter "status:todo"`.

---

**Note:** This skill does not modify any tasks; it only reads and presents them.
