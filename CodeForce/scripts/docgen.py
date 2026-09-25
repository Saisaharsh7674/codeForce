#!/usr/bin/env python3
"""KPMG Engage document generator (stdlib only).

Produces Word (.docx) documents for three document types used by the team:
  - impact   : Impact Analysis Document
  - solution : Solution Document
  - rca      : Root Cause Analysis Document

A .docx file is an Office Open XML package: a ZIP archive containing a small
set of XML parts. This module builds those parts by hand so it has no third
party dependencies (python-docx is not available in this environment).

Usage:
    python3 docgen.py <spec.json> [--outdir DIR]

The spec JSON drives the content. See build_argparser() docstring and the
sample specs under .claude/scripts/samples/ for the schema of each type.
"""

import argparse
import json
import os
import sys
import zipfile
from xml.sax.saxutils import escape

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


# --------------------------------------------------------------------------
# Low level OOXML building blocks
# --------------------------------------------------------------------------

def _rpr(bold=False, italic=False, size=None, color=None):
    parts = []
    if bold:
        parts.append("<w:b/>")
    if italic:
        parts.append("<w:i/>")
    if color:
        parts.append(f'<w:color w:val="{color}"/>')
    if size:
        # size is in points; OOXML uses half-points
        parts.append(f'<w:sz w:val="{int(size) * 2}"/>')
    if not parts:
        return ""
    return "<w:rPr>" + "".join(parts) + "</w:rPr>"


def _run(text, bold=False, italic=False, size=None, color=None):
    text = escape(text or "")
    rpr = _rpr(bold, italic, size, color)
    return f'<w:r>{rpr}<w:t xml:space="preserve">{text}</w:t></w:r>'


def paragraph(text="", bold=False, italic=False, size=None, color=None,
              style=None, spacing_after=120):
    """A single paragraph. `text` may be a string or a list of run dicts."""
    ppr_bits = []
    if style:
        ppr_bits.append(f'<w:pStyle w:val="{style}"/>')
    if spacing_after is not None:
        ppr_bits.append(f'<w:spacing w:after="{spacing_after}"/>')
    ppr = "<w:pPr>" + "".join(ppr_bits) + "</w:pPr>" if ppr_bits else ""

    if isinstance(text, list):
        runs = "".join(
            _run(r.get("text", ""), r.get("bold", False), r.get("italic", False),
                 r.get("size"), r.get("color"))
            for r in text
        )
    else:
        runs = _run(text, bold, italic, size, color)
    return f"<w:p>{ppr}{runs}</w:p>"


def heading(text, level=1):
    sizes = {1: 16, 2: 13, 3: 12}
    return paragraph(text, bold=True, size=sizes.get(level, 12),
                     color="1F3864", spacing_after=160)


def _cell(content, width=None, shade=None, bold=False):
    """A table cell. `content` is a string or a list of paragraph XML strings."""
    tcpr = ["<w:tcPr>"]
    if width:
        tcpr.append(f'<w:tcW w:w="{width}" w:type="dxa"/>')
    if shade:
        tcpr.append(f'<w:shd w:val="clear" w:color="auto" w:fill="{shade}"/>')
    tcpr.append("</w:tcPr>")
    tcpr = "".join(tcpr) if (width or shade) else ""

    if isinstance(content, list):
        body = "".join(content)
    else:
        body = paragraph(content, bold=bold, spacing_after=40)
    if not body:
        body = paragraph("", spacing_after=40)
    return f"<w:tc>{tcpr}{body}</w:tc>"


