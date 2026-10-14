"use client";

/** t/compliance (V426): where every student's biodata stands — the counts from the quarter-hourly reading, the students behind
 *  each count (filtered, searched, printed or exported), and the data-quality picture: addresses missing, not addresses, shared.
 *  V434: the one Biodata compliance screen — the ICT Director's switch with its readiness, what is missing and where, the
 *  required items with what each would do, the exceptions and the history are here too, all from the same reading. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { pct, type ComplianceOverview } from "@/lib/biodata-gate";
import { STUDENT_LEVELS } from "@/lib/levels";
import { Exceptions, GateHistory, GatePanel, Requirements } from "./GateAdmin";

export interface ComplianceSummary {
  faculty: string | null; department: string | null;
  summary: { total: number; up_to_date: number; incomplete: number; review_required: number; outdated: number; migrated: number; migrated_reviewed: number;
    no_email: number; no_phone: number; invalid_email: number; invalid_phone: number; never_signed_in: number; reminded_week: number; computed_at: string | null };
  quality: { shared_emails: number; students_sharing_email: number; shared_phones: number; students_sharing_phone: number; missing_email: number; missing_phone: number; invalid_email: number; invalid_phone: number; missing_passport: number };
  gate: { enabled: boolean; remind_enabled: boolean; review_days: number | null };
  requirements: { item: string; label: string; required: boolean }[];
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string }[];
  /** V434: what is missing, and the counts by faculty (by department within a faculty), from the same reading */
  items?: { item: string; label: string; students: number }[];
  units?: { code: string | null; name: string; faculty_code: string | null; total: number; incomplete: number; up_to_date: number }[];
}
export interface StudentRow {
  student_id: string; matric_no: string | null; jamb_reg_no: string | null; surname: string; other_names: string; faculty: string | null; department: string | null;
  programme: string | null; level: number; entry_session: string | null; status: string; email: string | null; phone: string | null; missing_labels: string[] | null;
  last_updated: string | null; confirmed_at: string | null; last_reminded_at: string | null; total: number;
}
export interface StudentsPage { rows: StudentRow[]; total: number; page: number; size: number; computedAt: string | null }
export interface Filters { status: string; faculty: string; department: string; programme: string; level: string; session: string; entryMode: string; migrated: string; q: string; page: string;
  /** V434: the required item missing, and the sex */
  missing: string; sex: string }
/** V430: staff reach */
export interface StaffRow { person_id: string; staff_number: string | null; surname: string; given_names: string; email: string | null; phone: string | null; status: string; offices: string | null; signed_in: boolean; last_reminded_at: string | null; total: number }
export interface StaffPage {
  summary: { total: number; reachable: number; phone_only: number; email_only: number; unreachable: number; no_email: number; bad_email: number; no_phone: number; bad_phone: number; never_signed_in: number; reminded_week: number };
  rows: StaffRow[]; total: number; page: number; size: number; remindEnabled: boolean; offices: { code: string; label: string }[];
}
export interface StaffFilters { status: string; office: string; q: string; page: string }
const REACH: Record<string, [string, "ok" | "bad" | "warn" | "grey"]> = { REACHABLE: ["Reachable", "ok"], PHONE_ONLY: ["Phone only", "warn"], EMAIL_ONLY: ["E-mail only", "warn"], UNREACHABLE: ["Unreachable", "bad"] };

const when = (s: string | null | undefined) => (s ? new Date(s).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "");
const day = (s: string | null | undefined) => (s ? new Date(s).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "");
const STATUS: Record<string, [string, "ok" | "bad" | "warn" | "grey"]> = { UP_TO_DATE: ["Up to date", "ok"], INCOMPLETE: ["Incomplete", "bad"], REVIEW_REQUIRED: ["Review required", "warn"], OUTDATED: ["Outdated", "warn"] };

