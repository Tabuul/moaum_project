"use client";

/** PROGRAMME CHANGES (V297): the register of every applicant now on a programme other than the one they applied for — the
 *  programme applied for, the programme held now, the reason, the stage the change was made at, who recommended and who
 *  approved it — filtered and exported; the queue of changes awaiting a decision; and the admission correction: an error found
 *  after the Board's decision, even after school fees, recommended by the Academic Office with the error described and decided
 *  by the Registrar's office, never by its recommender. Before anything is recommended the server says what the correction
 *  would do — the road, the engine's verdict, the school fees before and after, the courses to return, the letter to reissue.
 *  Every rule is the server's; this screen shows it and passes the officer's word on. */
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { money } from "@/lib/format";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { whenAt } from "@/lib/eligibility";
import {
  EXPORT_HEAD, NO_FILTER, ROUTE_WORD, STAGE_WORD, admissionWord, exportBody, feeFollowUp, feeWord, filterRows, name, officeWord, parseHistory, stageWord, tally,
  type ChangeStage, type FindRow, type PendingRow, type Preview, type RegisterFilter, type RegisterPage, type RegisterRow,
} from "@/lib/programme-changes";

const RECOMMENDERS = ["academic", "registrar", "dregistrar", "super"];
const CORRECTION_DECIDERS = ["registrar", "dregistrar", "vc", "super"];
const CHANGE_DECIDERS = ["academic", "registrar", "dregistrar", "super"];
const OVERRIDERS = ["registrar", "dregistrar", "dvc", "vc", "super"];
const ELIGIBLE = ["ELIGIBLE", "ELIGIBLE_SCREENING"];
const VERDICT_WORD: Record<string, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  ELIGIBLE: ["ELIGIBLE", "ok"], ELIGIBLE_SCREENING: ["ELIGIBLE · SCREENING", "ok"], NOT_ELIGIBLE: ["NOT ELIGIBLE", "bad"], UNVERIFIED: ["NOT VERIFIED", "warn"],
};
const verdict = (v: string | null | undefined) => { const [w, k] = VERDICT_WORD[v ?? ""] ?? [v ?? "—", "grey" as const]; return <Pil kind={k}>{w}</Pil>; };
const num = (x: number | null | undefined) => Number(x ?? 0);

/** what a correction would do to the fees, the courses and the documents — the same words for the recommender and the approver */
function Impact({ pv }: { pv: Preview }) {
  const f = pv.fees ?? null;
  const regs = (pv.registrations ?? []).filter((r) => r.status !== "LOCKED");
  return (
    <div className="stack" style={{ gap: 8 }}>
      {f ? (
        <KvGrid cls="grid--4" pairs={[
          [`School fees paid · ${f.session}`, <b key="p" className="tnum">{money(num(f.paid))}</b>],
          [`Due on ${pv.current.name}`, <span key="n" className="tnum">{money(num(f.dueNow))}</span>],
          [pv.target ? `Due on ${pv.target.name}` : "Due on the new programme", <span key="a" className="tnum">{f.dueAfter == null ? "—" : money(num(f.dueAfter))}</span>],
          ["After the correction", f.dueAfter == null ? "—" : num(f.excessAfter) > 0 ? <Pil key="x" kind="warn">Excess {money(num(f.excessAfter))} — the Bursary credits or refunds it</Pil>
            : num(f.balanceAfter) > 0 ? <Pil key="x" kind="info">Balance {money(num(f.balanceAfter))} for the student to pay</Pil> : <Pil key="x" kind="ok">Settled</Pil>],
        ]} />
      ) : <div className="sub2">Not yet on the student register: no school fees are paid, and nothing but the programme changes.</div>}
      <ul className="plain sub2" style={{ display: "grid", gap: 2 }}>
        <li>The acceptance fee, already paid, stands; school fees paid are kept and counted against the new programme&rsquo;s fees.</li>
        {regs.length ? <li>{regs.length} course registration{regs.length === 1 ? "" : "s"} ({regs.map((r) => `${r.session} semester ${r.semester}, ${r.status.toLowerCase()}, ${r.courses} course${r.courses === 1 ? "" : "s"}`).join("; ")}) returned to the student: the old programme&rsquo;s courses are dropped.</li> : null}
        {num(pv.matricRows) > 0 ? <li>The matriculation number proposed on the old programme is released from its batch; the student is numbered with the new programme&rsquo;s.</li> : null}
        {pv.letterIssued ? <li>The admission letter is reissued for the new programme (same number, a new version); the earlier one answers REPLACED to the verifier.</li> : null}
        {pv.formsIssued ? <li>The screening forms are regenerated for the new programme.</li> : null}
      </ul>
    </div>
  );
}

