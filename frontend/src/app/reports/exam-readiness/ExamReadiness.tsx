"use client";

/** V640: Examination Readiness — the figures of a session and semester for the scope chosen, by a grouping that opens one level
 *  down, each figure opening its students; a course; each course of a department or faculty; the package of six reports under one
 *  DBO/EXAM reference; the presets; the readiness reports saved and shared. Every count and list is the server's. */
import Link from "next/link";
import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { ApiResult, Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";

import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { BY, CATEGORY, COURSE_COLUMNS, EXCEPTION, PACKAGE_PARTS, PRESETS, SUMMARY_COLUMNS, columnsFor, drill, filterLines, money, semWord, words,
  type CourseRow, type Issued, type Options, type ReadinessRow, type StudentPage, type Summary, type SummaryRow } from "@/lib/exam-readiness";

export interface View { by: string; rule: string; type: string; course: string; cat: string; astatus: string; mode: string; cfac: string; cdept: string; cby: string }

export interface SavedReport { id: string; name: string; description: string | null; definition: Record<string, string>; shared_offices: string[]; owner: string | null; mine: boolean }

const BASE = "/api/bff/api/v1/reports/exam-readiness";
const PAGE = 50;

export function ExamReadiness({ scope, structure, sessions, ceiling, options, view, session, semester, summary, students, courses, courseOwner, courseOptions,
  saved, offices, actorName }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; options: Options; view: View; session: string; semester: number;
  summary: ApiResult<Summary>; students: ApiResult<StudentPage> | null; courses: ApiResult<{ rows: CourseRow[]; at: string }> | null; courseOwner: string;
  courseOptions: { code: string; title: string; dept_code: string }[]; saved: SavedReport[] | null; offices: { code: string; label: string }[];
  actorName: string | null;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [list, setList] = useState<StudentPage | null>(students && students.ok ? students.data : null);
  const [q, setQ] = useState("");
  const [sort, setSort] = useState("name");
  const [pkg, setPkg] = useState<Issued | null>(null);
  const [cdept, setCdept] = useState(view.cdept || scope.dept || "");
  const [crsOptions, setCrsOptions] = useState(courseOptions);
  const [saveName, setSaveName] = useState("");
  const [shareWith, setShareWith] = useState<string[]>([]);
  const sum = summary.ok ? summary.data : null;
  const filters = sum?.filters ?? { session, semester, paidRule: view.rule };

  const href = (patch: Record<string, string>) => {
    const p = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) {
      if (v) p.set(k, v);
      else p.delete(k);
    }
    return `${pathname}?${p.toString()}`;
  };
  const go = (patch: Record<string, string>) => router.push(href(patch));

  async function call<T>(path: string, method: "GET" | "POST" | "PUT", body: unknown, reason: string): Promise<T | null> {
    setProblem(null);
    const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j ?? { status: r.status, title: r.statusText };
      setProblem(p); notifyProblem(p);
      return null;
    }
    return j as T;
  }

  /** the request's own filters, for a page of students, an export or a part of the package */
  const baseQuery = (f: Record<string, unknown> = {}) => {
    const p = new URLSearchParams({ session: String(f.session ?? session), semester: String(f.semester ?? semester), rule: String(f.paidRule ?? view.rule) });
    const fac = (f.faculty as string) ?? scope.fac; const dept = (f.department as string) ?? scope.dept; const prog = (f.programme as string) ?? scope.prog;
    const level = f.level != null ? String(f.level) : scope.level;
    const type = (f.programmeType as string) ?? view.type; const course = (f.course as string) ?? view.course;
    if (fac) p.set("fac", fac);
    if (dept) p.set("dept", dept);
    if (prog) p.set("prog", prog);
    if (level) p.set("level", level);
    if (type) p.set("type", type);
    if (course) p.set("course", course);
    return p;
  };

  async function page(n: number, category = list?.category ?? view.cat, search = q, order = sort) {
    const p = baseQuery();
    p.set("category", category || "ALL");
    if (view.astatus) p.set("astatus", view.astatus);
    if (search.trim()) p.set("q", search.trim());
    p.set("sort", order);
    p.set("page", String(n));
    p.set("size", String(PAGE));
    const r = await call<StudentPage>(`${BASE}/students?${p.toString()}`, "GET", undefined, "Examination readiness students read");
    if (r) setList(r);
  }

  async function log(action: "EXPORT" | "PRINT", title: string, rows: number, reference: string | null, format: string, f: Record<string, unknown>) {
    await call(`${BASE}/log`, "POST", { action, title, rows, reference, format, filters: f }, `Examination readiness ${action.toLowerCase()}ed: ${title}`);
  }

  const meta = (f: Record<string, unknown>, extra: [string, string][] = []): [string, string][] => [
    ...filterLines(f, options.types), ["Scope", sum?.scope ?? options.scope.words], ...(actorName ? [["Generated by", actorName] as [string, string]] : []), ...extra];

  async function studentsAll(category: string, f: Record<string, unknown>): Promise<StudentPage | null> {
    const p = baseQuery(f);
    p.set("category", category);
    p.set("size", "60000");
    return call<StudentPage>(`${BASE}/students?${p.toString()}`, "GET", undefined, `Examination readiness exported: ${category}`);
  }

  async function exportStudents(format: "XLSX" | "PDF", category: string, title: string, f: Record<string, unknown>, serial: string, extra: [string, string][] = []) {
    const w = format === "PDF" ? window.open("", "_blank") : null;
    setBusy(true);
    try {
      const r = await studentsAll(category, f);
      if (!r) { w?.close(); return; }
      const course = f.course ? String(f.course) : undefined;
      const cols = columnsFor(category, !!course, r.amounts);
      const ctx = { session: String(f.session ?? session), semester: Number(f.semester ?? semester), course };
      const rows = r.rows.map((x) => cols.map(([, fn]) => fn(x, ctx)));
      const headers = cols.map(([h]) => h);
      const m = meta(f, [["Students", r.total.toLocaleString("en-GB")], ["Data as of", new Date(r.at).toLocaleString("en-GB")], ...extra]);
      if (format === "XLSX") {
        const b = await brandedXlsx(title, headers, rows, { serial, meta: m });
        downloadBlob(b, `${title.replace(/[^A-Za-z0-9]+/g, "-").toLowerCase()}.xlsx`);
      } else {
        brandedPrint(title, `${ctx.session} · ${semWord(ctx.semester)} Semester · ${sum?.scope ?? options.scope.words}`, headers, rows, serial, { meta: m, orientation: "landscape", window: w, generatedBy: actorName });
      }
      await log(format === "PDF" ? "PRINT" : "EXPORT", title, r.total, serial.startsWith("DBO/") ? serial : null, format, f);
    } finally {
      setBusy(false);
    }
  }

  const summaryHeaders = (label: string) => [label, ...SUMMARY_COLUMNS.map(([, h]) => h)];
  const summaryRows = (rows: SummaryRow[], total: SummaryRow) => [...rows, total].map((r) => [r.label, ...SUMMARY_COLUMNS.map(([k]) => Number(r[k]))]);

  async function exportSummary(format: "XLSX" | "PDF", by: string, title: string, f: Record<string, unknown>, serial: string, extra: [string, string][] = []) {
    const w = format === "PDF" ? window.open("", "_blank") : null;
    setBusy(true);
    try {
      const p = baseQuery(f);
      p.set("by", by);
      const s = await call<Summary>(`${BASE}/summary?${p.toString()}`, "GET", undefined, `Examination readiness summary exported by ${by}`);
      if (!s) { w?.close(); return; }
      const label = BY.find(([k]) => k === by)?.[1] ?? "Group";
      const m = meta(f, [["Data as of", new Date(s.at).toLocaleString("en-GB")], ...extra]);
      if (format === "XLSX") {
        const b = await brandedXlsx(title, summaryHeaders(label), summaryRows(s.rows, s.total), { serial, meta: m });
        downloadBlob(b, `${title.replace(/[^A-Za-z0-9]+/g, "-").toLowerCase()}.xlsx`);
      } else {
        brandedPrint(title, `${String(f.session ?? session)} · ${semWord(Number(f.semester ?? semester))} Semester`, summaryHeaders(label), summaryRows(s.rows, s.total), serial,
          { meta: m, orientation: "landscape", window: w, generatedBy: actorName });
      }
      await log(format === "PDF" ? "PRINT" : "EXPORT", title, s.rows.length, serial.startsWith("DBO/") ? serial : null, format, f);
    } finally {
      setBusy(false);
    }
  }

  const courseHeaders = ["Course", "Title", "CU", "Department", ...COURSE_COLUMNS.map(([, h]) => h)];
  async function exportCourses(format: "XLSX" | "PDF", title: string, f: Record<string, unknown>, serial: string, extra: [string, string][] = []) {
    const w = format === "PDF" ? window.open("", "_blank") : null;
    setBusy(true);
    try {
      const p = baseQuery(f);
      p.delete("course");
      p.delete("type");
      const owner = (f.department as string) || scope.dept;
      const ownerFac = (f.faculty as string) || scope.fac;
      if (owner) p.set("cdept", owner);
      else if (ownerFac) p.set("cfac", ownerFac);
      else p.set("all", "true");
      const c = await call<{ rows: CourseRow[]; at: string }>(`${BASE}/courses?${p.toString()}`, "GET", undefined, "Course readiness exported");
      if (!c) { w?.close(); return; }
      const rows = c.rows.map((r) => [r.course_code, r.title, r.units, r.department, ...COURSE_COLUMNS.map(([k]) => Number(r[k]))]);
      const m = meta(f, [["Courses", String(c.rows.length)], ["Data as of", new Date(c.at).toLocaleString("en-GB")], ...extra]);
      if (format === "XLSX") {
        const b = await brandedXlsx(title, courseHeaders, rows, { serial, meta: m });
        downloadBlob(b, `${title.replace(/[^A-Za-z0-9]+/g, "-").toLowerCase()}.xlsx`);
      } else {
        brandedPrint(title, `${String(f.session ?? session)} · ${semWord(Number(f.semester ?? semester))} Semester`, courseHeaders, rows, serial,
          { meta: m, orientation: "landscape", window: w, generatedBy: actorName });
      }
      await log(format === "PDF" ? "PRINT" : "EXPORT", title, c.rows.length, serial.startsWith("DBO/") ? serial : null, format, f);
    } finally {
      setBusy(false);
    }
  }

  async function issuePackage() {
    setBusy(true);
    try {
      const body = { session, semester, fac: scope.fac || null, dept: scope.dept || null, prog: scope.prog || null, level: scope.level ? Number(scope.level) : null,
        type: view.type || null, course: view.course || null, rule: view.rule };
      const r = await call<Issued>(`${BASE}/package`, "POST", body, "Examination readiness report package issued");
      if (r) {
        setPkg(r);
        notify(`${r.reference} issued: ${r.figures.total.toLocaleString("en-GB")} students`);
      }
    } finally {
      setBusy(false);
    }
  }

  async function part(n: number, format: "XLSX" | "PDF") {
    if (!pkg) return;
    const p = PACKAGE_PARTS.find((x) => x.n === n)!;
    const title = `Report ${p.n} — ${p.title}`;
    const extra: [string, string][] = [["Package", `${pkg.title} · report ${p.n} of 6`], ["Issued", new Date(pkg.generatedAt).toLocaleString("en-GB")]];
    if (p.kind === "students") await exportStudents(format, p.category!, title, pkg.filters, pkg.reference, extra);
    else if (p.kind === "courses") await exportCourses(format, title, pkg.filters, pkg.reference, extra);
    else await exportSummary(format, p.by!, title, pkg.filters, pkg.reference, extra);
  }

  async function chooseCourseDept(d: string) {
    setCdept(d);
    if (!d) { setCrsOptions([]); return; }
    const p = new URLSearchParams({ session, semester: String(semester), cdept: d });
    const r = await call<{ code: string; title: string; dept_code: string }[]>(`${BASE}/courses/options?${p.toString()}`, "GET", undefined, "Courses offered read");
    if (r) setCrsOptions(r);
  }

  async function saveReport() {
    setBusy(true);
    try {
      const definition: Record<string, string> = {};
      for (const k of ["session", "sem", "fac", "dept", "prog", "level", "by", "rule", "type", "course", "cat", "view", "cdept", "cfac"]) {
        const v = params.get(k);
        if (v) definition[k === "sem" ? "semester" : k] = v;
      }
      if (!definition.session) definition.session = session;
      if (!definition.semester) definition.semester = String(semester);
      const r = await call<SavedReport>("/api/bff/api/v1/dbops/saved", "POST", { name: saveName.trim(), kind: "EXAM_READINESS", definition, sharedOffices: shareWith },
        `Readiness report saved: ${saveName.trim()}`);
      if (r) { notify(`Saved: ${r.name}`); setSaveName(""); router.refresh(); }
    } finally {
      setBusy(false);
    }
  }

  async function archive(id: string) {
    const r = await call("/api/bff/api/v1/dbops/saved/" + id + "/archive", "POST", {}, "Readiness report archived");
    if (r) router.refresh();
  }

  const openSaved = (d: Record<string, string>) => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(d)) p.set(k === "semester" ? "sem" : k, v);
    return `${pathname}?${p.toString()}`;
  };

  const t = sum?.total;
  const tile = (key: keyof NonNullable<typeof t>, cat: string, caption: string, colour: string | null = null) =>
    [CATEGORY[cat]?.[0] ?? cat, t ? Number(t[key]).toLocaleString("en-GB") : "—", colour, caption, href({ cat })] as [string, string, string | null, string, string];
  const groupLabel = BY.find(([k]) => k === view.by)?.[1] ?? "Faculty";
  const listCat = list?.category ?? view.cat;
  const listCols = list ? columnsFor(listCat, !!view.course, list.amounts) : [];
  const courseWord = view.course ? (crsOptions.find((c) => c.code === view.course)?.title ? `${view.course} — ${crsOptions.find((c) => c.code === view.course)!.title}` : view.course) : "";
  const departments = structure.faculties.flatMap((f) => f.departments.map((d) => ({ code: d.code, name: d.name, fac: f.code })));

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="students" count={t ? Number(t.total) : 0} of={t ? Number(t.total) : 0} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!summary.ok ? <ProblemNotice problem={summary.problem} /> : null}

      <Panel title="Examination readiness" right={sum ? `${sum.scope} · read ${new Date(sum.at).toLocaleTimeString("en-GB")} (live)` : ""}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="er-type" label="Programme type">
              <select id="er-type" className="ctl" value={view.type} onChange={(e) => go({ type: e.target.value, cat: "" })}>
                <option value="">Every programme type</option>
                {options.types.map((x) => <option key={x.code} value={x.code}>{x.label}</option>)}
              </select>
            </Field>
            <Field id="er-rule" label="Paid means">
              <select id="er-rule" className="ctl" value={view.rule} onChange={(e) => go({ rule: e.target.value === "FULL" ? "FULL" : "" })}>
                <option value="CARD">A school-fees payment confirmed (examination card rule)</option>
                <option value="FULL">School fees paid in full (Bursary rule)</option>
              </select>
            </Field>
            <Field id="er-by" label="Count by">
              <select id="er-by" className="ctl" value={view.by} onChange={(e) => go({ by: e.target.value })}>
                {BY.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
              </select>
            </Field>
            <Field id="er-cdept" label="Course of department">
              <select id="er-cdept" className="ctl" value={cdept} onChange={(e) => void chooseCourseDept(e.target.value)}>
                <option value="">Choose a department</option>
                {departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
              </select>
            </Field>
            <Field id="er-course" label="Course">
              <select id="er-course" className="ctl" value={view.course} onChange={(e) => go({ course: e.target.value, cat: "" })} disabled={!crsOptions.length && !view.course}>
                <option value="">Every course</option>
                {view.course && !crsOptions.some((c) => c.code === view.course) ? <option value={view.course}>{view.course}</option> : null}
                {crsOptions.map((c) => <option key={c.code} value={c.code}>{c.code} — {c.title}</option>)}
              </select>
            </Field>
            <span className="ml-auto row row--tight">
              <Btn kind="ghost" size="sm" onClick={() => router.refresh()}>Refresh</Btn>
              <Btn kind="primary" disabled={busy || !t} onClick={() => void issuePackage()}>GENERATE EXAMINATION READINESS REPORT</Btn>
            </span>
          </div>
          <div className="sub2" style={{ marginTop: "var(--s-2)" }}>
            {session} · {semWord(semester)} Semester{view.course ? ` · course ${courseWord}` : ""}. Paid means {view.rule === "FULL" ? "school fees paid in full for the semester (the Bursary's rule)" : "a school-fees payment confirmed for the session — the examination card's own rule"}; a pending, expired or unconfirmed reference is never paid.
            Registered means the registration engine&rsquo;s own reading (submitted, approved or locked{view.course ? ", with the course on it" : ""}). Not paid counts only a student charged a fee; a student charged nothing is &ldquo;no fee stated&rdquo;.
            {view.course ? " A course reads the University course registration; the College of Health Sciences (200 Level and above) and the School of Postgraduate Studies keep theirs apart." : ""}
          </div>
        </PBody>
        <Tiles items={[
          ["Total eligible", t ? Number(t.total).toLocaleString("en-GB") : "—", null, sum?.scope ?? "", href({ cat: "ALL" })],
          tile("paid_registered", "PAID_REGISTERED", "the students expected in the hall", "var(--green-ink)"),
          tile("paid_not_registered", "PAID_NOT_REGISTERED", "paid, registration missing", "var(--amber-ink)"),
          tile("not_paid", "NOT_PAID", `${t ? Number(t.not_paid_registered).toLocaleString("en-GB") : 0} of them registered`, "var(--red-ink)"),
        ]} />
        <Tiles items={[
          tile("no_fee_stated", "NO_FEE_STATED", "nothing charged — not counted as not paid"),
          tile("exam_cards", "EXAM_CARD", "the card's own rule"),
          tile("exceptions", "EXCEPTIONS", "draft, returned, empty, awaiting approval"),
          tile("part_paid", "PART_PAID", "paid, something outstanding"),
        ]} />
      </Panel>

      {pkg ? (
        <Panel title={`Report package ${pkg.reference}`} right={<Btn kind="ghost" size="sm" onClick={() => setPkg(null)}>Close</Btn>}>
          <PBody>
            <Note kind="ok" title={pkg.title}>
              Issued {new Date(pkg.generatedAt).toLocaleString("en-GB")}{actorName ? ` by ${actorName}` : ""}. Every report carries the reference {pkg.reference}, the same filters and the time the data was read.
              {" "}{pkg.figures.total.toLocaleString("en-GB")} students: {pkg.figures.paid_registered.toLocaleString("en-GB")} paid and registered, {pkg.figures.paid_not_registered.toLocaleString("en-GB")} paid not registered, {pkg.figures.not_paid.toLocaleString("en-GB")} not paid.
            </Note>
          </PBody>
          <DTable pageSize={0} noPrint cols={["Report", "", ""]}
            rows={PACKAGE_PARTS.map((p) => [
              <b key="t">{`Report ${p.n} — ${p.title}`}</b>,
              <Btn key="x" kind="ghost" size="sm" disabled={busy} onClick={() => void part(p.n, "XLSX")}>Excel</Btn>,
              <Btn key="p" kind="ghost" size="sm" disabled={busy} onClick={() => void part(p.n, "PDF")}>PDF</Btn>,
            ])} />
        </Panel>
      ) : null}

      {sum ? (
        <Panel title={`By ${groupLabel.toLowerCase()}`} right={
          <span className="row row--tight">
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportSummary("XLSX", view.by, `Examination readiness by ${groupLabel.toLowerCase()}`, filters, docSerial("DBO-EXAM"))}>Excel</Btn>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportSummary("PDF", view.by, `Examination readiness by ${groupLabel.toLowerCase()}`, filters, docSerial("DBO-EXAM"))}>PDF</Btn>
          </span>
        }>
          {sum.rows.length ? (
            <DTable pageSize={0} noPrint cols={[groupLabel, ...SUMMARY_COLUMNS.map(([, h]) => h + "|num")]}
              rows={[...sum.rows, sum.total].map((r) => [
                r.key === "ALL" ? <b key="l">Total</b> : <span key="l">{r.label}</span>,
                ...SUMMARY_COLUMNS.map(([k, , cat]) => {
                  const n = Number(r[k]);
                  const to = r.key === "ALL" ? href({ cat }) : href(drill(view.by, r.key, cat));
                  return n ? <Link key={k} className="lnk tnum" href={to}>{n.toLocaleString("en-GB")}</Link> : <span key={k} className="sub2 tnum">0</span>;
                }),
              ])} />
          ) : <PBody><div className="sub2">No student of the scope for {session} {semWord(semester).toLowerCase()} semester.</div></PBody>}
        </Panel>
      ) : null}

      {list ? (
        <Panel title={`${CATEGORY[listCat]?.[0] ?? words(listCat)}${view.course ? ` — ${courseWord}` : ""}`}
          right={`${list.total.toLocaleString("en-GB")} student${list.total === 1 ? "" : "s"} · ${list.scope}`}>
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              <Field id="er-q" label="Name, matriculation or JAMB number">
                <input id="er-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void page(1); }} maxLength={80} />
              </Field>
              <Field id="er-sort" label="Order">
                <select id="er-sort" className="ctl" value={sort} onChange={(e) => { setSort(e.target.value); void page(1, listCat, q, e.target.value); }}>
                  <option value="name">Name A to Z</option><option value="matric">Matriculation number</option><option value="department">Department</option>
                  <option value="programme">Programme</option><option value="level">Level</option>{list.amounts ? <option value="outstanding">Outstanding, largest first</option> : null}
                </select>
              </Field>
              <Btn kind="secondary" disabled={busy} onClick={() => void page(1)}>Search</Btn>
              <span className="ml-auto row row--tight">
                <Btn kind="ghost" size="sm" disabled={busy || !list.total} onClick={() => void exportStudents("XLSX", listCat, `${CATEGORY[listCat]?.[0] ?? listCat}${view.course ? ` — ${view.course}` : ""}`, filters, docSerial("DBO-EXAM"))}>Excel</Btn>
                <Btn kind="ghost" size="sm" disabled={busy || !list.total} onClick={() => void exportStudents("PDF", listCat, `${CATEGORY[listCat]?.[0] ?? listCat}${view.course ? ` — ${view.course}` : ""}`, filters, docSerial("DBO-EXAM"))}>PDF</Btn>
                <LinkBtn kind="ghost" href={href({ cat: "" })}>Close</LinkBtn>
              </span>
            </div>
            <div className="sub2" style={{ marginTop: "var(--s-1)" }}>{CATEGORY[listCat]?.[2] ?? ""}{list.amounts ? "" : " · amounts are read by the offices that hold the fee records"}</div>
          </PBody>
          {list.rows.length ? (
            <DTable pageSize={0} noPrint
              cols={["S/N|num", ...listCols.map(([h]) => h + (["Level", "Courses Registered", "Total CU", "Amount Required", "Amount Paid", "Outstanding"].includes(h) ? "|num" : "")), "Exception", "|num"]}
              rows={list.rows.map((r: ReadinessRow, i) => [
                <span key="n" className="tnum">{(list.page - 1) * list.size + i + 1}</span>,
                ...listCols.map(([h, fn]) => {
                  const v = fn(r, { session, semester, course: view.course || undefined });
                  return h === "Student Name" ? <Two key={h} a={String(v)} b={words(r.academic_status)} />
                    : typeof v === "number" && ["Amount Required", "Amount Paid", "Outstanding"].includes(h) ? <span key={h} className="tnum">{money(v)}</span>
                    : <span key={h} className={typeof v === "number" ? "tnum" : undefined}>{String(v)}</span>;
                }),
                r.exception ? <Pil key="x" kind="warn">{EXCEPTION[r.exception] ?? words(r.exception)}</Pil> : <span key="x" className="sub2">—</span>,
                <LinkBtn key="v" kind="ghost" href={`/students/${r.student_id}`}>Record</LinkBtn>,
              ])} />
          ) : <PBody><div className="sub2">No student in this figure.</div></PBody>}
          <PBody>
            <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
              <span className="sub2">Page {list.page} of {Math.max(1, Math.ceil(list.total / list.size))} · read {new Date(list.at).toLocaleTimeString("en-GB")}</span>
              <span className="ml-auto row row--tight">
                <Btn kind="ghost" size="sm" disabled={busy || list.page <= 1} onClick={() => void page(list.page - 1)}>Previous</Btn>
                <Btn kind="ghost" size="sm" disabled={busy || list.page * list.size >= list.total} onClick={() => void page(list.page + 1)}>Next</Btn>
              </span>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Courses" right={
        <span className="row row--tight">
          <select className="ctl" aria-label="Courses of" value={view.cby} onChange={(e) => go({ view: "courses", cby: e.target.value === "faculty" ? "faculty" : "" })}>
            <option value="department">Courses of a department</option><option value="faculty">Courses of a faculty</option>
          </select>
          {view.cby === "faculty" ? (
            <select className="ctl" aria-label="Faculty" value={courseOwner} onChange={(e) => go({ view: "courses", cby: "faculty", cfac: e.target.value })}>
              <option value="">Choose a faculty</option>
              {structure.faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
            </select>
          ) : (
            <select className="ctl" aria-label="Department" value={courseOwner} onChange={(e) => go({ view: "courses", cdept: e.target.value })}>
              <option value="">Choose a department</option>
              {departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
            </select>
          )}
          {courses && courses.ok && courses.data.rows.length ? (
            <>
              <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportCourses("XLSX", "Course registration and examination readiness", { ...filters, ...(view.cby === "faculty" ? { faculty: courseOwner } : { department: courseOwner }) }, docSerial("DBO-EXAM"))}>Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportCourses("PDF", "Course registration and examination readiness", { ...filters, ...(view.cby === "faculty" ? { faculty: courseOwner } : { department: courseOwner }) }, docSerial("DBO-EXAM"))}>PDF</Btn>
            </>
          ) : null}
        </span>
      }>
        {courses && !courses.ok ? <PBody><ProblemNotice problem={courses.problem} /></PBody> : null}
        {courses && courses.ok ? (
          courses.data.rows.length ? (
            <DTable pageSize={25} noPrint cols={["Course", "Title", "CU|num", ...COURSE_COLUMNS.map(([, h]) => h + "|num")]}
              rows={courses.data.rows.map((c) => [
                <b key="c" className="tnum">{c.course_code}</b>, <span key="t">{c.title}</span>, <span key="u" className="tnum">{c.units}</span>,
                ...COURSE_COLUMNS.map(([k]) => {
                  const n = Number(c[k]);
                  const cat = k === "registered_paid" ? "PAID_REGISTERED" : k === "registered_not_paid" ? "NOT_PAID" : k === "expected_not_registered_paid" ? "PAID_NOT_REGISTERED" : "ALL";
                  return n ? <Link key={k} className="lnk tnum" href={href({ course: c.course_code, cat, view: "" })}>{n.toLocaleString("en-GB")}</Link> : <span key={k} className="sub2 tnum">0</span>;
                }),
              ])}
              texts={courses.data.rows.map((c) => `${c.course_code} ${c.title}`)} />
          ) : <PBody><div className="sub2">No course of {courseOwner} is offered in {session} {semWord(semester).toLowerCase()} semester.</div></PBody>
        ) : <PBody><div className="sub2">Choose a department or a faculty: each course it offers in the semester, the students registered for it and how many paid, and the students the programme structure expects who have not registered it. Every number opens its students.</div></PBody>}
      </Panel>

      <Panel title="Quick reports">
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
            {PRESETS.map((p, i) => <LinkBtn key={p.href} kind="ghost" href={p.href}>{`${i + 1}. ${p.label}`}</LinkBtn>)}
          </div>
        </PBody>
      </Panel>

      {saved ? (
        <Panel title="Saved readiness reports" right={`${saved.length}`}>
          {saved.length ? (
            <DTable pageSize={10} noPrint cols={["Report", "Shared with", "By", "|num"]}
              rows={saved.map((s) => [
                <Two key="n" a={s.name} b={s.description ?? Object.entries(s.definition).map(([k, v]) => `${k} ${v}`).join(" · ")} />,
                <span key="s" className="sub2">{s.shared_offices.length ? s.shared_offices.map((o) => offices.find((x) => x.code === o)?.label ?? o).join(", ") : "—"}</span>,
                <span key="b" className="sub2">{s.mine ? "You" : s.owner ?? ""}</span>,
                <span key="a" className="row row--tight">
                  <LinkBtn kind="ghost" href={openSaved(s.definition)}>Open</LinkBtn>
                  {s.mine ? <Btn kind="ghost" size="sm" onClick={() => void archive(s.id)}>Archive</Btn> : null}
                </span>,
              ])} />
          ) : null}
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              <Field id="er-save" label="Save this report as"><input id="er-save" className="ctl" value={saveName} onChange={(e) => setSaveName(e.target.value)} maxLength={150} style={{ minWidth: 280 }}
                placeholder={`${session} ${semWord(semester)} Semester — ${sum?.scope ?? ""}`} /></Field>
              <Field id="er-share" label="Share with">
                <select id="er-share" className="ctl" multiple value={shareWith} onChange={(e) => setShareWith(Array.from(e.target.selectedOptions).map((o) => o.value))} style={{ minWidth: 220, height: 80 }}>
                  {offices.filter((o) => ["ict", "academic", "registrar", "dregistrar", "records", "exams", "bursar", "dean", "hod", "vc", "dvc", "dbops"].includes(o.code))
                    .map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
                </select>
              </Field>
              <Btn kind="secondary" disabled={busy || saveName.trim().length < 3} onClick={() => void saveReport()}>Save</Btn>
            </div>
            <div className="sub2" style={{ marginTop: "var(--s-1)" }}>A saved report keeps its filters; each office that opens it reads it within its own scope, with the data as it stands then.</div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}

