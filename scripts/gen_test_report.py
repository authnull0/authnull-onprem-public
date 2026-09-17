#!/usr/bin/env python3
"""Generate API-Test-Report.xlsx from API-INVENTORY.md.

Usage:
    python3 scripts/gen_test_report.py

Reads API-INVENTORY.md (endpoints + request payload field trees) and the
per-module internal/*/routes.go files (route-level auth middleware), then writes
API-Test-Report.xlsx with four sheets:

    Test Cases   one pre-filled happy-path row per endpoint
    Summary      per-module rollup, all COUNTIFS formulas
    Defects      blank defect log with dropdowns
    Environment  build/session/sign-off template

The workbook is written directly as OOXML (a zip of XML parts) so this has no
third-party dependencies -- openpyxl is not required.

Note: route registrations that are commented out in routes.go are ignored, both
here and in API-INVENTORY.md. The four /mfa/passkey/* routes are commented out in
internal/mfa/routes.go and are deliberately absent.
"""

import collections
import glob
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INVENTORY = os.path.join(ROOT, "API-INVENTORY.md")
OUT = os.path.join(ROOT, "API-Test-Report.xlsx")

# A commented-out registration is not a route. Matching these was an earlier bug
# that put four phantom /mfa/passkey/* rows in the sheet.
COMMENTED = re.compile(r"^\s*//")

# ── 1. route-level auth middleware, from routes.go source order ──────────────


def route_auth():
    auth = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "internal", "*", "routes.go"))):
        mod = path.split(os.sep + "internal" + os.sep)[1].split(os.sep)[0]
        lines = open(path, encoding="utf-8-sig").read().split("\n")
        parent, created, prefix = {}, {}, {}
        mw = collections.defaultdict(list)

        for i, ln in enumerate(lines):
            if COMMENTED.match(ln):
                continue
            m = re.search(r'(\w+)\s*:?=\s*(\w+)\.Group\("([^"]*)"\)', ln)
            if m:
                v, par, pre = m.groups()
                parent[v], created[v] = par, i
                prefix[v] = prefix.get(par, "") + pre
            m = re.search(r"(\w+)\.Use\((?:middlewares?\.)?(\w+)\(", ln)
            if m:
                mw[m.group(1)].append((i, m.group(2)))

        def chain(var, line):
            """Middleware applying to a route on `var` at `line`.

            gin copies the parent's handler chain when a group is created, so a
            parent's Use() only reaches a child group created after it.
            """
            got, cur, seen = [], var, set()
            while cur and cur not in seen:
                seen.add(cur)
                for used_at, name in mw.get(cur, []):
                    if cur == var:
                        if used_at < line:
                            got.append(name)
                    elif used_at < created.get(var, line):
                        got.append(name)
                cur = parent.get(cur)
            return got

        for i, ln in enumerate(lines):
            if COMMENTED.match(ln):
                continue
            m = re.search(r'(\w+)\.(GET|POST|PUT|DELETE|PATCH|OPTIONS)\("([^"]*)"', ln)
            if not m:
                continue
            var, meth, p = m.groups()
            # Audit logging is not an auth gate.
            names = [n for n in chain(var, i) if "Audit" not in n]
            auth[(mod, meth + " " + prefix.get(var, "") + p)] = names[0] if names else "None"
    return auth


# ── 2. parse API-INVENTORY.md ────────────────────────────────────────────────


