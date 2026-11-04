#!/usr/bin/env python3
"""Anonymize delimited text exports (CSV/TSV/DATEV EXTF) before an AI agent looks at them.

Policy: every column is MASKED unless its header is on the safe list (or passed via --keep).
Masked values are replaced by stable pseudonyms (P0001, p0001@example.invalid) so the same raw
value maps to the same token across all files of a run, and across runs that reuse the map.

Output:
  file  foo.csv     -> foo.anon.csv                 (next to the original)
  dir   exports/    -> exports-anon/                (sibling, same sub-structure)
  map   <input>.anon-map.PRIVATE.csv                (next to the original; raw values - agents must NOT read it)

stdout carries only file names, row counts and column headers - never cell values.
Standard library only. Run with `python3 -I`.
"""
import argparse
import csv
import io
import re
import sys
from pathlib import Path

TEXT_SUFFIXES = {".csv", ".tsv", ".txt"}

# Headers that carry business data, not personal data. Compared after normalize().
SAFE_EXACT = {
    # generic / Plenigo revenue forecast / RAB
    "invoice_date", "invoice date", "invoice_id", "invoice_item_position", "delivery_list_name",
    "cost_center", "revenue_account", "currency", "sum", "document no.", "document type",
    "total net", "vat", "total gross", "amount", "net", "gross", "tax", "tax_rate", "date",
    # DATEV bookings (Buchungsstapel)
    "umsatz", "soll/haben-kennzeichen", "wkz umsatz", "kurs", "basis-umsatz", "wkz basis-umsatz",
    "konto", "gegenkonto (ohne bu-schlüssel)", "bu-schlüssel", "belegdatum", "belegfeld 1",
    "belegfeld 2", "skonto", "postensperre", "sachverhalt", "zinssperre", "kost1 - kostenstelle",
    "kost2 - kostenstelle", "kost-menge", "eu-steuersatz (bestimmung)", "abw. versteuerungsart",
    "sachverhalt l+l", "funktionsergänzung l+l", "bu 49 hauptfunktionstyp",
    "bu 49 hauptfunktionsnummer", "bu 49 funktionsergänzung", "stück", "gewicht", "zahlweise",
    "forderungsart", "veranlagungsjahr", "zugeordnete fälligkeit", "skontotyp", "auftragsnummer",
    "buchungstyp", "ust-schlüssel (anzahlungen)", "eu-land (anzahlungen)",
    "sachverhalt l+l (anzahlungen)", "eu-steuersatz (anzahlungen)", "erlöskonto (anzahlungen)",
    "herkunft-kz", "buchungs guid", "kost-datum", "skontosperre", "postensperre bis",
    "kennzeichen sobil-buchung", "festschreibung", "leistungsdatum", "datum zuord. steuerperiode",
    "fälligkeit", "generalumkehr (gu)", "steuersatz", "land", "eu-steuersatz (ursprung)",
    # DATEV debtors (Debitoren/Kreditoren) - only non-identifying attributes
    "adressatentyp", "eu-mitgliedstaat", "adressart", "sprache", "währungssteuerung",
    "zahlungsbedingung", "fälligkeit in tagen (debitor)", "skonto in prozent (debitor)",
    "kreditlimit (debitor)", "mahnung", "kontoauszug", "zinsberechnung", "lastschrift",
    "land (rechnungsadresse)", "insolvent", "leerfeld",
}
SAFE_PATTERNS = [
    re.compile(r"^\d{8}$"),                      # forecast period columns, e.g. 20260630
    re.compile(r"^beleginfo - art \d+$"),         # the *type* label; "Inhalt" stays masked
    re.compile(r"^zusatzinformation ?- ?art \d+$"),
    re.compile(r"^länderkennzeichen \d+$"),
]
# DATEV EXTF line 1 (metadata): 1-based positions that can hold a person's name/initials.
EXTF_META_MASK = {9, 10, 18}  # exported by, imported by, Diktatkürzel

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalize(header: str) -> str:
    return " ".join(header.strip().strip('"').lower().split())


def is_safe(header: str, extra_keep: set, extra_mask: set) -> bool:
    h = normalize(header)
    if h in extra_mask:
        return False
    if h in extra_keep or h in SAFE_EXACT:
        return True
    return any(p.match(h) for p in SAFE_PATTERNS)


