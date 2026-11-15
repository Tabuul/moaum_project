"use client";

/** t/identitycompletion (V749): the identity information of the students in study and the staff in service — the counts under the
 *  filters, each count a link to the people behind it, the list by what is missing, searched, paged, and the whole filtered list as
 *  a branded Excel workbook. Read only: the people complete it themselves on their dashboards, or the card desk records it. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { STUDENT_LEVELS } from "@/lib/levels";
import { day } from "@/lib/format";
import {
  STAFF_CATEGORIES, STAFF_MISSING, STUDENT_MISSING, bloodWord, categoryWord, pageOf, staffEmailWord, staffPhotoWord, staffRowOf, studentRowOf,
  type Choice, type CompletionTab, type ListPage, type StaffCounts, type StaffRow, type StudentCounts, type StudentRow,
} from "@/lib/identity";

export interface CompletionFilters {
  faculty: string; department: string; programme: string; level: string; unit: string; category: string; missing: string; q: string; page: number;
}

/** the most rows one workbook carries (the API's export reads at most this many at once); a larger list is narrowed first */
const EXPORT_CAP = 20000;

const pct = (n: number, of: number) => (of > 0 ? `${Math.round((n / of) * 100)}%` : "—");
const fmt = (n: number) => n.toLocaleString("en-GB");

