---
name: anonymizing-customer-data
description: Use when a file or folder the agent needs to read may contain personal customer data (customer exports, DATEV EXTF Debitoren/Buchungen, RAB, revenue forecasts, production CSV/TSV dumps, files with names, emails, addresses, VAT IDs or IBANs), or when the user asks to anonymize, pseudonymize or strip PII from data before analysis. Produces a masked copy the agent can read instead of the original.
---

# Anonymizing Customer Data

## Overview

Company policy: personal customer data must not be put into an AI. This skill lets you debug with real exports anyway: `anonymize.py` writes a copy where every column is **masked unless it is on a safe list** (amounts, dates, accounts, tax rates, currency, document numbers, DATEV type labels). Masked values become stable pseudonyms (`P0007`, `p0007@example.invalid`), so the same raw value gets the same token in every file of the run — joins across files still work.

**The core rule: you never open the original. You run the script on it and read only the output.**

## Safe to do without permission

These show structure, not values:
- list files, sizes, `file` types, zip listings (`unzip -l`)
- print only the header row (for DATEV EXTF: line 2; line 1 is metadata and can contain the exporting user's name)
- per-column counts of filled / distinct values, without printing the values

Never `cat`, `head`, `Read`, `grep` (with matching lines shown), or quote data rows of the original.

## Steps

1. Ask the user before running, and name the path (the user stays in charge of what gets processed).
2. Run it (standard library only; `-I` keeps it isolated from the data directory):
   ```bash
   python3 -I ~/.claude/skills/anonymizing-customer-data/anonymize.py <file-or-dir> [--keep "Header"]... [--mask "Header"]...
   ```
   - file `foo.csv` → `foo.anon.csv` next to it
   - dir `exports/` → `exports-anon/` sibling, same sub-structure
   - pseudonym map → `<name>.anon-map.PRIVATE.csv` next to the original. **Never read it** — it holds the raw values. Re-runs reuse it, so tokens stay stable between runs.
3. Read the summary: per file, which headers were kept and which masked. It prints headers only, never values.
4. Work only from the `.anon` / `-anon` output.

## Tuning

- A masked column you need for the analysis (e.g. `Buchungstext` holding only "Rechnung"/"Gutschrift"): **ask the user** whether it is free of personal data, then re-run with `--keep "Buchungstext"`. Don't decide that from the data yourself — you'd have to look at it.
- A safe-listed column that does carry personal data in some export: `--mask "Header"`.
- If the user debugs with the real customer ID, they can look up a token in the PRIVATE map themselves; ask them to.

## Limits — tell the user when they apply

- Only delimited text files (`.csv`, `.tsv`, `.txt`) are processed. PDFs, zips, xlsx, JSON etc. are listed as **SKIPPED — do not read them**. Ask the user to unzip archives first, or to check the file in some other way.
- Masking works per column. Personal data sitting in a safe-listed column (e.g. a name typed into a document-number field) gets through.
- Quoting is normalized (minimal quoting), so the output is not byte-identical to the original. If the bug is about file formatting or quoting, say so — the copy can't show it.
- Single-file runs and directory runs use different maps; to correlate several files, run on their common folder.
