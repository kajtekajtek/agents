---
name: task-planner
description: Turns a Jira issue key or free-form task description into a single markdown plan file (task scope, current state, high-level implementation steps, references). Use when the user wants a task plan, implementation outline, ticket breakdown, plan file, or asks to plan work from a Jira ticket or feature description.
---

# Task planner

## When to use

- User provides a **Jira key** (e.g. `PLAT-440`) or describes a feature/bug without a ticket.
- User asks for a **plan**, **scope**, **implementation outline**, or a **markdown file** to understand work before coding.

## Workflow

1. **Clarify input**
   - If only a ticket key is given, treat summary, description, and acceptance criteria from Jira as the source of truth when available.
   - If the user describes the task in chat, use that text
   - **Ask targeted questions** if the goal is ambiguous, details are unclear, design decisions are to be made. **Don't speculate**

2. **Jira (optional)**
   - If a ticket key is provided **and** the Atlassian MCP server is available: read that MCP server’s tool descriptors first, then fetch the issue and use its fields for **Task Description** and **Acceptance Criteria**.
   - If MCP is missing or auth fails, proceed from the user’s pasted ticket text or ask them to paste the ticket body.

3. **Codebase**
   - Read `README.md` or project docs if unfamiliar with the repo.
   - Inspect files and modules that the task likely touches so **Current State** is accurate and concise—not speculative.
   - If the directory is empty or user input involves external repositories **and** Github MCP server is available, use it to search for the codebases 

4. **Write the file**
   - **Path / name**
     - With issue key: `{KEY}.md` (e.g. `PLAT-440.md`).
     - Without ticket: derive a short **kebab-case or Pascal-style feature slug** for the filename (e.g. `ecosio-status-worker-plan.md`); avoid generic names like `plan.md`.
   - **Location**: repository root unless the user specifies another directory.

5. **Depth**
   - **Implementation Plan** stays **high level**: phases, components to touch, what to test, useful patterns—not line-by-line or full code design (that belongs in a follow-up / plan mode).

## Output template

Use this structure verbatim for section headings (adjust title line only):

```markdown
# [ticket number / feature name]

## Task Description

[General task description — narrative or bullets as fits the source.]

### Acceptance Criteria

- [From Jira/user input when present]
- [Otherwise infer from the task description; keep bullets short and testable]

## Current State

- Short overview of the **project** (what it is, main stack if known).
- **Involved parts today**: modules, services, or files relevant to this task and how they behave now (facts from the repo, not guesses).

## Implementation Plan

- High-level steps (ordered or grouped).
- Which **components** change vs **new**; no deep technical spec.
- **Testing**: what to verify (unit, integration, manual).
- **Design / architecture**: patterns or constraints worth following (only if grounded in codebase or ticket).

## References

- Docs for libraries/frameworks/tools that matter.
- If Atlassian MCP works: link or cite relevant **Confluence** pages when found.
- If GitHub MCP works: repos or examples (org/user) that show similar patterns.
```

## Quality checks

- [ ] Filename matches issue key or a clear feature slug.
- [ ] Acceptance criteria are explicit or clearly labeled as inferred.
- [ ] **Current State** reflects the actual repo (paths/names where helpful).
- [ ] **Implementation Plan** is broad, not a full low-level design.
- [ ] **References** lists real links or search leads, not placeholders.
