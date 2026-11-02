"""Ubah teks Markdown sederhana (balasan panjang bot) menjadi file Word .docx.

Mendukung: # / ## / ### heading, paragraf, daftar "- " / "* " / "1. ", **tebal**, *miring*,
[teks](url), tabel Markdown sederhana, dan garis "---" (diabaikan).
"""
import io
import re

from docx import Document
from docx.shared import Pt

INLINE = re.compile(r"(\*\*[^*]+\*\*|__[^_]+__|\*[^*\s][^*]*\*|\[[^\]]+\]\([^)]+\)|`[^`]+`)")


def _inline(par, text):
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            par.add_run(part[2:-2]).bold = True
        elif part.startswith("`") and part.endswith("`"):
            par.add_run(part[1:-1]).font.name = "Consolas"
        elif part.startswith("[") and "](" in part:
            t, u = part[1:-1].split("](", 1)
            par.add_run(t)
            par.add_run(f" ({u})").italic = True
        elif part.startswith("__") and part.endswith("__") and len(part) > 4:
            par.add_run(part[2:-2]).italic = True
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            par.add_run(part[1:-1]).italic = True
        else:
            par.add_run(part)


def title_of(md: str) -> str:
    for line in md.splitlines():
        s = line.strip().lstrip("#").strip().strip("*").strip()
        if s:
            return s[:70]
    return "dokumen"


def convert(md: str) -> bytes:
    doc = Document()
    doc.styles["Normal"].font.name = "Calibri"
    doc.styles["Normal"].font.size = Pt(11)
    lines = md.replace("\r\n", "\n").split("\n")
    i = 0
    buf = []
    headed = False
    first = next((k for k, x in enumerate(lines) if x.strip()), 0)

    def flush():
        if buf:
            _inline(doc.add_paragraph(), " ".join(x.strip() for x in buf))
            buf.clear()

    while i < len(lines):
        line = lines[i].rstrip()
        s = line.strip()
        m = re.match(r"^(#{1,4})\s+(.*)$", s)
        bold_line = re.match(r"^\*\*([^*]{2,120})\*\*:?$", s)  # baris tebal sendirian = subjudul (format Telegram)
        if m:
            flush()
            doc.add_heading(m.group(2).strip().strip("*"), level=min(len(m.group(1)), 3))
            headed = True
        elif bold_line:
            flush()
            doc.add_heading(bold_line.group(1).strip(), level=1 if not headed else 2)
            headed = True
        elif not headed and not buf and i == first and len(s) <= 90 and not s.endswith("."):
            doc.add_heading(s, level=1)  # baris pertama pendek tanpa titik = judul
            headed = True
        elif re.match(r"^[-*•]\s+", s):
            flush()
            _inline(doc.add_paragraph(style="List Bullet"), re.sub(r"^[-*•]\s+", "", s))
        elif re.match(r"^\d+[.)]\s+", s):
            flush()
            _inline(doc.add_paragraph(style="List Number"), re.sub(r"^\d+[.)]\s+", "", s))
        elif s.startswith("|") and s.endswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.match(r"^:?-{2,}:?$", c) for c in cells if c):
                    rows.append(cells)
                i += 1
            if rows:
                n = max(len(r) for r in rows)
                t = doc.add_table(rows=len(rows), cols=n)
                t.style = "Table Grid"
                for r, cells in enumerate(rows):
                    for c, val in enumerate(cells):
                        _inline(t.cell(r, c).paragraphs[0], val)
                        if r == 0:
                            for run in t.cell(r, c).paragraphs[0].runs:
                                run.bold = True
            continue
        elif re.match(r"^(-{3,}|\*{3,}|_{3,})$", s):
            flush()
        elif not s:
            flush()
        else:
            buf.append(s)
        i += 1
    flush()
    out = io.BytesIO()
    doc.save(out)
    return out.getvalue()
