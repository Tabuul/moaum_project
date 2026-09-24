"use client";

import { notifyProblem } from "@/components/proto/Toast";
/**
 * A member of staff's whole record in a pop-up, opened from any list that names them — the Staff
 * register, the Search desk, the establishment roll. The photograph HR holds, the person and their
 * rank, department and status, then tabs: Overview (appointment, employment, contact, offices held),
 * Profile (the academic CV they keep: research interests, publications, grants, collaborations …),
 * Teaching (the courses they carry, with class sizes) and Leave. Read-only; pay is not shown here.
 */
import { useEffect, useState, type ReactNode } from "react";
import { Btn, KvGrid, Note, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Passport, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";

interface Person {
  id: string; staff_number: string | null; surname: string; given_names: string; email: string | null; phone: string | null;
  ended_on: string | null; ended_reason: string | null; pno: string | null; sex: string | null; rank: string | null; conuass_step: number | null;
  date_first_appointment: string | null; department_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  grade: string | null; step: number | null; category: string | null; appointment_date: string | null; employment_status: string | null;
  employment_ended_on: string | null; status: string; has_photo: boolean; has_account: boolean;
}
interface Office { office_code: string; office: string; scope_kind: string; scope_id: string | null; scope_name: string | null; instrument: string | null; valid_from: string; valid_to: string | null; live: boolean }
interface Profile {
  email: string | null; phone: string | null; department: string | null; faculty: string | null; responsibility: string | null;
  scholar_url: string | null; orcid: string | null; research_interests: string | null; masters_graduated: number; phd_graduated: number;
  publications: string; grants: string; collaborations: string; conferences: string; assignments: string; innovations: string;
  patents: string; achievements: string; contributions: string; updated_at: string;
}
interface Teaching { session: string; semester: number; course_code: string; title: string; units: number; role: string; students: number }
interface Leave { leave_type: string; leave_name: string | null; from_date: string; to_date: string; days: number; state: string; requested_at: string; decided_at: string | null }
interface StaffRecord { person: Person; offices: Office[]; profile: Profile | null; teaching: Teaching[]; leave: Leave[] }

type Tab = "overview" | "profile" | "teaching" | "leave";
const TABS: [Tab, string][] = [["overview", "Overview"], ["profile", "Profile"], ["teaching", "Teaching"], ["leave", "Leave"]];
const words = (s: string | null | undefined) => (s ?? "").split("_").map((w) => (w ? w.charAt(0) + w.slice(1).toLowerCase() : w)).join(" ");
const rankCase = (r: string | null) => (r ? r.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase()).replace(/\bIi\b/g, "II") : "—");
const LISTS: [keyof Profile, string][] = [
  ["publications", "Publications"], ["grants", "Grants"], ["collaborations", "Collaborations"], ["conferences", "Conferences attended"],
  ["assignments", "National and international assignments"], ["innovations", "Innovations"], ["patents", "Patents"],
  ["achievements", "Achievements"], ["contributions", "Contributions to society"],
];
function list(json: string | null | undefined): string[] {
  try { const v = JSON.parse(json ?? "[]"); return Array.isArray(v) ? v.map((x) => (typeof x === "string" ? x : JSON.stringify(x))) : []; } catch { return []; }
}

const H =({ children }: { children: ReactNode }) => <div className="sub2 eyebrow eyebrow--gap">{children}</div>;

