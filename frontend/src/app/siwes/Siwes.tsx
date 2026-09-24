"use client";

/** rSiwes — the department's SIWES supervision: a supervisor per student, and the coordinator's
 *  practical report mark. The supervisor's own assessment (/40) is entered on their dashboard. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Offering {
  id: string; course_code: string; title: string; units: number; dept_code: string; dept_name: string;
  session: string; semester: number; sheet_id: string | null; sheet_stage: string | null; students: number; assigned: number;
}
export interface SiwesStudent {
  student_id: string; number: string | null; surname: string; other_names: string; programme: string | null; level: number;
  supervisor_id: string | null; supervisor: string | null;
  supervisor_mark: number | null; practical_mark: number | null; total: number | null; outcome: string | null;
}
export interface Supervisor { id: string; name: string; staff_number: string | null }

const STAGE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  ENTRY: ["warn", "Entry open"], VERIFICATION: ["info", "Verification"], PUBLISHED: ["ok", "Published"],
};

export function Siwes({ sessions, session, semester, offerings, offeringId, students, pool }: {
  sessions: string[]; session: string; semester: number; offerings: Offering[]; offeringId: string;
  students: SiwesStudent[]; pool: Supervisor[];
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [practical, setPractical] = useState<Record<string, string>>({});
  const offering = offerings.find((o) => o.id === offeringId) ?? null;
  const entryOpen = offering?.sheet_stage === "ENTRY";

  function go(next: { session?: string; sem?: number; offering?: string }) {
    const q = new URLSearchParams();
    q.set("session", next.session ?? session);
    q.set("sem", String(next.sem ?? semester));
    if (next.offering ?? offeringId) q.set("offering", next.offering ?? offeringId);
    queryNav(`/siwes?${q.toString()}`);
  }

  async function send(path: string, body: unknown, reason: string, key: string): Promise<boolean> {
    setBusy(key);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/siwes${path}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <Note kind="info" title="A SIWES course is supervised, not taught to a class">
        Each student is assigned a supervisor, who records that student&rsquo;s assessment out of 40 on their own dashboard. You record the report of the practicals out of 60 here. A student&rsquo;s mark is complete only when both parts are in; the sheet then goes through the results chain like any other.
      </Note>

      <div className="card"><div className="card__body row row--end">
        <div style={{ minWidth: 150 }}><Field id="sw-session" label="Session">
          <select id="sw-session" className="ctl" value={session} onChange={(e) => go({ session: e.target.value })}>
            {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select></Field></div>
        <div style={{ minWidth: 130 }}><Field id="sw-sem" label="Semester">
          <select id="sw-sem" className="ctl" value={semester} onChange={(e) => go({ sem: Number(e.target.value) })}>
            <option value={1}>First</option><option value={2}>Second</option>
          </select></Field></div>
        <div style={{ minWidth: 280 }}><Field id="sw-off" label="SIWES course">
          <SearchSelect id="sw-off" value={offeringId} placeholder="Choose the SIWES course…"
            options={offerings.map((o) => ({ value: o.id, label: `${o.course_code} — ${o.title} (${o.dept_name})` }))} onChange={(v) => go({ offering: v })} /></Field></div>
      </div></div>

      {err ? <ProblemNotice problem={err} /> : null}

      {!offering ? (
        <Note kind="info" title="No SIWES course this session and semester">
          A SIWES course appears here once the department offers an industrial-training course for the session. Mark the course as industrial training in the catalogue and open its registration.
        </Note>
      ) : (
        <>
          <Tiles items={[
            ["Students", String(offering.students), null, "On this SIWES offering"],
            ["Supervisors assigned", String(offering.assigned), offering.assigned < offering.students ? "var(--red-ink)" : "var(--green-ink)", offering.assigned < offering.students ? `${offering.students - offering.assigned} still to assign` : "All assigned"],
            ["Score sheet", offering.sheet_stage ? (STAGE[offering.sheet_stage]?.[1] ?? offering.sheet_stage) : "Not open", offering.sheet_stage ? null : "var(--red-ink)", offering.sheet_stage ? "" : "Open the exam session to score"],
            ["Course", `${offering.course_code}`, null, `${offering.units} units`],
          ]} />

          <Panel title="Students and their supervisors" right={`${offering.dept_name} · ${session} · ${semester === 1 ? "first" : "second"} semester`}>
            {students.length ? (
              <DTable cols={["Matric|mid", "Name", "Programme", "Supervisor", "Assessment /40|mid", "Practical /60|num", "Total|mid"]} rows={students.map((s) => [
                <span className="tnum" key="m">{s.number ?? "—"}</span>,
                <strong key="n">{s.surname}, {s.other_names}</strong>,
                <span className="sub2" key="p">{s.programme ?? "—"}</span>,
                <div key="sup" style={{ minWidth: 200 }}>
                  <SearchSelect id={`sup-${s.student_id}`} value={s.supervisor_id ?? ""} placeholder="Assign a supervisor…"
                    options={pool.map((p) => ({ value: p.id, label: p.name }))}
                    onChange={(v) => { if (v) void send(`/offerings/${offeringId}/students/${s.student_id}/supervisor`, { supervisor: v }, `SIWES supervisor assigned to ${s.surname}`, `sup-${s.student_id}`); }} />
                </div>,
                <span className={`tnum${s.supervisor_mark == null ? " ink-muted" : ""}`} key="a">{s.supervisor_mark ?? "—"}</span>,
                <div key="pr" className="row row--tight row--right">
                  <input className="ctl tnum" style={{ width: 64 }} inputMode="numeric" disabled={!entryOpen || busy !== null}
                    value={`pr-${s.student_id}` in practical ? practical[`pr-${s.student_id}`] : (s.practical_mark ?? "")}
                    onChange={(e) => setPractical({ ...practical, [`pr-${s.student_id}`]: e.target.value })} />
                  <Btn kind="ghost" disabled={!entryOpen || busy !== null} onClick={() => {
                    const raw = `pr-${s.student_id}` in practical ? practical[`pr-${s.student_id}`] : String(s.practical_mark ?? "");
                    const mark = Number(raw);
                    if (raw.trim() === "" || Number.isNaN(mark)) return;
                    const reason = s.practical_mark != null && s.practical_mark !== mark ? window.prompt(`Why is ${s.surname}'s practical mark changing from ${s.practical_mark} to ${mark}?`) ?? "" : "";
                    if (s.practical_mark != null && s.practical_mark !== mark && !reason.trim()) return;
                    void send(`/offerings/${offeringId}/students/${s.student_id}/practical`, { mark, reason }, `SIWES practical report recorded for ${s.surname}`, `pr-${s.student_id}`);
                  }}>{busy === `pr-${s.student_id}` ? "Saving…" : "Save"}</Btn>
                </div>,
                s.total != null ? <Pil kind="ok" key="t">{s.total}</Pil> : <span className="sub2 tnum" key="t">—</span>,
              ])} texts={students.map((s) => `${s.number} ${s.surname} ${s.other_names} ${s.supervisor ?? ""}`)} />
            ) : <PBody><div className="sub2">No student has an approved registration for this SIWES course yet.</div></PBody>}
            {!entryOpen && offering.sheet_stage ? <PBody><div className="sub2">The sheet is at {STAGE[offering.sheet_stage]?.[1] ?? offering.sheet_stage}; marks change by amendment now. Return it to entry to correct one.</div></PBody> : null}
          </Panel>
        </>
      )}
    </>
  );
}