def parse_inventory():
    md = open(INVENTORY, encoding="utf-8").read().split("\n")
    entries, mod, i = [], None, 0
    while i < len(md):
        ln = md[i]
        m = re.match(r"^## (\w[\w\- ]*?)\s+\(\d+ unique handlers\)", ln)
        if m:
            mod = m.group(1).strip()
            i += 1
            continue
        if ln.startswith("## top-level"):
            break
        if ln.startswith("### ") and mod:
            e = {
                "module": mod, "primary": ln[4:].strip(), "aliases": [],
                "handler": "", "file": "", "bodies": [], "query": [], "param": [],
                "headers": [], "formfile": [], "formfields": [],
                "multipart": False, "nobody": False,
            }
            i += 1
            while i < len(md) and not md[i].startswith("### ") and not md[i].startswith("## "):
                l = md[i]
                if l.startswith("aliases: "):
                    e["aliases"] = [x.strip() for x in l[9:].split(",")]
                elif l.startswith("handler: "):
                    hm = re.match(r"handler: `(.+?)`(?: — (.+))?$", l)
                    if hm:
                        e["handler"], e["file"] = hm.group(1), hm.group(2) or ""
                elif l.startswith("body ("):
                    tname = l[6:].rstrip("):")
                    i += 1
                    if i < len(md) and md[i].startswith("```"):
                        i += 1
                        blk = []
                        while i < len(md) and not md[i].startswith("```"):
                            blk.append(md[i])
                            i += 1
                        e["bodies"].append((tname, blk))
                elif l.startswith("query: "):
                    e["query"] = [x.strip() for x in l[7:].split(",")]
                elif l.startswith("path params: "):
                    e["param"] = [x.strip() for x in l[13:].split(",")]
                elif l.startswith("headers: "):
                    e["headers"] = [x.strip() for x in l[9:].split(",")]
                elif l.startswith("form file: "):
                    e["formfile"] = [x.strip() for x in l[11:].split(",")]
                elif l.startswith("form fields: "):
                    e["formfields"] = [x.strip() for x in l[13:].split(",")]
                elif "_multipart/form-data upload_" in l:
                    e["multipart"] = True
                elif "_no request payload_" in l:
                    e["nobody"] = True
                i += 1
            entries.append(e)
            continue
        i += 1
    return entries


# ── 3. field tree -> JSON sample ────────────────────────────────────────────

HINT = {
    "orgid": 1, "tenantid": 1, "domainid": 1, "userid": 1, "pageno": 1,
    "pagesize": 10, "pageid": 1, "pagenumber": 1, "email": "test@example.com",
    "password": "Test@1234", "url": "tenant.org.example.com",
    "username": "testuser", "firstname": "Test", "lastname": "User",
    "phone": "+10000000000", "code": "123456", "name": "test",
    "status": "active", "groupname": "qa-group", "confirmpassword": "Test@1234",
}
NUM = {"int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16",
       "uint32", "uint64", "float32", "float64", "byte", "rune"}


def leaf(key, t):
    k = key.lower().replace("_", "").replace("-", "")
    t = t.strip()
    is_slice = t.startswith("[]") or t.startswith("*[]")
    b = t.lstrip("*").lstrip("[]").lstrip("*").strip()

    # Seed values are keyed by field name, but the same name can carry different
    # types: tenantId is an int on most endpoints and an Azure AD GUID string on
    # the provider-config ones. Only apply a hint when the type agrees.
    if k in HINT and not is_slice:
        hint = HINT[k]
        if (isinstance(hint, str) and b == "string") or (
            isinstance(hint, int) and not isinstance(hint, bool) and b in NUM
        ):
            return hint

    if b.startswith("map["):
        return {}
    if b in NUM:
        v = 0
    elif b == "string":
        v = ""
    elif b == "bool":
        v = False
    elif b == "time.Time":
        v = "2026-08-04T00:00:00Z"
    elif b in ("any", "interface{}", "json.RawMessage"):
        v = None
    else:
        v = {}
    return [v] if is_slice else v


def build(blk):
    """Rebuild a JSON sample from the indented `key: type` tree."""
    root = {}
    stack = [(-1, root)]
    for raw in blk:
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        s = raw.strip()
        if s.startswith("<embeds") or s.startswith("..."):
            continue
        m = re.match(r"^(.+?):\s*(.+?)(?:\s+\(required\))?$", s)
        if not m:
            continue
        key, t = m.group(1).strip(), m.group(2).strip()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1] if stack else root
        cont = parent[0] if isinstance(parent, list) else parent
        if not isinstance(cont, dict):
            continue
        if t in ("object", "[]object"):
            child = {}
            cont[key] = [child] if t.startswith("[]") else child
            stack.append((indent, child))
        else:
            cont[key] = leaf(key, t)
            stack.append((indent, cont))
    return root


# ── 4. rows ─────────────────────────────────────────────────────────────────

PREFIX = {"pam": "/api/v1/pam", "tenant": "/api/v1/tenant"}
MODCODE = {"pam": "PAM", "policy": "POL", "ad": "AD", "user": "USR",
           "tenant": "TNT", "mfa": "MFA", "issuer": "ISS", "wallet": "WAL",
           "database": "DB", "dashboard": "DSH", "serviceaccounts": "SVC",
           "verifier": "VER", "org": "ORG", "endpoint": "EP",
           "dbconsole": "DBC", "entra": "ENT"}
