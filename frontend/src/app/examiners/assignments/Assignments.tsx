"use client";
/** Project assignments on the desk (V254): filtered by session, status, examiner and unit; a deadline extended, a project
 *  reassigned or withdrawn on a reason; the examiner told each time. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, PageHead, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RecommendationPil, STATUS, StatusPil, dayOf, daysWords, type AssignmentRow, type ExaminerRow } from "@/lib/examiners";

interface Filters { session: string; status: string; examiner: string; dept: string; q: string; overdue: boolean }
type Dialog = { kind: "reassign" | "deadline" | "withdraw"; a: AssignmentRow } | null;

export function Assignments({ rows, examiners, sessions, filters }: { rows: AssignmentRow[]; examiners: ExaminerRow[]; sessions: string[]; filters: Filters }) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [q, setQ] = useState(filters.q);
  const [f, setF] = useState({ examinerId: "", reason: "", deadline: "" });
  const nav = (patch: Partial<Filters>) => {
    const next = { ...filters, ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v) qs.set(k, String(v));
    go(`/examiners/assignments${qs.toString() ? "?" + qs.toString() : ""}`);
  };
  const open = rows.filter((r) => ["ASSIGNED", "IN_REVIEW", "REOPENED"].includes(r.status));
  const overdue = rows.filter((r) => r.overdue);

  async function post(path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason); router.refresh(); return true;
    } finally { setBusy(false); }
  }
  const openDialog = (kind: "reassign" | "deadline" | "withdraw", a: AssignmentRow) => { setProblem(null); setF({ examinerId: "", reason: "", deadline: a.deadline }); setDialog({ kind, a }); };

  return (
    <>
      <PageHead title="Project Assignments" description="Every project with an external examiner, where each review stands, and the acts the desk takes on an assignment."
        actions={<><LinkBtn kind="primary" href="/examiners/projects">Register or Assign a Project</LinkBtn><LinkBtn href="/examiners/reports">Reports</LinkBtn></>} />
      {problem && !dialog ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["Assignments shown", String(rows.length), null, filters.session || "Every session"],
        ["Pending", String(open.length), open.length ? "var(--amber-ink)" : null, "Not yet submitted"],
        ["Overdue", String(overdue.length), overdue.length ? "var(--red-ink)" : null, "Past the review deadline"],
        ["Submitted", String(rows.filter((r) => r.status === "SUBMITTED" || r.status === "LOCKED").length), null, `${rows.filter((r) => r.status === "LOCKED").length} locked`],
      ]} />
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); nav({ q }); }}>
        <div className="row">
          <Field id="as-q" label="Search" style={{ flex: "2 1 220px" }}><input id="as-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Title, candidate, matric number, examiner" /></Field>
          <Field id="as-session" label="Session" style={{ flex: "1 1 130px" }}><select id="as-session" className="ctl" value={filters.session} onChange={(e) => nav({ session: e.target.value })}><option value="">Every</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
          <Field id="as-status" label="Status" style={{ flex: "1 1 150px" }}><select id="as-status" className="ctl" value={filters.status} onChange={(e) => nav({ status: e.target.value })}><option value="">Every</option><option value="pending">Pending</option><option value="done">Submitted or locked</option>{Object.entries(STATUS).filter(([k]) => !["REASSIGNED", "WITHDRAWN"].includes(k)).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field>
          <Field id="as-ex" label="Examiner" style={{ flex: "1 1 180px" }}><select id="as-ex" className="ctl" value={filters.examiner} onChange={(e) => nav({ examiner: e.target.value })}><option value="">Every</option>{examiners.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}</select></Field>
          <label className="row row--tight" style={{ alignSelf: "flex-end", paddingBottom: 8 }}><input type="checkbox" className="chk" checked={filters.overdue} onChange={(e) => nav({ overdue: e.target.checked })} /> <span>Overdue only</span></label>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}><Btn kind="primary" type="submit">Search</Btn>{Object.values(filters).some(Boolean) ? <Btn kind="ghost" onClick={() => { setQ(""); go("/examiners/assignments"); }}>Clear</Btn> : null}</div>
        </div>
      </form>
      <Panel title="Assignments" right={`${rows.length} shown`}>
        {rows.length ? (
          <DTable pageSize={0} cols={["Candidate", "Project", "Examiner", "Session|mid", "Assigned|mid", "Deadline|mid", "Status|mid", "Assessment", "|num"]} rows={rows.map((a) => [
            <span key="c"><strong>{a.student}</strong><div className="sub2 tnum">{a.number}</div></span>,
            <span key="t"><Link className="lnk" href={`/examiners/assignments/${a.id}`}>{a.title}</Link><div className="sub2">{a.programme} · {a.department}</div></span>,
            <span key="e"><Link className="lnk" href={`/examiners/${a.examiner_id}`}>{a.examiner}</Link><div className="sub2">{a.institution}</div></span>,
            <span key="s" className="tnum">{a.session}</span>,
            <span key="as" className="tnum sub2">{dayOf(a.assigned_at)}</span>,
            <span key="d" className={`tnum${a.overdue ? " ink-red b600" : ""}`}>{dayOf(a.deadline)}<div className="sub2">{daysWords(a.days_left, a.status)}</div></span>,
            <StatusPil key="st" status={a.status} />,
            <span key="r">{a.total != null ? <><span className="tnum b600">{a.total}/{a.max_total}</span> <span className="sub2 tnum">{a.grade}</span><div><RecommendationPil value={a.final_recommendation} /></div></> : <span className="sub2">—</span>}</span>,
            <span key="o" className="row row--inline row--tight row--right">
              {!["LOCKED"].includes(a.status) ? <Btn kind="ghost" size="sm" onClick={() => openDialog("deadline", a)}>Extend</Btn> : null}
              {!["LOCKED"].includes(a.status) ? <Btn kind="ghost" size="sm" onClick={() => openDialog("reassign", a)}>Reassign</Btn> : null}
              <LinkBtn href={`/examiners/assignments/${a.id}`} kind={a.status === "SUBMITTED" ? "primary" : "ghost"} size="sm">{a.status === "SUBMITTED" || a.status === "LOCKED" ? "View Assessment" : "Open"}</LinkBtn>
            </span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing matches. Widen the filters, or register and assign a project.</div></PBody>}
      </Panel>

      {dialog?.kind === "deadline" ? (
        <Modal title="Extend the review deadline" sub={`${dialog.a.title} · ${dialog.a.examiner}`} onClose={() => setDialog(null)}
          foot={<><Btn kind="ghost" onClick={() => setDialog(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !f.deadline || f.deadline === dialog.a.deadline} onClick={async () => { if (await post(`/assignments/${dialog.a.id}/deadline`, { deadline: f.deadline, reason: f.reason || null }, "Review deadline changed")) setDialog(null); }}>Change the Deadline</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="dl-date" label="New deadline" required><input id="dl-date" className="ctl" type="date" value={f.deadline} onChange={(e) => setF({ ...f, deadline: e.target.value })} /></Field>
            <Field id="dl-reason" label="Reason" hint="Goes on the record and to the examiner"><input id="dl-reason" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {dialog?.kind === "reassign" ? (
        <Modal title="Reassign the project" sub={`${dialog.a.title} · now with ${dialog.a.examiner}`} onClose={() => setDialog(null)}
          foot={<><Btn kind="ghost" onClick={() => setDialog(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || !f.examinerId || f.reason.trim().length < 5} onClick={async () => { if (await post(`/assignments/${dialog.a.id}/reassign`, { examinerId: f.examinerId, reason: f.reason.trim(), deadline: f.deadline || null }, "Project reassigned")) setDialog(null); }}>Reassign</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="ra-ex" label="New examiner" required><select id="ra-ex" className="ctl" value={f.examinerId} onChange={(e) => setF({ ...f, examinerId: e.target.value })}><option value="">Choose…</option>{examiners.filter((e) => e.status === "ACTIVE" && e.id !== dialog.a.examiner_id).map((e) => <option key={e.id} value={e.id}>{e.name} · {e.institution}</option>)}</select></Field>
            <Field id="ra-deadline" label="Deadline for the new examiner"><input id="ra-deadline" className="ctl" type="date" value={f.deadline} onChange={(e) => setF({ ...f, deadline: e.target.value })} /></Field>
            <Field id="ra-reason" label="Reason" required hint="Recorded with the previous examiner, the new one, who changed it and when; both examiners are told"><textarea id="ra-reason" className="ctl" rows={3} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
            <div className="sub2">The current assignment ends and its draft, if any, stays on record; the new examiner starts afresh.</div>
            <div><Btn kind="ghost" size="sm" onClick={() => setDialog({ kind: "withdraw", a: dialog.a })}>Withdraw the assignment instead</Btn></div>
          </div>
        </Modal>
      ) : null}
      {dialog?.kind === "withdraw" ? (
        <Modal title="Withdraw the assignment" sub={`${dialog.a.title} · ${dialog.a.examiner}`} onClose={() => setDialog(null)}
          foot={<><Btn kind="ghost" onClick={() => setDialog(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || f.reason.trim().length < 5} onClick={async () => { if (await post(`/assignments/${dialog.a.id}/withdraw`, { reason: f.reason.trim() }, "Assignment withdrawn")) setDialog(null); }}>Withdraw</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <Field id="wd-reason" label="Reason" required><textarea id="wd-reason" className="ctl" rows={3} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
