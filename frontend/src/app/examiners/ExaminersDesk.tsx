"use client";
/** The external examiners desk (V254): the figures for the session, the register of examiners with each one's standing,
 *  and a new examiner recorded and invited in one act. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { EXAMINER_STATUS, ExaminerPil, dayOf, type ExaminerRow } from "@/lib/examiners";

export interface Dashboard {
  totals: { examiners: number; active_examiners: number; pending_invitations: number; assigned: number; pending: number; in_review: number; submitted: number; locked: number; overdue: number; avg_days_to_submit: number | null };
  byExaminer: { key: string; examiner_id: string; n: number; submitted: number; overdue: number }[];
  byDepartment: { key: string; n: number; submitted: number; overdue: number }[];
  byProgramme: { key: string; n: number; submitted: number }[];
  byStatus: { key: string; n: number }[];
  overdueList: { id: string; title: string; student: string; number: string; examiner: string; deadline: string; status: string }[];
  recent: { id: string; title: string; student: string; number: string; examiner: string; status: string; deadline: string; assigned_at: string }[];
  sessions: string[];
}
interface Faculty { code: string; name: string; departments: { code: string; name: string }[] }
const EMPTY = { title: "", firstName: "", middleName: "", lastName: "", email: "", phone: "", institution: "", department: "", rank: "", specialization: "", qualification: "", professional: "", experienceYears: "", country: "Nigeria", region: "", orcid: "", notes: "", invite: true };

export function ExaminersDesk({ dash, session, examiners, faculties }: { dash: Dashboard; session: string; examiners: ExaminerRow[]; faculties: Faculty[] }) {
  void faculties;
  const router = useRouter();
  const go = useQueryNav();
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const [open, setOpen] = useState(false);
  const [f, setF] = useState({ ...EMPTY });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const t = dash.totals;
  const shown = examiners.filter((e) => (!status || e.status === status) && (!q.trim() || `${e.name} ${e.email} ${e.institution} ${e.specialization ?? ""}`.toLowerCase().includes(q.trim().toLowerCase())));
  const ready = f.firstName.trim() && f.lastName.trim() && /^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/.test(f.email.trim()) && f.institution.trim();

  async function create() {
    if (!ready) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/examiners", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`External examiner ${f.lastName.trim()} recorded${f.invite ? " and invited" : ""}`) },
        body: JSON.stringify({ ...f, experienceYears: f.experienceYears ? Number(f.experienceYears) : null }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify(f.invite ? "Examiner recorded and the invitation sent" : "Examiner recorded");
      setOpen(false); setF({ ...EMPTY });
      router.push(`/examiners/${j.id}`);
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title="External Examiners" description="Scholars from other institutions appointed to assess final-year projects independently: the register, their appointments, the projects sent to them."
        actions={<><Btn kind="primary" onClick={() => setOpen(true)}>New Examiner</Btn><LinkBtn href="/examiners/assignments">Project Assignments</LinkBtn><LinkBtn href="/examiners/reports">Reports</LinkBtn></>} />
      {problem && !open ? <ProblemNotice problem={problem} /> : null}
      <div className="scope">
        <div className="scope__f"><label htmlFor="ex-session">Session</label>
          <select id="ex-session" className="ws__select" value={session} onChange={(e) => go(`/examiners${e.target.value ? `?session=${encodeURIComponent(e.target.value)}` : ""}`)}>
            <option value="">Every session</option>{dash.sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select></div>
      </div>
      <Tiles items={[
        ["Examiners", String(n(t.examiners)), null, `${n(t.active_examiners)} active · ${n(t.pending_invitations)} awaiting activation`],
        ["Assigned projects", String(n(t.assigned)), null, session || "Every session", "/examiners/assignments"],
        ["Pending reviews", String(n(t.pending)), n(t.pending) ? "var(--amber-ink)" : null, `${n(t.in_review)} in review`, "/examiners/assignments?status=pending"],
        ["Submitted", String(n(t.submitted)), null, `${n(t.locked)} locked · ${t.avg_days_to_submit != null ? `${t.avg_days_to_submit} days on average` : "no completion time yet"}`, "/examiners/assignments?status=done"],
      ]} />
      {n(t.overdue) ? (
        <Panel title="Overdue reviews" right={`${n(t.overdue)} past the deadline`}>
          <DTable pageSize={0} cols={["Project", "Candidate", "Examiner", "Deadline|mid", "|num"]} rows={dash.overdueList.map((r) => [
            <span key="t">{r.title}</span>, <span key="c">{r.student}<div className="sub2 tnum">{r.number}</div></span>, <span key="e">{r.examiner}</span>,
            <span key="d" className="tnum ink-red b600">{dayOf(r.deadline)}</span>, <LinkBtn key="o" href={`/examiners/assignments/${r.id}`} size="sm">Open</LinkBtn>,
          ])} />
        </Panel>
      ) : null}

      <Panel title="The register" right={`${examiners.length} examiner${examiners.length === 1 ? "" : "s"}`}>
        <PBody>
          <div className="row">
            <input className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name, email, institution or specialisation" aria-label="Search examiners" style={{ flex: "2 1 260px" }} />
            <select className="ctl" value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Status" style={{ flex: "1 1 160px" }}>
              <option value="">Every status</option>{Object.entries(EXAMINER_STATUS).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
            </select>
          </div>
        </PBody>
        {shown.length ? (
          <DTable cols={["Examiner", "Institution", "Specialisation", "Status|mid", "Projects|mid", "Overdue|mid", "Sign-in|mid", "|num"]} rows={shown.map((e) => [
            <span key="n"><Link className="lnk b600" href={`/examiners/${e.id}`}>{e.name}</Link><div className="sub2">{e.email}</div></span>,
            <span key="i">{e.institution}{e.rank ? <div className="sub2">{e.rank}</div> : null}</span>,
            <span key="s" className="sub2">{e.specialization ?? "—"}</span>,
            <span key="st"><ExaminerPil status={e.status} />{e.status === "PENDING_ACTIVATION" && e.invitation_expires_at ? <div className="sub2">link to {dayOf(e.invitation_expires_at)}</div> : null}</span>,
            <span key="p" className="tnum">{n(e.assigned)}<div className="sub2">{n(e.pending)} pending · {n(e.submitted)} in</div></span>,
            <span key="o" className={`tnum${n(e.overdue) ? " ink-red b600" : ""}`}>{n(e.overdue)}</span>,
            <span key="l" className="sub2 tnum">{e.last_sign_in_at ? dayOf(e.last_sign_in_at) : e.has_signin ? "Never" : "—"}</span>,
            <LinkBtn key="v" href={`/examiners/${e.id}`} size="sm">Open</LinkBtn>,
          ])} texts={shown.map((e) => `${e.name} ${e.email} ${e.institution} ${e.status}`)} />
        ) : <PBody><div className="sub2">{examiners.length ? "Nobody matches." : "No external examiner is on the register yet. Record one and send the invitation."}</div></PBody>}
      </Panel>

      <div className="grid grid--2">
        <Panel title="Projects by examiner" right={session || "Every session"}>
          {dash.byExaminer.length ? <DTable pageSize={0} cols={["Examiner", "Assigned|mid", "Submitted|mid", "Overdue|mid"]} rows={dash.byExaminer.map((r, i) => [<Link key={"e" + i} className="lnk" href={`/examiners/${r.examiner_id}`}>{r.key}</Link>, <span key={"n" + i} className="tnum">{n(r.n)}</span>, <span key={"s" + i} className="tnum">{n(r.submitted)}</span>, <span key={"o" + i} className={`tnum${n(r.overdue) ? " ink-red" : ""}`}>{n(r.overdue)}</span>])} /> : <PBody><div className="sub2">No assignments yet.</div></PBody>}
        </Panel>
        <Panel title="Reviews by department" right="Submitted against assigned">
          {dash.byDepartment.length ? <DTable pageSize={0} cols={["Department", "Assigned|mid", "Submitted|mid", "Overdue|mid", ""]} rows={dash.byDepartment.map((r, i) => [<span key={"d" + i}>{r.key}</span>, <span key={"n" + i} className="tnum">{n(r.n)}</span>, <span key={"s" + i} className="tnum">{n(r.submitted)}</span>, <span key={"o" + i} className={`tnum${n(r.overdue) ? " ink-red" : ""}`}>{n(r.overdue)}</span>, <span key={"b" + i} className="meter"><span className="meter__bar"><span className="meter__fill" style={{ width: `${n(r.n) ? Math.round((100 * n(r.submitted)) / n(r.n)) : 0}%` }} /></span></span>])} /> : <PBody><div className="sub2">No assignments yet.</div></PBody>}
        </Panel>
      </div>
      <Panel title="Recent assignments" right="The latest ten">
        {dash.recent.length ? <DTable pageSize={0} cols={["Project", "Candidate", "Examiner", "Status|mid", "Deadline|mid", "|num"]} rows={dash.recent.map((r) => [<span key="t">{r.title}</span>, <span key="c">{r.student}</span>, <span key="e">{r.examiner}</span>, <Pil key="s" kind="info">{r.status.replace("_", " ").toLowerCase()}</Pil>, <span key="d" className="tnum">{dayOf(r.deadline)}</span>, <LinkBtn key="o" href={`/examiners/assignments/${r.id}`} size="sm">Open</LinkBtn>])} /> : <PBody><div className="sub2">Nothing assigned yet.</div></PBody>}
      </Panel>

      {open ? (
        <Modal title="New External Examiner" sub="Recorded on the register; invited by email when ticked" onClose={() => setOpen(false)} wide
          foot={<><Btn kind="ghost" onClick={() => setOpen(false)}>Cancel</Btn><Btn kind="primary" disabled={busy || !ready} onClick={() => void create()}>{busy ? "Saving…" : f.invite ? "Record and Send Invitation" : "Record Examiner"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="grid grid--3">
            <Field id="ne-title" label="Title"><input id="ne-title" className="ctl" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} placeholder="Prof." /></Field>
            <Field id="ne-first" label="First name" required><input id="ne-first" className="ctl" value={f.firstName} onChange={(e) => setF({ ...f, firstName: e.target.value })} /></Field>
            <Field id="ne-middle" label="Middle name"><input id="ne-middle" className="ctl" value={f.middleName} onChange={(e) => setF({ ...f, middleName: e.target.value })} /></Field>
            <Field id="ne-last" label="Last name" required><input id="ne-last" className="ctl" value={f.lastName} onChange={(e) => setF({ ...f, lastName: e.target.value })} /></Field>
            <Field id="ne-email" label="Email" required hint="Becomes the username"><input id="ne-email" className="ctl" type="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} /></Field>
            <Field id="ne-phone" label="Phone"><input id="ne-phone" className="ctl" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} /></Field>
            <Field id="ne-inst" label="Institution" required><input id="ne-inst" className="ctl" value={f.institution} onChange={(e) => setF({ ...f, institution: e.target.value })} /></Field>
            <Field id="ne-dept" label="Department"><input id="ne-dept" className="ctl" value={f.department} onChange={(e) => setF({ ...f, department: e.target.value })} /></Field>
            <Field id="ne-rank" label="Position or rank"><input id="ne-rank" className="ctl" value={f.rank} onChange={(e) => setF({ ...f, rank: e.target.value })} /></Field>
            <Field id="ne-spec" label="Area of specialisation"><input id="ne-spec" className="ctl" value={f.specialization} onChange={(e) => setF({ ...f, specialization: e.target.value })} /></Field>
            <Field id="ne-qual" label="Highest qualification"><input id="ne-qual" className="ctl" value={f.qualification} onChange={(e) => setF({ ...f, qualification: e.target.value })} /></Field>
            <Field id="ne-prof" label="Professional qualifications"><input id="ne-prof" className="ctl" value={f.professional} onChange={(e) => setF({ ...f, professional: e.target.value })} /></Field>
            <Field id="ne-years" label="Years of academic experience"><input id="ne-years" className="ctl tnum" inputMode="numeric" value={f.experienceYears} onChange={(e) => setF({ ...f, experienceYears: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            <Field id="ne-country" label="Country"><input id="ne-country" className="ctl" value={f.country} onChange={(e) => setF({ ...f, country: e.target.value })} /></Field>
            <Field id="ne-region" label="State or region"><input id="ne-region" className="ctl" value={f.region} onChange={(e) => setF({ ...f, region: e.target.value })} /></Field>
            <Field id="ne-orcid" label="ORCID"><input id="ne-orcid" className="ctl tnum" value={f.orcid} onChange={(e) => setF({ ...f, orcid: e.target.value })} /></Field>
          </div>
          <Field id="ne-notes" label="Notes for the desk" hint="Never shown to the examiner"><textarea id="ne-notes" className="ctl" rows={2} value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} /></Field>
          <label className="row row--tight mt-2"><input type="checkbox" className="chk" checked={f.invite} onChange={(e) => setF({ ...f, invite: e.target.checked })} /> <span>Send the invitation email now; the link works once and for fourteen days</span></label>
        </Modal>
      ) : null}
    </>
  );
}
