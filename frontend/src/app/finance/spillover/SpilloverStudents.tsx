"use client";

/**
 * The Bursary's spillover students (V637). For a session: every student in study charged the spillover lines — SP1/SP2 at the final
 * level as the level desk sets them, or above it — with the SP year, the semesters a course is registered in (a semester's spillover
 * fee is owed only then, never a full session), the carry-overs the results state, due, paid, owing and where each stands; by faculty,
 * department, SP year, state or search; Excel and PDF, S/N first. The server decides who is in spillover and every figure.
 */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { StudentOpen } from "@/components/StudentModal";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { LIST_STATE_WORDS, semesterWord, type ListState } from "@/lib/spillover";

export interface SpilloverRow {
  student_id: string; student: string; matric_no: string | null; programme_code: string; programme: string; dept_code: string; department: string;
  faculty_code: string; faculty: string; level: number; final_level: number; spill_year: number | null; spillover_state: string | null;
  registered_semesters: number[]; carryovers: number; due: number | string; paid: number | string; owing: number | string; state: ListState;
  last_paid_at: string | null; last_reference: string | null;
}
export interface SpilloverList { session: string; sessions: string[]; rows: SpilloverRow[] }
type Unit = { faculty_code: string; faculty: string; dept_code: string; department: string };

const n = (v: unknown) => Number(v ?? 0).toLocaleString("en-GB");
const money = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const num = (v: unknown) => Math.round(Number(v ?? 0) * 100) / 100;
const semsWords = (sems: number[]) => (sems.length ? sems.map((x) => semesterWord(x).replace(" semester", "")).join(" & ") + (sems.length === 1 ? " semester" : " semesters") : "None");

export const SPILLOVER_HEADERS = ["S/N", "Student", "Matric No.", "Faculty", "Department", "Programme", "Level", "SP year", "Semesters registered", "Carry-overs",
  "Due (₦)", "Paid (₦)", "Owing (₦)", "State", "Last reference"];

function href(f: Record<string, string>): string {
  const q = new URLSearchParams();
  for (const k of ["session", "fac", "dept", "year", "state", "q"]) if (f[k]) q.set(k, f[k]);
  return `/finance/spillover${q.toString() ? `?${q.toString()}` : ""}`;
}