export function Compliance({ d, students, filters, actingOffice, staff = null, staffFilters = { status: "", office: "", q: "", page: "1" }, admin = null }:
  { d: ComplianceSummary; students: StudentsPage | null; filters: Filters; actingOffice: string | null; staff?: StaffPage | null; staffFilters?: StaffFilters;
    /** V434: the switch's half — the gate, the required items, and for the ICT Director the exceptions and the history */
    admin?: ComplianceOverview | null }) {
  const [sf, setSf] = useState<StaffFilters>(staffFilters);
  const goStaff = (next: StaffFilters) => {
    const p = new URLSearchParams();
    (Object.keys(filters) as (keyof Filters)[]).forEach((k) => { if (filters[k] && !(k === "page" && filters[k] === "1")) p.set(k, filters[k]); });
    if (next.status) p.set("staffStatus", next.status);
    if (next.office) p.set("office", next.office);
    if (next.q) p.set("sq", next.q);
    if (next.page && next.page !== "1") p.set("spage", next.page);
    router.push(`/biodata/compliance${p.toString() ? `?${p}` : ""}#staff`);
  };
  const router = useRouter();
  const may = ["ict", "admin", "super", "registrar"].includes(actingOffice ?? "");
  const bound = !["ict", "admin", "super", "registrar", "dregistrar", "academic", "records", "dsa"].includes(actingOffice ?? "");
  const [f, setF] = useState<Filters>(filters);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [dups, setDups] = useState<{ kind: string; rows: { value: string; students: number; names: string }[] } | null>(null);
  const s = d.summary;
  const items = d.items ?? [];
  const units = d.units ?? [];
  const missingLabel = (item: string) => items.find((x) => x.item === item)?.label ?? d.requirements.find((r) => r.item === item)?.label ?? item;

  function go(next: Filters) {
    const p = new URLSearchParams();
    (Object.keys(next) as (keyof Filters)[]).forEach((k) => { if (next[k] && !(k === "page" && next[k] === "1")) p.set(k, next[k]); });
    router.push(`/biodata/compliance${p.toString() ? `?${p}` : ""}`);
  }
  const tile = (status: string) => () => go({ ...filters, status, page: "1" });

  async function refresh() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/biodata/compliance/refresh", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Biodata status reading taken now") }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`Reading taken over ${(j as { students?: number })?.students ?? 0} students`);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function showDuplicates(kind: "EMAIL" | "PHONE") {
    setBusy(true); setProblem(null);
    try {
      const scope = new URLSearchParams({ kind });
      if (d.faculty) scope.set("faculty", d.faculty);
      if (d.department) scope.set("department", d.department);
      const r = await fetch(`/api/bff/api/v1/biodata/compliance/duplicates?${scope}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setDups({ kind, rows: j as { value: string; students: number; names: string }[] });
    } finally { setBusy(false); }
  }

  const COLS = ["S/N", "Student", "Matric number", "JAMB number", "Faculty", "Department", "Programme", "Level", "Email", "Phone", "Status", "Missing", "Last updated", "Last reminder"];
  const rowsOut = () => (students?.rows ?? []).map((r, i) => [String(i + 1), `${r.surname}, ${r.other_names}`, r.matric_no ?? "", r.jamb_reg_no ?? "", r.faculty ?? "", r.department ?? "", r.programme ?? "",
    String(r.level), r.email ?? "", r.phone ?? "", STATUS[r.status]?.[0] ?? r.status, (r.missing_labels ?? []).join(", "), day(r.last_updated), day(r.last_reminded_at)]);
  const title = `Biodata compliance${filters.status ? " — " + (STATUS[filters.status]?.[0] ?? filters.status) : ""}${filters.missing ? " — missing " + missingLabel(filters.missing).toLowerCase() : ""}${d.faculty ? " — " + (d.faculties.find((x) => x.code === d.faculty)?.name ?? d.faculty) : ""}`;
  const depts = d.departments.filter((x) => !f.faculty || x.faculty_code === f.faculty);
  const pages = students ? Math.max(1, Math.ceil(students.total / students.size)) : 1;

  return (
    <>
      {admin ? <GatePanel admin={admin} readiness={{ total: s.total, incomplete: s.incomplete, computedAt: s.computed_at, scoped: !!(d.faculty || d.department) }} /> : null}
      <Note kind="info" title={`From the reading taken ${s.computed_at ? when(s.computed_at) : "— not yet"}; the scheduler takes one every quarter of an hour`}>
        {d.gate.enabled ? "The biodata gate is ON: a student with incomplete required items reaches only the biodata page. " : "The biodata gate is OFF. "}
        {d.gate.remind_enabled || d.gate.enabled ? "The weekly reminder runs on Monday mornings to every student whose record is not up to date." : "The weekly reminder is off."}
        {" "}Required: {d.requirements.filter((r) => r.required).map((r) => r.label).join(", ")}.
        {bound ? " You read your own faculty or department." : ""}
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Students", String(s.total), null, "On the register, in the portal's use"],
        ["Up to date", String(s.up_to_date), "var(--green-ink)", "Click a count to list them"],
        ["Incomplete", String(s.incomplete), s.incomplete ? "var(--red-ink)" : null, "A required item missing"],
        ["Review required", String(s.review_required), s.review_required ? "var(--chrome)" : null, "Came over, never reviewed or confirmed"],
        ["Outdated", String(s.outdated), s.outdated ? "var(--chrome)" : null, d.gate.review_days ? `Past ${d.gate.review_days} days` : "No review period set"],
        ["Came over from the old portal", String(s.migrated), null, `${s.migrated_reviewed} of them up to date`],
        ["No e-mail · no phone", `${s.no_email} · ${s.no_phone}`, s.no_email || s.no_phone ? "var(--red-ink)" : null, `${s.invalid_email} bad e-mails · ${s.invalid_phone} bad phones`],
        ["Never signed in", String(s.never_signed_in), null, `${s.reminded_week} reminded this week`],
      ]} />
      <div className="row row--wrap row--tight mt-1">
        <Btn kind="ghost" size="sm" onClick={tile("UP_TO_DATE")}>Up to date</Btn>
        <Btn kind="ghost" size="sm" onClick={tile("INCOMPLETE")}>Incomplete</Btn>
        <Btn kind="ghost" size="sm" onClick={tile("REVIEW_REQUIRED")}>Review required</Btn>
        <Btn kind="ghost" size="sm" onClick={tile("OUTDATED")}>Outdated</Btn>
        <Btn kind="ghost" size="sm" onClick={() => go({ ...filters, status: "", migrated: "true", page: "1" })}>Came over</Btn>
        {may ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void refresh()}>Take the reading now</Btn> : null}
        <LinkBtn kind="ghost" size="sm" href="/notices/campaigns?open=new">Write to them</LinkBtn>
      </div>

      <div className="grid grid--2">
        <Panel title="What is missing" right={<span className="sub2">Students missing each required item</span>}>
          {items.length ? (
            <DTable pageSize={0} cols={["Item", "Students|num", "Share|num", "|num"]} rows={items.map((x) => [
              <span key="i" className="b600">{x.label}</span>,
              <span key="n" className="tnum">{x.students.toLocaleString()}</span>,
              <span key="p" className="tnum sub2">{pct(x.students, s.total)}</span>,
              <Btn key="l" kind="ghost" size="sm" onClick={() => go({ ...filters, status: "INCOMPLETE", missing: x.item, page: "1" })}>Students</Btn>,
            ])} texts={items.map((x) => x.label)} />
          ) : <PBody><div className="sub2">Nothing is missing.</div></PBody>}
        </Panel>
        <Panel title={d.faculty ? "By department" : "By faculty"}>
          {units.length ? (
            <DTable pageSize={0} cols={[d.faculty ? "Department" : "Faculty", "Students|num", "Incomplete|num", "Up to date|num", "Complete|num", "|num"]} rows={units.map((x) => [
              <span key="n" className="b600">{x.name}</span>,
              <span key="t" className="tnum">{x.total.toLocaleString()}</span>,
              <span key="i" className="tnum">{x.incomplete.toLocaleString()}</span>,
              <span key="u" className="tnum">{x.up_to_date.toLocaleString()}</span>,
              <span key="c" className="tnum sub2">{pct(x.total - x.incomplete, x.total)}</span>,
              x.code ? <Btn key="l" kind="ghost" size="sm" onClick={() => go({ ...filters, status: "INCOMPLETE", page: "1", ...(d.faculty ? { department: x.code ?? "" } : { faculty: x.code ?? "", department: "" }) })}>Incomplete</Btn> : <span key="l" />,
            ])} texts={units.map((x) => x.name)} />
          ) : <PBody><div className="sub2">No student in this view.</div></PBody>}
        </Panel>
      </div>

      <Panel title="Data quality" right="Addresses the portal cannot use, or that several students share">
        <PBody>
          <div className="row row--wrap row--tight">
            <span><b>{d.quality.shared_emails}</b> e-mails shared by {d.quality.students_sharing_email} students</span>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void showDuplicates("EMAIL")}>Show</Btn>
            <span><b>{d.quality.shared_phones}</b> phones shared by {d.quality.students_sharing_phone} students</span>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void showDuplicates("PHONE")}>Show</Btn>
            <span><b>{d.quality.missing_passport}</b> without a passport photograph</span>
          </div>
          {dups ? (
            <div className="mt-2">
              <DTable cols={[dups.kind === "EMAIL" ? "E-mail" : "Phone", "Students|num", "Who"]} rows={dups.rows.map((r) => [<span className="tnum" key="v">{r.value}</span>, <span className="tnum" key="n">{r.students}</span>, <span className="sub2" key="w">{r.names}</span>])} />
              {dups.rows.length === 0 ? <div className="sub2">None shared.</div> : null}
            </div>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="Students" right={students ? `${students.total} matching · page ${students.page} of ${pages}` : ""}>
        <PBody style={{ borderBottom: "1px solid var(--line-2)" }}>
          <form className="row row--wrap row--tight" onSubmit={(e) => { e.preventDefault(); go({ ...f, page: "1" }); }}>
            <select className="ctl" aria-label="Status" value={f.status} onChange={(e) => setF({ ...f, status: e.target.value })}>
              <option value="">Any status</option><option value="UP_TO_DATE">Up to date</option><option value="INCOMPLETE">Incomplete</option><option value="REVIEW_REQUIRED">Review required</option><option value="OUTDATED">Outdated</option>
            </select>
            {!bound ? (
              <select className="ctl" aria-label="Faculty" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, department: "" })}>
                <option value="">Any faculty</option>{d.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            ) : null}
            {!bound || actingOffice === "dean" || actingOffice === "facultyofficer" ? (
              <select className="ctl" aria-label="Department" value={f.department} onChange={(e) => setF({ ...f, department: e.target.value })}>
                <option value="">Any department</option>{depts.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            ) : null}
            <select className="ctl" aria-label="Level" value={f.level} onChange={(e) => setF({ ...f, level: e.target.value })}>
              <option value="">Any level</option>{STUDENT_LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
            <input className="ctl" aria-label="Entry session" placeholder="Entry session" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })} style={{ width: 120 }} />
            <select className="ctl" aria-label="Missing" value={f.missing} onChange={(e) => setF({ ...f, missing: e.target.value })}>
              <option value="">Missing anything</option>{d.requirements.filter((r) => r.required).map((r) => <option key={r.item} value={r.item}>Missing {r.label.toLowerCase()}</option>)}
            </select>
            <select className="ctl" aria-label="Gender" value={f.sex} onChange={(e) => setF({ ...f, sex: e.target.value })}>
              <option value="">Any gender</option><option value="F">Female</option><option value="M">Male</option>
            </select>
            <select className="ctl" aria-label="Came over" value={f.migrated} onChange={(e) => setF({ ...f, migrated: e.target.value })}>
              <option value="">Came over or not</option><option value="true">Came over</option><option value="false">Admitted on the portal</option>
            </select>
            <input className="ctl" aria-label="Search" placeholder="Name, number, e-mail or phone" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} style={{ minWidth: 220 }} />
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
            <LinkBtn kind="ghost" size="sm" href="/biodata/compliance">Clear</LinkBtn>
            {students?.rows.length ? <>
              <Btn kind="ghost" size="sm" onClick={() => brandedPrint(title, `${students.total} students · ${when(s.computed_at)}`, COLS, rowsOut(), docSerial("BIO"))}>Print</Btn>
              <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx(title, COLS, rowsOut(), { serial: docSerial("BIO") }), "Biodata compliance.xlsx")}>Excel</Btn>
            </> : null}
          </form>
        </PBody>
        {students?.rows.length ? (
          <DTable cols={["Student", "Programme", "Level|mid", "Contact", "Status|mid", "Missing", "Updated|mid", "Reminded|mid"]} rows={students.rows.map((r) => [
            <span key="s"><a href={`/students/${r.student_id}`}><b>{r.surname}, {r.other_names}</b></a><div className="sub2 tnum">{r.matric_no ?? r.jamb_reg_no ?? ""}</div></span>,
            <span key="p" className="sub2">{r.programme ?? ""}<div>{r.department ?? ""}</div></span>,
            <span className="tnum" key="l">{r.level}</span>,
            <span key="c" className="sub2">{r.email ?? <i>no e-mail</i>}<div className="tnum">{r.phone ?? <i>no phone</i>}</div></span>,
            <Pil key="st" kind={STATUS[r.status]?.[1] ?? "grey"}>{STATUS[r.status]?.[0] ?? r.status}</Pil>,
            <span key="m" className="sub2">{(r.missing_labels ?? []).join(", ")}</span>,
            <span key="u" className="sub2 tnum">{day(r.last_updated)}{r.confirmed_at ? <div>confirmed {day(r.confirmed_at)}</div> : null}</span>,
            <span key="r" className="sub2 tnum">{day(r.last_reminded_at)}</span>,
          ])} texts={students.rows.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.email ?? ""} ${r.phone ?? ""} ${r.status}`)} />
        ) : <PBody><div className="sub2">{students ? "Nobody matches." : "The list could not be read."}</div></PBody>}
        {students && pages > 1 ? (
          <PBody><div className="row row--inline row--tight">
            <Btn kind="ghost" size="sm" disabled={students.page <= 1} onClick={() => go({ ...filters, page: String(students.page - 1) })}>Previous</Btn>
            <span className="sub2">page {students.page} of {pages}</span>
            <Btn kind="ghost" size="sm" disabled={students.page >= pages} onClick={() => go({ ...filters, page: String(students.page + 1) })}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>

      {staff ? (() => {
        const ss = staff.summary;
        const spages = Math.max(1, Math.ceil(staff.total / staff.size));
        return (
          <div id="staff">
            <Panel title="Staff reach" right={`${ss.total} active staff with an office · ${staff.remindEnabled ? "weekly reminder on" : "weekly reminder off"}`}>
              <PBody style={{ borderBottom: "1px solid var(--line-2)" }}>
                <Tiles items={[
                  ["Reachable", String(ss.reachable), "var(--green-ink)", "E-mail and phone both usable"],
                  ["Phone only", String(ss.phone_only), ss.phone_only ? "var(--chrome)" : null, `${ss.no_email} with no e-mail · ${ss.bad_email} not an address`],
                  ["E-mail only", String(ss.email_only), ss.email_only ? "var(--chrome)" : null, `${ss.no_phone} with no phone · ${ss.bad_phone} not a number`],
                  ["Unreachable", String(ss.unreachable), ss.unreachable ? "var(--red-ink)" : "var(--green-ink)", `${ss.never_signed_in} never signed in · ${ss.reminded_week} reminded this week`],
                ]} />
                <form className="row row--wrap row--tight mt-2" onSubmit={(e) => { e.preventDefault(); goStaff({ ...sf, page: "1" }); }}>
                  <select className="ctl" aria-label="Reach" value={sf.status} onChange={(e) => setSf({ ...sf, status: e.target.value })}>
                    <option value="">Any</option><option value="REACHABLE">Reachable</option><option value="PHONE_ONLY">Phone only</option><option value="EMAIL_ONLY">E-mail only</option><option value="UNREACHABLE">Unreachable</option>
                  </select>
                  <select className="ctl" aria-label="Office" value={sf.office} onChange={(e) => setSf({ ...sf, office: e.target.value })}>
                    <option value="">Any office</option>{staff.offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
                  </select>
                  <input className="ctl" aria-label="Search staff" placeholder="Name, staff number, e-mail or phone" value={sf.q} onChange={(e) => setSf({ ...sf, q: e.target.value })} style={{ minWidth: 220 }} />
                  <Btn kind="secondary" size="sm" type="submit">Search</Btn>
                  <LinkBtn kind="ghost" size="sm" href="/notices/campaigns?open=new">Write to the staff</LinkBtn>
                </form>
              </PBody>
              {staff.rows.length ? (
                <DTable cols={["Staff member", "Offices", "E-mail", "Phone", "Reach|mid", "Signed in|mid", "Reminded|mid"]} rows={staff.rows.map((r) => [
                  <span key="n"><b>{r.surname}, {r.given_names}</b><div className="sub2 tnum">{r.staff_number ?? ""}</div></span>,
                  <span key="o" className="sub2">{r.offices ?? ""}</span>,
                  <span key="e" className="sub2">{r.email ?? <i>none</i>}</span>,
                  <span key="p" className="sub2 tnum">{r.phone ?? <i>none</i>}</span>,
                  <Pil key="r" kind={REACH[r.status]?.[1] ?? "grey"}>{REACH[r.status]?.[0] ?? r.status}</Pil>,
                  <span key="s" className="sub2">{r.signed_in ? "Yes" : "Never"}</span>,
                  <span key="m" className="sub2 tnum">{day(r.last_reminded_at)}</span>,
                ])} texts={staff.rows.map((r) => `${r.surname} ${r.given_names} ${r.staff_number ?? ""} ${r.email ?? ""} ${r.phone ?? ""} ${r.status}`)} />
              ) : <PBody><div className="sub2">Nobody matches.</div></PBody>}
              {spages > 1 ? (
                <PBody><div className="row row--inline row--tight">
                  <Btn kind="ghost" size="sm" disabled={staff.page <= 1} onClick={() => goStaff({ ...staffFilters, page: String(staff.page - 1) })}>Previous</Btn>
                  <span className="sub2">page {staff.page} of {spages}</span>
                  <Btn kind="ghost" size="sm" disabled={staff.page >= spages} onClick={() => goStaff({ ...staffFilters, page: String(staff.page + 1) })}>Next</Btn>
                </div></PBody>
              ) : null}
            </Panel>
          </div>
        );
      })() : null}

      {admin ? <Requirements items={admin.requirements} canSet={admin.canSet} gateOn={admin.gate.enabled} /> : null}
      {admin?.canSet ? <Exceptions rows={admin.exceptions ?? []} today={admin.today} /> : null}
      {admin?.canSet ? <GateHistory admin={admin} /> : null}
    </>
  );
}