export function ProgrammeChanges({ page, actingOffice, openApp }: { page: RegisterPage; actingOffice: string | null; openApp: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const office = actingOffice ?? "";
  const mayRecommend = RECOMMENDERS.includes(office);
  const mayOverride = OVERRIDERS.includes(office);
  const session = page.session;
  const base = `/api/bff/api/v1/admissions/sessions/${session}/programme-changes`;
  const [f, setF] = useState<RegisterFilter>(NO_FILTER);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [viewing, setViewing] = useState<RegisterRow | null>(null);
  // the correction: find the applicant, see the road and the impact, recommend
  const [correcting, setCorrecting] = useState(openApp != null);
  const [finder, setFinder] = useState("");
  const [found, setFound] = useState<FindRow[] | null>(null);
  const [pv, setPv] = useState<Preview | null>(null);
  const [to, setTo] = useState("");
  const [reason, setReason] = useState("ADMISSION_ERROR");
  const [note, setNote] = useState("");
  const [overrideReason, setOverrideReason] = useState("");
  // the decision on a change or a correction awaiting one
  const [deciding, setDeciding] = useState<{ p: PendingRow; kind: "approve" | "reject" } | null>(null);
  const [dNote, setDNote] = useState("");
  const [dPv, setDPv] = useState<Preview | null>(null);

  // arriving with ?app= (from Programme Eligibility or the screening desk) opens the correction on that application
  useEffect(() => {
    if (!openApp) return;
    let live = true;
    fetch(`${base}/${openApp}/preview`, { cache: "no-store" }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok) setPv(j as Preview); else setProblem((j as Problem) ?? { status: r.status, title: r.statusText });
    }).catch(() => { if (live) setProblem({ status: 0, title: "Could not read the application." }); });
    return () => { live = false; };
  }, [openApp, base]);

  const rows = useMemo(() => filterRows(page.rows, f), [page.rows, f]);
  const t = tally(page.rows);
  const faculties = [...new Set(page.rows.map((r) => r.current_faculty ?? "").filter(Boolean))].sort();
  const applied = [...new Map(page.rows.filter((r) => r.applied_code != null).map((r) => [r.applied_code as string, r.applied_programme ?? r.applied_code ?? ""])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
  const reasonsUsed = [...new Map(page.rows.filter((r) => r.reason_code != null).map((r) => [r.reason_code as string, r.reason ?? r.reason_code ?? ""])).entries()];
  const sub = [f.stage ? stageWord(f.stage) : "", f.reason ? reasonsUsed.find(([c]) => c === f.reason)?.[1] ?? f.reason : "", f.faculty, f.applied ? `applied for ${applied.find(([c]) => c === f.applied)?.[1] ?? f.applied}` : "",
    f.from ? `from ${f.from}` : "", f.to ? `to ${f.to}` : "", f.q ? `search “${f.q}”` : ""].filter(Boolean).join(" · ") || "Every applicant moved";

  async function read<T>(url: string): Promise<T | null> {
    const r = await fetch(url, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
    return j as T;
  }
  async function post<T>(url: string, body: unknown, label: string): Promise<T | null> {
    const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
    notify(label);
    return j as T;
  }

  const startCorrection = () => { setProblem(null); setFound(null); setFinder(""); setPv(null); setTo(""); setReason("ADMISSION_ERROR"); setNote(""); setOverrideReason(""); setCorrecting(true); };
  const closeCorrection = () => { setCorrecting(false); setPv(null); setFound(null); if (openApp) go(`/admissions/programme-changes?session=${encodeURIComponent(session)}`); };
  async function find() {
    if (finder.trim().length < 3) { setProblem({ status: 422, title: "Type at least three letters or digits of the name, JAMB number or application number." }); return; }
    setBusy("find"); setProblem(null);
    try { setFound((await read<FindRow[]>(`${base}/find?q=${encodeURIComponent(finder.trim())}`)) ?? []); } finally { setBusy(null); }
  }
  async function choose(appId: string, code: string) {
    setBusy("preview"); setProblem(null);
    try {
      const p = await read<Preview>(`${base}/${appId}/preview${code ? `?to=${encodeURIComponent(code)}` : ""}`);
      if (p) { setPv(p); setTo(code); }
    } finally { setBusy(null); }
  }
  const target = pv?.target ?? null;
  const refused = target != null && !ELIGIBLE.includes(target.result);
  const rs = page.reasons.find((x) => x.code === reason) ?? null;
  const ready = pv != null && pv.route === "CORRECTION" && pv.openRequest == null && target != null && !!rs && note.trim().length > 0 && (!refused || (mayOverride && overrideReason.trim().length > 0));
  async function recommend() {
    if (!pv || !target || !ready) return;
    setBusy("correct");
    try {
      const done = await post<Preview>(`${base}/${pv.applicationId}/correct`, { programmeCode: target.code, reasonCode: reason, note: note.trim(), override: refused, overrideReason: refused ? overrideReason.trim() : null },
        `Admission correction recommended: ${pv.name} from ${pv.current.name} to ${target.name}`);
      if (done) { setPv(done); router.refresh(); }
    } finally { setBusy(null); }
  }

  async function openDecision(p: PendingRow, kind: "approve" | "reject") {
    setProblem(null); setDNote(""); setDPv(null); setDeciding({ p, kind });
    if (p.kind === "CORRECTION") {
      const d = await read<Preview>(`${base}/${p.application_id}/preview?to=${encodeURIComponent(p.to_programme_code)}`);
      if (d) setDPv(d);
    }
  }
  async function decide() {
    if (!deciding) return;
    const { p, kind } = deciding;
    if (kind === "reject" && !dNote.trim()) { const pr: Problem = { status: 422, title: "A rejection carries its reason." }; setProblem(pr); notifyProblem(pr); return; }
    setBusy("decide");
    try {
      const what = p.kind === "CORRECTION" ? "Admission correction" : "Programme change";
      const done = await post<{ state: string }>(`${base}/requests/${p.id}/${kind}`, { note: dNote.trim() || null }, `${what} ${kind === "approve" ? "approved" : "rejected"}: ${name(p)} to ${p.to_programme}`);
      if (done) { setDeciding(null); setDPv(null); router.refresh(); }
    } finally { setBusy(null); }
  }
  const mayDecide = (p: PendingRow) => (p.kind === "CORRECTION" ? CORRECTION_DECIDERS.includes(office) && p.mine !== true : CHANGE_DECIDERS.includes(office));

  const excel = async () => { const blob = await brandedXlsx("Programme Change Register", EXPORT_HEAD, exportBody(rows), { sheetName: "Programme Changes", serial: docSerial("PCR"), sub: `${session} · ${sub}` }); downloadBlob(blob, `programme-changes-${session.replace("/", "-")}.xlsx`); };
  const pdf = () => brandedPrint("Programme Change Register", `${session} · ${sub}`, EXPORT_HEAD, exportBody(rows), docSerial("PCR"));

  return (
    <>
      <PageHead title="Programme changes"
        description={`${session} · applicants now on a programme other than the one applied for. An admission found in error after the Board's decision is corrected here: recommended by the Academic Office, approved by the Registrar's office.`}
        actions={<>
          <select className="ctl" aria-label="Session" style={{ width: 150 }} value={session} onChange={(e) => go(`/admissions/programme-changes?session=${encodeURIComponent(e.target.value)}`)}>
            {(page.sessions.some((s) => s.name === session) ? page.sessions : [{ name: session, applications: 0, changed: 0 }, ...page.sessions]).map((s) => <option key={s.name} value={s.name}>{s.name}{s.changed ? ` · ${s.changed} moved` : ""}</option>)}
          </select>
          {mayRecommend ? <Btn kind="primary" onClick={startCorrection}>Correct an admission</Btn> : null}
          <Btn kind="secondary" disabled={!rows.length} onClick={() => void excel()}>Excel</Btn>
          <Btn kind="ghost" disabled={!rows.length} onClick={pdf}>PDF</Btn>
        </>} />
      {problem && !correcting && !deciding ? <ProblemNotice problem={problem} /> : null}
      <Tiles cls="grid--3" items={[
        ["Applicants moved", String(t.applicants), null, "From the programme they applied for"],
        ["Before the decision", String(t.beforeDecision), null, "The applicant’s or the Office’s request"],
        ["At screening", String(t.screening), null, "The screening officer’s change"],
        ["Admission corrections", String(t.corrections), t.corrections ? "var(--amber-ink)" : null, "After the decision, up to matriculation"],
        ["Awaiting a decision", String(page.pending.length), page.pending.length ? "var(--amber-ink)" : null, "Changes and corrections recommended"],
        ["School fees to follow up", String(t.followUp), t.followUp ? "var(--red-ink)" : null, "A correction left a balance owed, or an excess to credit"],
      ]} />

      {page.pending.length ? (
        <Panel title="Awaiting a decision" right={<Pil kind="warn">{page.pending.length} recommended</Pil>}>
          <DTable pageSize={0} cols={["Applicant", "From → To", "Kind|mid", "Reason", "Recommended", "Admission then|mid", "|num"]} rows={page.pending.map((p) => [
            <span key="a"><strong>{name(p)}</strong><div className="sub2 tnum">{p.jamb_reg_no} · {p.application_no}</div></span>,
            <span key="p">{p.from_programme}<div>→ <b>{p.to_programme}</b></div>{p.override ? <div className="sub2">Override: {p.override_reason ?? ""}</div> : null}</span>,
            <Pil key="k" kind={p.kind === "CORRECTION" ? "warn" : "info"}>{p.kind === "CORRECTION" ? "Correction" : "Change"}</Pil>,
            <span key="r">{p.reason ?? p.reason_code ?? "—"}{p.note ? <div className="sub2">{p.note}</div> : null}</span>,
            <span key="w" className="sub2">{p.requested_by_kind === "APPLICANT" ? "The applicant" : officeWord(p.recommended_office)}{p.recommended_by ? ` · ${p.recommended_by}` : ""}<div className="tnum">{whenAt(p.requested_at)}</div></span>,
            <span key="s" className="sub2">{p.kind === "CORRECTION" ? admissionWord(p.admission_stage) : p.screening_state_at_request ? "At screening" : "Before the decision"}</span>,
            <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
              {mayDecide(p) ? <><Btn kind="go" size="sm" disabled={busy !== null} onClick={() => void openDecision(p, "approve")}>{p.kind === "CORRECTION" ? "Review and approve" : "Approve"}</Btn><Btn kind="urgent" size="sm" disabled={busy !== null} onClick={() => void openDecision(p, "reject")}>Reject</Btn></>
                : p.mine ? <Pil kind="grey">Your recommendation — another officer decides</Pil> : <span className="sub2">{p.kind === "CORRECTION" ? "For the Registrar’s office" : "For the Admissions Office"}</span>}
            </span>,
          ])} />
        </Panel>
      ) : null}

      <div className="scope">
        <div className="scope__f"><Field id="pc-stage" label="Stage"><select id="pc-stage" className="ctl" value={f.stage} onChange={(e) => setF({ ...f, stage: e.target.value })}><option value="">Every stage</option>{(Object.keys(STAGE_WORD) as ChangeStage[]).map((s) => <option key={s} value={s}>{STAGE_WORD[s][0]}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="pc-reason" label="Reason"><select id="pc-reason" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })}><option value="">Every reason</option>{reasonsUsed.map(([c, l]) => <option key={c} value={c}>{l}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="pc-fac" label="Faculty now"><select id="pc-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value })}><option value="">All</option>{faculties.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="pc-applied" label="Programme applied for"><select id="pc-applied" className="ctl" value={f.applied} onChange={(e) => setF({ ...f, applied: e.target.value })}><option value="">All</option>{applied.map(([c, l]) => <option key={c} value={c}>{l}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="pc-from" label="Approved from"><input id="pc-from" type="date" className="ctl" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} /></Field></div>
        <div className="scope__f"><Field id="pc-to" label="Approved to"><input id="pc-to" type="date" className="ctl" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></Field></div>
        <div className="scope__f grow"><Field id="pc-q" label="Search" hint="Name, JAMB number, application number, programme, reason or note">
          <div className="scope__search"><input id="pc-q" className="ctl" placeholder="Search the register…" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} /><Btn kind="ghost" onClick={() => setF(NO_FILTER)}>Reset</Btn></div>
        </Field></div>
      </div>

      <Panel title="Applicants moved from the programme they applied for" right={`${rows.length} of ${page.rows.length} · names A–Z`}>
        {rows.length ? (
          <DTable pageSize={50} cols={["S/N|num", "Applicant", "Applied for", "Now", "Reason", "Stage|mid", "Approved", "Admission now", "School fees", "|num"]} rows={rows.map((r, i) => {
            const fu = feeFollowUp(r);
            return [
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <span key="a"><strong>{name(r)}</strong><div className="sub2 tnum">{r.jamb_reg_no} · {r.application_no}</div></span>,
              <span key="f">{r.applied_programme ?? "—"}<div className="sub2">{r.applied_faculty ?? ""}</div></span>,
              <span key="n"><b>{r.current_programme}</b><div className="sub2">{r.current_faculty ?? ""}{r.moved === false ? " · back to the programme applied for" : ""}</div></span>,
              <span key="r">{r.reason ?? "—"}{r.note ? <div className="sub2">{r.note}</div> : null}{r.override ? <div><Pil kind="warn">Override</Pil></div> : null}</span>,
              <span key="s"><Pil kind={STAGE_WORD[r.stage]?.[1] ?? "grey"}>{stageWord(r.stage)}</Pil>{r.changes > 1 ? <div className="sub2">{r.changes} changes</div> : null}</span>,
              <span key="d" className="sub2">{whenAt(r.decided_at)}<div>{officeWord(r.decided_office)}{r.decided_by ? ` · ${r.decided_by}` : ""}</div></span>,
              <span key="w" className="sub2">{admissionWord(r.stage_now)}</span>,
              <span key="m" className="sub2">{feeWord(r) || "—"}{fu === "EXCESS" ? <div><Pil kind="warn">Excess to credit</Pil></div> : fu === "BALANCE" ? <div><Pil kind="info">Balance owed</Pil></div> : null}</span>,
              <Btn key="v" kind="ghost" size="sm" onClick={() => setViewing(r)}>Details</Btn>,
            ];
          })} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.application_no} ${r.applied_programme ?? ""} ${r.current_programme} ${r.reason ?? ""}`)} />
        ) : (
          <PBody><Note kind="info" title={page.rows.length ? "No applicant matches the filters" : `No applicant has changed programme in ${session}`}>
            {page.rows.length ? "Widen the filters or press Reset." : "An approved change of programme — on the applicant's request, at the screening or by an admission correction — lists the applicant here."}
          </Note></PBody>
        )}
      </Panel>

      {viewing ? (() => {
        const h = parseHistory(viewing.history);
        return (
          <Modal title={`${name(viewing)} · ${viewing.application_no}`} sub={`${viewing.jamb_reg_no} · ${viewing.entry_mode === "UTME" ? "UTME" : "Direct Entry"} · ${session}`} wide onClose={() => setViewing(null)}
            foot={<><span className="grow" /><Btn kind="primary" onClick={() => setViewing(null)}>Close</Btn></>}>
            <div className="stack">
              <KvGrid cls="grid--2" pairs={[
                ["Programme applied for", <span key="a">{viewing.applied_programme ?? "—"}<div className="sub2">{[viewing.applied_faculty, viewing.applied_department].filter(Boolean).join(" · ")}</div></span>],
                ["Programme now", <span key="n"><b>{viewing.current_programme}</b><div className="sub2">{[viewing.current_faculty, viewing.current_department].filter(Boolean).join(" · ")}</div></span>],
                ["Reason", <span key="r">{viewing.reason ?? "—"}{viewing.note ? <div className="sub2">{viewing.note}</div> : null}</span>],
                ["Stage", <Pil key="s" kind={STAGE_WORD[viewing.stage]?.[1] ?? "grey"}>{stageWord(viewing.stage)}</Pil>],
                ["Recommended", <span key="w" className="sub2">{viewing.requested_by_kind === "APPLICANT" ? "The applicant" : officeWord(viewing.recommended_office)}{viewing.recommended_by ? ` · ${viewing.recommended_by}` : ""} · {whenAt(viewing.requested_at)}</span>],
                ["Approved", <span key="d" className="sub2">{officeWord(viewing.decided_office)}{viewing.decided_by ? ` · ${viewing.decided_by}` : ""} · {whenAt(viewing.decided_at)}{viewing.decision_note ? ` · ${viewing.decision_note}` : ""}</span>],
                ["Eligibility", <span key="e">{verdict(viewing.eligibility)}{viewing.override ? <div className="sub2">Override: {viewing.override_reason ?? ""}</div> : null}</span>],
                ["Admission", <span key="t" className="sub2">{viewing.stage_then ? `${admissionWord(viewing.stage_then)} when corrected · ` : ""}{admissionWord(viewing.stage_now)} now</span>],
              ]} />
              {viewing.kind === "CORRECTION" ? (
                <Note kind="info" title="What the correction did">
                  {viewing.fees_paid != null ? <>School fees {viewing.fee_session}: paid {money(num(viewing.fees_paid))}; due {money(num(viewing.fees_due_before))} on the programme applied for, {money(num(viewing.fees_due_after))} on the new one{viewing.paid_now != null ? <> · today paid {money(num(viewing.paid_now))} of {money(num(viewing.due_now))}</> : null}. </> : "No school fees had been paid. "}
                  {num(viewing.registrations_returned) ? `${viewing.registrations_returned} course registration(s) returned, ${num(viewing.courses_dropped)} course(s) dropped. ` : ""}
                  {num(viewing.matric_rows_dropped) ? "A proposed matriculation number was released. " : ""}
                  {viewing.letter_reissued ? "The admission letter was reissued. " : ""}{viewing.forms_reissued ? "The screening forms were regenerated." : ""}
                </Note>
              ) : null}
              <div className="eyebrow">Every change, in order</div>
              <ol className="plain" style={{ display: "grid", gap: 6 }}>
                {h.map((x) => (
                  <li key={x.id} className="row row--tight" style={{ gap: 8, alignItems: "baseline", flexWrap: "wrap" }}>
                    <span className="tnum sub2" style={{ minWidth: 140 }}>{whenAt(x.decidedAt)}</span>
                    <span>{x.from} → <b>{x.to}</b></span>
                    <Pil kind={STAGE_WORD[x.stage]?.[1] ?? "grey"}>{stageWord(x.stage)}</Pil>
                    <span className="sub2">{x.reason ?? ""}{x.note ? ` · ${x.note}` : ""}{x.decidedOffice ? ` · approved by the ${officeWord(x.decidedOffice)}` : ""}{x.override ? ` · override: ${x.overrideReason ?? ""}` : ""}</span>
                  </li>
                ))}
              </ol>
            </div>
          </Modal>
        );
      })() : null}

      {correcting ? (
        <Modal title="Correct an admission" sub={`${session} · after the Board's decision — offered, accepted, screened, on the register or with school fees paid — up to matriculation`} wide onClose={closeCorrection}
          foot={<><Btn kind="ghost" onClick={closeCorrection}>Close</Btn><span className="grow" />{pv && pv.route === "CORRECTION" && pv.openRequest == null ? <Btn kind="primary" disabled={!ready || busy !== null} onClick={() => void recommend()}>Recommend the correction</Btn> : null}</>}>
          <div className="stack">
            {problem ? <ProblemNotice problem={problem} /> : null}
            {!pv ? (
              <>
                <Field id="pc-find" label="The applicant" hint="Name, JAMB number or application number — at least three characters">
                  <form className="scope__search" onSubmit={(e) => { e.preventDefault(); void find(); }}><input id="pc-find" className="ctl" autoFocus value={finder} onChange={(e) => setFinder(e.target.value)} placeholder="e.g. 20261234567AB" /><Btn kind="primary" type="submit" disabled={busy !== null}>Find</Btn></form>
                </Field>
                {found ? (found.length ? (
                  <DTable pageSize={0} cols={["Applicant", "Programme", "Where it stands|mid", "Road", "|num"]} rows={found.map((x) => [
                    <span key="a"><strong>{name(x)}</strong><div className="sub2 tnum">{x.jamb_reg_no} · {x.application_no}</div></span>,
                    <span key="p">{x.programme}</span>,
                    <span key="s" className="sub2">{admissionWord(x.stage)}</span>,
                    <span key="r"><Pil kind={ROUTE_WORD[x.route]?.[1] ?? "grey"}>{ROUTE_WORD[x.route]?.[0] ?? x.route}</Pil>{x.route !== "CORRECTION" ? <div className="sub2">{x.detail}</div> : null}</span>,
                    x.route === "CORRECTION" ? <Btn key="c" kind="secondary" size="sm" disabled={busy !== null} onClick={() => void choose(x.id, "")}>Choose</Btn> : <span key="c" />,
                  ])} />
                ) : <Note kind="info" title="No applicant of this session matches">Check the number, or the session chosen above.</Note>) : null}
              </>
            ) : (
              <>
                <KvGrid cls="grid--3" pairs={[
                  ["Applicant", <span key="a"><b>{pv.name}</b><div className="sub2 tnum">{pv.jambRegNo} · {pv.applicationNo}</div></span>],
                  ["Admitted to", <span key="p"><b>{pv.current.name}</b><div className="sub2">{[pv.current.faculty, pv.current.department].filter(Boolean).join(" · ")}</div></span>],
                  ["Where it stands", <span key="s">{admissionWord(pv.stage)}{pv.student?.admissionNo ? <div className="sub2 tnum">{pv.student.admissionNo}</div> : null}</span>],
                ]} />
                {pv.route !== "CORRECTION" ? (
                  <Note kind="bad" title={ROUTE_WORD[pv.route]?.[0] ?? pv.route}>{pv.detail}</Note>
                ) : pv.openRequest ? (
                  <Note kind="info" title={`A ${pv.openRequest.kind === "CORRECTION" ? "correction" : "change"} to ${pv.openRequest.to} awaits a decision`}>
                    Recommended {whenAt(pv.openRequest.requestedAt)}. It is decided on the queue above{pv.openRequest.kind === "CORRECTION" ? " by the Registrar's office" : ""}; nothing more is recommended until it is.
                  </Note>
                ) : (
                  <>
                    <Field id="pc-to-prog" label="Correct the admission to" required>
                      <select id="pc-to-prog" className="ctl" value={to} disabled={busy !== null} onChange={(e) => void choose(pv.applicationId, e.target.value)}>
                        <option value="">Choose the programme…</option>
                        {page.programmes.filter((x) => x.code !== pv.current.code).map((x) => <option key={x.code} value={x.code}>{x.name}{x.faculty ? ` — ${x.faculty}` : ""}</option>)}
                      </select>
                    </Field>
                    {target ? (
                      <>
                        <div className="row row--between"><span><b>{target.name}</b>{target.faculty ? <span className="sub2"> · {target.faculty}{target.department ? ` · ${target.department}` : ""}</span> : null}</span>{verdict(target.result)}</div>
                        {refused ? (
                          <Note kind={mayOverride ? "info" : "bad"} title="The engine does not find the candidate eligible for this programme">
                            {(target.reasons ?? []).join("; ") || "The session's admission settings do not say so."} {mayOverride ? "The Registrar's office may recommend it by override, with the reason; the override stays on the record." : "Only the Registrar's office may recommend a programme the engine refuses."}
                          </Note>
                        ) : null}
                        <Impact pv={pv} />
                        <Field id="pc-reason-c" label="Reason" required>
                          <select id="pc-reason-c" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)}>{page.reasons.map((x) => <option key={x.code} value={x.code}>{x.label}</option>)}</select>
                        </Field>
                        <Field id="pc-note" label="What was found in error" hint="What the Registrar decides on; it stays on the record" required>
                          <textarea id="pc-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Offered Computer Science on a mis-keyed UTME score; the Board's approved list names Accounting" />
                        </Field>
                        {refused && mayOverride ? (
                          <Field id="pc-override" label="Reason for the override" required><textarea id="pc-override" className="ctl" rows={2} value={overrideReason} onChange={(e) => setOverrideReason(e.target.value)} /></Field>
                        ) : null}
                        <div className="sub2">The correction takes effect only when the Registrar, the Deputy Registrar or the Vice-Chancellor&rsquo;s office approves it — never the officer who recommends it. The applicant is told when it is decided.</div>
                      </>
                    ) : <div className="sub2">Choose the programme to see the verdict and what the correction would change.</div>}
                  </>
                )}
                <div><Btn kind="ghost" disabled={busy !== null} onClick={() => { setPv(null); setFound(null); setTo(""); setNote(""); setOverrideReason(""); setProblem(null); }}>Another applicant</Btn></div>
              </>
            )}
          </div>
        </Modal>
      ) : null}

      {deciding ? (
        <Modal title={`${deciding.kind === "approve" ? "Approve" : "Reject"} the ${deciding.p.kind === "CORRECTION" ? "admission correction" : "change of programme"} to ${deciding.p.to_programme}`}
          sub={`${name(deciding.p)} · ${deciding.p.jamb_reg_no} · from ${deciding.p.from_programme}`} wide={deciding.p.kind === "CORRECTION"} onClose={() => { setDeciding(null); setDPv(null); }}
          foot={<><Btn kind="ghost" onClick={() => { setDeciding(null); setDPv(null); }}>Back</Btn><span className="grow" /><Btn kind={deciding.kind === "approve" ? "go" : "urgent"} disabled={busy !== null} onClick={() => void decide()}>{deciding.kind === "approve" ? (deciding.p.kind === "CORRECTION" ? "Approve and correct the admission" : "Approve and change the programme") : "Reject"}</Btn></>}>
          <div className="stack">
            {problem ? <ProblemNotice problem={problem} /> : null}
            <KvGrid cls="grid--2" pairs={[
              ["Reason", <span key="r">{deciding.p.reason ?? deciding.p.reason_code ?? "—"}{deciding.p.note ? <div className="sub2">{deciding.p.note}</div> : null}</span>],
              ["Recommended", <span key="w" className="sub2">{deciding.p.requested_by_kind === "APPLICANT" ? "The applicant" : officeWord(deciding.p.recommended_office)}{deciding.p.recommended_by ? ` · ${deciding.p.recommended_by}` : ""} · {whenAt(deciding.p.requested_at)}</span>],
              ["Eligibility then", <span key="e">{verdict(deciding.p.eligibility_at_request)}{deciding.p.override ? <div className="sub2">Override: {deciding.p.override_reason ?? ""}</div> : null}</span>],
              ["Admission then", <span key="s" className="sub2">{deciding.p.kind === "CORRECTION" ? admissionWord(deciding.p.admission_stage) : deciding.p.screening_state_at_request ? "At screening" : "Before the decision"}</span>],
            ]} />
            {deciding.p.kind === "CORRECTION" ? (dPv ? (
              <>
                {dPv.route !== "CORRECTION" ? <Note kind="bad" title="The admission has moved on since the recommendation">{dPv.detail}</Note> : null}
                {dPv.target ? <div className="row row--between"><span>Eligibility now for <b>{dPv.target.name}</b></span>{verdict(dPv.target.result)}</div> : null}
                <Impact pv={dPv} />
              </>
            ) : <div className="sub2">Reading what the correction would do…</div>) : (
              <div className="sub2">Eligibility is read again now; the programme changes on the record and the applicant is told.</div>
            )}
            <Field id="pc-dnote" label={deciding.kind === "approve" ? "Note (optional)" : "Reason (required)"} required={deciding.kind === "reject"}>
              <textarea id="pc-dnote" className="ctl" rows={3} value={dNote} onChange={(e) => setDNote(e.target.value)} />
            </Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