export function SpilloverStudents({ data, structure, filters, generatedBy }: { data: SpilloverList; structure: Unit[]; filters: Record<string, string>; generatedBy: string | null }) {
  const go = useQueryNav();
  const nav = (c: Record<string, string>) => go(href({ ...filters, session: data.session, ...c }));
  const [busy, setBusy] = useState(false);
  const faculties = Array.from(new Map(structure.map((u) => [u.faculty_code, u.faculty])).entries());
  const departments = structure.filter((u) => !filters.fac || u.faculty_code === filters.fac);
  const rows = data.rows;
  const count = (st: ListState) => rows.filter((r) => r.state === st).length;
  const sum = (k: "due" | "paid" | "owing", st?: ListState) => rows.filter((r) => !st || r.state === st).reduce((a, r) => a + Number(r[k] ?? 0), 0);
  const scopeWords = [data.session, filters.fac ? faculties.find(([c]) => c === filters.fac)?.[1] ?? filters.fac : "", filters.dept ? departments.find((u) => u.dept_code === filters.dept)?.department ?? filters.dept : "",
    filters.year ? `SP${filters.year}` : "", filters.state ? LIST_STATE_WORDS[filters.state as ListState]?.[0] ?? filters.state : ""].filter(Boolean).join(" · ");
  const title = `Spillover students, ${data.session}`;
  const reportRows = () => rows.map((r, i) => [i + 1, r.student, r.matric_no ?? "", r.faculty, r.department, r.programme, r.level, r.spill_year ? `SP${r.spill_year}` : "Spillover",
    semsWords(r.registered_semesters), r.carryovers, num(r.due), num(r.paid), num(r.owing), LIST_STATE_WORDS[r.state]?.[0] ?? r.state, r.last_reference ?? ""]);

  return (
    <>
      <Tiles cls="grid--5" items={[
        ["Spillover students", n(rows.length), null, `${scopeWords}${rows.length >= 1000 ? " · first 1,000" : ""}`],
        ["No course registered", n(count("NOT_REGISTERED")), null, "Nothing owed until a course is registered", href({ ...filters, session: data.session, state: "NOT_REGISTERED" })],
        ["Owing", n(count("OWES") + count("PART_PAID")), count("OWES") + count("PART_PAID") ? "var(--red-ink)" : null, `${money(sum("owing"))} still to pay`, href({ ...filters, session: data.session, state: "OWES" })],
        ["Paid", n(count("PAID")), "var(--green-ink)", `${money(sum("paid", "PAID"))} for the semesters registered`, href({ ...filters, session: data.session, state: "PAID" })],
        ["Paid above what is owed", n(count("PAID_ABOVE")), count("PAID_ABOVE") ? "var(--amber-ink)" : null, `${money(sum("paid", "PAID_ABOVE") - sum("due", "PAID_ABOVE"))} above · carried or refunded on the overpaid desk`, href({ ...filters, session: data.session, state: "PAID_ABOVE" })],
      ]} />
      <Panel title={`Spillover students · ${data.session}`} right={`${n(rows.length)} listed`}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="sp-session" label="Session" style={{ flex: "0 1 150px" }}>
              <select id="sp-session" className="ctl" value={data.session} onChange={(e) => nav({ session: e.target.value })}>
                {(data.sessions.includes(data.session) ? data.sessions : [data.session, ...data.sessions]).map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
            </Field>
            <Field id="sp-q" label="Search" style={{ flex: "2 1 200px" }}>
              <input id="sp-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Name, matriculation, JAMB or application number"
                onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
            </Field>
            <Field id="sp-fac" label="Faculty" style={{ flex: "1 1 180px" }}>
              <SearchSelect id="sp-fac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any faculty" options={faculties.map(([c, l]) => ({ value: c, label: l }))} />
            </Field>
            <Field id="sp-dept" label="Department" style={{ flex: "1 1 200px" }}>
              <SearchSelect id="sp-dept" value={filters.dept ?? ""} onChange={(v) => nav({ dept: v })} allLabel="Any department" options={departments.map((u) => ({ value: u.dept_code, label: u.department }))} />
            </Field>
            <Field id="sp-year" label="SP year" style={{ flex: "0 1 120px" }}>
              <select id="sp-year" className="ctl" value={filters.year ?? ""} onChange={(e) => nav({ year: e.target.value })}>
                <option value="">Any</option><option value="1">SP1</option><option value="2">SP2</option><option value="3">SP3</option>
              </select>
            </Field>
            <Field id="sp-state" label="State" style={{ flex: "0 1 200px" }}>
              <select id="sp-state" className="ctl" value={filters.state ?? ""} onChange={(e) => nav({ state: e.target.value })}>
                <option value="">Any</option>
                {(Object.keys(LIST_STATE_WORDS) as ListState[]).map((k) => <option key={k} value={k}>{LIST_STATE_WORDS[k][0]}</option>)}
              </select>
            </Field>
            {filters.q || filters.fac || filters.dept || filters.year || filters.state ? <Btn kind="ghost" onClick={() => go(href({ session: data.session }))}>Clear</Btn> : null}
          </div>
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
            <Btn kind="ghost" size="sm" busy={busy} busyLabel="Preparing…" disabled={!rows.length} onClick={async () => {
              setBusy(true);
              try { downloadBlob(await brandedXlsx(title, SPILLOVER_HEADERS, reportRows(), { sheetName: "Spillover", serial: docSerial("SPL"), sub: scopeWords, meta: [["Scope", scopeWords], ["Rows", String(rows.length)]] }), `spillover-students-${data.session.replace("/", "-")}.xlsx`); }
              finally { setBusy(false); }
            }}>Download Excel</Btn>
            <Btn kind="ghost" size="sm" disabled={!rows.length} onClick={() => brandedPrint(title, scopeWords, SPILLOVER_HEADERS, reportRows(), docSerial("SPL"), { meta: [["Scope", scopeWords]], generatedBy, orientation: "landscape" })}>Download PDF</Btn>
          </div>
        </PBody>
        {rows.length ? (
          <DTable pageSize={50} cols={["Student", "Level · SP", "Semesters registered", "Carry-overs|num", "Due|num", "Paid|num", "Owing|num", "State", "|num"]}
            texts={rows.map((r) => `${r.student} ${r.matric_no ?? ""} ${r.programme} ${r.department}`)}
            rows={rows.map((r) => [
              <span key="s"><b>{r.student}</b><div className="sub2 tnum">{r.matric_no ?? "—"} · {r.programme}</div></span>,
              <span key="l" className="tnum">{r.level} · <b>{r.spill_year ? `SP${r.spill_year}` : "Spillover"}</b><div className="sub2">final level {r.final_level}</div></span>,
              <span key="g" className="sub2">{semsWords(r.registered_semesters)}</span>,
              <span key="c" className="tnum">{r.carryovers}</span>,
              <span key="d" className="tnum">{money(r.due)}</span>,
              <span key="p" className="tnum">{money(r.paid)}</span>,
              <span key="o" className={`tnum${Number(r.owing) >= 1 ? " ink-red b600" : " sub2"}`}>{money(r.owing)}</span>,
              <span key="t"><Pil kind={LIST_STATE_WORDS[r.state]?.[1] ?? "grey"}>{LIST_STATE_WORDS[r.state]?.[0] ?? r.state}</Pil></span>,
              <span key="x"><StudentOpen id={r.student_id} label="Record" kind="ghost" /></span>,
            ])} />
        ) : <PBody><div className="sub2">No spillover student matches the filters.</div></PBody>}
        <PBody>
          <Note kind="info" title="How spillover students pay">
            A student is in spillover when the records place them past their programme&rsquo;s length: SP1 or SP2 at the final level, as the level desk sets it, or a
            level above it. A spillover student pays a semester&rsquo;s spillover fee only for a semester they register a course in &mdash; one semester, or both &mdash;
            never the whole session&rsquo;s school fees for being in spillover. The fee is the spillover line the Bursary states for the programme, SP year and
            semester on Fee Setup. &ldquo;Paid above what is owed&rdquo; is money paid against the full-session charge before this rule: it is carried into the next
            session or refunded on the overpaid desk.
          </Note>
        </PBody>
      </Panel>
    </>
  );
}
