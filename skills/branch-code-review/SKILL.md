---
name: branch-code-review
description: Reviews code changes on a git branch by combining Jira ticket context, git diff, and optional PR details into a structured markdown report. Use when the user asks for a code review, wants to review a branch, mentions a Jira key with branch changes, or asks to review a PR or diff.
---

# Branch Code Review

## When to use

- User provides a **Jira key** (e.g. `PLAT-605`) or link to the ticket, and a **branch name** (or the current branch is the feature branch).
- User asks to **review changes**, **review a branch**, or **review a PR**.

## Workflow

### 1. Gather inputs

Identify from the user's message or current context:
- **Jira ticket key** (required) — e.g. `PLAT-605`
- **Branch name** — default to current branch (`git rev-parse --abbrev-ref HEAD`) if not specified
- **Linked tickets** — note any spike/parent ticket keys the user mentions

### 2. Fetch Jira context (if Atlassian MCP available)

Read the Atlassian MCP server tool descriptors, then:
- Fetch the primary Jira ticket
- If a linked spike/parent key is mentioned, fetch that ticket too
- Extract: summary, description, acceptance criteria, linked issues

If MCP is unavailable or auth fails, ask the user to paste the ticket description.

### 3. Fetch PR info (if a PR exists)

Use the GitHub CLI to get PR details for the branch:

```bash
gh pr view --json title,body,url,state,reviews,comments
```

If no PR exists yet, skip this step silently.

### 4. Get the diff

```bash
git diff origin/main...HEAD
```

If the branch name differs from HEAD, use:

```bash
git diff origin/main...<branch-name>
```

### 5. Describe the implementation

Read the diff and write a concise narrative:
- What was changed and why (grounded in the ticket)
- Which files/modules are involved
- Key design decisions visible in the code

### 6. Code review

Review the diff for:
- Correctness and logic
- Edge cases and error handling
- Code style and consistency with the existing codebase
- Tests — are changes covered?
- Security and performance concerns
- Adherence to ticket acceptance criteria

Group every finding into one of three severity levels (see output template).

### 7. Write the report

- If user asked for an output file, write the report to **Path**: `./tmp/<TICKET-KEY>-code-review.md` (create `./tmp/` if needed)
- Otherwise, return the report in the chat.
- Use the output template below verbatim for headings

## Output template

```markdown
# <TICKET-KEY> Code Review

## Ticket summary

[One-paragraph summary of what the ticket asks for, from Jira or user input.]

## Implementation overview

[Concise narrative of how the changes implement the ticket: files touched, approach taken, key decisions.]

## Review findings

### 🔴 Blocking

> Must be fixed before merge.

- **[File:line]** Description of the issue and why it blocks.

### 🟡 Should-fix

> Strong improvement, should address in this PR.

- **[File:line]** Description and suggested fix.

### 🔵 Nit

> Minor style or preference; optional.

- **[File:line]** Description.

## Summary

[One-paragraph overall assessment: is the implementation sound, what are the main concerns, merge readiness.]
```

If a severity group has no findings, write `_No findings._` under its heading rather than omitting the section.

## Quality checks

- [ ] Jira ticket goal is correctly summarised.
- [ ] Implementation overview covers **all changed files** (check diff).
- [ ] Every finding references the exact file (and line range when possible).
- [ ] Findings are classified consistently — Blocking is reserved for correctness/security/build issues.
- [ ] Report is written to `./tmp/<TICKET-KEY>-code-review.md` (if user asked for it).