def table(rows, col_widths=None, header_shade="1F3864", first_row_header=False):
    """Build a table.

    rows: list of rows; each row is a list of cells. A cell is either a string
          or a dict {text, bold, shade, colspan}.
    """
    borders = (
        "<w:tblBorders>"
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        "</w:tblBorders>"
    )
    tblpr = (
        "<w:tblPr>"
        '<w:tblW w:w="5000" w:type="pct"/>'
        '<w:tblLayout w:type="fixed"/>'
        f"{borders}"
        "</w:tblPr>"
    )

    grid = ""
    if col_widths:
        grid = "<w:tblGrid>" + "".join(
            f'<w:gridCol w:w="{w}"/>' for w in col_widths
        ) + "</w:tblGrid>"

    out = [f"<w:tbl>{tblpr}{grid}"]
    for i, row in enumerate(rows):
        out.append("<w:tr>")
        for j, cell in enumerate(row):
            if isinstance(cell, dict):
                text = cell.get("text", "")
                bold = cell.get("bold", False)
                shade = cell.get("shade")
                colspan = cell.get("colspan", 1)
            else:
                text, bold, shade, colspan = str(cell), False, None, 1

            is_header = first_row_header and i == 0
            if is_header:
                bold = True
                shade = shade or header_shade

            width = col_widths[j] if col_widths and j < len(col_widths) else None
            para = paragraph(
                text, bold=bold,
                color="FFFFFF" if is_header else None,
                spacing_after=40,
            )
            tcpr = ["<w:tcPr>"]
            if width:
                tcpr.append(f'<w:tcW w:w="{width}" w:type="dxa"/>')
            if colspan > 1:
                tcpr.append(f'<w:gridSpan w:val="{colspan}"/>')
            if shade:
                tcpr.append(f'<w:shd w:val="clear" w:color="auto" w:fill="{shade}"/>')
            tcpr.append("</w:tcPr>")
            out.append(f"<w:tc>{''.join(tcpr)}{para}</w:tc>")
        out.append("</w:tr>")
    out.append("</w:tbl>")
    # a trailing empty paragraph keeps Word happy after a table
    out.append(paragraph("", spacing_after=120))
    return "".join(out)


# --------------------------------------------------------------------------
# Document package assembly
# --------------------------------------------------------------------------

def _content_types():
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>'
    )


def _root_rels():
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/>'
        '</Relationships>'
    )


def _document_rels():
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/>'
        '</Relationships>'
    )


def _styles():
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:styles xmlns:w="{W_NS}">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>'
        '<w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/></w:style>'
        '</w:styles>'
    )


def _document(body_xml):
    sect = (
        '<w:sectPr>'
        '<w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="720" w:footer="720" w:gutter="0"/>'
        '</w:sectPr>'
    )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:document xmlns:w="{W_NS}">'
        f'<w:body>{body_xml}{sect}</w:body>'
        '</w:document>'
    )


def write_docx(path, body_xml):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", _content_types())
        z.writestr("_rels/.rels", _root_rels())
        z.writestr("word/_rels/document.xml.rels", _document_rels())
        z.writestr("word/styles.xml", _styles())
        z.writestr("word/document.xml", _document(body_xml))


# --------------------------------------------------------------------------
# Standard reference lists (from the KPMG templates)
# --------------------------------------------------------------------------

DEFAULT_PROFILES = [
    "KPMG Sales User", "Data Steward", "Executive Assistant Extended",
    "Executive Assistant Limited", "Executive Assistant", "Limited Integration User",
    "Ownbackup User", "KPMG Marketing User", "Glass Breaker Profile",
    "Splunk – Event Monitering", "Integration User",
    "Integration User – Marketing Cloud", "Analytics Cloud Integration User",
    "Analytics Cloud Security User", "System Administrator",
    "Admin read only Alteryx", "Admin Read Only",
]

DEFAULT_INTEGRATIONS = [
    "ADL", "Mule Soft", "CRMA", "Marketing Cloud", "ECC", "NGCLEAS", "GRIP", "SYNC",
]


# --------------------------------------------------------------------------
# Document builders
# --------------------------------------------------------------------------

