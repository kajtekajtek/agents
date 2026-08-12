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

- `--fix` — apply Blocking/Should-fix findings to the working tree (step 7). Nits are left alone unless asked.
- `--comment` — post each finding as an inline PR review comment (step 8). Requires an open PR.

Both can be combined. With neither, the skill just reports findings.

## Workflow

### 1. Gather inputs

- **Jira ticket key** (required) — e.g. `PLAT-605`
- **Branch name** — default to current branch (`git rev-parse --abbrev-ref HEAD`)
- **Linked tickets** — note any spike/parent keys the user mentions

### 2. Fetch Jira context

Fetch the primary ticket (and linked spike/parent, if mentioned) via Atlassian MCP. If the tool takes a fields filter, request only `summary`, `description`, `acceptance criteria`, and `linked issues` — skip changelog/attachments/watchers payloads you won't use. If MCP is unavailable, ask the user to paste the ticket description.

### 3. Fetch PR info (if a PR exists)

```bash
gh pr view --json number,title,url
```

Only pull `reviews,comments` as well if `--comment` is set (needed to avoid posting duplicate comments in step 8). If no PR exists, skip silently.

### 4. Delegate the diff review to a subagent

The diff itself is the biggest token cost in this skill and has no reason to live in your main context for the rest of the conversation. Dispatch it instead of reading it directly:

Spawn `Agent` (subagent_type `general-purpose`, foreground — you need its result before continuing) with a prompt that includes:
- The ticket summary, description, and acceptance criteria from step 2
- The branch/commit range to diff: `origin/main...HEAD` (or `origin/main...<branch-name>` if reviewing a branch other than the current one)
- Instructions to: run `git diff --stat` first to gauge size, then the full diff excluding generated/lockfiles (e.g. `git diff origin/main...HEAD -- . ':!*.lock' ':!package-lock.json' ':!*.min.js' ':!pnpm-lock.yaml' ':!yarn.lock'`)
- The review checklist: correctness/logic, edge cases and error handling, style/consistency, test coverage, security/performance, adherence to the acceptance criteria
- The severity model: Blocking (correctness/security/build issues that must be fixed before merge), Should-fix (strong improvement, address in this PR), Nit (minor, optional)
- The exact return shape needed (see below) — ask it to return this as its final answer, nothing else

Required return shape (plain text/JSON in the subagent's final message):
```
{
  "implementation_overview": "<files/modules touched, key decisions, grounded in the ticket>",
  "findings": [
    {
      "file": "...", "line": 42,
      "summary": "Blocking: ...",
      "failure_scenario": "...",
      "short_summary": "...",
      "category": "correctness"
    }
  ]
}
```

### 5. Report findings

Take the subagent's `findings` array and call `ReportFindings` once, ordered most-severe first (Blocking → Should-fix → Nit):

- `file`, `line` — exact location
- `summary` — leads with the severity label, e.g. `"Blocking: <defect>"` — this is the only place severity lives; steps 7–8 parse it back out
- `failure_scenario` — concrete triggering input/state, or the concrete downside for style/test-coverage findings
- `short_summary` — compressed claim, ≤60 chars, no severity prefix
- `category` — defect type (`correctness`, `security`, `performance`, `style`, `test-coverage`, ...)

Pass `findings: []` if the subagent found nothing — don't skip the call.

### 6. Narrative output

In chat (or the optional file), give what the tool call doesn't carry:
- Ticket summary (one paragraph)
- Implementation overview (from the subagent's `implementation_overview`)
- One-paragraph overall merge-readiness assessment

If the user asked for a file, write those three sections to `./tmp/<TICKET-KEY>-code-review.md` (create `./tmp/` if needed) — findings stay in the `ReportFindings` call, not the file.

### 7. Apply fixes (`--fix` only)

For each finding whose `summary` starts with `Blocking:` or `Should-fix:`, Read the target file and use Edit to apply the fix. Skip `Nit:` findings unless asked. Re-call `ReportFindings` with the same findings, each annotated with `outcome`: `fixed`, `skipped`, or `no_change_needed`.

### 8. Post inline PR comments (`--comment` only)

Requires an open PR (step 3).

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
COMMIT_SHA=$(git rev-parse HEAD)
```

For each finding with a `line`:

```bash
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments \
  -f body="**<summary>**

<failure_scenario>" \
  -f commit_id="$COMMIT_SHA" \
  -f path="<file>" \
  -F line=<line>
```

Skip findings that match an existing comment/review already fetched in step 3. Findings without a `line`, or rejected because the line isn't part of the diff, fall back to one consolidated `gh pr comment`.

## Quality checks

- [ ] Diff review was delegated to a subagent — raw diff isn't sitting in the main conversation.
- [ ] `ReportFindings` was called even with zero findings.
- [ ] Every finding has an exact file (and line, when possible) and a concrete `failure_scenario`.
- [ ] Every `summary` leads with its severity label; `category` separately records defect type.
- [ ] `--fix` only touches Blocking/Should-fix findings, and outcomes are re-reported.
- [ ] `--comment` only runs when a PR exists, skips duplicates, and falls back gracefully for findings with no line.