PRIORITY = {"org": "P1", "tenant": "P1", "mfa": "P1", "user": "P1", "pam": "P1",
            "policy": "P1", "ad": "P2", "wallet": "P2", "issuer": "P2",
            "database": "P2", "serviceaccounts": "P2", "dashboard": "P3",
            "verifier": "P3", "endpoint": "P3", "dbconsole": "P3", "entra": "P3"}
MODORDER = ["org", "tenant", "mfa", "user", "pam", "policy", "ad", "wallet",
            "issuer", "database", "serviceaccounts", "dashboard", "verifier",
            "endpoint", "dbconsole", "entra"]


def build_rows():
    auth = route_auth()
    bymod = collections.defaultdict(list)
    for e in parse_inventory():
        bymod[e["module"]].append(e)

    rows = []
    for mod in MODORDER:
        n = 0
        for e in bymod.get(mod, []):
            h = e["handler"]
            if h.startswith("func(") or "gin.WrapF" in h:
                continue  # inline health checks / websocket upgrades
            allp = [e["primary"]] + e["aliases"]
            cand = [p for p in allp if "/%s/" % mod in p.lower()]
            primary = cand[0] if cand else e["primary"]
            meth, path = primary.split(" ", 1)
            n += 1

            payload = ""
            if e["bodies"]:
                obj = build(e["bodies"][0][1])
                payload = json.dumps(obj) if obj else "{}"
            elif e["multipart"]:
                payload = "<multipart/form-data>"
            elif e["nobody"]:
                payload = "(no request body)"

            extras = []
            if e["query"]:
                extras.append("query: " + ", ".join(e["query"]))
            if e["param"]:
                extras.append("path: " + ", ".join(e["param"]))
            if e["formfile"]:
                extras.append("file: " + ", ".join(e["formfile"]))
            if e["formfields"]:
                extras.append("form: " + ", ".join(e["formfields"]))

            rows.append({
                "id": "%s-%03d-01" % (MODCODE[mod], n), "module": mod,
                "priority": PRIORITY[mod], "method": meth,
                "endpoint": PREFIX.get(mod, "/api/v1") + path,
                "auth": auth.get((mod, primary), "None"),
                "scenario": "Valid request — happy path",
                "casetype": "Positive", "payload": payload,
                "notes": " | ".join(extras),
                "bodytype": e["bodies"][0][0] if e["bodies"] else "",
                "handler": h, "file": e["file"],
                "aliases": "; ".join(e["aliases"]),
                "headers": ", ".join(e["headers"]),
            })
    return rows


# ── 5. xlsx writer ──────────────────────────────────────────────────────────


