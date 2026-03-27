---
name: research
description: Produces source-backed research notes, comparisons, and briefs with citations. Use when the user asks to gather information, compare sources, validate claims, or create structured research summaries with references.
---

# Research

Create concise, source-backed outputs from user-provided materials and external sources.

## When to Use

- User asks to gather information, conduct research, compare viewpoints, or validate claims.
- User asks for structured notes, briefing documents, literature summaries, or evidence-backed answers.
- Task requires citations and traceable claims.

## When Not to Use

- Simple factual Q and A that does not require multi-source validation.
- Opinion-only requests without evidence requirements.
- Pure implementation tasks where external research is not needed.

## Inputs

- Start with references and files provided by the user.
- If needed, find additional reputable sources to close gaps.
- If the user provides a template, keep its structure and fill missing sections.
- If no template is provided:
  - In agent mode: create a markdown document.
  - In ask mode: answer directly in chat.

## Workflow

1. Discover
   - Collect candidate sources relevant to `{user_query}`.
   - For each large source, do quick triage first. Stop early if irrelevant.
2. Evaluate
   - Prefer higher-authority sources:
     - Official docs, standards, and primary data
     - Peer-reviewed or institutional publications
     - Reputable secondary sources
     - Community posts (lowest confidence)
   - Note publication date when recency matters.
3. Synthesize
   - Extract only information that answers the request.
   - Separate evidence from inference.
   - If evidence is missing, label the statement as an assumption.
4. Resolve conflicts
   - If sources disagree, present both views with citations.
   - Do not force a single conclusion unless source quality clearly supports one side.
5. Validate
   - Confirm each important claim is traceable to at least one citation.

## Output Modes

### Quick mode

Use for short answers and iterative chats.

- Keep structure simple.
- Cite claims inline using links or numeric citations.
- Include only essential references.

### Formal mode

Use for reports, handoff docs, or user templates.

- Use numeric citations in text, then provide `## References`.
- Ensure each citation maps to a valid URL.
- Avoid duplicate entries between `## References` and `## Further Reading`.

For citation examples and edge cases, see [reference-format.md](reference-format.md).

## Writing Style

- No conversational filler.
- Be concise but readable. Prefer clear prose over heavy abbreviation.
- Use bullets, short paragraphs, and tables when they improve clarity.
- Use `Key: Value` for dense factual sections.
- Use code fences only for code.

## Quality Checklist

- Every major claim has a citation or is marked as an assumption.
- Sources are relevant and authority-ranked where needed.
- Conflicting evidence is surfaced, not hidden.
- Links are valid and references are not duplicated.
- The output directly answers the user request.