export function Completion({ tab, tabs, filters, faculties, departments: allDepartments, programmes: allProgrammes, units, studentCounts, staffCounts, countsProblem, students, staff, listProblem }: {
  tab: CompletionTab;
  /** the tabs the acting office reads (lib/identity completionTabs) — a tab it cannot read is not offered */
  tabs: CompletionTab[];
  filters: CompletionFilters;
  /** what the counts can be narrowed by, as the API lists it with the counts */
  faculties: Choice[];
  departments: Choice[];
  programmes: Choice[];
  units: Choice[];
  studentCounts: StudentCounts | null;
  staffCounts: StaffCounts | null;
  countsProblem: Problem | null;
  students: ListPage<StudentRow> | null;
  staff: ListPage<StaffRow> | null;
  listProblem: Problem | null;
}) {
  const router = useRouter();
  const [f, setF] = useState<CompletionFilters>(filters);
  const [exporting, setExporting] = useState(false);

  /** the address for these filters (the tab's own; another tab starts clear) */
  const href = (next: Partial<CompletionFilters> & { tab?: "students" | "staff" }) => {
    const t = next.tab ?? tab;
    const merged: CompletionFilters = t === tab ? { ...filters, page: 1, ...next } : { faculty: "", department: "", programme: "", level: "", unit: "", category: "", missing: "", q: "", page: 1 };
    const p = new URLSearchParams();
    p.set("tab", t);
    const keys: (keyof CompletionFilters)[] = t === "students" ? ["faculty", "department", "programme", "level", "missing", "q"] : ["faculty", "unit", "category", "missing", "q"];
    for (const k of keys) if (merged[k]) p.set(k, String(merged[k]));
    if (merged.page > 1) p.set("page", String(merged.page));
    return `/identity/completion?${p}`;
  };
  const go = (next: Partial<CompletionFilters> & { tab?: "students" | "staff" }) => router.push(href(next));

  // each list narrowed by the choice above it
  const departments = allDepartments.filter((d) => !f.faculty || d.facultyCode === f.faculty);
  const programmes = allProgrammes.filter((p) => (!f.department || p.deptCode === f.department) && (!f.faculty || p.facultyCode === f.faculty));
  // the staff's departments and units, those of the faculty chosen
  const staffUnits = units.filter((u) => !f.faculty || u.facultyCode === f.faculty);

  const facName = (code: string) => faculties.find((x) => x.code === code)?.name ?? code;
  const narrowing = [
    filters.faculty ? facName(filters.faculty) : "",
    tab === "students" && filters.department ? allDepartments.find((d) => d.code === filters.department)?.name ?? filters.department : "",
    tab === "students" && filters.programme ? allProgrammes.find((p) => p.code === filters.programme)?.name ?? filters.programme : "",
    tab === "students" && filters.level ? `${filters.level} Level` : "",
    tab === "staff" && filters.unit ? units.find((u) => u.code === filters.unit)?.name ?? filters.unit : "",
    tab === "staff" && filters.category ? categoryWord(filters.category) : "",
  ].filter(Boolean).join(" · ");
  const missingWord = (tab === "students" ? STUDENT_MISSING : STAFF_MISSING).find(([k]) => k === filters.missing)?.[1] ?? "";
  const title = `Identity completion — ${tab === "students" ? "students" : "staff"}${missingWord && filters.missing ? ` — ${missingWord.toLowerCase()}` : ""}`;

  async function exportAll() {
    if (exporting) return;
    setExporting(true);
    try {
      const p = new URLSearchParams();
      const keys: (keyof CompletionFilters)[] = tab === "students" ? ["faculty", "department", "programme", "level", "missing", "q"] : ["faculty", "unit", "category", "missing", "q"];
      for (const k of keys) if (filters[k]) p.set(k, String(filters[k]));
      // the whole filtered list in one reading (the API's export: up to 20,000 rows)
      p.set("export", "true");
      const r = await fetch(`/api/bff/api/v1/identity/completion/${tab}/list?${p}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const pg = tab === "students" ? pageOf(j, studentRowOf, { page: 1, size: EXPORT_CAP }) : pageOf(j, staffRowOf, { page: 1, size: EXPORT_CAP });
      const total = pg.total;
      const rows: (StudentRow | StaffRow)[] = pg.rows.slice(0, EXPORT_CAP);
      const cols = tab === "students"
        ? ["Student", "Matriculation number", "Faculty", "Department", "Programme", "Level", "Blood group", "Blood group confirmed", "Confirmed on", "Photograph", "Complete"]
        : ["Member of staff", "Staff number", "Category", "Department or unit", "Faculty", "Photograph", "E-mail", "E-mail state", "Blood group", "Blood group confirmed", "Can sign in", "Complete"];
      const out = tab === "students"
        ? (rows as StudentRow[]).map((r) => [r.name, r.matricNo ?? "", r.faculty ?? "", r.department ?? "", r.programme ?? "", r.level == null ? "" : String(r.level),
            r.bloodGroup ?? "", r.bloodConfirmed ? "Yes" : "No", r.bloodConfirmedAt ? day(r.bloodConfirmedAt) : "", r.hasPhoto ? "Yes" : "No", r.complete ? "Yes" : "No"])
        : (rows as StaffRow[]).map((r) => [r.name, r.staffNumber ?? "", categoryWord(r.category), r.unit ?? "", r.faculty ?? "", staffPhotoWord(r.hasPhoto, r.photoEnhanced)[0],
            r.email ?? "", staffEmailWord(r.email, r.emailVerified, r.emailPending)[0], r.bloodGroup ?? "", r.bloodConfirmed ? "Yes" : "No", r.canSignIn ? "Yes" : "No", r.complete ? "Yes" : "No"]);
      const sub = [narrowing, filters.q ? `search “${filters.q}”` : "", total > rows.length ? `the first ${fmt(rows.length)} of ${fmt(total)}` : `${fmt(rows.length)} ${tab === "students" ? "students" : "staff"}`].filter(Boolean).join(" · ");
      const serial = docSerial("IDC");
      downloadBlob(await brandedXlsx(title, cols, out, { serial, sub, sheetName: tab === "students" ? "Students" : "Staff" }), `${title.replace(/[\\/:*?"<>|]/g, "-")}.xlsx`);
      if (total > rows.length) notify(`The first ${fmt(rows.length)} of ${fmt(total)} are in the workbook: narrow the list for the rest`, "warn");
    } catch {
      notifyProblem({ status: 0, title: "The list could not be read" });
    } finally {
      setExporting(false);
    }
  }

  const page = tab === "students" ? students : staff;
  const pages = page ? Math.max(1, Math.ceil(page.total / Math.max(1, page.size))) : 1;
  const missingOptions = tab === "students" ? STUDENT_MISSING : STAFF_MISSING;

  return (
    <>
      {tabs.length > 1 ? (
        <Tabs label="Who" value={tab} onChange={(t) => { if (t !== tab) go({ tab: t }); }}
          items={tabs.map((t) => ({ id: t, label: t === "students" ? "Students" : "Staff" }))} />
      ) : null}

      <Note kind="info" title={tab === "students" ? "Students in study — what the student identity card waits on" : "Staff in service — what the staff identity card and the University's letters need"}>
        {tab === "students"
          ? "A student's card is printed once the blood group is confirmed (by the student on the dashboard, or recorded at the card desk) and the matriculation number is issued; the photograph prints in its frame. Students are asked on their dashboard until their blood group is confirmed."
          : "In service means a staff number, an office today or the HR register, and not deactivated or out of service in HR (every employment ended, from the exit's effective date) — the staff card's own reading. Complete means the photograph enhanced and accepted, the e-mail address verified by a code, and the blood group confirmed. Staff who cannot sign in (on the HR register only, or with no sign-in) are never asked on a dashboard: reach them another way."}
        {narrowing ? ` Showing: ${narrowing}.` : ""}
      </Note>

      <Panel title="Narrow the count">
        <PBody>
          <form className="row row--wrap row--tight" onSubmit={(e) => { e.preventDefault(); go({ ...f, page: 1 }); }}>
            <select className="ctl" aria-label="Faculty" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, department: "", programme: "", unit: "" })} style={{ maxWidth: 260 }}>
              <option value="">Every faculty</option>
              {faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              {f.faculty && !faculties.some((x) => x.code === f.faculty) ? <option value={f.faculty}>{f.faculty}</option> : null}
            </select>
            {tab === "students" ? (
              <>
                <select className="ctl" aria-label="Department" value={f.department} onChange={(e) => setF({ ...f, department: e.target.value, programme: "" })} style={{ maxWidth: 260 }}>
                  <option value="">Every department</option>
                  {departments.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
                <select className="ctl" aria-label="Programme" value={f.programme} onChange={(e) => setF({ ...f, programme: e.target.value })} style={{ maxWidth: 260 }}>
                  <option value="">Every programme</option>
                  {programmes.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
                <select className="ctl" aria-label="Level" value={f.level} onChange={(e) => setF({ ...f, level: e.target.value })}>
                  <option value="">Every level</option>
                  {STUDENT_LEVELS.map((l) => <option key={l} value={l}>{l} Level</option>)}
                </select>
              </>
            ) : (
              <>
                <select className="ctl" aria-label="Department or unit" value={f.unit} onChange={(e) => setF({ ...f, unit: e.target.value })} style={{ maxWidth: 280 }}>
                  <option value="">Every department and unit</option>
                  {staffUnits.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
                <select className="ctl" aria-label="Category" value={f.category} onChange={(e) => setF({ ...f, category: e.target.value })}>
                  {STAFF_CATEGORIES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </>
            )}
            <Btn kind="secondary" size="sm" type="submit">Show</Btn>
            <LinkBtn kind="ghost" size="sm" href={`/identity/completion?tab=${tab}`}>Clear</LinkBtn>
          </form>
        </PBody>
      </Panel>

      {countsProblem ? <ProblemNotice problem={countsProblem} /> : null}
      {tab === "students" && studentCounts ? (() => {
        const c = studentCounts;
        return (
          <Tiles cls="grid--3" items={[
            ["Students in study", fmt(c.total), null, "Admitted, active, on probation or dormant", href({ missing: "" })],
            ["Blood group confirmed", fmt(c.blood_confirmed), "var(--green-ink)", `${pct(c.blood_confirmed, c.total)} · ${fmt(c.blood_unconfirmed)} given, not confirmed · ${fmt(c.blood_missing)} none`, href({ missing: "BLOOD" })],
            ["With a photograph", fmt(c.with_photo), null, `${pct(c.with_photo, c.total)} · ${fmt(c.without_photo)} without`, href({ missing: "PHOTO" })],
            ["No matriculation number", fmt(c.without_matric), c.without_matric ? "var(--chrome)" : null, "The card waits on it", href({ missing: "MATRIC" })],
            ["Complete", fmt(c.complete), "var(--green-ink)", `${pct(c.complete, c.total)} · blood group confirmed, photograph, matriculation number`],
            ["Need updating", fmt(c.needs_update), c.needs_update ? "var(--red-ink)" : "var(--green-ink)", "Click a count to list them", href({ missing: "ANY" })],
          ]} />
        );
      })() : null}
      {tab === "staff" && staffCounts ? (() => {
        const c = staffCounts;
        return (
          <Tiles cls="grid--3" items={[
            ["Staff in service", fmt(c.total), null, `${fmt(c.no_sign_in)} cannot sign in to be asked`, href({ missing: "" })],
            ["Photograph enhanced and accepted", fmt(c.photo_enhanced), "var(--green-ink)", `${pct(c.photo_enhanced, c.total)} · ${fmt(c.with_photo)} with any photograph · ${fmt(c.without_photo)} none`, href({ missing: "PHOTO" })],
            ["E-mail verified", fmt(c.email_verified), "var(--green-ink)", `${pct(c.email_verified, c.total)} · ${fmt(c.email_unverified)} not verified · ${fmt(c.email_missing)} none`, href({ missing: "EMAIL" })],
            ["Blood group confirmed", fmt(c.blood_confirmed), "var(--green-ink)", `${pct(c.blood_confirmed, c.total)} · ${fmt(c.blood_unconfirmed)} not confirmed · ${fmt(c.blood_missing)} none`, href({ missing: "BLOOD" })],
            ["Complete", fmt(c.complete), "var(--green-ink)", `${pct(c.complete, c.total)} · all three done`],
            ["Not complete", fmt(Math.max(0, c.total - c.complete)), c.total - c.complete > 0 ? "var(--red-ink)" : "var(--green-ink)", "Click a count to list them", href({ missing: "ANY" })],
          ]} />
        );
      })() : null}

      <Panel title={tab === "students" ? "Students" : "Staff"} right={page ? `${fmt(page.total)} matching · page ${page.page} of ${pages}` : ""}>
        <PBody style={{ borderBottom: "1px solid var(--line-2)" }}>
          <form className="row row--wrap row--tight" onSubmit={(e) => { e.preventDefault(); go({ ...f, page: 1 }); }}>
            <select className="ctl" aria-label="What is missing" value={f.missing} onChange={(e) => setF({ ...f, missing: e.target.value })}>
              {missingOptions.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </select>
            <input className="ctl" aria-label="Search" placeholder={tab === "students" ? "Name, matriculation, admission or JAMB number" : "Name, staff number or e-mail"}
              value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} style={{ minWidth: 240 }} />
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
            {page && page.total > 0 ? (
              <Btn kind="ghost" size="sm" busy={exporting} busyLabel="Preparing…" onClick={() => exportAll()}>Excel</Btn>
            ) : null}
          </form>
        </PBody>
        {listProblem ? <PBody><ProblemNotice problem={listProblem} /></PBody> : null}
        {tab === "students" && students && students.rows.length ? (
          <DTable pageSize={0} cols={["Student", "Programme", "Level|mid", "Blood group", "Photograph|mid", "Complete|mid"]} rows={students.rows.map((r) => {
            const [bw, bk] = bloodWord(r.bloodGroup, r.bloodConfirmed);
            return [
              <span key="s"><a className="lnk" href={`/students/${encodeURIComponent(r.studentId)}`}><b>{r.name || "—"}</b></a><div className="sub2 tnum">{r.matricNo ?? "No matriculation number"}</div></span>,
              <span key="p" className="sub2">{r.programme ?? ""}<div>{r.department ?? ""}</div></span>,
              <span key="l" className="tnum">{r.level ?? ""}</span>,
              <span key="b"><Pil kind={bk}>{bw}</Pil>{r.bloodConfirmed && r.bloodConfirmedAt ? <div className="sub2 tnum">{day(r.bloodConfirmedAt)}</div> : null}</span>,
              <Pil key="ph" kind={r.hasPhoto ? "ok" : "bad"}>{r.hasPhoto ? "On file" : "None"}</Pil>,
              <Pil key="c" kind={r.complete ? "ok" : "warn"}>{r.complete ? "Complete" : "Not yet"}</Pil>,
            ];
          })} texts={students.rows.map((r) => `${r.name} ${r.matricNo ?? ""} ${r.programme ?? ""} ${r.bloodGroup ?? ""}`)} />
        ) : null}
        {tab === "staff" && staff && staff.rows.length ? (
          <DTable pageSize={0} cols={["Member of staff", "Department or unit", "Category", "Photograph", "E-mail", "Blood group", "Sign-in|mid", "Complete|mid"]} rows={staff.rows.map((r) => {
            const [pw, pk] = staffPhotoWord(r.hasPhoto, r.photoEnhanced);
            const [ew, ek] = staffEmailWord(r.email, r.emailVerified, r.emailPending);
            const [bw, bk] = bloodWord(r.bloodGroup, r.bloodConfirmed);
            return [
              <span key="n"><b>{r.name || "—"}</b><div className="sub2 tnum">{r.staffNumber ?? ""}</div></span>,
              <span key="u" className="sub2">{r.unit ?? "—"}<div>{r.faculty ?? ""}</div></span>,
              <span key="c" className="sub2">{categoryWord(r.category)}</span>,
              <Pil key="p" kind={pk}>{pw}</Pil>,
              <span key="e"><span className="sub2">{r.email ?? ""}</span><div><Pil kind={ek}>{ew}</Pil></div></span>,
              <Pil key="b" kind={bk}>{bw}</Pil>,
              <span key="s" className="sub2">{r.canSignIn ? "Can sign in" : r.inOffice ? "No sign-in" : "HR register only"}</span>,
              <Pil key="k" kind={r.complete ? "ok" : "warn"}>{r.complete ? "Complete" : "Not yet"}</Pil>,
            ];
          })} texts={staff.rows.map((r) => `${r.name} ${r.staffNumber ?? ""} ${r.email ?? ""} ${r.unit ?? ""}`)} />
        ) : null}
        {page && !page.rows.length ? <PBody><div className="sub2">Nobody matches.</div></PBody> : null}
        {page && pages > 1 ? (
          <PBody><div className="row row--inline row--tight">
            <Btn kind="ghost" size="sm" disabled={page.page <= 1} onClick={() => go({ ...filters, page: page.page - 1 })}>Previous</Btn>
            <span className="sub2">page {page.page} of {pages}</span>
            <Btn kind="ghost" size="sm" disabled={page.page >= pages} onClick={() => go({ ...filters, page: page.page + 1 })}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>
    </>
  );
}
