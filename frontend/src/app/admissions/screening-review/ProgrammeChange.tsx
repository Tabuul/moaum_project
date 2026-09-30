"use client";

/** The screening officer's change of programme (V284): the candidate's current admission and the engine's verdict on it with the
 *  requirement that failed, every alternative evaluated under the session's settings with its O'Level, UTME-combination and score
 *  ticks, the details of any one, the recommendation of an eligible one with a configured reason (the override reserved to the
 *  Registrar's offices, recorded as such), and the approval — re-validated on the server — that changes the programme, screens
 *  the record successful and opens school fees. Nothing here is guessed: every verdict is the engine's, read from the API. */
import { useEffect, useMemo, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, LinkBtn, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { GROUPS, KIND_WORD, VERDICT, headline, mark, parseChecks, whenAt, type ChangeReason, type ChangeRequest, type Check, type CheckStatus, type Detail, type ResultRow } from "@/lib/eligibility";

const tick = (s: CheckStatus) => <span className={s === "MET" ? "ink-green b700" : s === "NOT_MET" ? "ink-red b700" : "sub2"}>{mark(s)}</span>;
const eligible = (r: ResultRow) => r.result === "ELIGIBLE" || r.result === "ELIGIBLE_SCREENING";

function Checks({ checks }: { checks: Check[] }) {
  return (
    <div className="stack" style={{ gap: 8 }}>
      {GROUPS.map(([title, kinds]) => {
        const cs = checks.filter((c) => kinds.includes(c.kind));
        if (!cs.length) return null;
        return (
          <div key={title}>
            <div className="eyebrow mb-1">{title}</div>
            {cs.map((c, i) => <div key={i} className="row row--tight" style={{ gap: 8, alignItems: "baseline" }}>{tick(c.status)}<span><b>{c.label || KIND_WORD[c.kind] || c.kind}</b> — required: {c.requirement || "—"} · candidate: {c.candidate || "—"}{c.mandatory ? "" : <span className="sub2"> (advisory)</span>}</span></div>)}
          </div>
        );
      })}
    </div>
  );
}

export function ProgrammeChange({ base, appId, may, mayOverride, current, onChanged }: {
  base: string; appId: string; may: boolean; mayOverride: boolean;
  current: { name: string; programme: string; faculty: string | null; department: string | null; session: string; jamb: string; utme: number | null; screeningState: string | null };
  onChanged: () => void;
}) {
  const [d, setD] = useState<Detail | null>(null);
  const [reasons, setReasons] = useState<ChangeReason[]>([]);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [showAll, setShowAll] = useState(false);
  const [fac, setFac] = useState("");
  const [dept, setDept] = useState("");
  const [q, setQ] = useState("");
  const [detailOf, setDetailOf] = useState<ResultRow | null>(null);
  const [choosing, setChoosing] = useState<ResultRow | null>(null);
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [overrideReason, setOverrideReason] = useState("");
  const [decidingNote, setDecidingNote] = useState("");

  useEffect(() => {
    let live = true;
    fetch(`${base}/eligibility/${appId}`, { cache: "no-store" }).then(async (r) => { const j = await r.json().catch(() => null); if (!live) return; if (r.ok) setD(j as Detail); else setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); }).catch(() => { if (live) setProblem({ status: 0, title: "Could not read the engine's verdict." }); });
    fetch(`${base}/eligibility/reasons`, { cache: "no-store" }).then(async (r) => { const j = await r.json().catch(() => null); if (live && r.ok && Array.isArray(j)) setReasons(j as ChangeReason[]); }).catch(() => undefined);
    return () => { live = false; };
  }, [base, appId]);

  async function call<T>(path: string, body: unknown, label: string, key: string): Promise<T | null> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`${base}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
      notify(label); return j as T;
    } finally { setBusy(null); }
  }
  const recommend = async () => {
    if (!choosing) return;
    const rs = reasons.find((x) => x.code === reason);
    if (!rs) { setProblem({ status: 422, title: "Choose the reason for the change." }); return; }
    if (rs.requires_note && !note.trim()) { setProblem({ status: 422, title: `Describe the reason: "${rs.label}" needs a note.` }); return; }
    const over = !eligible(choosing);
    if (over && !overrideReason.trim()) { setProblem({ status: 422, title: "An eligibility override carries its reason." }); return; }
    const r = await call<Detail>(`/eligibility/${appId}/change`, { programmeCode: choosing.programme_code, reasonCode: reason, note: note.trim() || null, override: over, overrideReason: over ? overrideReason.trim() : null },
      `Programme change to ${choosing.programme} recommended for ${current.name}`, "rec");
    if (r) { setD(r); setChoosing(null); setDetailOf(null); setReason(""); setNote(""); setOverrideReason(""); onChanged(); }
  };
  const decide = async (c: ChangeRequest, kind: "approve" | "reject") => {
    if (kind === "reject" && !decidingNote.trim()) { setProblem({ status: 422, title: "A rejection carries its reason." }); return; }
    const r = await call<Detail>(`/eligibility/changes/${c.id}/${kind}`, { note: decidingNote.trim() || null }, kind === "approve" ? `Programme change approved: ${c.to_programme}` : `Programme change rejected: ${c.to_programme}`, kind);
    if (r) { setD(r); setDecidingNote(""); onChanged(); }
  };

  const applied = d?.applied ?? null;
  const appliedChecks = useMemo(() => parseChecks(applied), [applied]);
  const failed = appliedChecks.filter((c) => c.status === "NOT_MET" && c.mandatory);
  const alts = d?.alternatives ?? [];
  const faculties = [...new Map(alts.map((r) => [r.faculty_code ?? r.faculty ?? "", r.faculty ?? ""])).entries()].filter(([k]) => k);
  const depts = [...new Set(alts.filter((r) => !fac || (r.faculty_code ?? r.faculty) === fac).map((r) => r.department ?? "").filter(Boolean))];
  const needle = q.trim().toLowerCase();
  const shown = alts.filter((r) => (showAll || needle || eligible(r)) && (!fac || (r.faculty_code ?? r.faculty) === fac) && (!dept || r.department === dept)
    && (!needle || `${r.programme} ${r.programme_code} ${r.department ?? ""} ${r.faculty ?? ""}`.toLowerCase().includes(needle)));
  const open = (d?.changes ?? []).find((c) => c.state === "REQUESTED") ?? null;
  const approvedAfter = (d?.changes ?? []).filter((c) => c.state === "APPROVED");
  const canRecommend = may && !open && ["PENDING", "IN_REVIEW", "CORRECTION_REQUIRED", "UNSUCCESSFUL"].includes(current.screeningState ?? "");

  return (
    <div className="stack">
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="eyebrow">Current admission</div>
      <KvGrid cls="grid--3" pairs={[["Applicant", current.name], ["Programme", <b key="p">{current.programme}</b>], ["Session", current.session], ["Faculty", current.faculty ?? "—"], ["Department", current.department ?? "—"], ["JAMB score", <span key="j" className="tnum">{current.utme ?? "—"}</span>]]} />
      {!d ? <div className="sub2">Reading the engine&rsquo;s verdict…</div> : (
        <>
          <div className="eyebrow">Current programme eligibility</div>
          <div className="row row--between">
            <span><b>{applied?.programme ?? current.programme}</b> · <Pil kind={VERDICT[d.run.applied_result][1]}>{VERDICT[d.run.applied_result][0]}</Pil></span>
            <span className="sub2">Policy {d.run.session}{d.run.rules_version ? ` · V${d.run.rules_version}` : ""} ({(d.run.policy_state ?? "").toLowerCase()}) · evaluated {whenAt(d.run.evaluated_at)}{d.run.stale ? " · stale: settings changed since" : ""}</span>
          </div>
          {failed.length ? <Note kind="bad" title="Configured requirements not met">{failed.map((c, i) => <div key={i}>✕ <b>{c.label || KIND_WORD[c.kind] || c.kind}</b> — required: {c.requirement || "—"} · candidate: {c.candidate || "—"}</div>)}</Note>
            : d.run.applied_result === "NOT_ELIGIBLE" ? <Note kind="bad" title="Not eligible">{(applied?.reasons ?? []).join("; ")}</Note> : <Note kind="ok" title="The candidate meets the programme's requirements">A change of programme is not called for by eligibility; it may still be recommended on the screening decision or programme suitability.</Note>}

          {may && !open && current.screeningState === "SUCCESSFUL" ? (
            <Note kind="info" title="The screening is successful: the programme is no longer changed here"
              action={<LinkBtn kind="secondary" href={`/admissions/programme-changes?session=${encodeURIComponent(current.session)}&app=${appId}`}>Correct the admission on Programme Changes</LinkBtn>}>
              An error found in the admission since — even after school fees — is corrected as an admission correction: recommended with the error described and approved by the Registrar&rsquo;s office, the fees paid kept against the new programme.
            </Note>
          ) : null}
          {approvedAfter.length ? approvedAfter.map((c) => <Note key={c.id} kind="ok" title={`Programme change approved · ${c.from_programme} → ${c.to_programme}`}>{whenAt(c.decided_at)}{c.decided_officer ? ` · ${c.decided_officer}` : ""}{c.reason_code ? ` · ${reasons.find((x) => x.code === c.reason_code)?.label ?? c.reason_code}` : ""}{c.override ? ` · OVERRIDE (engine: ${c.original_eligibility}) — ${c.override_reason}` : ""}{c.decision_note ? ` · ${c.decision_note}` : ""}</Note>) : null}
          {open ? (
            <Note kind="info" title={`Programme change awaiting approval · ${open.from_programme} → ${open.to_programme}`}>
              Recommended {whenAt(open.requested_at)} by the {open.recommended_office ?? open.requested_by_kind.toLowerCase()}{open.reason_code ? ` · ${reasons.find((x) => x.code === open.reason_code)?.label ?? open.reason_code}` : ""}{open.note ? ` · ${open.note}` : ""}. Engine at recommendation: {open.eligibility_at_request}{open.override ? ` · OVERRIDE — ${open.override_reason}` : ""}.
              {may ? (
                <div className="mt-2 stack" style={{ gap: 8 }}>
                  <Field id="pc-dn" label="Note for the decision" hint="Required for a rejection"><input id="pc-dn" className="ctl" value={decidingNote} onChange={(e) => setDecidingNote(e.target.value)} /></Field>
                  <div className="row row--inline row--tight"><Btn kind="go" disabled={busy !== null} onClick={() => void decide(open, "approve")}>Approve: change the programme and screen successful</Btn><Btn kind="urgent" disabled={busy !== null} onClick={() => void decide(open, "reject")}>Reject</Btn></div>
                  <div className="sub2">Approval re-reads eligibility on the server, changes the candidate&rsquo;s and the student&rsquo;s programme (the original stays on the request and the trail), records the screening as successful on the new programme, generates the screening forms for it, keeps the acceptance fee paid once and opens school fees.</div>
                </div>
              ) : null}
            </Note>
          ) : null}

          <div className="row row--between">
            <div className="eyebrow">Eligible alternative programmes{showAll ? " and those considered" : ""}</div>
            <label className="sub2 row row--tight" style={{ gap: 6 }}><input type="checkbox" className="pchk" checked={showAll} onChange={(e) => setShowAll(e.target.checked)} /> Show programmes considered and not eligible, with the reason</label>
          </div>
          <div className="row row--tight" style={{ gap: 8, flexWrap: "wrap" }}>
            <select className="ctl" style={{ width: 200 }} value={fac} onChange={(e) => { setFac(e.target.value); setDept(""); }}><option value="">All faculties</option>{faculties.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
            <select className="ctl" style={{ width: 200 }} value={dept} onChange={(e) => setDept(e.target.value)}><option value="">All departments</option>{depts.map((x) => <option key={x} value={x}>{x}</option>)}</select>
            <input className="ctl" style={{ width: 240 }} placeholder="Search programme, code, department, faculty" value={q} onChange={(e) => setQ(e.target.value)} />
          </div>
          {shown.length ? (
            <DTable pageSize={0} cols={["Programme", "Faculty", "Department", "O'Level|mid", "JAMB combination|mid", "JAMB score|mid", "Overall|mid", "|num"]} rows={shown.map((r) => {
              const h = headline(parseChecks(r));
              return [
                <span key="p"><b>{r.programme}</b><div className="sub2 tnum">{r.programme_code}{r.suggested ? " · suggested" : ""}</div></span>,
                <span key="f" className="sub2">{r.faculty ?? "—"}</span>, <span key="d" className="sub2">{r.department ?? "—"}</span>,
                <span key="o">{tick(h.olevel)}</span>, <span key="c">{tick(h.combination)}</span>, <span key="s">{tick(h.score)}</span>,
                <Pil key="v" kind={VERDICT[r.result][1]}>{eligible(r) ? "ELIGIBLE" : r.result === "UNVERIFIED" ? "REQUIRES VERIFICATION" : "NOT ELIGIBLE"}</Pil>,
                <span key="a" className="row row--inline row--tight"><Btn kind="ghost" size="sm" onClick={() => setDetailOf(detailOf?.programme_code === r.programme_code ? null : r)}>{detailOf?.programme_code === r.programme_code ? "Hide details" : "Details"}</Btn>
                  {canRecommend && eligible(r) ? <Btn kind="primary" size="sm" onClick={() => { setChoosing(r); setReason(reasons[0]?.code ?? ""); }}>Select programme</Btn> : canRecommend && mayOverride && !eligible(r) ? <Btn kind="secondary" size="sm" onClick={() => { setChoosing(r); setReason(reasons[0]?.code ?? ""); }}>Override…</Btn> : null}</span>,
              ];
            })} />
          ) : <div className="sub2">{alts.length ? "No programme matches the filter." : d.run.applied_result === "NOT_ELIGIBLE" ? "No programme under the session's settings finds this candidate eligible." : "Alternatives are searched only when the applied programme is refused; recalculate on Programme Eligibility to evaluate them."}</div>}
          {detailOf ? (
            <div className="card"><div className="card__body stack">
              <div className="row row--between"><b>Programme eligibility details · {detailOf.programme}</b><Pil kind={VERDICT[detailOf.result][1]}>{eligible(detailOf) ? "ELIGIBLE FOR PROGRAMME CHANGE" : VERDICT[detailOf.result][0]}</Pil></div>
              <Checks checks={parseChecks(detailOf)} />
              {detailOf.reasons?.length ? <div className="sub2">Reasons: {detailOf.reasons.join("; ")}</div> : null}
            </div></div>
          ) : null}
        </>
      )}

      {choosing && d ? (
        <Modal title="Confirm programme change" sub={`${current.name} · ${current.session}`} onClose={() => setChoosing(null)}
          foot={<><Btn kind="ghost" onClick={() => setChoosing(null)}>Back</Btn><Btn kind={eligible(choosing) ? "primary" : "urgent"} disabled={busy !== null} onClick={() => void recommend()}>{eligible(choosing) ? "Recommend the change" : "Recommend by override"}</Btn></>}>
          <KvGrid cls="grid--2" pairs={[
            ["Current programme", current.programme], ["New programme", <b key="n">{choosing.programme}</b>],
            ["Current faculty", current.faculty ?? "—"], ["New faculty", choosing.faculty ?? "—"],
            ["Current department", current.department ?? "—"], ["New department", choosing.department ?? "—"],
          ]} />
          {(() => { const h = headline(parseChecks(choosing)); return <div className="mt-2 row row--tight" style={{ gap: 14 }}><span>{tick(h.olevel)} O&rsquo;Level requirements</span><span>{tick(h.combination)} JAMB combination</span><span>{tick(h.score)} JAMB score</span><span>{tick(eligible(choosing) ? "MET" : "NOT_MET")} Admission policy</span></div>; })()}
          {!eligible(choosing) ? <Note kind="bad" title="The engine finds the candidate not eligible for this programme">{choosing.reasons.join("; ")} — recommending it is an override reserved to the Registrar&rsquo;s offices; the verdict, your reason and your name stay on the request and the trail.</Note> : null}
          <Field id="pc-reason" label="Reason for change" required><select id="pc-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)}>{reasons.map((r) => <option key={r.code} value={r.code}>{r.label}</option>)}</select></Field>
          <Field id="pc-note" label={reasons.find((x) => x.code === reason)?.requires_note ? "Description (required)" : "Note"} required={!!reasons.find((x) => x.code === reason)?.requires_note}><textarea id="pc-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          {!eligible(choosing) ? <Field id="pc-ovr" label="Override reason" required><textarea id="pc-ovr" className="ctl" rows={2} value={overrideReason} onChange={(e) => setOverrideReason(e.target.value)} /></Field> : null}
          <p className="sub2">The programme is re-validated on the server now and again at approval; nothing changes until an authorised officer approves. The acceptance fee is never charged again.</p>
        </Modal>
      ) : null}
    </div>
  );
}
