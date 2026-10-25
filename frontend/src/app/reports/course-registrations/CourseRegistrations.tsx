"use client";

/** V652: the Course Registration Report — the scope bar, the filters, the figures, then course by course (with the attendance sheets
 *  issued from the courses ticked), the students and their courses a page at a time, and the summary by every dimension. Every figure
 *  is the server's; an export carries its DBO/REG reference from the official report register. */
import Link from "next/link";
import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { ApiResult, Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, downloadBlob } from "@/lib/exportbrand";
import {
  CATEGORIES, CATEGORY_WORD, COURSE_COLUMNS, DIMENSIONS, MANUAL_PRESETS, REG_STATUSES, ROW_COLUMNS, dimensionLabel, dimensionRows, drill, eligibilityWord,
  filterLines, manualLines, regQuery, semWord, totalRow, words, type CourseRow, type RegFilters, type RegPage, type RegRow, type ReportScope, type SummaryRow,
} from "@/lib/course-registration-report";

export type View = "courses" | "rows" | "summary";

const BASE = "/api/bff/api/v1/reports/course-registrations";
const KEEPERS = ["exams", "facultyexams", "records", "hod", "gst", "eps", "academic", "registrar", "dregistrar", "super"];

interface Issued { issued: number; students: number; sheets: { reference: string; version: number; students: number; manual_lines: number; offering_id: string; scope_dept: string | null; scope_prog: string | null; scope_fac: string | null }[] }

const n = (v: number | null | undefined) => Number(v ?? 0).toLocaleString("en-GB");

