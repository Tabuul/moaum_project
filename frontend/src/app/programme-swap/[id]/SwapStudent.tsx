"use client";

/**
 * One student's programme swap (V578): the record as it stands (FROM), the placement to move to (TO — faculty, department,
 * programme, level, cascading and searchable), the kind and the reason; VALIDATE asks the server what the swap would do and what
 * stands in its way; the preview shows it all — what changes, what stays, the fee lines under each programme, the registration
 * impact — and CONFIRM prepares the swap for another officer's decision. Nothing on the record changes here.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Passport, day } from "@/components/proto/blocks";
import { KIND_WORDS, REVIEW_WORDS, refusalWords, signalWords, type CheckResult, type Faculty, type ReviewStatus, type SwapKind } from "@/lib/programme-swap";
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
  signals: { matric_segment: string | null; programme_segment: string | null; registration: { dept: string; department: string | null; share: number } | null; admitted: { code: string; name: string | null } | null } | null;
  review: { status: ReviewStatus; note: string | null; reviewed_at: string; reviewed_office: string | null; reviewed_by: string | null } | null;
}

const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export function SwapStudent({ view, faculties, actingOffice }: { view: StudentView; faculties: Faculty[]; actingOffice: string | null }) {
  const router = useRouter();
  const s = view.student;
  const prepares = ["academic", "ict", "registrar", "dregistrar", "super"].includes(actingOffice ?? "");
  const [target, setTarget] = useState<Target>({ faculty: "", dept: "", programme: "", level: s.current_level ? String(s.current_level) : "" });
  const [session, setSession] = useState(view.session ?? "");
  const [kind, setKind] = useState<SwapKind>(view.signals?.admitted || s.entry_session ? "LEGACY_MIGRATION_CORRECTION" : "PROGRAMME_CORRECTION");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<"check" | "confirm" | null>(null);
  const [check, setCheck] = useState<CheckResult | null>(null);
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
      const r = await swapPost<CheckResult>("/check", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: session || null }, "Programme swap check");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setCheck(r.data);
    } finally { setBusy(null); }
  }
  async function confirm() {
    setBusy("confirm");
    try {
      const r = await swapPost<{ id: string; swap_ref: string }>("", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: session || null, kind, reason },
        `Programme swap prepared for ${s.matric_no ?? s.id}: ${target.programme} at ${target.level}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setDone(r.data);
      notify(`Programme swap ${r.data.swap_ref} prepared: another officer decides it`);
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

      {view.openTransfer ? <Note kind="bad" title="An inter-departmental transfer is under way">To {view.openTransfer.to_programme_code}, {words(view.openTransfer.state)} since {day(view.openTransfer.applied_at)}. It is effected or withdrawn there before a swap.</Note> : null}
      {view.pendingSwap ? <Note kind="info" title={`Swap ${view.pendingSwap.swap_ref} awaits a decision`} action={<LinkBtn kind="primary" size="sm" href={`/programme-swap?tab=swaps&status=PENDING_APPROVAL&q=${encodeURIComponent(view.pendingSwap.swap_ref)}`}>Open it</LinkBtn>}>
        To {view.pendingSwap.to_programme} at {view.pendingSwap.to_level} Level, prepared {day(view.pendingSwap.prepared_at)}. Another officer decides it on the Swaps tab.</Note> : null}
      {done ? <Note kind="ok" title={`Programme swap ${done.swap_ref} prepared`} action={<LinkBtn kind="primary" size="sm" href={`/programme-swap?tab=swaps&status=PENDING_APPROVAL&q=${encodeURIComponent(done.swap_ref)}`}>See the pending swaps</LinkBtn>}>
        Nothing on the record has changed yet: an officer of the Academic Office or the Registry other than you{kind === "LEGACY_MIGRATION_CORRECTION" ? ", or the Director of ICT," : ""} approves it, and the placement moves then.</Note> : null}

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
            {prepares && !view.pendingSwap && !view.openTransfer ? (
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
                <Field id="sw-reason" label="Reason" hint="Required, ten characters at least; kept on the swap and the audit trail" full>
                  <textarea id="sw-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)}
                    placeholder="e.g. Student changed to this programme before migration; the legacy record kept the old programme" />
                </Field>
                <div className="row">
                  <Btn kind="secondary" busy={busy === "check"} busyLabel="Validating programme…" disabled={!chosen || !!busy || sameAsNow} onClick={validate}
                    title={sameAsNow ? "The student is on that programme at that level already" : undefined}>Validate</Btn>
                  {check ? <span className="sub2">Then confirm below.</span> : null}
                </div>
              </>
            ) : <div className="sub2">{!prepares ? "A swap is prepared by the Academic Office, the Registry or the Director of ICT." : "No swap can be prepared while a transfer or a swap is under way."}</div>}
          </PBody>
        </Panel>
      </div>

      {check ? (
        <Panel title="Programme swap preview" right={check.ok ? <Pil kind="ok">Ready</Pil> : <Pil kind="bad">Blocked</Pil>}>
          <PBody>
            {check.refusals.length ? <Note kind="bad" title="The swap cannot be made">{check.refusals.map((r) => <div key={r}>{refusalWords(r)}</div>)}</Note> : null}
            {check.warnings.length ? <Note kind="info" title="Requires review: look at these before confirming">{check.warnings.map((w) => <div key={w.code}>{w.text}</div>)}</Note> : null}
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
              <Btn kind="primary" busy={busy === "confirm"} busyLabel="Processing programme swap…" disabled={!check.ok || !!busy || reason.trim().length < 10 || !!done} onClick={confirm}
                title={reason.trim().length < 10 ? "Give the reason first" : undefined}>Confirm programme swap</Btn>
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