def build_impact(spec):
    b = []
    b.append(heading("Impact Analysis", 1))

    # Header info table
    dev = spec.get("developer", "")
    reviewer = spec.get("reviewer", "")
    prepared_by = spec.get("prepared_by", dev)
    date = spec.get("date", "")
    jira = spec.get("jira", "")
    title = spec.get("title", "")
    brief = spec.get("brief_description", "")

    header_rows = [
        [{"text": "IMPACT ANALYSIS", "bold": True, "shade": "1F3864",
          "colspan": 4}],
        [{"text": "Jira#", "bold": True, "shade": "D9E2F3"}, jira,
         {"text": "Title", "bold": True, "shade": "D9E2F3"}, title],
        [{"text": "", "shade": "D9E2F3"}, "",
         {"text": "Developer", "bold": True, "shade": "D9E2F3"}, dev],
        [{"text": "Brief Description", "bold": True, "shade": "D9E2F3"},
         {"text": brief, "colspan": 3}],
        [{"text": "Reviewer", "bold": True, "shade": "D9E2F3"},
         {"text": reviewer, "colspan": 3}],
        [{"text": "Prepared by", "bold": True, "shade": "D9E2F3"}, prepared_by,
         {"text": "Date", "bold": True, "shade": "D9E2F3"}, date],
    ]
    b.append(table(header_rows, col_widths=[2200, 3400, 1800, 3400]))

    # 1. Executive summary
    b.append(heading("1. Executive Summary", 2))
    b.append(paragraph(spec.get("executive_summary", "")))

    # 2. Scope
    b.append(heading("2. Scope of Impact Analysis", 2))
    b.append(paragraph(spec.get("scope",
             "There is no downstream impact on any system with these changes.")))

    # Impacted components
    b.append(heading("Impacted Components", 3))
    comp_rows = [[{"text": "#"}, {"text": "Component Name"},
                  {"text": "Type"}, {"text": "Impact Type"}]]
    for i, c in enumerate(spec.get("components", []), start=1):
        comp_rows.append([str(i), c.get("name", ""), c.get("type", ""),
                          c.get("impact", "")])
    if len(comp_rows) == 1:
        comp_rows.append(["1", "", "", ""])
    b.append(table(comp_rows, col_widths=[600, 5000, 2500, 2700],
                   first_row_header=True))

    # Impacted profiles
    b.append(heading("Impacted Profiles", 3))
    prof_flags = spec.get("profiles", {})
    prof_rows = [[{"text": "Name"}, {"text": "Y/N"}]]
    for name in DEFAULT_PROFILES:
        prof_rows.append([name, prof_flags.get(name, "N")])
    b.append(table(prof_rows, col_widths=[7000, 3800], first_row_header=True))

    # Impacted permission sets
    b.append(heading("Impacted Permission Sets", 3))
    ps = spec.get("permission_sets", [])
    ps_rows = [[{"text": "Name"}]]
    if ps:
        for name in ps:
            ps_rows.append([name])
    else:
        ps_rows.append(["None"])
    b.append(table(ps_rows, col_widths=[10800], first_row_header=True))

    # Impacted integrations
    b.append(heading("Impacted Integration Systems", 3))
    integ_flags = spec.get("integrations", {})
    integ_rows = [[{"text": "Name"}, {"text": "Y/N"},
                   {"text": "Sign off from integrated system (Y/N)"}]]
    for name in DEFAULT_INTEGRATIONS:
        row = integ_flags.get(name, {})
        if isinstance(row, str):
            row = {"impacted": row}
        integ_rows.append([name, row.get("impacted", "N"),
                           row.get("signoff", "N")])
    b.append(table(integ_rows, col_widths=[4000, 2000, 4800],
                   first_row_header=True))

    return "".join(b)


def build_solution(spec):
    b = []
    jira = spec.get("jira", "")
    b.append(heading(f"Solution document for {jira}", 1))
    b.append(paragraph(spec.get("title", ""), bold=True))

    def labelled(label, value):
        if value:
            b.append(paragraph([{"text": f"{label}: ", "bold": True},
                                {"text": value}]))

    labelled("Description", spec.get("description", ""))
    labelled("Expected Result", spec.get("expected_result", ""))
    labelled("Actual Result", spec.get("actual_result", ""))
    labelled("Solution business/functional impact",
             spec.get("business_impact", "none, this is purely a code fix."))
    labelled("Root Cause", spec.get("root_cause", ""))

    b.append(heading("Resolution", 2))
    for line in _as_list(spec.get("resolution", [])):
        b.append(paragraph(line))

    b.append(heading("Solution", 2))
    sol_rows = [[{"text": "Item"}, {"text": "New/Existing"},
                 {"text": "Name"}, {"text": "Change Description"}]]
    for i, item in enumerate(spec.get("solution_items", []), start=1):
        sol_rows.append([str(i), item.get("status", "Existing"),
                         item.get("name", ""), item.get("change", "")])
    if len(sol_rows) == 1:
        sol_rows.append(["1", "Existing", "", ""])
    b.append(table(sol_rows, col_widths=[700, 1800, 3300, 5000],
                   first_row_header=True))

    b.append(heading("Changes", 2))
    for ch in _as_list(spec.get("changes", [])):
        b.append(paragraph(ch))

    b.append(heading("Impact Analysis Brief", 2))
    b.append(paragraph(spec.get("impact_brief", "No Impacts")))

    b.append(heading("Components Impacted", 3))
    for c in _as_list(spec.get("components_impacted", [])):
        b.append(paragraph("•  " + c))

    return "".join(b)


