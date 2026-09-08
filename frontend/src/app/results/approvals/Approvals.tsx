"use client";

/** staffApprovals — proto/part5.html: the desk's queue, with its refusals on the row. */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, type SheetListing } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
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
        setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
        return false;
      }
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
      {said ? (
        <div className="notice notice--info">
          <div>
            <div className="notice__t" style={{ color: "var(--chrome)" }}>Nothing was sent</div>
            <p style={{ color: "#124A63" }}>{said}</p>
          </div>
        </div>
      ) : null}
      <div className="grid grid--4">
        <div className="tile"><span className="eyebrow">Expected sheets</span><span className="n tnum">{t.expected}</span><span className="c">In this scope</span></div>
        <div className="tile"><span className="eyebrow">Senate approved</span><span className="n tnum" style={{ color: "var(--green-ink)" }}>{t.senateApproved}</span><span className="c">{t.expected ? `${Math.round((100 * t.senateApproved) / t.expected)}% complete` : "Nothing expected yet"}</span></div>
        <div className="tile"><span className="eyebrow">In workflow</span><span className="n tnum" style={{ color: "var(--chrome)" }}>{t.inWorkflow}</span><span className="c">Moving through stages</span></div>
        <div className="tile"><span className="eyebrow">Not submitted</span><span className="n tnum" style={{ color: "var(--red-ink)" }}>{t.notSubmitted}</span><span className="c">{t.notSubmitted ? "Waiting on lecturers" : "Nothing outstanding"}</span></div>
      </div>

      <div className="card">
        <div className="card__head"><span className="card__title">{title}</span><span className="sub2">{sub}</span></div>
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
                    <td><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}</div></td>
                    <td className="sub2">{s.deptName}</td>
                    <td className="mid tnum">{s.candidates}</td>
                    <td className="mid">{s.failRate === null ? <span style={{ color: "var(--faint)" }}>—</span> : high ? <span className="pill pill--bad tnum">{s.failRate}%</span> : <span className="tnum">{s.failRate}%</span>}</td>
                    <td>
                      {s.stage === "ENTRY" ? (
                        <><strong style={{ color: "var(--red-ink)" }}>Not submitted</strong><div className="sub2">{s.lecturer ?? "No lecturer allocated"}{s.daysLate ? ` · ${s.daysLate} days overdue` : ""}</div></>
                      ) : (
                        <>{stageText}{s.blockedForYou ? <div className="sub2">You approved the previous stage — another holder of the next desk must approve this one</div> : who ? <div className="sub2">With {who}</div> : null}{high ? <div className="sub2" style={{ color: "var(--red-ink)" }}>Fail rate above half the candidates — review before approving</div> : null}</>
                      )}
                    </td>
                    <td className="num">
                      {s.stage === "ENTRY" ? (
                        <><button className="btn btn--ghost btn--sm" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${s.id}/remind`, {}, `Reminder for ${s.courseCode}`, s.id)}>Remind</button> <button className="btn btn--urgent btn--sm" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${s.id}/remind`, {}, `Escalation for ${s.courseCode}`, s.id)}>Escalate</button></>
                      ) : s.stage === "PUBLISHED" ? (
                        <Link href={`/results/chain?sheet=${s.id}`} className="btn btn--ghost btn--sm">Chain</Link>
                      ) : s.blockedForYou || !s.mayAct ? (
                        <><button className="btn btn--sm" disabled>Not available to you</button> <Link href={`/results/chain?sheet=${s.id}`} className="btn btn--ghost btn--sm">Review</Link></>
                      ) : high ? (
                        <><button className="btn btn--ghost btn--sm" onClick={() => { setReturning(s.id); setComment(""); }}>Return</button> <Link href={`/results/chain?sheet=${s.id}`} className="btn btn--primary btn--sm">Review</Link></>
                      ) : (
                        <><button className="btn btn--ghost btn--sm" onClick={() => { setReturning(s.id); setComment(""); }}>Return</button> <button className="btn btn--go btn--sm" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, {}, `${s.courseCode} approved at ${s.stage.toLowerCase()} by ${actingOffice}`, s.id)}>{busy === s.id ? "Approving…" : "Approve"}</button></>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {returning ? (
        <Modal title="Return the sheet to the lecturer" sub="The reason goes on the record" onClose={() => setReturning(null)}
          foot={<><button className="btn btn--ghost btn--sm" onClick={() => setReturning(null)}>Cancel</button><span style={{ flexGrow: 1 }} /><button className="btn btn--urgent btn--sm" disabled={!comment.trim() || busy !== null} onClick={async () => { if (await post(`/api/bff/api/v1/results/sheets/${returning}/return`, { comment }, "Sheet returned", returning)) setReturning(null); }}>Return it</button></>}>
          <Field id="ret-why" label="Why it is returned" hint="The lecturer sees this, and so does the audit trail. It re-enters the chain at verification, not at the stage it left.">
            <input id="ret-why" className="ctl" value={comment} onChange={(e) => setComment(e.target.value)} autoComplete="off" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
