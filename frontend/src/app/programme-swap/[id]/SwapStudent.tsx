"use client";

/**
 * One student's programme swap (V578): the record as it stands (FROM), the placement to move to (TO — faculty, department,
 * programme, level, cascading and searchable), the kind and the reason; VALIDATE asks the server what the swap would do and what
 * stands in its way; the preview shows it all — what changes, what stays, the fee lines under each programme, the registration
 * impact — and CONFIRM makes the swap: the officer who initiates it decides it, and the placement moves at once (V633).
 * V669: the kind "Approved transfer restored (old portal)" restores a transfer approved on the old portal — the programme left, the
 * session it took effect, the date and the old portal's reference recorded with it, an application left in the transfer queue to the
 * same programme withdrawn; no new application, fee or approval, and the matriculation number untouched.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Passport, day } from "@/components/proto/blocks";
import { KIND_WORDS, REVIEW_WORDS, refusalWords, restoreWords, signalWords, type CheckResult, type Faculty, type RestoreCheck, type RestoreDone, type ReviewStatus,
  type SwapKind } from "@/lib/programme-swap";
import { words } from "@/lib/full-record";
import { TargetPicker, type Target } from "../TargetPicker";
import { ProgrammeHistory } from "../ProgrammeHistory";
import { swapPost } from "../swap-call";

export interface StudentView {
  student: { id: string; surname: string; other_names: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null; status: string;
    entry_mode: string | null; study_mode: string | null; entry_session: string | null; entry_level: number | null; current_level: number | null; centre_code: string | null;
    programme_code: string; programme: string | null; category: string | null; dept_code: string | null; department: string | null; faculty_code: string | null;
    faculty: string | null; levels: number[] | null; programme_type: string | null };
  session: string; sessions: string[];
  history: Record<string, unknown>[];
  openTransfer: { state: string; to_programme_code: string; applied_at: string } | null;
  pendingSwap: { id: string; swap_ref: string; to_programme: string; to_level: number; prepared_at: string } | null;
  swaps: { id: string; swap_ref: string; status: string; kind: string; from_programme: string; from_level: number | null; to_programme: string; to_level: number; prepared_at: string; decided_at: string | null }[];
  signals: { matric_segment: string | null; programme_segment: string | null; registration: { dept: string; department: string | null; share: number } | null; admitted: { code: string | null; name: string | null } | null } | null;
  review: { status: ReviewStatus; note: string | null; reviewed_at: string; reviewed_office: string | null; reviewed_by: string | null } | null;
}

const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export function SwapStudent({ view, faculties, actingOffice, restoreInitially = false }: { view: StudentView; faculties: Faculty[]; actingOffice: string | null;
  restoreInitially?: boolean }) {
  const router = useRouter();
  const s = view.student;
  const prepares = ["academic", "ict", "registrar", "dregistrar", "super"].includes(actingOffice ?? "");
  const [target, setTarget] = useState<Target>({ faculty: "", dept: "", programme: "", level: s.current_level ? String(s.current_level) : "" });
  const [session, setSession] = useState(view.session ?? "");
  const [kind, setKind] = useState<SwapKind>(restoreInitially ? "APPROVED_TRANSFER_RESTORED"
    : view.signals?.admitted || s.entry_session ? "LEGACY_MIGRATION_CORRECTION" : "PROGRAMME_CORRECTION");
  // V669: the old portal's transfer, when it is restored
  const restoring = kind === "APPROVED_TRANSFER_RESTORED";
  const [prior, setPrior] = useState({ from: s.programme_code, session: "", semester: "", approvedOn: "", reference: "" });
  const [restored, setRestored] = useState<RestoreDone | null>(null);
  const programmes = faculties.flatMap((f) => f.departments.flatMap((d) => d.programmes.map((p) => ({ code: p.code, name: p.name, dept: d.name }))))
    .sort((a, b) => a.name.localeCompare(b.name));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<"check" | "confirm" | null>(null);
  const [check, setCheck] = useState<RestoreCheck | null>(null);
  const [done, setDone] = useState<{ id: string; swap_ref: string } | null>(null);
  const signals = view.signals ? signalWords({ matric_segment: view.signals.matric_segment, programme_segment: view.signals.programme_segment,
    registration_dept: view.signals.registration?.dept ?? null, registration_dept_name: view.signals.registration?.department ?? null,
    registration_share: view.signals.registration?.share ?? null, admitted_programme: view.signals.admitted?.code ?? null, admitted_programme_name: view.signals.admitted?.name ?? null,
    programme_code: s.programme_code, dept_code: s.dept_code }) : [];
  const chosen = target.programme && target.level;
  const sameAsNow = target.programme === s.programme_code && Number(target.level) === s.current_level;

  async function validate() {
    setBusy("check");
    setCheck(null);
    try {
      const r = restoring
        ? await swapPost<RestoreCheck>("/restore-transfer/check", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: session || null,
            fromProgramme: prior.from || null, transferSession: prior.session || null, approvedOn: prior.approvedOn || null }, "Approved transfer restoration checked")
        : await swapPost<CheckResult>("/check", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: session || null }, "Programme swap check");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setCheck(r.data);
    } finally { setBusy(null); }
  }
  async function confirm() {
    setBusy("confirm");
    try {
      if (restoring) {
        const r = await swapPost<RestoreDone>("/restore-transfer", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: session || null,
          fromProgramme: prior.from || null, transferSession: prior.session || null, transferSemester: prior.semester ? Number(prior.semester) : null,
          approvedOn: prior.approvedOn || null, reference: prior.reference.trim() || null, reason }, `Approved transfer restored for ${s.matric_no ?? s.id}: ${target.programme} at ${target.level}`);
        if (!r.ok) { notifyProblem(r.problem); return; }
        setRestored(r.data);
        notify(r.data.recordOnly ? "The transfer approved on the old portal is recorded; the student's placement stands" : `Approved transfer restored (${r.data.swapRef}): the student is on ${target.programme} at ${target.level} Level`);
        router.refresh();
        return;
      }
      const r = await swapPost<{ id: string; swap_ref: string }>("", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: session || null, kind, reason },
        `Programme swap made for ${s.matric_no ?? s.id}: ${target.programme} at ${target.level}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setDone(r.data);
      notify(`Programme swap ${r.data.swap_ref} completed: the student is on ${target.programme} at ${target.level} Level`);
      router.refresh();
    } finally { setBusy(null); }
  }

  return (
    <>
      <div className="card">
        <div className="card__body row" style={{ flexDirection: "row", gap: "var(--s-5)" }}>
          <Passport w={64} h={80} src={`/api/bff/api/v1/student/students/${s.id}/passport`} alt="" />
          <div className="grow" style={{ minWidth: 200 }}>
            <div className="t-lg b700">{s.surname}, {s.other_names}</div>
            <div className="sub2 tnum">{s.matric_no ?? s.admission_no ?? "No number yet"}{s.jamb_reg_no ? ` · JAMB ${s.jamb_reg_no}` : ""} · {s.programme ?? s.programme_code} · {s.current_level ?? "—"} Level</div>
          </div>
          <div className="row">
            <Pil kind={s.status === "ACTIVE" ? "ok" : "grey"}>{words(s.status)}</Pil>
            {view.review ? <Pil kind={view.review.status === "SWAPPED" ? "ok" : "info"}>{REVIEW_WORDS[view.review.status]}</Pil> : null}
            <LinkBtn kind="ghost" href={`/students/${s.id}`}>Full record</LinkBtn>
            <LinkBtn kind="ghost" href="/programme-swap">Back to the desk</LinkBtn>
          </div>
        </div>
      </div>

      {view.openTransfer ? <Note kind="bad" title="An inter-departmental transfer is under way"
        action={prepares && !restoring ? <Btn kind="secondary" size="sm" onClick={() => { setKind("APPROVED_TRANSFER_RESTORED"); setCheck(null); }}>Approved on the old portal? Restore it</Btn> : undefined}>
        To {view.openTransfer.to_programme_code}, {words(view.openTransfer.state)} since {day(view.openTransfer.applied_at)}. It is effected or withdrawn there before a swap.
        If the transfer was approved on the old portal already, restore it instead: the application is withdrawn and no new one is made.</Note> : null}
      {view.pendingSwap ? <Note kind="info" title={`Swap ${view.pendingSwap.swap_ref} awaits a decision`} action={<LinkBtn kind="primary" size="sm" href={`/programme-swap?tab=swaps&status=PENDING_APPROVAL&q=${encodeURIComponent(view.pendingSwap.swap_ref)}`}>Open it</LinkBtn>}>
        To {view.pendingSwap.to_programme} at {view.pendingSwap.to_level} Level, prepared {day(view.pendingSwap.prepared_at)}. It is decided on the Swaps tab.</Note> : null}
      {restored ? <Note kind="ok" title={restored.recordOnly ? "Approved transfer recorded" : `Approved transfer restored (${restored.swapRef})`}
        action={restored.swapRef ? <LinkBtn kind="primary" size="sm" href={`/programme-swap?tab=swaps&status=COMPLETED&q=${encodeURIComponent(restored.swapRef)}`}>See the swap</LinkBtn> : undefined}>
        {restored.recordOnly ? "The student's placement stands; the transfer approved on the old portal is in the programme history below." : "The placement has moved to the approved programme and level; the transfer approved on the old portal and the old placement are in the programme history below."}
        {restored.withdrawnApplication ? " The application left in the transfer queue is withdrawn." : ""} New transfer applications: {restored.transferApplicationsCreated}. Matriculation number unchanged{restored.matricNo ? ` (${restored.matricNo})` : ""}.</Note> : null}
      {done ? <Note kind="ok" title={`Programme swap ${done.swap_ref} completed`} action={<LinkBtn kind="primary" size="sm" href={`/programme-swap?tab=swaps&status=COMPLETED&q=${encodeURIComponent(done.swap_ref)}`}>See the swap</LinkBtn>}>
        The placement has moved: the record reads the new programme and level, the old placement stays in the programme history below, and the student is told.</Note> : null}

      <div className="grid grid--2">
        <Panel title="Current record" right="FROM">
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Faculty", s.faculty ?? s.faculty_code ?? "—"], ["Department", s.department ?? s.dept_code ?? "—"], ["Programme", `${s.programme ?? "—"} (${s.programme_code})`],
              ["Level", s.current_level ? `${s.current_level} Level` : "—"], ["Session", view.session], ["Programme type", s.programme_type ?? s.category ?? "—"],
              ["Admission route", words(s.entry_mode) || "—"], ["Study mode", words(s.study_mode) || "—"], ["Entry", `${s.entry_session ?? "—"} · ${s.entry_level ?? "—"} Level`]]} />
            {signals.length ? <Note kind="info" title="Why this record is flagged">{signals.map((w) => <div key={w}>{w}</div>)}</Note> : <div className="sub2 mt-2">The record&rsquo;s number, registration and admission agree with its programme.</div>}
            {view.review?.note ? <div className="sub2 mt-2">Review: {view.review.note} ({view.review.reviewed_by ?? view.review.reviewed_office}, {day(view.review.reviewed_at)})</div> : null}
          </PBody>
        </Panel>
        <Panel title="New record" right="TO">
          <PBody>
            {prepares && !view.pendingSwap && (!view.openTransfer || restoring) ? (
              <>
                <TargetPicker faculties={faculties} value={target} onChange={(t) => { setTarget(t); setCheck(null); }} />
                <div className="grid grid--2">
                  <Field id="sw-session" label="Effective session">
                    <select id="sw-session" className="ctl" value={session} onChange={(e) => { setSession(e.target.value); setCheck(null); }}>
                      {(view.sessions.includes(session) ? view.sessions : [session, ...view.sessions]).filter(Boolean).map((x) => <option key={x} value={x}>{x}</option>)}
                    </select>
                  </Field>
                  <Field id="sw-kind" label="Change type">
                    <select id="sw-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value as SwapKind)}>
                      {(Object.keys(KIND_WORDS) as SwapKind[]).map((k) => <option key={k} value={k}>{KIND_WORDS[k]}</option>)}
                    </select>
                  </Field>
                </div>
                {restoring ? (
                  <>
                    <Note kind="info" title="Restore a transfer approved on the old portal">The student is put on the approved programme and level directly, and the old
                      portal&rsquo;s transfer is recorded in the history. No transfer application, fee or approval is made, and the matriculation number stays as it is.</Note>
                    <div className="grid grid--2">
                      <Field id="sw-from" label="Transferred from (programme)">
                        <select id="sw-from" className="ctl" value={prior.from} onChange={(e) => { setPrior({ ...prior, from: e.target.value }); setCheck(null); }}>
                          {programmes.map((p) => <option key={p.code} value={p.code}>{p.name} · {p.dept} ({p.code})</option>)}
                        </select>
                      </Field>
                      <Field id="sw-tses" label="Transfer took effect in (session)">
                        <select id="sw-tses" className="ctl" value={prior.session} onChange={(e) => { setPrior({ ...prior, session: e.target.value }); setCheck(null); }}>
                          <option value="">The effective session above</option>
                          {view.sessions.map((x) => <option key={x} value={x}>{x}</option>)}
                        </select>
                      </Field>
                      <Field id="sw-tsem" label="Semester">
                        <select id="sw-tsem" className="ctl" value={prior.semester} onChange={(e) => setPrior({ ...prior, semester: e.target.value })}>
                          <option value="">Not recorded</option><option value="1">First</option><option value="2">Second</option>
                        </select>
                      </Field>
                      <Field id="sw-appr" label="Approved on">
                        <input id="sw-appr" className="ctl" type="date" value={prior.approvedOn} onChange={(e) => { setPrior({ ...prior, approvedOn: e.target.value }); setCheck(null); }} />
                      </Field>
                      <Field id="sw-tref" label="Old portal transfer reference" full>
                        <input id="sw-tref" className="ctl" value={prior.reference} maxLength={80} placeholder="e.g. TRF/2024/00125" onChange={(e) => setPrior({ ...prior, reference: e.target.value })} />
                      </Field>
                    </div>
                  </>
                ) : null}
                <Field id="sw-reason" label="Reason" hint="Required, ten characters at least; kept on the swap and the audit trail" full>
                  <textarea id="sw-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)}
                    placeholder={restoring ? "e.g. Transfer approved by Senate on the old portal; the migration put the student back in the department left"
                      : "e.g. Student changed to this programme before migration; the legacy record kept the old programme"} />
                </Field>
                <div className="row">
                  <Btn kind="secondary" busy={busy === "check"} busyLabel="Validating programme…" disabled={!chosen || !!busy || (sameAsNow && !restoring)} onClick={validate}
                    title={sameAsNow && !restoring ? "The student is on that programme at that level already" : undefined}>Validate</Btn>
                  {check ? <span className="sub2">Then confirm below.</span> : null}
                </div>
              </>
            ) : <div className="sub2">{!prepares ? "A swap is made by the Academic Office, the Registry or the Director of ICT." : "No swap can be made while a transfer or a swap is under way; a transfer approved on the old portal is restored (see above)."}</div>}
          </PBody>
        </Panel>
      </div>

      {check ? (
        <Panel title={restoring ? "Approved transfer restoration preview" : "Programme swap preview"} right={check.ok ? <Pil kind="ok">Ready</Pil> : <Pil kind="bad">Blocked</Pil>}>
          <PBody>
            {restoring && check.restore ? (
              <Note kind="info" title="This restores a previously approved transfer. It will NOT create a new transfer application.">
                {restoreWords(check).map((w) => <div key={w}>{w}</div>)}
                <div className="sub2 mt-1">Transferred from {check.restore.fromProgrammeName ?? check.restore.fromProgramme ?? "—"} · took effect {check.restore.transferSession}
                  {check.restore.approvedOn ? ` · approved ${day(check.restore.approvedOn)}` : ""}{prior.reference.trim() ? ` · ${prior.reference.trim()}` : ""}</div>
              </Note>
            ) : null}
            {check.refusals.length ? <Note kind="bad" title="The swap cannot be made">{check.refusals.map((r) => <div key={r}>{refusalWords(r)}</div>)}</Note> : null}
            {/* V669: what the restoration does is said above; the review points are the rest */}
            {check.warnings.filter((w) => !restoring || !["APPLICATION_WITHDRAWN", "RECORD_ONLY"].includes(w.code)).length ? (
              <Note kind="info" title="Requires review: look at these before confirming">
                {check.warnings.filter((w) => !restoring || !["APPLICATION_WITHDRAWN", "RECORD_ONLY"].includes(w.code)).map((w) => <div key={w.code}>{w.text}</div>)}</Note>
            ) : null}
            <div className="grid grid--2">
              <div><div className="eyebrow">Old</div><KvGrid cls="grid--2" pairs={[["Faculty", check.from.facultyName ?? "—"], ["Department", check.from.department ?? "—"], ["Programme", check.from.programmeName ?? check.from.programme], ["Level", `${check.from.level ?? "—"} Level`]]} /></div>
              <div><div className="eyebrow">New</div>{check.to ? <KvGrid cls="grid--2" pairs={[["Faculty", check.to.facultyName ?? "—"], ["Department", check.to.department ?? "—"], ["Programme", check.to.programmeName ?? check.to.programme], ["Level", `${check.to.level ?? "—"} Level`]]} /> : <div className="sub2">No programme chosen.</div>}</div>
            </div>
            <KvGrid cls="grid--3" pairs={[
              ["Course registration", check.registration && check.registration.registered > 0
                ? `${check.registration.registered} course${check.registration.registered === 1 ? "" : "s"} registered for ${check.session}: ${check.registration.applicable} applicable, ${check.registration.extra.length} not offered to the new programme, ${check.registration.missingCore.length} core not registered — kept as it is${check.registration.extra.length || check.registration.missingCore.length ? ", requires review" : ""}`
                : `None for ${check.session}`],
              ["Results", "Historical results preserved"],
              ["Finance", check.fees ? `No transaction changed · ${check.session} fee lines: ${naira(check.fees.current)} now, ${naira(check.fees.new)} under the new programme` : "No transaction changed"],
              ["Matriculation number", "No change"], ["Student ID and JAMB number", "No change"], ["Effective session", check.session],
            ]} />
            {check.registration && (check.registration.extra.length || check.registration.missingCore.length) ? (
              <div className="sub2 mt-2">
                {check.registration.extra.length ? <div>Not offered to the new programme: {check.registration.extra.map((c) => `${c.code} ${c.title}`).join("; ")}</div> : null}
                {check.registration.missingCore.length ? <div>Core courses of the new programme not registered: {check.registration.missingCore.map((c) => `${c.code} ${c.title}`).join("; ")}</div> : null}
              </div>
            ) : null}
            <div className="row mt-3">
              <Btn kind="ghost" disabled={!!busy} onClick={() => setCheck(null)}>Cancel</Btn>
              <Btn kind="primary" busy={busy === "confirm"} busyLabel={restoring ? "Restoring the approved transfer…" : "Processing programme swap…"}
                disabled={!check.ok || !!busy || reason.trim().length < 10 || !!done || !!restored} onClick={confirm}
                title={reason.trim().length < 10 ? "Give the reason first" : undefined}>{restoring ? (check.restore?.recordOnly ? "Record the approved transfer" : "Restore approved transfer") : "Confirm programme swap"}</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Programme history" right="Every placement the record has had">
        <ProgrammeHistory rows={view.history} />
      </Panel>
      {view.swaps.length ? (
        <Panel title="Swaps of this record">
          <PBody>
            {view.swaps.map((x) => <div key={x.id} className="row row--between"><span className="tnum">{x.swap_ref} · {KIND_WORDS[x.kind as SwapKind] ?? x.kind}</span><span className="sub2">{x.from_programme} {x.from_level ?? ""} → {x.to_programme} {x.to_level} · {words(x.status)} · {day(x.decided_at ?? x.prepared_at)}</span></div>)}
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