export function StaffModal({ id, onClose }: { id: string; onClose: () => void }) {
  const [rec, setRec] = useState<StaffRecord | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<Tab>("overview");

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`/api/bff/api/v1/hr/staff/${id}`, { cache: "no-store" });
      if (!live) return;
      if (!r.ok) { const j = await r.json().catch(() => null); setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setRec((await r.json()) as StaffRecord);
    })();
    return () => { live = false; };
  }, [id]);

  const p = rec?.person;
  const live = rec?.offices.filter((o) => o.live) ?? [];
  const past = rec?.offices.filter((o) => !o.live) ?? [];
  const pf = rec?.profile ?? null;

  let body: ReactNode;
  if (problem) body = <ProblemNotice problem={problem} />;
  else if (!rec || !p) body = <Note kind="info" title="Reading the record…">One moment.</Note>;
  else body = (
    <>
      <div className="row row--top mb-3" style={{ gap: "var(--s-4)" }}>
        <div style={{ width: 96, height: 118, flexShrink: 0 }}>
          {p.has_photo ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={`/api/bff/api/v1/hr/staff/${p.id}/photo`} alt={`${p.surname}, ${p.given_names} — photograph`}
              style={{ width: 96, height: 118, objectFit: "cover", borderRadius: "var(--r)", border: "1px solid var(--line-2)", display: "block" }} />
          ) : <Passport w={96} h={118} radius={6} src={null} />}
        </div>
        <div className="grow" style={{ minWidth: 240 }}>
          <div className="phead__t">{p.surname}, {p.given_names}</div>
          <div className="sub2 tnum mt-1">{p.staff_number ?? "—"}{p.pno ? ` · PNO ${p.pno}` : ""}</div>
          <div className="sub2 mt-1">{rankCase(p.rank)}{p.department ? ` · ${p.department}` : ""}</div>
          <div className="sub2">{p.faculty ?? ""}</div>
          <div className="row mt-2">
            <Pil kind={p.status === "ACTIVE" ? "ok" : p.status === "SUSPENDED" ? "warn" : "grey"}>{words(p.status)}</Pil>
            <Pil kind={p.category === "ACADEMIC" ? "info" : "grey"}>{p.category === "ACADEMIC" ? "Academic" : p.category ? "Non-teaching" : live.some((o) => ["lecturer", "hod", "dean"].includes(o.office_code)) ? "Academic" : "Staff"}</Pil>
            {p.sex ? <Pil kind="grey">{p.sex === "F" ? "Female" : "Male"}</Pil> : null}
            {p.has_account ? null : <Pil kind="grey">No portal account</Pil>}
          </div>
        </div>
      </div>

      <div className="mb-3"><Tabs look="line" label="Staff record" items={TABS.map(([id, label]) => ({ id, label }))} value={tab} onChange={setTab} /></div>

      {tab === "overview" ? (
        <>
          <KvGrid cls="grid--2" pairs={[
            ["Rank", `${rankCase(p.rank)}${p.conuass_step != null ? ` · step ${p.conuass_step}` : ""}`],
            ["Grade / step", p.grade ? `${p.grade} · ${p.step}` : "—"],
            ["Category", p.category ? words(p.category) : "—"],
            ["First appointment", p.date_first_appointment ? day(p.date_first_appointment) : p.appointment_date ? day(p.appointment_date) : "—"],
            ["Home department", p.department ? `${p.department} (${p.department_code})` : p.department_code ?? "—"],
            ["Faculty", p.faculty ?? "—"],
            ["Email", p.email ?? pf?.email ?? "—"],
            ["Phone", p.phone ?? pf?.phone ?? "—"],
            ...(p.ended_on ? [["Service ended", `${day(p.ended_on)}${p.ended_reason ? ` · ${p.ended_reason}` : ""}`] as [string, string]] : []),
          ]} />
          <H>Offices held</H>
          {live.length ? (
            <DTable cols={["Office", "Scope", "Instrument", "Since"]} rows={live.map((o) => [<strong key="o">{o.office}</strong>, o.scope_name ?? (o.scope_id ? `${words(o.scope_kind)} ${o.scope_id}` : words(o.scope_kind)), <span key="i" className="sub2">{o.instrument ?? "—"}</span>, <span key="d" className="sub2">{day(o.valid_from)}{o.valid_to ? ` → ${day(o.valid_to)}` : ""}</span>])} texts={live.map((o) => o.office)} />
          ) : <div className="sub2">Holds no office on the portal.</div>}
          {past.length ? (<><H>Past offices</H><DTable cols={["Office", "Scope", "From", "To"]} rows={past.map((o) => [o.office, o.scope_name ?? words(o.scope_kind), <span key="f" className="sub2">{day(o.valid_from)}</span>, <span key="t" className="sub2">{o.valid_to ? day(o.valid_to) : "—"}</span>])} texts={past.map((o) => o.office)} /></>) : null}
        </>
      ) : null}

      {tab === "profile" ? (
        pf ? (
          <>
            <KvGrid cls="grid--2" pairs={[
              ["Responsibility", pf.responsibility ?? "—"], ["Research interests", pf.research_interests ?? "—"],
              ["Master's graduated", String(pf.masters_graduated ?? 0)], ["PhDs graduated", String(pf.phd_graduated ?? 0)],
              ["ORCID", pf.orcid ?? "—"], ["Google Scholar", pf.scholar_url ? <a key="s" href={pf.scholar_url} target="_blank" rel="noopener">{pf.scholar_url}</a> : "—"],
            ]} />
            {LISTS.map(([k, label]) => { const items = list(pf[k] as string); return items.length ? (<div key={k}><H>{label} ({items.length})</H><ol className="m-0" style={{ paddingLeft: "var(--s-5)", lineHeight: 1.5 }}>{items.map((x, i) => <li key={i}>{x}</li>)}</ol></div>) : null; })}
            <div className="sub2 mt-3">Profile kept by the member of staff · last updated {day(pf.updated_at)}.</div>
          </>
        ) : <div className="sub2">This member of staff has not filled their academic profile.</div>
      ) : null}

      {tab === "teaching" ? (
        rec.teaching.length ? (
          <DTable cols={["Session", "Sem|mid", "Course", "Title", "Units|num", "Role|mid", "Students|num"]}
            rows={rec.teaching.map((t) => [t.session, String(t.semester), <span key="c" className="tnum">{t.course_code}</span>, t.title, <span key="u" className="tnum">{t.units}</span>, <Pil key="r" kind={t.role === "Lecturer" ? "info" : "grey"}>{t.role}</Pil>, <span key="s" className="tnum">{t.students}</span>])}
            texts={rec.teaching.map((t) => `${t.session} ${t.course_code} ${t.title}`)} />
        ) : <div className="sub2">No course is allocated to this member of staff.</div>
      ) : null}

      {tab === "leave" ? (
        rec.leave.length ? (
          <DTable cols={["Leave", "From", "To", "Days|num", "State|mid", "Requested"]}
            rows={rec.leave.map((l) => [l.leave_name ?? words(l.leave_type), <span key="f" className="sub2">{day(l.from_date)}</span>, <span key="t" className="sub2">{day(l.to_date)}</span>, <span key="d" className="tnum">{l.days}</span>, <Pil key="s" kind={l.state === "APPROVED" ? "ok" : l.state === "REFUSED" || l.state === "CANCELLED" ? "grey" : "info"}>{words(l.state)}</Pil>, <span key="r" className="sub2">{day(l.requested_at)}</span>])}
            texts={rec.leave.map((l) => `${l.leave_type} ${l.state}`)} />
        ) : <div className="sub2">No leave on record.</div>
      ) : null}
    </>
  );

  return (
    <Modal wide title={p ? `${p.surname}, ${p.given_names}` : "Member of staff"} sub={p ? `${p.staff_number ?? ""}${p.rank ? ` · ${rankCase(p.rank)}` : ""}` : "Reading the record"} onClose={onClose}
      foot={<><span className="sub2">Read from the staff record as it stands now.</span><span className="grow" />{p ? <a href={`/staff/idcard/pdf?id=${p.id}`} target="_blank" rel="noopener" className="btn btn--ghost btn--sm">ID card (PDF)</a> : null}<Btn kind="primary" onClick={onClose}>Close</Btn></>}>
      {body}
    </Modal>
  );
}

/** a button that names a member of staff and opens their record in the pop-up — for any list */
export function StaffOpen({ id, label, kind = "primary", className }: { id: string; label?: ReactNode; kind?: "primary" | "ghost" | "link"; className?: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      {kind === "link"
        ? <button type="button" className={className} style={{ background: "none", border: "none", padding: 0, cursor: "pointer", font: "inherit", color: "var(--chrome)", fontWeight: 600, textAlign: "left" }} onClick={() => setOpen(true)}>{label ?? "Details"}</button>
        : <button type="button" className={className ?? `btn btn--${kind} btn--sm`} onClick={() => setOpen(true)}>{label ?? "Details"}</button>}
      {open ? <StaffModal id={id} onClose={() => setOpen(false)} /> : null}
    </>
  );
}
