"use client";

/**
 * V442: the accounts still on their first password — the person's own number opens them, to whoever knows it. The students'
 * counts and list within the office's scope (a Dean or Head their own faculty or department), by unit; the staff and migrated
 * applicants for the offices that read the whole University. A reminder is a campaign with the filter "Still on their first
 * password" and the template "Choose your own password".
 */
import { useEffect, useState } from "react";
import { Btn, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

interface Summary { student_accounts: number; students_first: number; students_first_never: number; students_signed_in_first: number }
interface Others { staff_accounts: number; staff_first: number; staff_first_never: number; applicants_first: number }
interface Unit { code: string | null; name: string | null; accounts: number; first: number; first_never: number }
interface StudentRow { student_id: string; number: string; name: string; programme: string | null; department: string | null; faculty: string | null; level: number | null; status: string; account_created: string; last_signed_in_at: string | null }
interface StaffRow { person_id: string; staff_number: string | null; username: string; name: string; offices: string | null; set_at: string; last_sign_in_at: string | null; email: string | null; phone: string | null }
interface Page<T> { rows: T[]; total: number; page: number; size: number }
interface Reading extends Page<StudentRow> { faculty: string | null; department: string | null; summary: Summary; units: Unit[]; others: Others | null }

const STAFF_OFFICES = ["ict", "admin", "super", "registrar", "dregistrar", "hrm", "records"];

function day(iso: string | null): string {
  return iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "never";
}

export function FirstPasswords({ actingOffice, faculty, department }: { actingOffice: string | null; faculty: string; department: string }) {
  const [f, setF] = useState({ faculty, department, never: false, q: "", page: 1 });
  const [q, setQ] = useState("");
  const [d, setD] = useState<Reading | null>(null);
  const [failed, setFailed] = useState(false);
  const [staff, setStaff] = useState<Page<StaffRow> | null>(null);
  const [showStaff, setShowStaff] = useState(false);
  const mayStaff = STAFF_OFFICES.includes(actingOffice ?? "");

  useEffect(() => {
    let live = true;
    (async () => {
      const p = new URLSearchParams();
      if (f.faculty) p.set("faculty", f.faculty);
      if (f.department) p.set("department", f.department);
      if (f.never) p.set("never", "true");
      if (f.q) p.set("q", f.q);
      p.set("page", String(f.page));
      p.set("size", "100");
      const r = await fetch(`/api/bff/api/v1/biodata/compliance/first-passwords?${p}`, { cache: "no-store" });
      if (!live) return;
      if (!r.ok) { setFailed(true); return; }
      setD((await r.json()) as Reading);
    })();
    return () => { live = false; };
  }, [f]);

  useEffect(() => {
    if (!showStaff) return;
    let live = true;
    (async () => {
      const r = await fetch("/api/bff/api/v1/biodata/compliance/first-passwords/staff?size=500", { cache: "no-store" });
      if (!live || !r.ok) return;
      setStaff((await r.json()) as Page<StaffRow>);
    })();
    return () => { live = false; };
  }, [showStaff]);

  if (failed) return null;
  if (!d) return <Panel title="First passwords"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  const s = d.summary;
  const pages = Math.max(1, Math.ceil(d.total / d.size));
  const unitWord = d.department ? "Programme" : d.faculty ? "Department" : "Faculty";
  return (
    <Panel title="First passwords" right="Accounts that still open with the person's own number as the password">
      <PBody>
        <Tiles items={[
          ["Students on their first password", String(s.students_first), s.students_first ? "var(--red-ink)" : "var(--green-ink)", `of ${s.student_accounts} student accounts`],
          ["Never signed in", String(s.students_first_never), null, "Nobody has claimed these accounts"],
          ["Signed in, not yet changed", String(s.students_signed_in_first), null, "Asked to change at every sign-in"],
          ...(d.others ? [
            ["Staff on their first password", String(d.others.staff_first), d.others.staff_first ? "var(--red-ink)" : null, `of ${d.others.staff_accounts} staff accounts · ${d.others.staff_first_never} never signed in`] as [string, string, string | null, string],
            ["Migrated applicants", String(d.others.applicants_first), null, "Still opening on the JAMB number"] as [string, string, string | null, string],
          ] : []),
        ]} />
        <div className="sub2">
          An account nobody has claimed opens with the person&rsquo;s own number to whoever knows it; the portal asks for a new password at the first sign-in. To remind them,
          write a campaign on Campaigns &amp; announcements with the template <b>Choose your own password</b> and the filter <b>Still on their first password</b>.
        </div>
      </PBody>
      {d.units.length > 1 ? (
        <DTable cols={[unitWord, "Accounts|num", "On first password|num", "Never signed in|num", "Share|num"]} rows={d.units.map((u) => [
          !d.department && u.code ? <button key="u" type="button" className="linklike" onClick={() => setF(d.faculty ? { ...f, department: u.code ?? "", page: 1 } : { ...f, faculty: u.code ?? "", department: "", page: 1 })}>{u.name ?? u.code}</button> : <span key="u">{u.name ?? u.code ?? "—"}</span>,
          <span key="a" className="tnum">{u.accounts}</span>,
          <span key="f" className="tnum">{u.first}</span>,
          <span key="n" className="tnum">{u.first_never}</span>,
          <span key="s" className="tnum">{u.accounts ? `${Math.round((100 * u.first) / u.accounts)}%` : "—"}</span>,
        ])} />
      ) : null}
      <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
        <form className="row row--wrap row--tight" onSubmit={(e) => { e.preventDefault(); setF({ ...f, q: q.trim(), page: 1 }); }}>
          {f.faculty || f.department ? <Btn kind="ghost" size="sm" onClick={() => setF({ ...f, faculty: "", department: "", page: 1 })}>Whole scope</Btn> : null}
          <label className="row row--inline row--tight"><input type="checkbox" checked={f.never} onChange={(e) => setF({ ...f, never: e.target.checked, page: 1 })} /> Never signed in only</label>
          <input className="ctl" aria-label="Search" placeholder="Name or number" value={q} onChange={(e) => setQ(e.target.value)} style={{ minWidth: 200 }} />
          <Btn kind="secondary" size="sm" type="submit">Search</Btn>
          <Btn kind="ghost" size="sm" disabled={!d.rows.length} onClick={async () => downloadBlob(await brandedXlsx("Accounts still on their first password",
            ["Number", "Name", "Programme", "Department", "Faculty", "Level", "Status", "Last signed in"],
            d.rows.map((r) => [r.number, r.name, r.programme ?? "", r.department ?? "", r.faculty ?? "", String(r.level ?? ""), r.status, day(r.last_signed_in_at)]),
            { serial: docSerial("FPW") }), "First passwords.xlsx")}>Excel (this page)</Btn>
          <span className="sub2">{d.total} student{d.total === 1 ? "" : "s"}{d.department ? ` in ${d.department}` : d.faculty ? ` in ${d.faculty}` : ""}</span>
        </form>
      </PBody>
      {d.rows.length ? (
        <DTable cols={["Number", "Name", "Programme", "Level|num", "Status|mid", "Last signed in|mid"]} rows={d.rows.map((r) => [
          <a key="n" className="tnum" href={`/students/${r.student_id}`}>{r.number}</a>, r.name, <span key="p" className="sub2">{r.programme ?? "—"}</span>,
          <span key="l" className="tnum">{r.level ?? "—"}</span>, <span key="s" className="sub2">{r.status.toLowerCase()}</span>, <span key="d" className="sub2">{day(r.last_signed_in_at)}</span>,
        ])} />
      ) : <PBody><div className="sub2">No student account in this scope is still on its first password.</div></PBody>}
      {pages > 1 ? (
        <PBody>
          <div className="row row--tight">
            <Btn kind="ghost" size="sm" disabled={f.page <= 1} onClick={() => setF({ ...f, page: f.page - 1 })}>Previous</Btn>
            <span className="sub2">Page {d.page} of {pages}</span>
            <Btn kind="ghost" size="sm" disabled={f.page >= pages} onClick={() => setF({ ...f, page: f.page + 1 })}>Next</Btn>
          </div>
        </PBody>
      ) : null}
      {mayStaff ? (
        <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
          <Btn kind="ghost" size="sm" onClick={() => setShowStaff(!showStaff)}>{showStaff ? "Hide the staff" : "Show the staff on their first password"}</Btn>
          {showStaff && staff ? (
            staff.rows.length ? (
              <DTable cols={["Staff number", "Name", "Offices", "Account set|mid", "Last signed in|mid", "E-mail", "Phone"]} rows={staff.rows.map((r) => [
                <span key="n" className="tnum">{r.staff_number ?? r.username}</span>, r.name, <span key="o" className="sub2">{r.offices ?? "—"}</span>,
                <span key="s" className="sub2">{day(r.set_at)}</span>, <span key="l" className="sub2">{day(r.last_sign_in_at)}</span>,
                <span key="e" className="sub2">{r.email ?? "—"}</span>, <span key="p" className="sub2">{r.phone ?? "—"}</span>,
              ])} />
            ) : <div className="sub2 mt-1">Every member of staff has chosen a password.</div>
          ) : null}
        </PBody>
      ) : null}
    </Panel>
  );
}
