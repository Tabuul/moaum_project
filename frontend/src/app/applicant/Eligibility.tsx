"use client";

/** The applicant's programme eligibility (V266): the verdict on the programme applied for with every reason, the alternative
 *  programmes the engine found them eligible for on the current admission policy — each with its details and a request to
 *  change — and the state of a request made. Nothing here is an offer; the Admissions Office decides a change and the
 *  Board decides admission. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { headline, parseChecks, whenAt, type Detail, type ResultRow } from "@/lib/eligibility";
import { CheckTables, Mark, ReasonList, VerdictPil } from "@/lib/eligibility-view";

export function Eligibility() {
  const [d, setD] = useState<Detail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [viewing, setViewing] = useState<ResultRow | null>(null);
  const [asking, setAsking] = useState<ResultRow | null>(null);
  const [note, setNote] = useState("");

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/applicant/me/eligibility", { cache: "no-store" })
      .then(async (r) => { const j = await r.json().catch(() => null); if (!live) return; if (!r.ok) setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); else setD(j as Detail); })
      .catch(() => { if (live) setProblem({ status: 0, title: "Could not read your eligibility." }); });
    return () => { live = false; };
  }, []);

  async function post(path: string, body: unknown, label: string) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/applicant/me/eligibility${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return false; }
      setD(j as Detail); notify(label); return true;
    } finally { setBusy(false); }
  }

  if (!d) return problem ? <Note kind="bad" title="Programme eligibility">{problem.title}</Note> : <Panel title="Programme eligibility"><PBody><div className="sub2">Reading your eligibility…</div></PBody></Panel>;
  if (!d.available) return <Note kind="info" title="Programme eligibility">{d.note ?? "Your eligibility is read once you submit the application form."}</Note>;
  const applied = d.applied;
  const eligible = d.alternatives.filter((a) => a.result === "ELIGIBLE" || a.result === "ELIGIBLE_SCREENING");
  const open = d.changes.find((c) => c.state === "REQUESTED") ?? null;
  const last = d.changes[0] ?? null;

  return (
    <>
      <Panel title="Programme eligibility" right={<span className="row row--inline row--tight"><VerdictPil v={d.run.applied_result} /><Btn kind="ghost" size="sm" disabled={busy} onClick={() => void post("/recalculate", {}, "Eligibility recalculated")}>Recalculate</Btn></span>}>
        <PBody>
          <KvGrid cls="grid--3" pairs={[["Applied programme", applied?.programme ?? d.run.applied_programme ?? "—"], ["Status", <VerdictPil key="v" v={d.run.applied_result} />],
            ["Read under", `${d.run.session} policy · version ${d.run.rules_version ?? "?"}${d.run.policy_state && d.run.policy_state !== "IN_FORCE" ? " (draft settings — provisional)" : ""} · ${whenAt(d.run.evaluated_at)}`]]} />
          {d.run.applied_result === "NOT_ELIGIBLE" ? (
            <Note kind="bad" title="Your selected programme does not currently meet the admission requirements based on the information provided">
              {eligible.length ? <>However, based on your O&rsquo;Level results, your UTME subject combination and the current admission policy, the following programmes may be available to you. This is eligibility information, not an offer of admission, and your programme changes only if you ask and the Admissions Office approves.</> : <>No eligible alternative programme was found based on the submitted qualifications and the current admission policy. The reasons are below; if a result on your record is incomplete, contact the Admissions Office.</>}
            </Note>
          ) : d.run.applied_result === "UNVERIFIED" ? (
            <Note kind="info" title="Some requirements cannot yet be verified">A result the rules need is not yet on your record (for example your O&rsquo;Level result as JAMB sent it). The verdict is read again when it arrives.</Note>
          ) : d.run.applied_result === "ELIGIBLE_SCREENING" ? (
            <Note kind="info" title="Academically eligible — additional screening required">You meet the academic requirements; the programme also requires the additional screening named below. This is not an offer of admission.</Note>
          ) : (
            <Note kind="ok" title="You meet the admission requirements of your selected programme">On the information on your record. This is not an offer of admission; the Admissions Board decides in the normal way.</Note>
          )}
          <div className="eyebrow mt-2 mb-1">Why</div>
          <ReasonList row={applied} />
          <div className="mt-2"><Btn kind="ghost" size="sm" onClick={() => setViewing(applied)}>View eligibility details</Btn></div>
        </PBody>
      </Panel>

      {open || (last && last.state !== "REQUESTED") ? (
        <Note kind={open ? "info" : last!.state === "APPROVED" ? "ok" : "bad"} title={open ? `Your request to change to ${open.to_programme} is with the Admissions Office` : last!.state === "APPROVED" ? `Your programme was changed to ${last!.to_programme}` : `Your request to change to ${last!.to_programme} was not approved`}>
          {open ? `Requested ${whenAt(open.requested_at)}. Your programme changes only when the Office approves; you will be told.` : `${whenAt(last!.decided_at)}${last!.decision_note ? ` · ${last!.decision_note}` : ""}`}
        </Note>
      ) : null}

      {d.run.applied_result === "NOT_ELIGIBLE" ? (
        <Panel title="Programmes you may be eligible for" right={eligible.length ? `${eligible.length} · on the current admission policy` : "None found"}>
          {eligible.length ? (
            <DTable pageSize={0} cols={["S/N|num", "Programme", "Faculty", "Department", "O'Level|mid", "UTME|mid", "Score|mid", "Overall", "|num"]} rows={eligible.map((a, i) => { const h = headline(parseChecks(a)); return [
              <span key="sn" className="tnum sub2">{i + 1}</span>, <strong key="p">{a.programme}</strong>, <span key="f">{a.faculty ?? "—"}</span>, <span key="d" className="sub2">{a.department ?? "—"}</span>,
              <Mark key="o" s={h.olevel} />, <Mark key="u" s={h.combination} />, <Mark key="s" s={h.score} />, <VerdictPil key="v" v={a.result} />,
              <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}><Btn kind="ghost" size="sm" onClick={() => setViewing(a)}>View Details</Btn>{d.canRequestChange ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => { setNote(""); setAsking(a); }}>Request Change</Btn> : null}</span>,
            ]; })} />
          ) : <PBody><div className="sub2">No eligible alternative programme was found based on the submitted qualifications and the current admission policy.</div></PBody>}
          {!d.canRequestChange && eligible.length ? <PBody><div className="sub2">{open ? "A change is already requested." : "The Board's decision on your application has been released; a change of programme is now a matter for the Admissions Office."}</div></PBody> : null}
        </Panel>
      ) : null}

      {viewing ? (
        <Modal title={`Programme eligibility · ${viewing.programme}`} sub={`${viewing.faculty ?? ""}${viewing.department ? ` · ${viewing.department}` : ""}`} wide onClose={() => setViewing(null)}
          foot={<><span className="row row--inline row--tight"><span className="sub2">Overall:</span> <VerdictPil v={viewing.result} /></span><span className="grow" /><Btn kind="primary" onClick={() => setViewing(null)}>Close</Btn></>}>
          <CheckTables row={viewing} />
        </Modal>
      ) : null}
      {asking ? (
        <Modal title={`Request a change to ${asking.programme}`} sub="The Admissions Office decides; nothing changes until it approves" onClose={() => setAsking(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(null)}>Back</Btn><Btn kind="primary" disabled={busy} onClick={async () => { const ok = await post("/change", { programmeCode: asking.programme_code, note: note.trim() || null }, `Change to ${asking.programme} requested`); if (ok) setAsking(null); }}>Request Change</Btn></>}>
          <p>Your application would be considered for <b>{asking.programme}</b> in place of <b>{applied?.programme ?? d.run.applied_programme}</b>. Your eligibility is read again when the Office decides. A change is not an offer of admission.</p>
          <Field id="pc-note" label="A note to the Admissions Office" hint="Optional"><textarea id="pc-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          {asking.result === "ELIGIBLE_SCREENING" ? <Pil kind="warn">Additional screening required for this programme</Pil> : null}
        </Modal>
      ) : null}
    </>
  );
}