class Pseudonymizer:
    def __init__(self, map_path: Path):
        self.map_path = map_path
        self.tokens = {}
        if map_path.exists():
            with map_path.open(encoding="utf-8", newline="") as fh:
                for row in csv.reader(fh):
                    if len(row) == 2 and row[0] != "token":
                        self.tokens[row[1]] = row[0]
        self.counter = len(self.tokens)

    def token(self, value: str) -> str:
        key = value.strip()
        if not key:
            return value
        tok = self.tokens.get(key)
        if tok is None:
            self.counter += 1
            tok = f"P{self.counter:04d}"
            self.tokens[key] = tok
        return f"{tok.lower()}@example.invalid" if EMAIL_RE.match(key) else tok

    def save(self):
        with self.map_path.open("w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["token", "original"])
            for orig, tok in sorted(self.tokens.items(), key=lambda kv: kv[1]):
                w.writerow([tok, orig])


def read_text(path: Path):
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig"), "utf-8-sig"
    for enc in ("utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            continue
    raise ValueError("undecodable")


def detect_delimiter(line: str) -> str:
    counts = {d: line.count(d) for d in (";", ",", "\t", "|")}
    return max(counts, key=counts.get)


def anonymize_file(src: Path, dst: Path, pseudo: Pseudonymizer, keep: set, mask: set) -> dict:
    text, enc = read_text(src)
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines(keepends=True)
    first = lines[0].lstrip('"') if lines else ""
    is_extf = first.startswith("EXTF") or first.startswith("DTVF")

    out = io.StringIO(newline="")
    meta_line = None
    if is_extf:
        meta_line, lines = lines[0], lines[1:]
    body = "".join(lines)
    delim = detect_delimiter(lines[0] if lines else (meta_line or ","))

    if meta_line is not None:
        meta = next(csv.reader([meta_line.rstrip("\r\n")], delimiter=delim))
        meta = [pseudo.token(v) if (i + 1) in EXTF_META_MASK and v.strip() else v for i, v in enumerate(meta)]
        csv.writer(out, delimiter=delim, lineterminator=newline).writerow(meta)

    reader = csv.reader(io.StringIO(body, newline=""), delimiter=delim)
    writer = csv.writer(out, delimiter=delim, lineterminator=newline)
    header = next(reader, None)
    if header is None:
        dst.write_text(out.getvalue(), encoding=enc, newline="")
        return {"rows": 0, "kept": [], "masked": []}
    safe = [is_safe(h, keep, mask) for h in header]
    writer.writerow(header)
    rows = 0
    filled = [0] * len(header)
    extra_masked = False
    for row in reader:
        rows += 1
        new = []
        for i, v in enumerate(row):
            if i < len(header) and safe[i]:
                new.append(v)
            else:
                if i >= len(header) and v.strip():
                    extra_masked = True
                new.append(pseudo.token(v) if v.strip() else v)
            if i < len(header) and v.strip():
                filled[i] += 1
        writer.writerow(new)
    dst.write_text(out.getvalue(), encoding=enc, newline="")
    used = [i for i in range(len(header)) if filled[i]]
    return {
        "rows": rows,
        "kept": [header[i] for i in used if safe[i]],
        "masked": [header[i] for i in used if not safe[i]] + (["<cells beyond header>"] if extra_masked else []),
        "extf": is_extf,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", type=Path, help="file or directory to anonymize")
    ap.add_argument("--keep", action="append", default=[], help="extra header to keep verbatim (repeatable)")
    ap.add_argument("--mask", action="append", default=[], help="header to mask even if on the safe list (repeatable)")
    args = ap.parse_args()

    src = args.path.resolve()
    if not src.exists():
        sys.exit(f"not found: {src}")
    keep = {normalize(k) for k in args.keep}
    mask = {normalize(m) for m in args.mask}

    if src.is_dir():
        out_root = src.with_name(src.name + "-anon")
        map_path = src.with_name(src.name + ".anon-map.PRIVATE.csv")
        files = sorted(p for p in src.rglob("*") if p.is_file())
    else:
        out_root = None
        map_path = src.with_name(src.stem + ".anon-map.PRIVATE.csv")
        files = [src]

    pseudo = Pseudonymizer(map_path)
    skipped = []
    print(f"input: {src}")
    for f in files:
        if f.name.endswith(".anon-map.PRIVATE.csv") or ".anon." in f.name:
            continue
        rel = f.relative_to(src) if out_root else Path(f.name)
        if f.suffix.lower() not in TEXT_SUFFIXES:
            skipped.append(str(rel))
            continue
        dst = (out_root / rel) if out_root else f.with_name(f.stem + ".anon" + f.suffix)
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            info = anonymize_file(f, dst, pseudo, keep, mask)
        except ValueError:
            skipped.append(f"{rel} (could not decode)")
            continue
        tag = " [DATEV EXTF]" if info.get("extf") else ""
        print(f"\n{rel}{tag}: {info['rows']} rows -> {dst}")
        print(f"  kept   ({len(info['kept'])}): {' | '.join(info['kept']) or '-'}")
        print(f"  masked ({len(info['masked'])}): {' | '.join(info['masked']) or '-'}")
    pseudo.save()
    if skipped:
        print(f"\nSKIPPED (not anonymized, do not read): {', '.join(skipped)}")
    if out_root:
        print(f"\noutput dir: {out_root}")
    print(f"pseudonym map (PRIVATE - agents must not read): {map_path}")


if __name__ == "__main__":
    main()
