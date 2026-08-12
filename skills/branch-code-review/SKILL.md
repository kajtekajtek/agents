---
name: branch-code-review
description: Reviews code changes on a git branch by combining Jira ticket context, git diff, and optional PR details, reporting findings via ReportFindings. Use when the user asks for a code review, wants to review a branch, mentions a Jira key with branch changes, or asks to review a PR or diff. Supports --fix (apply findings to the working tree) and --comment (post findings as inline PR comments).
---

# Branch Code Review

## When to use

- User provides a **Jira key** (e.g. `PLAT-605`) or link to the ticket, and a **branch name** (or the current branch is the feature branch).
- User asks to **review changes**, **review a branch**, or **review a PR**.

## Flags

Parse these from the user's invocation (e.g. `PLAT-605 --fix --comment`):

- `--fix` — after reporting findings, apply Blocking and Should-fix findings directly to the working tree (step 8). Nits are left alone unless the user says otherwise.
- `--comment` — post each finding as an inline PR review comment (step 9). Requires an open PR for the branch.

Both flags can be combined. Neither is required — with no flags, the skill just reports findings.

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

Classify every finding into one of three severity levels: Blocking (correctness/security/build issues that must be fixed before merge), Should-fix (strong improvement, address in this PR), Nit (minor, optional).

### 7. Report findings

Call `ReportFindings` once, findings ordered most-severe first (Blocking → Should-fix → Nit). Map each finding to the tool's schema:

- `file`, `line` — exact location
- `summary` — starts with the severity tier as a label, e.g. `"Blocking: <one-sentence defect>"`, `"Should-fix: ..."`, `"Nit: ..."` — this is the only place severity lives, so keep the label literal and parse it back out in steps 8–9
- `failure_scenario` — concrete input/state that triggers it, or (for style/test-coverage findings with no runtime failure) the concrete downside
- `short_summary` — compressed claim, ≤60 chars, no severity prefix here
- `category` — defect type, e.g. `correctness`, `security`, `performance`, `style`, `test-coverage`

Pass `findings: []` if the diff is clean — don't skip the call.

Then, in chat (or in the optional markdown file), give the narrative context the tool call doesn't carry:
- Ticket summary (one paragraph, from Jira or user input)
- Implementation overview (files/modules touched, key decisions, grounded in the ticket)
- One-paragraph overall merge-readiness assessment

If the user asked for an output file, write those three narrative sections to `./tmp/<TICKET-KEY>-code-review.md` (create `./tmp/` if needed) — the findings themselves live in the `ReportFindings` call, not the file.

### 8. Apply fixes (`--fix` only)

For each finding whose `summary` starts with `Blocking:` or `Should-fix:`, use Edit to apply the fix directly to the working tree. Skip `Nit:` findings unless the user asked for them too. Re-call `ReportFindings` with the same findings, each annotated with `outcome`: `fixed`, `skipped`, or `no_change_needed`.

### 9. Post inline PR comments (`--comment` only)

Requires an open PR (see step 3). Get the PR number and head commit:

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
COMMIT_SHA=$(git rev-parse HEAD)
```

For each finding that has a `line`, post an inline review comment:

```bash
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments \
  -f body="**<summary>**

<failure_scenario>" \
  -f commit_id="$COMMIT_SHA" \
  -f path="<file>" \
  -F line=<line>
```

Findings without a `line`, or where the API rejects the line as not part of the diff, fall back to a single consolidated comment via `gh pr comment`.

## Quality checks

- [ ] Jira ticket goal is correctly summarised.
- [ ] Implementation overview covers **all changed files** (check diff).
- [ ] `ReportFindings` was called even when there are zero findings.
- [ ] Every finding has an exact file (and line, when possible) and a concrete `failure_scenario`.
- [ ] Every `summary` leads with its severity label (`Blocking:` / `Should-fix:` / `Nit:`) — Blocking is reserved for correctness/security/build issues; `category` separately records the defect type.
- [ ] `--fix` only touches Blocking/Should-fix findings, and outcomes are re-reported.
- [ ] `--comment` only runs when a PR exists; falls back gracefully for findings with no line.
- [ ] Narrative sections are written to `./tmp/<TICKET-KEY>-code-review.md` (if user asked for it).
