"use client";

/** staffApprovals — proto/part5.html: the desk's queue, with its refusals on the row. */
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, type SheetListing } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, Tiles } from "@/components/proto/ui";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Approvals({
  scope,
  structure,
  sessions,
  courses,
  listing,
  actingOffice,
}: {
  scope: Scope;
  structure: ScopeStructure;
  sessions: string[];
  courses: { code: string; title: string; semester: number }[];
  listing: SheetListing;
  actingOffice: string | null;
}) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [returning, setReturning] = useState<string | null>(null);
  const [comment, setComment] = useState("");
  const [said, setSaid] = useState<string | null>(null);

  async function post(path: string, body: unknown, reason: string, key: string) {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (r.status === 202) {
        const j = await r.json();
        setSaid(j.note ?? "Accepted");
      } else if (!r.ok) {
        { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); }
        return false;
      }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  const t = listing.tiles;
  const title = listing.desk ? `Awaiting ${listing.desk}` : "Result sets";
  const sub = listing.desk ? "You cannot approve a stage you already approved" : "Every result set in the scope, and where it has reached";

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} courses={courses} what="result sets" count={listing.sheets.length} of={t.expected} withCourse />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="info" title="Nothing was sent">{said}</Note> : null}
      <Tiles items={[
        ["Expected sheets", String(t.expected), null, "In this scope"],
        ["Senate approved", String(t.senateApproved), "var(--green-ink)", t.expected ? `${Math.round((100 * t.senateApproved) / t.expected)}% complete` : "Nothing expected yet"],
        ["In workflow", String(t.inWorkflow), "var(--chrome)", "Moving through stages"],
        ["Not submitted", String(t.notSubmitted), "var(--red-ink)", t.notSubmitted ? "Waiting on lecturers" : "Nothing outstanding"],
      ]} />

      <Panel title={title} right={sub}>
        <div className="tablewrap">
          <table style={{ minWidth: 840 }}>
            <thead><tr><th>Course</th><th>Department</th><th className="mid">Students</th><th className="mid">Fail rate</th><th>Stage</th><th className="num">Action</th></tr></thead>
            <tbody>
              {listing.sheets.length === 0 ? (
                <tr><td colSpan={6} className="sub2">No score sheet exists in this scope. Sheets are generated when an examination session is opened over the allocated offerings.</td></tr>
              ) : listing.sheets.map((s) => {
                const [stageText, who] = STAGE_LABEL[s.stage] ?? [s.stage, ""];
                const high = s.failRate !== null && s.failRate > 50;
                return (
                  <tr key={s.id} style={high ? { background: "var(--red-wash)" } : undefined}>
                    <td><strong className="tnum">{s.courseCode}</strong>{s.sitting && s.sitting !== "MAIN" ? <span className="pill pill--info" style={{ marginLeft: 6 }}>{s.sitting === "RESIT" ? "Re-sit" : "Special"}</span> : null}<div className="sub2">{s.courseTitle}</div></td>
                    <td className="sub2">{s.deptName}</td>
                    <td className="mid tnum">{s.candidates}</td>
                    <td className="mid">{s.failRate === null ? <span className="ink-faint">—</span> : high ? <span className="pill pill--bad tnum">{s.failRate}%</span> : <span className="tnum">{s.failRate}%</span>}</td>
                    <td>
                      {s.stage === "ENTRY" ? (
                        <><strong className="ink-red">Not submitted</strong><div className="sub2">{s.lecturer ?? "No lecturer allocated"}{s.daysLate ? ` · ${s.daysLate} days overdue` : ""}</div></>
                      ) : (
                        <>{stageText}{s.blockedForYou ? <div className="sub2">You approved the previous stage — another holder of the next desk must approve this one</div> : who ? <div className="sub2">With {who}</div> : null}{high ? <div className="sub2 ink-red">Fail rate above half the candidates — review before approving</div> : null}</>
                      )}
                    </td>
                    <td className="num">
                      {s.stage === "ENTRY" ? (
                        <><Btn kind="ghost" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${s.id}/remind`, {}, `Reminder for ${s.courseCode}`, s.id)}>Remind</Btn> <Btn kind="urgent" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${s.id}/remind`, {}, `Escalation for ${s.courseCode}`, s.id)}>Escalate</Btn></>
                      ) : s.stage === "PUBLISHED" ? (
                        <LinkBtn href={`/results/chain?sheet=${s.id}`} kind="ghost">Chain</LinkBtn>
                      ) : s.stage === "SENATE" ? (
                        <><LinkBtn href="/results/senate" kind="primary">Record Senate minute</LinkBtn> <LinkBtn href={`/results/chain?sheet=${s.id}`} kind="ghost">Review</LinkBtn></>
                      ) : s.blockedForYou || !s.mayAct ? (
                        <><Btn kind="ghost" disabled>Not available to you</Btn> <LinkBtn href={`/results/chain?sheet=${s.id}`} kind="ghost">Review</LinkBtn></>
                      ) : high ? (
                        <><Btn kind="ghost" onClick={() => { setReturning(s.id); setComment(""); }}>Return</Btn> <LinkBtn href={`/results/chain?sheet=${s.id}`} kind="primary">Review</LinkBtn></>
                      ) : (
                        <><Btn kind="ghost" onClick={() => { setReturning(s.id); setComment(""); }}>Return</Btn> <Btn kind="go" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, {}, `${s.courseCode} approved at ${s.stage.toLowerCase()} by ${actingOffice}`, s.id)}>{busy === s.id ? "Approving…" : "Approve"}</Btn></>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Panel>

      {returning ? (
        <Modal title="Return the sheet to the lecturer" sub="The reason goes on the record" onClose={() => setReturning(null)}
          foot={<><Btn kind="ghost" onClick={() => setReturning(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={!comment.trim() || busy !== null} onClick={async () => { if (await post(`/api/bff/api/v1/results/sheets/${returning}/return`, { comment }, "Sheet returned", returning)) setReturning(null); }}>Return it</Btn></>}>
          <Field id="ret-why" label="Why it is returned" hint="The lecturer sees this, and so does the audit trail. It re-enters the chain at verification, not at the stage it left.">
            <input id="ret-why" className="ctl" value={comment} onChange={(e) => setComment(e.target.value)} autoComplete="off" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
