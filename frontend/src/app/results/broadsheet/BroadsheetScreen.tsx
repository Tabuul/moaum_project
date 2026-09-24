"use client";

/** tBroadsheet — proto/part26.html: every candidate in one programme at one level, across all their courses. */
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, type Broadsheet } from "@/lib/results";
import { loadCrest } from "@/lib/xlsx";
import { colName, xlsx, type Cell } from "@/lib/xlsx-write";
import { docSerial } from "@/lib/exportbrand";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const COLOUR = (points: number | null | undefined) => (points == null ? "var(--muted)" : points >= 4 ? "var(--green-ink)" : points >= 1 ? "var(--chrome)" : "var(--red-ink)");
const UNI = "Rev. Fr. Moses Orshio Adasu University, Makurdi";
const escd = (s: string) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c] ?? c);

export function BroadsheetScreen({ scope, structure, sessions, sheet }: { scope: Scope; structure: ScopeStructure; sessions: string[]; sheet: Broadsheet | null }) {
  const programme = structure.faculties.flatMap((f) => f.departments).flatMap((d) => d.programmes).find((p) => p.code === scope.prog);
  const semester = (scope.sem || "1") === "1" ? "First" : "Second";
  /* the course columns in the Senate's order: carryover courses (a course from a lower level, re-written
     this semester), then the core courses with the GST courses leading them, then elective */
  const lvl = Number(sheet?.level ?? 0);
  const isCarryCourse = (c: { level: number }) => Number(c.level) > 0 && Number(c.level) < lvl;
  const carryC = sheet ? sheet.courses.filter(isCarryCourse) : [];
  const gst = sheet ? sheet.courses.filter((c) => !isCarryCourse(c) && c.kind === "GST") : [];
  const core = sheet ? sheet.courses.filter((c) => !isCarryCourse(c) && c.kind !== "GST" && c.kind !== "Elective") : [];
  const elec = sheet ? sheet.courses.filter((c) => !isCarryCourse(c) && c.kind === "Elective") : [];
  const bands: [string, typeof core][] = ([["CARRYOVER COURSES", carryC], ["CORE COURSES", [...gst, ...core]], ["ELECTIVE COURSES", elec]] as [string, typeof core][]).filter((b) => b[1].length > 0);
  const markOf = (r: Broadsheet["rows"][number], code: string) => r.marks.find((m) => m.courseCode === code);
  const fx = (n: number | null) => (n === null || n === undefined ? "—" : Number(n).toFixed(2));
  /** the grade carries its weight: A5, B4, C3, D2, E1, F0 */
  const gw = (grade: string | null | undefined, points: number | null | undefined) =>
    grade == null ? "" : points == null ? grade : `${grade}${Number.isInteger(Number(points)) ? Number(points) : Number(points).toFixed(2)}`;
  /** a mark as text, the grade under the score — "75\nA5"; ABS over F0 for a candidate who did not sit; a score still in
   *  the chain marked as not yet counted */
  const markText = (m: ReturnType<typeof markOf>): string =>
    !m || m.stage === "NOT_REGISTERED" ? ""
      : m.counted ? (m.total == null ? "ABS\nF0" : `${m.total}\n${gw(m.grade, m.points)}`)
      : m.total != null ? `${m.total}\n${gw(m.grade, m.points)}\n(not yet counted)`
      : m.outcome && m.outcome !== "GRADED" && m.outcome !== "ABSENT" ? m.outcome.slice(0, 3)
      : "ABS\nF0";
  const cell = (m: ReturnType<typeof markOf>) =>
    !m || m.stage === "NOT_REGISTERED" ? <span className="sub2">—</span>
      : m.counted ? (m.total == null
          ? <span style={{ color: "var(--red-ink)", fontWeight: 700 }}><span className="tnum">ABS</span><div>F0</div></span>
          : <span><span className="tnum">{m.total}</span><div style={{ color: COLOUR(m.points), fontWeight: 700 }}>{gw(m.grade, m.points)}</div></span>)
      : m.total != null ? <span className="sub2" title={`${STAGE_LABEL[m.stage]?.[0] ?? m.stage} — not yet counted`}><span className="tnum">{m.total}</span><div style={{ fontWeight: 700 }}>{gw(m.grade, m.points)}</div></span>
      : m.outcome && m.outcome !== "GRADED" && m.outcome !== "ABSENT" ? <span className="sub2" title={m.outcome.toLowerCase()}>{m.outcome.slice(0, 3)}</span>
      : <span title={STAGE_LABEL[m.stage]?.[0] ?? m.stage} style={{ color: "var(--red-ink)", fontWeight: 700 }}><span className="tnum">ABS</span><div>F0</div></span>;
  const orderCols = bands.flatMap((b) => b[1]);
  /* from 200 level the sheet is in three lists: the class with no question of probation; at 200 level first
     semester the Direct Entry students, whose first semester this is (no standing to judge yet); and the
     PROBATION LIST — every student whose CGPA is under 1.0. Probation is pronounced in the first semester of every
     level above 100; at 100 level, and in every second semester, there is one list. */
  // probation is pronounced in the first semester of every level above 100: only then is the sheet in lists
  const sectioned = !!sheet && Number(sheet.level) >= 200 && Number(sheet.semester) === 1;
  const deSection = !!sheet && Number(sheet.level) === 200 && Number(sheet.semester) === 1;
  const isDE = (r: Broadsheet["rows"][number]) => deSection && r.entryMode === "DIRECT_ENTRY";
  const onProbation = (r: Broadsheet["rows"][number]) => sectioned && !isDE(r) && r.cgpa !== null && Number(r.cgpa) < 1.0;
  const sections: { title: string; rows: Broadsheet["rows"] }[] = !sheet ? [] : !sectioned ? [{ title: "", rows: sheet.rows }] : [
    { title: "", rows: sheet.rows.filter((r) => !isDE(r) && !onProbation(r)) },
    ...(deSection ? [{ title: "DIRECT ENTRY STUDENTS", rows: sheet.rows.filter(isDE) }] : []),
    { title: "PROBATION LIST", rows: sheet.rows.filter(onProbation) },
  ];
  /* the matriculation number's prefix (everything up to the last oblique) is the class's, shared by nearly every
     row: it sits under the MATRIC NO. heading once, and each cell carries the serial alone. A row whose number
     does not share the prefix — a transfer, an old-format number — shows in full. */
  const prefixOf = (n: string) => n.slice(0, n.lastIndexOf("/") + 1);
  const matricPrefix = (() => {
    if (!sheet) return "";
    const counts = new Map<string, number>();
    for (const r of sheet.rows) { const p = prefixOf(r.number); if (p) counts.set(p, (counts.get(p) ?? 0) + 1); }
    return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
  })();
  /* a carryover candidate from another year shares the prefix up to the year: they show as year/serial (22/65244) */
  const matricBase = matricPrefix ? matricPrefix.replace(/[^/]+\/$/, "") : "";
  const serialOf = (n: string) =>
    matricPrefix && n.startsWith(matricPrefix) ? n.slice(matricPrefix.length)
      : matricBase && n.startsWith(matricBase) ? n.slice(matricBase.length)
      : n;

  /* the CARRYOVER COURSES band already names each carryover course with the candidate's mark in it, so the
     separate CARRYOVER column said the same thing twice; it is not shown. The Cumulative band is only empty
     in 100 level first semester (nothing before it); 100 level second semester already has a standing. */
  const hideCarryover = true;
  const hideCum = Number(sheet?.level) === 100 && Number(sheet?.semester) === 1;

  /* the cover ("Examination Reporting Sheet") data, shared by the on-screen panel and the exports */
  const cov = sheet ? (() => {
    const fac = structure.faculties.find((f) => f.departments.some((d) => d.programmes.some((p) => p.code === scope.prog)));
    const dept = fac?.departments.find((d) => d.programmes.some((p) => p.code === scope.prog));
    const roll = sheet.rows.length;
    const sat = sheet.rows.filter((r) => r.gpa !== null).length;
    const notSit = roll - sat;
    // probation and withdrawal are judged on a cumulative standing, which a 100 level class does not yet have:
    // at 100 level both rows read Nil with no percentage; from 200 level first semester they are counted
    const standingApplies = Number(sheet.level) >= 200 && Number(sheet.semester) === 1;
    const probation = standingApplies ? sheet.rows.filter(onProbation).length : 0;   // the PROBATION LIST
    const withdraw = 0;   // no rule in force names a CGPA at which a candidate is advised to withdraw
    const pc = (n: number) => (sat ? `${Math.round((100 * n) / sat)}%` : "");
    const n0 = (n: number) => (n === 0 ? "Nil" : String(n));
    const SUM: [string, string, string][] = [
      ["Total Number of Candidates on Roll", String(roll), ""],
      ["Total Number of Candidates that Registered", String(roll), ""],
      ["Total Number of Candidates that did not Register", "Nil", ""],
      ["Total Number of Candidates at Examination", String(sat), sat ? "100" : ""],
      ["Total Number of Candidates that did not sit for the Examination", n0(notSit), notSit ? pc(notSit) : ""],
      ["Total Number of Candidates with Pass", String(sheet.passed), pc(sheet.passed)],
      ["Total Number of Candidates that Deferred", "Nil", ""],
      ["Total Number of Candidates with Carryover/Fail", String(sheet.carrying), pc(sheet.carrying)],
      ["Total Number of Candidates on Probation", n0(probation), standingApplies && probation ? pc(probation) : ""],
      ["Total Number of Candidates Advised to Withdraw", n0(withdraw), standingApplies && withdraw ? pc(withdraw) : ""],
      ["Total Number of Candidates Expelled", "Nil", ""],
    ];
    const KEY: [string, string][] = hideCum ? [
      ["CUR", "Credit Units Registered"], ["CUE", "Credit Units Earned"],
      ["GPA", "Grade Point Average"], ["WGP", "Weighted Grade Point"],
    ] : [
      ["CUR", "Credit Units Registered"], ["CUE", "Credit Units Earned"], ["WGP", "Weighted Grade Point"],
      ["GPA", "Grade Point Average"], ["TCR", "Total Credits Registered"], ["TCE", "Total Credits Earned"],
      ["TWGP", "Total Weighted Grade Point"], ["LCGPA", "Last Cumulative Grade Point Average"], ["CGPA", "Cumulative Grade Point Average"],
    ];
    return { facName: fac?.name ?? "—", deptName: dept?.name ?? "—", degree: programme?.name ?? sheet.programme, SUM, KEY };
  })() : null;

  const bsRow = (r: Broadsheet["rows"][number], i: number): Cell[] => [i + 1, serialOf(r.number), r.name,
    ...(hideCarryover ? [] : [r.carryovers.join(" ")]),
    ...orderCols.map((c) => markText(markOf(r, c.courseCode))),
    r.cur, r.cue, r.points, r.gpa ?? "", ...(hideCum ? [] : [r.tcr, r.tce, r.twgp, r.lcgpa ?? "", r.cgpa ?? ""]), r.remarks];

  async function exportExcel() {
    if (!sheet || !cov) return;
    const logo = await loadCrest();
    const serial = docSerial("BRD");
    const head = (t: string): Cell[][] => [[null, UNI], [null, t],
      [null, `${cov.degree} · ${sheet.level} Level · ${semester} semester · ${sheet.session} · Serial ${serial}`],
      [null, `Faculty of ${cov.facName} · Department of ${cov.deptName}`],
      [null, `Generated ${new Date().toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" })} from the register`], [], []];
    const summary: Cell[][] = [...head("Examination Reporting Sheet"),
      ["Faculty", cov.facName], ["Department", cov.deptName], ["Degree in view", cov.degree],
      ["Level", sheet.level], ["Semester", semester], ["Session", sheet.session], [],
      ["Summary of results", "", "%"], ...cov.SUM.map((s) => [s[0], s[1], s[2]] as Cell[]), [],
      ["Key", ""], ...cov.KEY.map((k) => [k[0], k[1]] as Cell[]), [],
      ["Courses", "", ""], ["Code", "Title", "Units"], ...orderCols.map((c) => [c.courseCode, c.title, c.units] as Cell[])];
    /* the heading as it stands on screen: two rows — S/N, MATRIC NO. (with the class's prefix), NAME OF CANDIDATE and
       REMARKS spanning both; the course bands and CURRENT and CUMULATIVE DATE over their columns; each course's code
       over its units — with the ranges merged. The heading is repeated for each list, with its own merges. */
    const broad: Cell[][] = [...head(`Broadsheet — ${cov.degree}, ${sheet.level} Level, ${semester} semester`)];
    const headerRows: number[] = [];
    const merges: string[] = [];
    const nCur = 4, nCum = hideCum ? 0 : 5;
    for (const sec of sections) {
      if (sec.title) { broad.push([], [sec.title]); }
      const r1 = broad.length, r2 = r1 + 1;           // 0-based indices of the two heading rows
      const top: Cell[] = ["S/N", `MATRIC NO.${matricPrefix ? "\n" + matricPrefix : ""}`, "NAME OF CANDIDATE"];
      const sub: Cell[] = ["", "", ""];
      let c = 3;
      const span = (label: string, n: number) => { if (!n) return; top.push(label); for (let k = 1; k < n; k++) top.push(""); if (n > 1) merges.push(`${colName(c)}${r1 + 1}:${colName(c + n - 1)}${r1 + 1}`); c += n; };
      for (const [label, list] of bands) { span(label, list.length); for (const co of list) sub.push(`${co.courseCode}\n${co.units}`); }
      span("CURRENT", nCur); sub.push("CUR", "CUE", "WGP", "GPA");
      if (!hideCum) { span("CUMULATIVE DATE", nCum); sub.push("TCR", "TCE", "TWGP", "LCGPA", "CGPA"); }
      top.push("REMARKS"); sub.push("");
      for (const col of [0, 1, 2, c]) merges.push(`${colName(col)}${r1 + 1}:${colName(col)}${r2 + 1}`);
      headerRows.push(r1, r2);
      broad.push(top, sub, ...sec.rows.map((r, i) => bsRow(r, i)));
      if (!sec.rows.length) broad.push(["None"]);
    }
    const book = xlsx([["Summary", summary], ["Broadsheet", broad, { headerRows, merges }]], { logo: logo ?? undefined });
    const blob = new Blob([book.buffer as ArrayBuffer], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `Result ${cov.degree} ${sheet.level}L ${sheet.session.replace("/", "-")} ${semester}.xlsx`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  function exportPdf() {
    if (!sheet || !cov) return;
    const crest = location.origin + "/crest.png";
    const serial = docSerial("BRD");
    const sumRows = cov.SUM.map((s) => `<tr><td>${escd(s[0])}</td><td class="n">${escd(String(s[1]))}</td><td class="p">${escd(s[2])}</td></tr>`).join("");
    const keyRows = cov.KEY.map((k) => `<tr><td class="ab">${k[0]}</td><td>${escd(k[1])}</td></tr>`).join("");
    const courseCells = (list: typeof sheet.courses) =>
      `<tr><td class="ab ch">Course Code</td><td class="ch">Course Title</td><td class="u ch">Credit Units</td></tr>`
      + list.map((c) => `<tr><td class="ab">${escd(c.courseCode)}</td><td>${escd(c.title)}</td><td class="u">${c.units}</td></tr>`).join("");
    const half = Math.ceil(orderCols.length / 2);
    const courseTwoCol = `<div class="cols2"><table class="t"><tbody>${courseCells(orderCols.slice(0, half))}</tbody></table>`
      + `<table class="t"><tbody>${courseCells(orderCols.slice(half))}</tbody></table></div>`;
    const gh = `<tr><th rowspan="2">S/N</th><th rowspan="2">MATRIC NO.${matricPrefix ? `<br><span style="font-weight:400;text-transform:none">${escd(matricPrefix)}</span>` : ""}</th><th rowspan="2">NAME OF CANDIDATE</th>${hideCarryover ? "" : `<th rowspan="2">CARRYOVER</th>`}`
      + bands.map((b) => `<th colspan="${b[1].length}">${b[0]}</th>`).join("")
      + `<th colspan="4">CURRENT</th>${hideCum ? "" : `<th colspan="5">CUMULATIVE DATE</th>`}<th rowspan="2">REMARKS</th></tr>`
      + `<tr>${orderCols.map((c) => `<th>${escd(c.courseCode)}<br>${c.units}</th>`).join("")}<th>CUR</th><th>CUE</th><th>WGP</th><th>GPA</th>${hideCum ? "" : `<th>TCR</th><th>TCE</th><th>TWGP</th><th>LCGPA</th><th>CGPA</th>`}</tr>`;
    const bodyOf = (list: Broadsheet["rows"]) => list.map((r, i) => `<tr><td>${i + 1}</td><td class="mt">${escd(serialOf(r.number))}</td><td class="nm">${escd(r.name)}</td>${hideCarryover ? "" : `<td class="co">${escd(r.carryovers.join(", ") || "—")}</td>`}`
      + orderCols.map((c) => { const m = markOf(r, c.courseCode); const t = markText(m); const v = !t ? "" : t === "ABS\nF0" ? "<b>ABS</b><br><b>F0</b>" : m!.counted ? `${m!.total}<br><b>${escd(gw(m!.grade, m!.points))}</b>` : t.includes("(not yet counted)") ? `<span style="color:#777">${m!.total}<br>${escd(gw(m!.grade, m!.points))}</span>` : escd(t); return `<td>${v}</td>`; }).join("")
      + `<td>${r.cur}</td><td>${r.cue}</td><td>${r.points}</td><td class="b">${fx(r.gpa)}</td>${hideCum ? "" : `<td>${r.tcr}</td><td>${r.tce}</td><td>${r.twgp}</td><td>${fx(r.lcgpa)}</td><td class="b">${fx(r.cgpa)}</td>`}<td class="co">${escd(r.remarks)}</td></tr>`).join("");
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>Result ${escd(cov.degree)} ${escd(sheet.session)}</title><style>
      body{font:12px system-ui,Arial,sans-serif;color:#111;padding:22px}
      .head{text-align:center;margin-bottom:14px}.head img{height:56px}.uni{font-weight:700;font-size:16px}.st{text-transform:uppercase;letter-spacing:.06em;text-decoration:underline;font-size:12px;color:#444}
      .meta{display:grid;grid-template-columns:1fr 1fr;gap:2px 30px;font-size:12px;margin:12px 0}.meta div{display:flex;gap:8px}.meta .k{min-width:110px;color:#555;text-transform:uppercase;font-size:10px}
      h3{font-size:12px;text-transform:uppercase;text-decoration:underline;margin:14px 0 6px}
      .cols{display:grid;grid-template-columns:1.6fr 1fr;gap:24px}
      .cols2{display:grid;grid-template-columns:1fr 1fr;gap:24px}
      .t td.ch{font-weight:700;text-transform:uppercase;font-size:10px;color:#333;border-bottom:1px solid #999}
      table{border-collapse:collapse;width:100%}.t td{padding:2px 6px;font-size:11.5px;vertical-align:top}.t td.n,.t td.p{text-align:right;width:40px}.t td.ab{font-family:monospace;font-weight:700}
      .bs{border-collapse:collapse;width:100%;margin-top:8px}.bs th,.bs td{border:1px solid #bbb;padding:3px 5px;text-align:center;font-size:10.5px}.bs td.nm,.bs td.co{text-align:left}
      .bs td.b{font-weight:700}.bs td.mt{white-space:nowrap;width:1%}.bs td.nm{white-space:nowrap}.bs td.co{min-width:150px}.sign{display:grid;grid-template-columns:1fr 1fr;gap:40px;margin-top:28px}.sign .role{font-style:italic;font-weight:600}.sign .ln{border-bottom:1px dotted #999;color:#555;padding:6px 0 2px;margin-bottom:6px}
      @media print{.pb{page-break-before:always}}</style></head><body>
      <div class="head"><img src="${crest}" alt=""><div class="uni">${escd(UNI)}</div><div class="st">Examination Reporting Sheet</div><div style="font-size:10px;color:#555;margin-top:3px">Serial ${escd(serial)} · generated ${escd(new Date().toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }))}</div></div>
      <div class="meta"><div><span class="k">Faculty</span><b>${escd(cov.facName)}</b></div><div><span class="k">Level</span><b>${sheet.level}</b></div>
        <div><span class="k">Department</span><b>${escd(cov.deptName)}</b></div><div><span class="k">Semester</span><b>${semester}</b></div>
        <div><span class="k">Degree in view</span><b>${escd(cov.degree)}</b></div><div><span class="k">Session</span><b>${escd(sheet.session)}</b></div></div>
      <div class="cols"><div><h3>Summary of results</h3><table class="t"><tbody>${sumRows}</tbody></table></div><div><h3>Key</h3><table class="t"><tbody>${keyRows}</tbody></table></div></div>
      <h3>Courses</h3>${courseTwoCol}
      <div class="sign"><div><div class="role">Dean of Faculty</div><div class="ln">Name</div><div class="ln">Sign</div><div class="ln">Date</div></div>
        <div><div class="role">Head of Department</div><div class="ln">Name</div><div class="ln">Sign</div><div class="ln">Date</div></div></div>
      <div class="pb"></div>
      ${sections.map((sec) => `${sec.title ? `<h3>${escd(sec.title)} · ${sec.rows.length}</h3>` : ""}<table class="bs"><thead>${gh}</thead><tbody>${sec.rows.length ? bodyOf(sec.rows) : `<tr><td colspan="40" style="text-align:left">None</td></tr>`}</tbody></table>`).join("")}</body></html>`;
    const w = window.open("", "_blank");
    if (!w) { return; }
    w.document.write(html);
    w.document.close();
    w.focus();
    setTimeout(() => w.print(), 350);
  }

  return (
    <>
      <Note kind="info" title="The broadsheet is computed, not typed">
        Every figure on this sheet comes from the score sheets and the grading scheme in force for the session. Nobody keys a GPA. A mark counts here once its set has passed the Faculty Board; a score still in the chain shows greyed as not yet counted, and the GPA is computed over what is approved so far. A candidate with no score on a counted set did not sit: ABS, graded F, and the course is owed. The remark reads CO: for a core course owed, Fail: for an elective failed, and TO GO ON PROBATION when the CGPA is under 1.0.
      </Note>
      <Note kind="info" title="A broadsheet is by programme and level. A score sheet is by course.">
        A score sheet carries every candidate registered for one course, from every programme the course was made available to. A broadsheet carries every candidate in one programme at one level, across all their courses, because a GPA belongs to a student in a programme.
      </Note>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="the broadsheet" count={sheet?.rows.length ?? 0} of={sheet?.rows.length ?? 0}
        onExport={sheet ? () => void exportExcel() : undefined} />
      {!sheet ? (
        <Note kind="info" title="Choose a programme and a level">The broadsheet is one programme at one level in one semester. Pick them in the bar above; the session and semester are the ones the bar holds.</Note>
      ) : (
        <>
          <Tiles items={[
            ["Candidates", String(sheet.rows.length), null, `${sheet.level} Level · ${semester} semester`],
            ["Mean GPA", sheet.meanGpa == null ? "—" : Number(sheet.meanGpa).toFixed(2), null, sheet.meanGpa == null ? "No approved set yet" : "Unweighted, this level"],
            ["Passed every course", String(sheet.passed), "var(--green-ink)", sheet.rows.length ? `${Math.round((100 * sheet.passed) / sheet.rows.length)}% of the level` : "—"],
            ["Carrying over", String(sheet.carrying), sheet.carrying ? "var(--red-ink)" : null, sheet.pendingSets ? `${sheet.pendingSets} set${sheet.pendingSets === 1 ? "" : "s"} still in the chain` : "One or more F grades"],
          ]} />
          {cov ? (
            <Panel title="Examination reporting sheet" right={<span style={{ display: "inline-flex", gap: 8 }}><Btn kind="ghost" onClick={() => void exportExcel()}>Download Excel</Btn><Btn kind="primary" onClick={exportPdf}>Download PDF</Btn></span>}>
              <PBody>
                <div className="ers">
                  <div className="ers__title">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src="/crest.png" alt="University crest" className="ers__crest" />
                    <div className="ers__uni">{UNI}</div>
                    <div className="ers__sub">Examination Reporting Sheet</div>
                  </div>
                  <div className="ers__meta">
                    <div>
                      <div><span className="k">Faculty</span><b>{cov.facName}</b></div>
                      <div><span className="k">Department</span><b>{cov.deptName}</b></div>
                      <div><span className="k">Degree in view</span><b>{cov.degree}</b></div>
                    </div>
                    <div>
                      <div><span className="k">Level</span><b>{sheet.level}</b></div>
                      <div><span className="k">Semester</span><b>{semester}</b></div>
                      <div><span className="k">Session</span><b className="tnum">{sheet.session}</b></div>
                    </div>
                  </div>
                  <div className="ers__cols">
                    <div>
                      <div className="ers__h">Summary of results</div>
                      <table className="ers__t"><tbody>
                        {cov.SUM.map(([l, n, p]) => <tr key={l}><td>{l}</td><td className="tnum n">{n}</td><td className="tnum p">{p}</td></tr>)}
                      </tbody></table>
                    </div>
                    <div>
                      <div className="ers__h">Key</div>
                      <table className="ers__t"><tbody>
                        {cov.KEY.map(([a, m]) => <tr key={a}><td className="tnum ab">{a}</td><td>{m}</td></tr>)}
                      </tbody></table>
                    </div>
                  </div>
                  <div className="ers__h" style={{ marginTop: 14 }}>Courses</div>
                  <table className="ers__t ers__courses"><tbody>
                    {orderCols.map((c) => <tr key={c.courseCode}><td className="tnum ab">{c.courseCode}</td><td>{c.title}</td><td className="tnum">{c.units} units</td></tr>)}
                  </tbody></table>
                  <div className="ers__sign">
                    <div><div className="role">Dean of Faculty</div><div className="ln">Name</div><div className="ln">Sign</div><div className="ln">Date</div></div>
                    <div><div className="role">Head of Department</div><div className="ln">Name</div><div className="ln">Sign</div><div className="ln">Date</div></div>
                  </div>
                </div>
              </PBody>
            </Panel>
          ) : null}
          <Panel title="" right={sheet.gradingInstrument ? `Grading scheme ${sheet.gradingInstrument} · score over grade` : "No grading scheme in force"}>
            {sheet.rows.length === 0 ? (
              <div className="card__body sub2">No approved registration at this level in {sheet.session} {semester.toLowerCase()} semester for this programme. The broadsheet has nobody to compute.</div>
            ) : sections.map((sec, si) => (
              <div key={si} style={{ overflowX: "auto", marginTop: si ? 18 : 0 }}>
                {sec.title ? <div className="ers__h" style={{ margin: "8px 0 6px", display: "flex", gap: 10, alignItems: "baseline" }}>{sec.title}<span className="sub2" style={{ textTransform: "none", fontWeight: 400 }}>{sec.rows.length} candidate{sec.rows.length === 1 ? "" : "s"}</span></div> : null}
                <table className="bsheet">
                  <thead>
                    <tr className="grp">
                      <th rowSpan={2} className="sn">S/N</th>
                      <th rowSpan={2} className="l">MATRIC NO.{matricPrefix ? <div style={{ fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{matricPrefix}</div> : null}</th>
                      <th rowSpan={2} className="l">NAME OF CANDIDATE</th>
                      {hideCarryover ? null : <th rowSpan={2}>CARRYOVER</th>}
                      {bands.map((b) => <th key={b[0]} colSpan={b[1].length} className="band">{b[0]}</th>)}
                      <th colSpan={4} className="band">CURRENT</th>
                      {hideCum ? null : <th colSpan={5} className="band">CUMULATIVE DATE</th>}
                      <th rowSpan={2} className="l">REMARKS</th>
                    </tr>
                    <tr className="sub">
                      {orderCols.map((c) => <th key={c.courseCode} className="course"><span className="mono">{c.courseCode}</span><span className="u">{c.units}</span></th>)}
                      <th>CUR</th><th>CUE</th><th>WGP</th><th>GPA</th>
                      {hideCum ? null : <><th>TCR</th><th>TCE</th><th>TWGP</th><th>LCGPA</th><th>CGPA</th></>}
                    </tr>
                  </thead>
                  <tbody>
                    {sec.rows.map((r, i) => (
                      <tr key={r.studentId}>
                        <td className="sn tnum">{i + 1}</td>
                        <td className="l tnum mt" title={r.number}>{serialOf(r.number)}</td>
                        <td className="l nm">{r.name}</td>
                        {hideCarryover ? null : <td className="co sub2">{r.carryovers.length ? r.carryovers.join(", ") : "—"}</td>}
                        {orderCols.map((c) => <td key={c.courseCode} className="mk">{cell(markOf(r, c.courseCode))}</td>)}
                        <td className="tnum">{r.cur}</td>
                        <td className="tnum">{r.cue}</td>
                        <td className="tnum">{Number(r.points)}</td>
                        <td className="tnum b">{fx(r.gpa)}</td>
                        {hideCum ? null : <>
                          <td className="tnum">{r.tcr}</td>
                          <td className="tnum">{r.tce}</td>
                          <td className="tnum">{Number(r.twgp)}</td>
                          <td className="tnum">{fx(r.lcgpa)}</td>
                          <td className="tnum b">{fx(r.cgpa)}</td>
                        </>}
                        <td className="rm" style={{ fontWeight: /PROBATION|CO:|Fail:/.test(r.remarks) ? 700 : 400, color: /PROBATION/.test(r.remarks) ? "var(--red-ink)" : undefined }}>{r.remarks}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {sec.rows.length === 0 ? <div className="sub2" style={{ padding: "8px 6px" }}>None</div> : null}
              </div>
            ))}
          </Panel>
          <style>{`
            .bsheet{border-collapse:collapse;font-size:12px;width:100%}
            .bsheet th,.bsheet td{border:1px solid var(--line);padding:4px 6px;text-align:center;vertical-align:middle}
            .bsheet thead th{background:var(--panel-2,var(--line-2));font-size:10.5px;letter-spacing:.03em;text-transform:uppercase;color:var(--chrome-dim)}
            .bsheet th.band{color:var(--chrome);font-weight:700}
            .bsheet th.l,.bsheet td.l{text-align:left;white-space:nowrap}
            .bsheet td.nm{white-space:normal;min-width:170px;font-weight:600}
            .bsheet td.mt{width:1%;white-space:nowrap}
            .bsheet th.course .mono{display:block;font-family:ui-monospace,monospace;font-weight:700}
            .bsheet th.course .u{display:block;font-size:10px;color:var(--chrome-dim)}
            .bsheet td.mk{min-width:44px}
            .bsheet td.b{font-weight:700}
            .bsheet td.co{text-align:left;min-width:110px;max-width:200px;white-space:normal}
            .bsheet td.rm{text-align:left;min-width:190px;max-width:340px;white-space:normal;font-size:11.5px}
            .bsheet tbody tr:nth-child(even) td{background:var(--line-2)}
            .ers{max-width:900px;margin:0 auto}
            .ers__title{text-align:center;margin-bottom:16px}
            .ers__crest{height:54px;width:auto;object-fit:contain;margin-bottom:4px}
            .ers__uni{font-weight:700;font-size:15px}
            .ers__sub{text-transform:uppercase;letter-spacing:.08em;font-size:12px;color:var(--chrome-dim);text-decoration:underline;margin-top:3px}
            .ers__meta{display:grid;grid-template-columns:1fr 1fr;gap:6px 32px;margin-bottom:18px;font-size:13px}
            .ers__meta>div>div{display:flex;gap:8px;padding:2px 0}
            .ers__meta .k{min-width:110px;color:var(--chrome-dim);text-transform:uppercase;font-size:11px;letter-spacing:.03em;align-self:center}
            .ers__cols{display:grid;grid-template-columns:1.5fr 1fr;gap:28px}
            .ers__h{font-weight:700;text-decoration:underline;font-size:12px;text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px}
            .ers__t{width:100%;font-size:12.5px;border-collapse:collapse}
            .ers__t td{padding:2px 6px;vertical-align:top}
            .ers__t td.n{text-align:right;width:44px;font-weight:600}
            .ers__t td.p{text-align:right;width:44px;color:var(--chrome-dim)}
            .ers__t td.ab{font-family:ui-monospace,monospace;font-weight:700;white-space:nowrap;width:64px}
            .ers__courses td:last-child{text-align:right;color:var(--chrome-dim);white-space:nowrap}
            .ers__sign{display:grid;grid-template-columns:1fr 1fr;gap:40px;margin-top:32px;font-size:13px}
            .ers__sign .role{font-style:italic;font-weight:600;margin-bottom:10px}
            .ers__sign .ln{color:var(--chrome-dim);border-bottom:1px dotted var(--line);padding:6px 0 2px;margin-bottom:6px}
          `}</style>
          <Panel title="The grading scheme this sheet used" right="Effective-dated: a 2019 result is graded by the 2019 scheme">
            <DTable cols={["Grade|mid", "From|mid", "To|mid", "Points|mid", "Meaning"]}
              rows={sheet.bands.map((b) => [
                <b key="g" style={{ color: COLOUR(b.points) }}>{gw(b.grade, b.points)}</b>,
                <span className="tnum" key="l">{b.low}</span>, <span className="tnum" key="h">{b.high}</span>, <span className="tnum" key="p">{b.points}</span>,
                <span key="m">{b.points >= 1 ? "Pass" : "Fail — the course is carried over"}</span>,
              ])} />
          </Panel>
          <Panel title="Classification" right="From the table in force">
            <DTable cols={["Class", "CGPA from|mid", "to|mid"]} rows={sheet.classes.map((c) => [<span key="c">{c.clazz}</span>, <span className="tnum" key="l">{fx(c.low)}</span>, <span className="tnum" key="h">{fx(c.high)}</span>])} />
          </Panel>
        </>
      )}
    </>
  );
}