def esc(t):
    t = str(t)
    for a, b in (("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ('"', "&quot;")):
        t = t.replace(a, b)
    return t.replace("\n", "&#10;").replace("\r", "").replace("\t", "    ")


def col(n):
    s = ""
    while n >= 0:
        s = chr(65 + n % 26) + s
        n = n // 26 - 1
    return s


def cell(r, c, val, style=0, kind="s"):
    ref = "%s%d" % (col(c), r)
    if val is None or val == "":
        return '<c r="%s" s="%d"/>' % (ref, style)
    if kind == "n":
        return '<c r="%s" s="%d"><v>%s</v></c>' % (ref, style, val)
    if kind == "f":
        return '<c r="%s" s="%d"><f>%s</f></c>' % (ref, style, esc(val))
    return '<c r="%s" s="%d" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (
        ref, style, esc(val))


STYLES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/></numFmts>
<fonts count="7">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font>
<font><sz val="9"/><name val="Consolas"/></font>
<font><b/><sz val="15"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>
<font><i/><sz val="9"/><color rgb="FF808080"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>
</fonts>
<fills count="9">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E79"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFC6EFCE"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFC7CE"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFEB9C"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE7E6E6"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left style="thin"><color rgb="FFD0D0D0"/></left><right style="thin"><color rgb="FFD0D0D0"/></right><top style="thin"><color rgb="FFD0D0D0"/></top><bottom style="thin"><color rgb="FFD0D0D0"/></bottom><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="13">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="top"/></xf>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="2" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="8" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="top"/></xf>
<xf numFmtId="0" fontId="2" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="9" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center"/></xf>
<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1"/>
</cellXfs>
<dxfs count="4">
<dxf><font><color rgb="FF006100"/></font><fill><patternFill><bgColor rgb="FFC6EFCE"/></patternFill></fill></dxf>
<dxf><font><color rgb="FF9C0006"/></font><fill><patternFill><bgColor rgb="FFFFC7CE"/></patternFill></fill></dxf>
<dxf><font><color rgb="FF9C6500"/></font><fill><patternFill><bgColor rgb="FFFFEB9C"/></patternFill></fill></dxf>
<dxf><font><color rgb="FF808080"/></font><fill><patternFill><bgColor rgb="FFE7E6E6"/></patternFill></fill></dxf>
</dxfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>'''


def sheet(cols, rows_xml, dim, freeze=None, autofilter=None, dv=None, cf=None):
    x = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
         '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
         '<dimension ref="%s"/>' % dim,
         '<sheetViews><sheetView workbookViewId="0">']
    if freeze:
        xs, ys, tl = freeze
        x.append('<pane xSplit="%d" ySplit="%d" topLeftCell="%s" activePane="bottomRight" state="frozen"/>' % (xs, ys, tl))
        x.append('<selection pane="bottomRight" activeCell="%s" sqref="%s"/>' % (tl, tl))
    x.append("</sheetView></sheetViews>")
    x.append('<sheetFormatPr defaultRowHeight="15"/>')
    if cols:
        x.append("<cols>")
        for i, w in enumerate(cols):
            x.append('<col min="%d" max="%d" width="%s" customWidth="1"/>' % (i + 1, i + 1, w))
        x.append("</cols>")
    x.append("<sheetData>")
    x.append(rows_xml)
    x.append("</sheetData>")
    if autofilter:
        x.append('<autoFilter ref="%s"/>' % autofilter)
    if cf:
        x.append(cf)
    if dv:
        x.append('<dataValidations count="%d">' % len(dv))
        for ref, items in dv:
            x.append('<dataValidation type="list" allowBlank="1" showInputMessage="1" '
                     'showErrorMessage="1" sqref="%s"><formula1>"%s"</formula1></dataValidation>' % (ref, items))
        x.append("</dataValidations>")
    x.append('<pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>')
    x.append("</worksheet>")
    return "".join(x)


def write_workbook(rows):
    # ── Test Cases ──
    HDR = ["Test ID", "Module", "Priority", "Method", "Endpoint", "Auth (route-level)",
           "Test Scenario", "Case Type", "Request Payload (JSON)", "Extra Params",
           "Exp. Status", "Expected Result", "Act. Status", "Actual Result", "Status",
           "Severity", "Defect ID", "Tester", "Date", "Remarks",
           "Request Type (ref)", "Handler (ref)", "Source File (ref)", "Alias Paths (ref)"]
    W = [14, 15, 8, 8, 46, 20, 32, 11, 64, 26, 10, 32, 10, 32, 11, 10, 11, 12, 12, 30, 30, 34, 44, 40]

    body = ['<row r="1" ht="30" customHeight="1">' +
            "".join(cell(1, i, h, 1) for i, h in enumerate(HDR)) + "</row>"]
    r = 2
    for d in rows:
        c = [cell(r, 0, d["id"], 2), cell(r, 1, d["module"], 2),
             cell(r, 2, d["priority"], 4), cell(r, 3, d["method"], 4),
             cell(r, 4, d["endpoint"], 2), cell(r, 5, d["auth"], 2),
             cell(r, 6, d["scenario"], 2), cell(r, 7, d["casetype"], 4),
             cell(r, 8, d["payload"], 3), cell(r, 9, d["notes"], 2),
             cell(r, 10, 200, 4, "n"), cell(r, 11, "", 2), cell(r, 12, "", 4),
             cell(r, 13, "", 2), cell(r, 14, "Not Run", 4), cell(r, 15, "", 4),
             cell(r, 16, "", 4), cell(r, 17, "", 2), cell(r, 18, "", 9),
             cell(r, 19, "", 2), cell(r, 20, d["bodytype"], 2),
             cell(r, 21, d["handler"], 2), cell(r, 22, d["file"], 2),
             cell(r, 23, d["aliases"], 2)]
        body.append('<row r="%d">%s</row>' % (r, "".join(c)))
        r += 1
    last = r - 1

    CF = ('<conditionalFormatting sqref="O2:O%d">'
          '<cfRule type="cellIs" dxfId="0" priority="1" operator="equal"><formula>"Pass"</formula></cfRule>'
          '<cfRule type="cellIs" dxfId="1" priority="2" operator="equal"><formula>"Fail"</formula></cfRule>'
          '<cfRule type="cellIs" dxfId="2" priority="3" operator="equal"><formula>"Blocked"</formula></cfRule>'
          '<cfRule type="cellIs" dxfId="3" priority="4" operator="equal"><formula>"Not Run"</formula></cfRule>'
          "</conditionalFormatting>"
          '<conditionalFormatting sqref="P2:P%d">'
          '<cfRule type="cellIs" dxfId="1" priority="5" operator="equal"><formula>"Critical"</formula></cfRule>'
          '<cfRule type="cellIs" dxfId="2" priority="6" operator="equal"><formula>"High"</formula></cfRule>'
          "</conditionalFormatting>") % (last, last)
    DV = [("C2:C%d" % last, "P1,P2,P3"),
          ("F2:F%d" % last, "AuthnzMiddleware,AuthnzCall,WalletKeyVerifier,None"),
          ("H2:H%d" % last, "Positive,Negative,Auth,Validation,Boundary"),
          ("O2:O%d" % last, "Pass,Fail,Blocked,Not Run,N/A"),
          ("P2:P%d" % last, "Critical,High,Medium,Low")]
    s1 = sheet(W, "".join(body), "A1:X%d" % last, freeze=(5, 1, "F2"),
               autofilter="A1:X%d" % last, dv=DV, cf=CF)

    # ── Summary ──
    pri = {d["module"]: d["priority"] for d in rows}
    b = ['<row r="1" ht="21" customHeight="1">' +
         cell(1, 0, "authnull-service — API Test Execution Summary", 5) + "</row>",
         '<row r="2">' + cell(2, 0,
         "All counts are formulas over the 'Test Cases' sheet — do not type into columns D–J.", 8) + "</row>"]
    SH = ["Module", "Priority", "Total Cases", "Pass", "Fail", "Blocked",
          "Not Run", "N/A", "% Pass", "% Executed"]
    b.append('<row r="4" ht="28" customHeight="1">' +
             "".join(cell(4, i, h, 1) for i, h in enumerate(SH)) + "</row>")
    r = 5
    q = "'Test Cases'!$B$2:$B$%d" % last
    st = "'Test Cases'!$O$2:$O$%d" % last
    for m in MODORDER:
        c = [cell(r, 0, m, 2), cell(r, 1, pri.get(m, ""), 4),
             cell(r, 2, "COUNTIF(%s,$A%d)" % (q, r), 4, "f"),
             cell(r, 3, 'COUNTIFS(%s,$A%d,%s,"Pass")' % (q, r, st), 4, "f"),
             cell(r, 4, 'COUNTIFS(%s,$A%d,%s,"Fail")' % (q, r, st), 4, "f"),
             cell(r, 5, 'COUNTIFS(%s,$A%d,%s,"Blocked")' % (q, r, st), 4, "f"),
             cell(r, 6, 'COUNTIFS(%s,$A%d,%s,"Not Run")' % (q, r, st), 4, "f"),
             cell(r, 7, 'COUNTIFS(%s,$A%d,%s,"N/A")' % (q, r, st), 4, "f"),
             cell(r, 8, "IFERROR(D%d/($C%d-$H%d),0)" % (r, r, r), 11, "f"),
             cell(r, 9, "IFERROR(($C%d-$G%d)/$C%d,0)" % (r, r, r), 11, "f")]
        b.append('<row r="%d">%s</row>' % (r, "".join(c)))
        r += 1
    tr = r
    c = [cell(tr, 0, "TOTAL", 6), cell(tr, 1, "", 10)]
    for i, cl in enumerate("CDEFGH"):
        c.append(cell(tr, 2 + i, "SUM(%s5:%s%d)" % (cl, cl, tr - 1), 10, "f"))
    c.append(cell(tr, 8, "IFERROR(D%d/($C%d-$H%d),0)" % (tr, tr, tr), 11, "f"))
    c.append(cell(tr, 9, "IFERROR(($C%d-$G%d)/$C%d,0)" % (tr, tr, tr), 11, "f"))
    b.append('<row r="%d">%s</row>' % (tr, "".join(c)))

    r = tr + 2
    b.append('<row r="%d">%s</row>' % (r, cell(r, 0, "Breakdown by case type", 12)))
    r += 1
    b.append('<row r="%d">%s</row>' % (r, "".join(cell(r, i, h, 1) for i, h in enumerate(
        ["Case Type", "Total", "Pass", "Fail", "Blocked", "Not Run"]))))
    r += 1
    qh = "'Test Cases'!$H$2:$H$%d" % last
    for ct in ["Positive", "Negative", "Auth", "Validation", "Boundary"]:
        c = [cell(r, 0, ct, 2), cell(r, 1, "COUNTIF(%s,$A%d)" % (qh, r), 4, "f")]
        for i, sv in enumerate(["Pass", "Fail", "Blocked", "Not Run"]):
            c.append(cell(r, 2 + i, 'COUNTIFS(%s,$A%d,%s,"%s")' % (qh, r, st, sv), 4, "f"))
        b.append('<row r="%d">%s</row>' % (r, "".join(c)))
        r += 1
    r += 1
    b.append('<row r="%d">%s</row>' % (r, cell(r, 0, "Open defects", 12)))
    r += 1
    for lbl, f in [("Total raised", "COUNTA(Defects!$A$4:$A$500)"),
                   ("Critical open", 'COUNTIFS(Defects!$I$4:$I$500,"Critical",Defects!$K$4:$K$500,"Open")'),
                   ("High open", 'COUNTIFS(Defects!$I$4:$I$500,"High",Defects!$K$4:$K$500,"Open")'),
                   ("Closed", 'COUNTIF(Defects!$K$4:$K$500,"Closed")')]:
        b.append('<row r="%d">%s%s</row>' % (r, cell(r, 0, lbl, 6), cell(r, 1, f, 4, "f")))
        r += 1
    s2 = sheet([26, 11, 13, 9, 9, 11, 11, 9, 10, 12], "".join(b), "A1:J%d" % r)

    # ── Defects ──
    DH = ["Defect ID", "Test ID", "Module", "Endpoint", "Summary",
          "Steps to Reproduce", "Expected", "Actual", "Severity", "Priority",
          "Status", "Assigned To", "Raised On", "Closed On", "Notes"]
    DW = [12, 15, 15, 44, 40, 52, 30, 30, 11, 10, 11, 14, 12, 12, 30]
    b = ['<row r="1" ht="21" customHeight="1">' + cell(1, 0, "Defect Log", 5) + "</row>",
         '<row r="3" ht="28" customHeight="1">' +
         "".join(cell(3, i, h, 1) for i, h in enumerate(DH)) + "</row>"]
    NB = 200
    for r in range(4, 4 + NB):
        c = [cell(r, i, "", 9 if i in (12, 13) else 4 if i in (8, 9, 10) else 2)
             for i in range(len(DH))]
        b.append('<row r="%d">%s</row>' % (r, "".join(c)))
    lastd = 3 + NB
    DDV = [("I4:I%d" % lastd, "Critical,High,Medium,Low"),
           ("J4:J%d" % lastd, "P1,P2,P3"),
           ("K4:K%d" % lastd, "Open,In Progress,Fixed,Retest,Closed,Won't Fix,Duplicate"),
           ("C4:C%d" % lastd, ",".join(MODORDER[:12]))]
    DCF = ('<conditionalFormatting sqref="I4:I%d">'
           '<cfRule type="cellIs" dxfId="1" priority="1" operator="equal"><formula>"Critical"</formula></cfRule>'
           '<cfRule type="cellIs" dxfId="2" priority="2" operator="equal"><formula>"High"</formula></cfRule>'
           "</conditionalFormatting>"
           '<conditionalFormatting sqref="K4:K%d">'
           '<cfRule type="cellIs" dxfId="0" priority="3" operator="equal"><formula>"Closed"</formula></cfRule>'
           '<cfRule type="cellIs" dxfId="1" priority="4" operator="equal"><formula>"Open"</formula></cfRule>'
           "</conditionalFormatting>") % (lastd, lastd)
    s3 = sheet(DW, "".join(b), "A1:O%d" % lastd, freeze=(1, 3, "B4"),
               autofilter="A3:O%d" % lastd, dv=DDV, cf=DCF)

    # ── Environment ──
    b = []
    state = {"r": 1}

    def row(xml):
        b.append('<row r="%d">%s</row>' % (state["r"], xml))
        state["r"] += 1

    b.append('<row r="1" ht="21" customHeight="1">%s</row>' %
             cell(1, 0, "Test Environment & Sign-off", 5))
    state["r"] = 3

    def sect(title):
        row(cell(state["r"], 0, title, 12))

    def kv(k, v=""):
        row(cell(state["r"], 0, k, 6) + cell(state["r"], 1, v, 7))

    sect("Build under test")
    for k, v in [("Base URL", "http://localhost:8080"), ("Branch", "on-prem"),
                 ("Commit SHA", ""), ("Build date", ""),
                 ("Deployment", "docker-compose"), ("Go version", "1.25.8")]:
        kv(k, v)
    state["r"] += 1
    sect("Dependencies")
    for k in ["PostgreSQL host / version", "Redis host / version",
              "authnz service URL (AUTHNZ_URL)", "SSC URL (SSC_URL)",
              "LDAP / AD domain used", "SMTP host (email OTP)"]:
        kv(k)
    state["r"] += 1
    sect("Session context — fill these in FIRST")
    row(cell(state["r"], 0,
        "Run org/orgsignup -> org/orglogin -> tenant/tenantlogin before anything else, then record the "
        "values below. Most payloads need orgId / tenantId and every AuthnzMiddleware route needs the token.", 8))
    state["r"] += 1
    for k in ["Test org name", "Test org ID (orgId)", "Test tenant ID (tenantId)",
              "Test domain ID (domainId)", "Test user email", "Test user password",
              "Session token (X-Authorization)", "Token format",
              "X-RequestUrl value", "Wallet key (WalletKeyVerifier routes)"]:
        kv(k)
    state["r"] += 1
    sect("Scope")
    kv("Total endpoints in build", str(len(rows)))
    for k in ["Endpoints in scope", "Modules excluded", "Exclusion reason"]:
        kv(k)
    state["r"] += 1
    sect("Auth column — how to read it")
    counts = collections.Counter(d["auth"] for d in rows)
    for k, v in [
        ("AuthnzMiddleware", "%d routes. Session validated by pkg/middleware. Requires X-Authorization." % counts["AuthnzMiddleware"]),
        ("AuthnzCall", "%d routes (dashboard, database). Same, different middleware entry point." % counts["AuthnzCall"]),
        ("WalletKeyVerifier", "%d routes (endpoint/*). Requires the agent wallet key, not a session token." % counts["WalletKeyVerifier"]),
        ("None", "%d routes have NO route-level middleware. This does NOT mean unauthenticated — several check "
                 "X-Authorization inside the handler. Verify per endpoint and raise a defect if genuinely open." % counts["None"]),
    ]:
        kv(k, v)
    state["r"] += 1
    sect("Sign-off")
    for k in ["Tested by", "Reviewed by", "Test start date", "Test end date",
              "Result (Pass / Pass with issues / Fail)", "Comments"]:
        kv(k)
    s4 = sheet([38, 86], "".join(b), "A1:B%d" % state["r"])

    # ── package ──
    SHEETS = [("Test Cases", s1), ("Summary", s2), ("Defects", s3), ("Environment", s4)]
    wb = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ',
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>']
    for i, (n, _) in enumerate(SHEETS):
        wb.append('<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % (n, i + 1, i + 1))
    wb.append('</sheets><calcPr calcId="0" fullCalcOnLoad="1"/></workbook>')

    rels = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">']
    for i, _ in enumerate(SHEETS):
        rels.append('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                    'relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % (i + 1, i + 1))
    rels.append('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                'relationships/styles" Target="styles.xml"/>' % (len(SHEETS) + 1))
    rels.append("</Relationships>")

    ct = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
          '<Default Extension="xml" ContentType="application/xml"/>',
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.sheet.main+xml"/>',
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.styles+xml"/>']
    for i in range(len(SHEETS)):
        ct.append('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.'
                  'openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % (i + 1))
    ct.append("</Types>")

    root_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                 'relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", "".join(ct))
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", "".join(wb))
        z.writestr("xl/_rels/workbook.xml.rels", "".join(rels))
        z.writestr("xl/styles.xml", STYLES)
        for i, (_, s) in enumerate(SHEETS):
            z.writestr("xl/worksheets/sheet%d.xml" % (i + 1), s)


def main():
    if not os.path.exists(INVENTORY):
        sys.exit("missing %s" % INVENTORY)
    rows = build_rows()
    write_workbook(rows)
    counts = collections.Counter(d["auth"] for d in rows)
    print("wrote %s" % OUT)
    print("test cases: %d" % len(rows))
    print("auth breakdown: %s" % dict(counts))


if __name__ == "__main__":
    main()