def build_rca(spec):
    b = []
    b.append(heading(spec.get("title", "Root Cause Analysis"), 1))

    info_rows = [
        [{"text": "Incident ID", "bold": True, "shade": "D9E2F3"},
         spec.get("incident_id", "")],
        [{"text": "Reported Date", "bold": True, "shade": "D9E2F3"},
         spec.get("reported_date", "")],
        [{"text": "Issue Description", "bold": True, "shade": "D9E2F3"},
         spec.get("issue_description", "")],
        [{"text": "Impact", "bold": True, "shade": "D9E2F3"},
         spec.get("impact", "")],
        [{"text": "Severity", "bold": True, "shade": "D9E2F3"},
         spec.get("severity", "")],
        [{"text": "Root Cause", "bold": True, "shade": "D9E2F3"},
         spec.get("root_cause", "")],
    ]
    b.append(table(info_rows, col_widths=[2600, 8200]))

    def section(name, key):
        content = spec.get(key)
        if not content:
            return
        b.append(heading(name, 2))
        for line in _as_list(content):
            b.append(paragraph(line))

    section("What Happened", "what_happened")
    section("Impact Analysis", "impact_analysis")
    section("Business Impact", "business_impact")
    section("Why it Happened", "why_it_happened")
    section("Debug Log Analysis", "debug_analysis")
    section("Impacted Records", "impacted_records")
    section("Salesforce Response / Root Cause Analysis", "salesforce_response")
    section("Summary", "summary")
    section("Proposed Solution", "proposed_solution")
    section("Expected Outcome", "expected_outcome")

    return "".join(b)


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


BUILDERS = {
    "impact": build_impact,
    "solution": build_solution,
    "rca": build_rca,
}

TITLES = {
    "impact": "Impact Analysis",
    "solution": "Solution Document",
    "rca": "RCA",
}


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def build_argparser():
    p = argparse.ArgumentParser(
        description="Generate KPMG Engage Word documents from a JSON spec.")
    p.add_argument("spec", help="Path to the JSON spec file.")
    p.add_argument("--outdir", default="docs/generated",
                   help="Directory to write the .docx files to.")
    return p


def slugify(text):
    keep = [c if c.isalnum() or c in "-_ " else "_" for c in (text or "doc")]
    return "".join(keep).strip().replace(" ", "_") or "doc"


def main(argv=None):
    args = build_argparser().parse_args(argv)
    with open(args.spec, encoding="utf-8") as fh:
        spec = json.load(fh)

    os.makedirs(args.outdir, exist_ok=True)

    # A spec may contain one document ("type" + fields) or many ("documents": [...])
    docs = spec["documents"] if "documents" in spec else [spec]

    written = []
    for doc in docs:
        dtype = doc.get("type")
        if dtype not in BUILDERS:
            print(f"ERROR: unknown document type {dtype!r}; "
                  f"expected one of {sorted(BUILDERS)}", file=sys.stderr)
            return 2
        body = BUILDERS[dtype](doc)
        key = doc.get("jira") or doc.get("incident_id") or TITLES[dtype]
        fname = f"{TITLES[dtype]}_{slugify(key)}.docx"
        out = os.path.join(args.outdir, fname)
        write_docx(out, body)
        written.append(out)
        print(f"Wrote {out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
