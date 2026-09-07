#!/usr/bin/env python3
"""Build the MOAUM portal prototype.

part6.html is ALWAYS LAST — it closes the IIFE and calls render().
Every other part is concatenated in numeric order, with the lettered
suffixes (4b, 4c, 5b) sitting immediately after the part they extend.
"""
import base64, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)

order = (["part1.html", "part2.html", "part3.html",
          "part4.html", "part4b.html", "part4c.html",
          "part5.html", "part5b.html"]
         + ["part%d.html" % n for n in range(7, 56)]
         + ["part6.html"])

missing = [f for f in order if not os.path.exists(f)]
if missing:
    sys.exit("missing: " + ", ".join(missing))

have = sorted(f for f in os.listdir(".") if re.match(r"^part[\d]+[a-c]?\.html$", f))
unused = [f for f in have if f not in order]
if unused:
    sys.exit("part files not in the build order: " + ", ".join(unused))

# newline="" keeps whatever the checkout has; CRLF is then folded to LF so a
# Windows checkout builds the same bytes as Linux and CI.
raw = "".join(open(f, encoding="utf-8", newline="").read() for f in order).replace("\r\n", "\n")
open("_raw.html", "w", encoding="utf-8", newline="").write(raw)

# duplicate top-level declaration scan — two definitions of one name is
# the failure this build has hit most often
names = re.findall(r"^  (?:var|function)\s+([A-Za-z_$][\w$]*)", raw, re.M)
dup = sorted({n for n in names if names.count(n) > 1})
print("%d declarations, %d duplicated%s" %
      (len(set(names)), len(dup), (": " + ", ".join(dup)) if dup else ""))

crest = base64.b64encode(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "moaum-crest.png"), "rb").read()).decode()
html = raw.replace("__CREST__", "data:image/png;base64," + crest)

assert html.count("\n  render();\n}());") == 1, "boot call not found exactly once"

open("moaum-portal-prototype.html", "w", encoding="utf-8", newline="").write(html)

# Written to _hooks.html, NOT _pv.html: every harness builds its own _pv.html
# from the clean prototype and would clobber this one. Two files under one
# name is a race whose loser is silent.
HOOK = ("  window.__S = S; window.__render = render; window.__SCREENS = SCREENS;\n"
        "  window.__ROLES = ROLES; window.__ROLE_KEYS = ROLE_KEYS;\n"
        "  window.__PROGT = PROGT; window.__JNAME = JNAME;\n"
        "  window.__TBLDOM = TBLDOM; window.__tblApply = tblApply;\n"
        "  window.__ADM_SRC = ADM_SRC;\n"
        "  window.__PROG_RULE_COUNT = function () {\n"
        "    return Object.keys(PROGT).filter(function (c) { return ADM_SRC.rules[c]; }).length; };\n\n  render();")
open("_hooks.html", "w", encoding="utf-8", newline="").write(html.replace("\n  render();\n}());",
                                         "\n" + HOOK + "\n}());"))

print("moaum-portal-prototype.html  %d lines, %.1f KB"
      % (html.count("\n") + 1, len(html) / 1024))
if dup:
    sys.exit(1)