export function CourseRegistrations({ scope, structure, sessions, ceiling, filters, view, session, semester, summary, reportScope, rows, courses, office, actorName }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; filters: RegFilters; view: View; session: string; semester: number | null;
  summary: SummaryRow[]; reportScope: ReportScope; rows: ApiResult<RegPage> | null; courses: ApiResult<{ rows: CourseRow[] }> | null; office: string; actorName: string | null;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [course, setCourse] = useState(filters.course);
  const [q, setQ] = useState(filters.q);
  const [from, setFrom] = useState(filters.from);
  const [to, setTo] = useState(filters.to);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [lines, setLines] = useState("10");
  const [custom, setCustom] = useState("");
  const [split, setSplit] = useState("NONE");
  const [reason, setReason] = useState("");
  const [issued, setIssued] = useState<Issued | null>(null);
  const total = totalRow(summary);
  const keeper = KEEPERS.includes(office);

  const href = (patch: Record<string, string>) => {
    const p = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) {
      if (v) p.set(k, v);
      else p.delete(k);
    }
    if (!("page" in patch)) p.delete("page");
    return `${pathname}?${p.toString()}`;
  };
  const go = (patch: Record<string, string>) => router.push(href(patch));

  async function call<T>(path: string, method: "GET" | "POST", body: unknown, why: string): Promise<T | null> {
    setProblem(null);
    const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j ?? { status: r.status, title: r.statusText };
      setProblem(p); notifyProblem(p);
      return null;
    }
    return j as T;
  }

  // the scope the API held the report to, named from the structure (the codes when a name is not in it)
  const fac = structure.faculties.find((f) => f.code === reportScope.faculty);
  const dept = structure.faculties.flatMap((f) => f.departments).find((d) => d.code === reportScope.department);
  const prog = structure.faculties.flatMap((f) => f.departments.flatMap((d) => d.programmes)).find((p) => p.code === reportScope.programme);
  const scopeWords = prog?.name ?? (dept ? `Department of ${dept.name}` : fac ? fac.name : null)
    ?? ([reportScope.faculty, reportScope.department, reportScope.programme].filter(Boolean).join(" · ") || "The University");
  const period = `${session} · ${semester ? `${semWord(semester)} Semester` : "Every semester"}`;
  const facts = (extra: [string, string][] = []): [string, string][] => [
    ["Session", session], ["Semester", semester ? semWord(semester) : "Every semester"], ["Scope", scopeWords],
    ...(scope.level ? [["Level", `${scope.level} Level`] as [string, string]] : []),
    ...(reportScope.courses ? [["Courses", `${reportScope.courses} office's own`] as [string, string]] : []),
    ...filterLines(filters), ...(actorName ? [["Generated by", actorName] as [string, string]] : []), ...extra,
  ];

  /** every row of the report with its reference on the report register, as a workbook or a printed list */
  async function exportRows(format: "XLSX" | "PDF") {
    const w = format === "PDF" ? window.open("", "_blank") : null;
    setBusy(true);
    try {
      const qs = regQuery(scope, filters);
      qs.set("title", "Course registration report");
      const r = await call<{ reference: string; truncated: boolean; rows: RegRow[] }>(`${BASE}/export?${qs.toString()}`, "GET", undefined, "Course registration report exported");
      if (!r) { w?.close(); return; }
      const headers = ROW_COLUMNS.map(([h]) => h);
      const body = r.rows.map((x) => ROW_COLUMNS.map(([, fn]) => fn(x)));
      const m = facts([["Registrations", n(r.rows.length)], ...(r.truncated ? [["Note", "The first 50,000 rows; narrow the filters for the rest"] as [string, string]] : [])]);
      if (format === "XLSX") {
        downloadBlob(await brandedXlsx("Course registration report", headers, body, { serial: r.reference, meta: m }), `course-registration-report-${session.replace("/", "-")}.xlsx`);
      } else {
        brandedPrint("Course registration report", period, headers, body, r.reference, { meta: m, orientation: "landscape", window: w, generatedBy: actorName });
      }
      notify(`${r.reference}: ${n(r.rows.length)} registrations`);
    } finally {
      setBusy(false);
    }
  }

  async function exportCourses(format: "XLSX" | "PDF") {
    if (!courses || !courses.ok) return;
    const headers = ["Course Code", "Course Title", "Units", "Category", "Curriculum", ...COURSE_COLUMNS.map(([, h]) => h), "Latest attendance sheet"];
    const body = courses.data.rows.map((c) => [c.shown_code, c.course_title, c.units, CATEGORY_WORD[c.category] ?? words(c.category), c.curriculum ?? "",
      ...COURSE_COLUMNS.map(([k]) => Number(c[k] ?? 0)), c.sheet_reference ?? ""]);
    const m = facts([["Courses", String(body.length)]]);
    if (format === "XLSX") downloadBlob(await brandedXlsx("Course registration by course", headers, body, { meta: m }), `course-registration-by-course-${session.replace("/", "-")}.xlsx`);
    else brandedPrint("Course registration by course", period, headers, body, undefined, { meta: m, orientation: "landscape", generatedBy: actorName });
  }

  async function exportDimension(dim: string, label: string) {
    const list = dimensionRows(summary, dim);
    const headers = [label, "Registrations", "Students", "Male", "Female", "Not stated", "Carry-over", "Card or permit"];
    const body = [...list, ...(total ? [{ ...total, label: "Total" }] : [])].map((r) => [r.dimension === "TOTAL" ? "Total" : dimensionLabel(dim, r), r.registrations, r.students, r.male, r.female, r.other_sex, r.carry_over, r.eligible]);
    downloadBlob(await brandedXlsx(`Course registration by ${label.toLowerCase()}`, headers, body, { meta: facts() }), `course-registration-by-${label.toLowerCase()}-${session.replace("/", "-")}.xlsx`);
  }

  async function generate() {
    const m = manualLines(lines, custom);
    if (m == null) { notifyProblem({ status: 400, title: "Manual lines are 0 to 60" }); return; }
    setBusy(true);
    try {
      const body = { offerings: [...picked], manualLines: m, reason: reason.trim() || null, fac: scope.fac || null, dept: scope.dept || null, prog: scope.prog || null, split };
      const r = await call<Issued>("/api/bff/api/v1/exams/attendance/sheets", "POST", body, `Examination attendance sheets issued for ${picked.size} course${picked.size === 1 ? "" : "s"}`);
      if (r) {
        setIssued(r);
        setPicked(new Set());
        notify(`${r.issued} attendance sheet${r.issued === 1 ? "" : "s"} issued · ${n(r.students)} students listed`);
        router.refresh();
      }
    } finally {
      setBusy(false);
    }
  }

  const pdfOf = (refs: string[]) => `/exams/attendance/sheets/pdf?${refs.map((r) => `ref=${encodeURIComponent(r)}`).join("&")}`;
  const cat = (k: string) => summary.find((r) => r.dimension === "CATEGORY" && r.key === k);
  const tile = (label: string, value: number | undefined, caption: string, to: string, colour: string | null = null) =>
    [label, value == null ? "0" : n(value), colour, caption, to] as [string, string, string | null, string, string];
  const courseRows = courses && courses.ok ? courses.data.rows : [];
  const allPicked = courseRows.length > 0 && courseRows.every((c) => picked.has(c.offering_id));
  const toggle = (id: string) => setPicked((s) => { const x = new Set(s); if (x.has(id)) x.delete(id); else x.add(id); return x; });

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="registrations" count={total?.registrations ?? 0} of={total?.registrations ?? 0} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Course registration report" right={`${scopeWords}${reportScope.courses ? ` · ${reportScope.courses} courses` : ""}`}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="cr-cat" label="Category">
              <select id="cr-cat" className="ctl" value={filters.category} onChange={(e) => go({ category: e.target.value })}>
                <option value="">Every course</option>
                {CATEGORIES.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
              </select>
            </Field>
            <Field id="cr-cur" label="Curriculum">
              <select id="cr-cur" className="ctl" value={filters.curriculum} onChange={(e) => go({ curriculum: e.target.value })}>
                <option value="">BMAS and CCMAS</option><option value="BMAS">BMAS</option><option value="CCMAS">CCMAS</option>
              </select>
            </Field>
            <Field id="cr-sex" label="Sex">
              <select id="cr-sex" className="ctl" value={filters.sex} onChange={(e) => go({ sex: e.target.value })}>
                <option value="">Everyone</option><option value="M">Male</option><option value="F">Female</option><option value="U">Not stated</option>
              </select>
            </Field>
            <Field id="cr-reg" label="Registration">
              <select id="cr-reg" className="ctl" value={filters.reg} onChange={(e) => go({ reg: e.target.value })}>
                <option value="">Every status</option>
                {REG_STATUSES.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
              </select>
            </Field>
            <Field id="cr-el" label="Card or permit">
              <select id="cr-el" className="ctl" value={filters.eligible} onChange={(e) => go({ eligible: e.target.value })}>
                <option value="">Held or not</option><option value="YES">Held</option><option value="NO">Not held</option>
              </select>
            </Field>
            <Field id="cr-course" label="Course code">
              <input id="cr-course" className="ctl" value={course} maxLength={24} placeholder="GST 111" onChange={(e) => setCourse(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter") go({ course: course.trim(), offering: "" }); }} style={{ width: 110 }} />
            </Field>
            <Field id="cr-q" label="Name, matriculation or JAMB number">
              <input id="cr-q" className="ctl" value={q} maxLength={80} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go({ q: q.trim() }); }} />
            </Field>
            <Field id="cr-from" label="Registered from"><input id="cr-from" type="date" className="ctl" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
            <Field id="cr-to" label="to"><input id="cr-to" type="date" className="ctl" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
            <label className="row row--tight" style={{ alignItems: "center", gap: 6 }}>
              <input type="checkbox" checked={filters.dropped} onChange={(e) => go({ dropped: e.target.checked ? "1" : "" })} /> Include dropped courses
            </label>
            <span className="ml-auto row row--tight">
              <Btn kind="secondary" onClick={() => go({ course: course.trim(), offering: course.trim() ? "" : filters.offering, q: q.trim(), from, to })}>Apply</Btn>
              <LinkBtn kind="ghost" href={`${pathname}?${new URLSearchParams(Object.fromEntries(["view", "session", "sem", "fac", "dept", "prog", "level"].map((k) => [k, params.get(k) ?? ""]).filter(([, v]) => v))).toString()}`}>Clear</LinkBtn>
            </span>
          </div>
          <div className="sub2" style={{ marginTop: "var(--s-2)" }}>
            {period}. A row is one student and one course on a registration of the session; dropped and withdrawn courses are left out unless included.
            Card or permit: the examination card for a departmental, faculty or other course, the GST &amp; EPS permit for a GST or EPS course.
            {filters.offering ? <> One class only · <Link className="lnk" href={href({ offering: "" })}>every course</Link>.</> : null}
          </div>
        </PBody>
        <Tiles items={[
          tile("Registrations", total?.registrations, "a student and a course", href({ view: "rows" })),
          tile("Students", total?.students, `${n(total?.male)} male · ${n(total?.female)} female${total?.other_sex ? ` · ${n(total.other_sex)} not stated` : ""}`, href({ view: "rows" })),
          tile("Carry-over", total?.carry_over, "registered again", href({ view: "rows", category: "CARRY_OVER" }), "var(--amber-ink)"),
          tile("Card or permit held", total?.eligible, `${n((total?.registrations ?? 0) - (total?.eligible ?? 0))} registrations without`, href({ view: "rows", eligible: "NO" }), "var(--green-ink)"),
        ]} />
        <Tiles items={[
          tile("GST courses", cat("GST")?.registrations, `${n(cat("GST")?.students)} students`, href({ category: "GST" })),
          tile("EPS courses", cat("EPS")?.registrations, `${n(cat("EPS")?.students)} students`, href({ category: "EPS" })),
          tile("Departmental courses", cat("DEPARTMENTAL")?.registrations, `${n(cat("DEPARTMENTAL")?.students)} students`, href({ category: "DEPARTMENTAL" })),
          tile("Other courses", (total?.registrations ?? 0) - (cat("GST")?.registrations ?? 0) - (cat("EPS")?.registrations ?? 0), "not GST or EPS: departmental, faculty and the rest", href({ category: "OTHER_COURSES" })),
        ]} />
      </Panel>

      <Tabs label="Report views" value={view} onChange={(v) => go({ view: v === "courses" ? "" : v })}
        items={[{ id: "courses", label: "Course by course" }, { id: "rows", label: "Students and courses" }, { id: "summary", label: "Summary" }]} />

      {view === "courses" ? (
        <Panel title="Course by course" right={
          <span className="row row--tight">
            <Btn kind="ghost" size="sm" disabled={!courseRows.length} onClick={() => void exportCourses("XLSX")}>Excel</Btn>
            <Btn kind="ghost" size="sm" disabled={!courseRows.length} onClick={() => void exportCourses("PDF")}>PDF</Btn>
          </span>
        }>
          {courses && !courses.ok ? <PBody><ProblemNotice problem={courses.problem} /></PBody> : null}
          {keeper ? (
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                <Field id="cr-lines" label="Manual attendance lines">
                  <select id="cr-lines" className="ctl" value={lines} onChange={(e) => setLines(e.target.value)}>
                    {MANUAL_PRESETS.map((x) => <option key={x} value={String(x)}>{x}</option>)}
                    <option value="custom">Custom</option>
                  </select>
                </Field>
                {lines === "custom" ? (
                  <Field id="cr-custom" label="Lines (0 to 60)"><input id="cr-custom" className="ctl" inputMode="numeric" value={custom} maxLength={2} onChange={(e) => setCustom(e.target.value)} style={{ width: 80 }} /></Field>
                ) : null}
                <Field id="cr-split" label="One sheet">
                  <select id="cr-split" className="ctl" value={split} onChange={(e) => setSplit(e.target.value)}>
                    <option value="NONE">For each course</option>
                    <option value="FACULTY">For each faculty of each course</option>
                    <option value="DEPARTMENT">For each department of each course</option>
                    <option value="PROGRAMME">For each programme of each course</option>
                  </select>
                </Field>
                <Field id="cr-reason" label="Reason, for a new version" hint="Needed when a sheet was already issued: late registration, a correction.">
                  <input id="cr-reason" className="ctl" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} style={{ minWidth: 260 }} />
                </Field>
                <span className="ml-auto">
                  <Btn kind="primary" disabled={busy || !picked.size} onClick={() => void generate()}>
                    {picked.size > 1 ? `GENERATE ALL ATTENDANCE SHEETS (${picked.size})` : "GENERATE ATTENDANCE SHEET"}
                  </Btn>
                </span>
              </div>
              <div className="sub2" style={{ marginTop: "var(--s-1)" }}>
                Tick the courses. Each course has its own sheet listing every student registered for it within {scopeWords.toLowerCase() === "the university" ? "the whole class" : scopeWords}, the card or permit marked, then the blank manual / late registration rows. A sheet already issued is kept as printed; the new one is the next version.
              </div>
            </PBody>
          ) : null}
          {issued ? (
            <PBody>
              <Note kind="ok" title={`${issued.issued} attendance sheet${issued.issued === 1 ? "" : "s"} issued`}
                action={<LinkBtn kind="primary" href={pdfOf(issued.sheets.map((s) => s.reference))}>Print {issued.issued === 1 ? "the sheet" : `all ${issued.issued}`} (PDF)</LinkBtn>}>
                {issued.sheets.slice(0, 12).map((s) => (
                  <span key={s.reference} className="row row--tight" style={{ gap: 8 }}>
                    <Link className="lnk tnum" href={pdfOf([s.reference])} target="_blank">{s.reference}</Link>
                    <span className="sub2">{n(s.students)} students · {s.manual_lines} manual lines</span>
                  </span>
                ))}
                {issued.sheets.length > 12 ? <span className="sub2">and {issued.sheets.length - 12} more</span> : null}
              </Note>
            </PBody>
          ) : null}
          {courseRows.length ? (
            <DTable pageSize={25} noPrint
              cols={[...(keeper ? ["|mid"] : []), "Course", "CU|num", "Category", ...COURSE_COLUMNS.map(([, h]) => h + "|num"), "Attendance sheet", ""]}
              rows={courseRows.map((c) => [
                ...(keeper ? [<input key="k" type="checkbox" aria-label={`Choose ${c.shown_code}`} checked={picked.has(c.offering_id)} onChange={() => toggle(c.offering_id)} />] : []),
                <Two key="c" a={<b className="tnum">{c.shown_code}</b>} b={c.course_title} />,
                <span key="u" className="tnum">{c.units}</span>,
                <span key="g" className="sub2">{CATEGORY_WORD[c.category] ?? words(c.category)}{c.curriculum ? ` · ${c.curriculum}` : ""}</span>,
                ...COURSE_COLUMNS.map(([k]) => {
                  const v = Number(c[k] ?? 0);
                  if (!v) return <span key={k} className="sub2 tnum">0</span>;
                  if (k === "students") return <Link key={k} className="lnk tnum" href={href({ view: "rows", offering: c.offering_id })}>{n(v)}</Link>;
                  if (k === "eligible") return <Link key={k} className="lnk tnum" href={href({ view: "rows", offering: c.offering_id, eligible: "YES" })}>{n(v)}</Link>;
                  if (k === "carry_over") return <Link key={k} className="lnk tnum" href={href({ view: "rows", offering: c.offering_id, category: "CARRY_OVER" })}>{n(v)}</Link>;
                  return <span key={k} className="tnum">{n(v)}</span>;
                }),
                c.sheet_reference
                  ? <Two key="s" a={<Link className="lnk tnum" href={pdfOf([c.sheet_reference])} target="_blank">{c.sheet_reference}</Link>} b={`${c.sheets} issued`} />
                  : <span key="s" className="sub2">None yet</span>,
                <LinkBtn key="a" kind="ghost" href={`/exams/attendance?offering=${c.offering_id}`}>Attendance</LinkBtn>,
              ])}
              texts={courseRows.map((c) => `${c.shown_code} ${c.course_code} ${c.course_title}`)} />
          ) : courses && courses.ok ? <PBody><div className="sub2">No course registered in this scope for {period}.</div></PBody> : null}
          {keeper && courseRows.length ? (
            <PBody>
              <span className="row row--tight">
                <Btn kind="ghost" size="sm" onClick={() => setPicked(allPicked ? new Set() : new Set(courseRows.map((c) => c.offering_id)))}>{allPicked ? "Clear the ticks" : `Tick every course (${courseRows.length})`}</Btn>
                <span className="sub2">{picked.size} ticked</span>
              </span>
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      {view === "rows" && rows ? (
        rows.ok ? (
          <Panel title="Students and courses" right={
            <span className="row row--tight">
              <span className="sub2">{n(rows.data.total)} registrations</span>
              <Btn kind="ghost" size="sm" disabled={busy || !rows.data.total} onClick={() => void exportRows("XLSX")}>Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={busy || !rows.data.total} onClick={() => void exportRows("PDF")}>PDF</Btn>
            </span>
          }>
            {rows.data.rows.length ? (
              <DTable pageSize={0} noPrint
                cols={["S/N|num", "Student", "Level|num", "Course", "CU|num", "Category", "Registration", "Card or permit", "School fees", ""]}
                rows={rows.data.rows.map((r, i) => [
                  <span key="n" className="tnum">{(rows.data.page - 1) * rows.data.size + i + 1}</span>,
                  <Two key="s" a={r.full_name} b={`${r.matric_no ?? r.jamb_no ?? ""} · ${r.programme}`} />,
                  <span key="l" className="tnum">{r.level ?? ""}</span>,
                  <Two key="c" a={<b className="tnum">{r.shown_code}</b>} b={r.course_title} />,
                  <span key="u" className="tnum">{r.units}</span>,
                  <span key="g">{CATEGORY_WORD[r.category] ?? words(r.category)}{r.carry_over ? <> <Pil kind="warn">Carry-over</Pil></> : null}</span>,
                  <Pil key="r" kind={r.registration_status === "APPROVED" || r.registration_status === "LOCKED" ? "ok" : r.registration_status === "SUBMITTED" ? "info" : "grey"}>{words(r.registration_status)}</Pil>,
                  <Pil key="e" kind={r.eligible ? "ok" : "warn"}>{eligibilityWord(r)}</Pil>,
                  r.fees_paid == null ? <span key="f" className="sub2">—</span> : <Pil key="f" kind={r.fees_paid ? "ok" : "bad"}>{r.fees_paid ? "Paid" : "Not paid"}</Pil>,
                  <LinkBtn key="v" kind="ghost" href={`/students/${r.student_id}`}>Record</LinkBtn>,
                ])} />
            ) : <PBody><div className="sub2">No registration matches.</div></PBody>}
            <PBody>
              <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
                <span className="sub2">Page {rows.data.page} of {Math.max(1, Math.ceil(rows.data.total / rows.data.size))}</span>
                <span className="ml-auto row row--tight">
                  <LinkBtn kind="ghost" href={href({ page: String(Math.max(1, rows.data.page - 1)) })}>Previous</LinkBtn>
                  <LinkBtn kind="ghost" href={href({ page: String(rows.data.page * rows.data.size < rows.data.total ? rows.data.page + 1 : rows.data.page) })}>Next</LinkBtn>
                </span>
              </div>
            </PBody>
          </Panel>
        ) : <ProblemNotice problem={rows.problem} />
      ) : null}

      {view === "summary" ? DIMENSIONS.filter(([d]) => d !== "COURSE").map(([dim, label]) => {
        const list = dimensionRows(summary, dim);
        return (
          <Panel key={dim} title={`By ${label.toLowerCase()}`} right={<Btn kind="ghost" size="sm" disabled={!list.length} onClick={() => void exportDimension(dim, label)}>Excel</Btn>}>
            {list.length ? (
              <DTable pageSize={dim === "PROGRAMME" || dim === "DEPARTMENT" ? 15 : 0} noPrint
                cols={[label, "Registrations|num", "Students|num", "Male|num", "Female|num", "Not stated|num", "Carry-over|num", "Card or permit|num"]}
                rows={[...list, ...(total ? [total] : [])].map((r) => [
                  r.dimension === "TOTAL" ? <b key="l">Total</b> : <Link key="l" className="lnk" href={href({ ...drill(dim, r.key), view: "" })}>{dimensionLabel(dim, r)}</Link>,
                  <span key="a" className="tnum">{n(r.registrations)}</span>, <span key="b" className="tnum">{n(r.students)}</span>,
                  <span key="c" className="tnum">{n(r.male)}</span>, <span key="d" className="tnum">{n(r.female)}</span>, <span key="e" className="tnum">{n(r.other_sex)}</span>,
                  <span key="f" className="tnum">{n(r.carry_over)}</span>, <span key="g" className="tnum">{n(r.eligible)}</span>,
                ])}
                texts={dim === "PROGRAMME" || dim === "DEPARTMENT" ? [...list.map((r) => dimensionLabel(dim, r)), ...(total ? ["Total"] : [])] : undefined} />
            ) : <PBody><div className="sub2">Nothing registered in this scope.</div></PBody>}
          </Panel>
        );
      }) : null}

      <Panel title="Statistics and dashboards">
        <PBody>
          <div className="sub2">
            The payment against registration figures, GST and EPS payments and registration, the examination card and permit counts and the dashboards by faculty, department and programme are the{" "}
            <Link className="lnk" href="/reports/master">Master University Report</Link>; the students paid and registered for the examination are{" "}
            <Link className="lnk" href="/reports/exam-readiness">Examination Readiness</Link>. Attendance is recorded and reconciled on{" "}
            <Link className="lnk" href="/exams/attendance">Examination Attendance</Link>.
          </div>
        </PBody>
      </Panel>
    </>
  );
}
