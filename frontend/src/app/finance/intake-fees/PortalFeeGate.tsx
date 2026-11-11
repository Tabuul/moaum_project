"use client";

/**
 * V724 — the student portal's fee gate, on the Bursar's Fee Setup desk: the one-row switch that holds a fresh UTME or
 * Direct Entry admit (ADMITTED, no matriculation number) out of the student portal until the session's school fees are
 * stated and paid — the first semester's, as the University chose on 11 November 2026, or the session's in full — from
 * which entry session on; the named students the Bursary lets through for a stated time; every change with a reason.
 * ON from deployment. The switch is the Bursar's, the Director of ICT's or an administrator's; an exception is the
 * Bursary's; the API refuses anyone else. Read on every request by the API, never cached here: the panel only reads
 * GET /finance/portal-gate and sends PUT / POST / DELETE to it. The pattern is biodata compliance's GateAdmin (V434).
 * Every change of the gate and every exception is made for a reason of at least five characters, at most 400 (the API's).
 */
import { useEffect, useState } from "react";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ProblemNotice } from "@/components/ProblemNotice";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { EXCEPTION_BASES, EXCEPTION_MAX_DAYS, GATE_EXCEPTORS, GATE_READERS, GATE_SETTERS, basisWord, clearsOnWord, type PortalGate, type PortalGateException } from "@/lib/intake-fees";

const B = "/api/bff/api/v1/finance/portal-gate";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const dayOnly = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
/** V724: a reason the record can be read by later — at least five characters; at most the API's 400 (@Size) */
const REASON_MIN = 5;
const REASON_MAX = 400;
const reasoned = (s: string) => s.trim().length >= REASON_MIN;

async function send(path: string, method: string, body: unknown, why: string): Promise<unknown | null> {
  const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j ?? {};
}

/** a date some days after another, both as YYYY-MM-DD */
function plusDays(day: string, n: number): string {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function PortalFeeGatePanel({ actingOffice, sessions = [] }: { actingOffice: string | null; sessions?: string[] }) {
  const office = actingOffice ?? "";
  const mayRead = GATE_READERS.includes(office);
  const canSet = GATE_SETTERS.includes(office);
  const canExcept = GATE_EXCEPTORS.includes(office);
  const [gate, setGate] = useState<PortalGate | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  // the switch as it is being changed, applied in one PUT with its reason
  const [ask, setAsk] = useState<"on" | "off" | null>(null);
  const [fromSession, setFromSession] = useState("");
  const [clearsOn, setClearsOn] = useState<"FIRST_SEMESTER" | "PAID_IN_FULL">("FIRST_SEMESTER");
  const [reason, setReason] = useState("");
  // the exception being granted, and the one being revoked
  const today = new Date().toISOString().slice(0, 10);
  const [form, setForm] = useState({ admissionNo: "", basis: "INSTALMENT_POLICY", reason: "", until: plusDays(today, 30) });
  const [revoking, setRevoking] = useState<PortalGateException | null>(null);
  const [why, setWhy] = useState("");

  // the gate as the API holds it, read after the page and again after each act (never cached: the API reads it on every request)
  const [reload, setReload] = useState(0);
  useEffect(() => {
    if (!mayRead) return;
    let alive = true;
    fetch(B, { cache: "no-store" }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      const g = j as PortalGate;
      setGate(g);
      setFromSession(g.fromSession);
      setClearsOn(g.clearsOn);
      setProblem(null);
    }).catch(() => {
      if (alive) setProblem({ status: 0, title: "The portal gate could not be read", remedy: { message: "Check the connection and reload.", office: "Directorate of ICT" } });
    });
    return () => { alive = false; };
  }, [mayRead, reload]);
  const load = () => setReload((n) => n + 1);

  if (!mayRead) return null;

  async function put(body: { enabled?: boolean; fromSession?: string; clearsOn?: string }, said: string) {
    setBusy("gate");
    try {
      const done = await send(B, "PUT", { ...body, reason: reason.trim() }, said);
      if (!done) return;
      notify(said);
      setAsk(null);
      setReason("");
      load();
    } finally {
      setBusy(null);
    }
  }

  async function grant() {
    setBusy("grant");
    try {
      const expires = new Date(`${form.until}T23:59:00`);
      const done = await send(`${B}/exceptions`, "POST",
        { admissionNo: form.admissionNo.trim(), basis: form.basis, reason: form.reason.trim(), expiresAt: expires.toISOString() },
        `Student portal fee gate exception for ${form.admissionNo.trim()}`);
      if (!done) return;
      notify(`Exception granted to ${form.admissionNo.trim()} until ${dayOnly(expires.toISOString())}`);
      setForm({ ...form, admissionNo: "", reason: "" });
      load();
    } finally {
      setBusy(null);
    }
  }

  async function revoke() {
    if (!revoking) return;
    setBusy("revoke");
    try {
      const done = await send(`${B}/exceptions/${revoking.id}?reason=${encodeURIComponent(why.trim())}`, "DELETE", undefined,
        `Student portal fee gate exception revoked for ${revoking.admissionNo ?? revoking.name}`);
      if (!done) return;
      notify(`Exception revoked for ${revoking.name}`);
      setRevoking(null);
      setWhy("");
      load();
    } finally {
      setBusy(null);
    }
  }

  const g = gate;
  const sessionChoices = [...new Set([...(g?.sessions ?? []), ...sessions, ...(g ? [g.fromSession] : [])])].filter(Boolean).sort().reverse();
  const ruleChanged = !!g && (fromSession !== g.fromSession || clearsOn !== g.clearsOn);
  const hasReason = reasoned(reason);
  const maxUntil = plusDays(today, EXCEPTION_MAX_DAYS - 1);
  const rows = g?.exceptions ?? [];

  return (
    <Panel title="Student portal fee gate" right={g ? <Pil kind={g.enabled ? "ok" : "grey"}>{g.enabled ? "ON" : "OFF"}</Pil> : <span className="sub2">Reading…</span>}>
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
      {g ? (
        <>
          <PBody>
            <div className="row row--top" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
              <div className="grow" style={{ minWidth: 240 }}>
                <div className="b600">Status: {g.enabled ? "ON" : "OFF"}</div>
                <div className="sub2 mt-1" style={{ lineHeight: 1.55 }}>
                  {g.enabled
                    ? <>A fresh UTME or Direct Entry admit of <b>{g.fromSession}</b> or later (admitted, not yet matriculated) stays on the applicant dashboard until the session&rsquo;s school fees are stated by the Bursary and paid — <b>{clearsOnWord(g.clearsOn).toLowerCase()}</b> — and the payment is verified. Being admitted, paying the acceptance fee, or holding an admission number does not open the student portal.</>
                    : <>Every fresh admit on the register may sign in to the student portal whether or not their school fees are paid. Turn the gate on to hold them on the applicant dashboard until the fees are stated and paid.</>}
                </div>
                {g.changedAt ? <div className="sub2 mt-1">Last changed {when(g.changedAt)}{g.changedOffice ? ` (${g.changedOffice})` : ""}{g.reason ? ` — ${g.reason}` : ""}</div> : null}
              </div>
              {canSet ? (
                <div className="row row--tight">
                  {g.enabled ? <Btn kind="urgent" disabled={busy !== null} onClick={() => setAsk("off")}>Turn off</Btn> : <Btn kind="primary" disabled={busy !== null} onClick={() => setAsk("on")}>Turn on</Btn>}
                </div>
              ) : null}
            </div>
            <div className="row row--end mt-3" style={{ borderTop: "1px solid var(--line-2)", paddingTop: 10, flexWrap: "wrap", gap: "var(--s-3)" }}>
              <Field id="pfg-from" label="Applies from entry session" hint="Freshers admitted into this session or a later one">
                <select id="pfg-from" className="ctl" value={fromSession} disabled={!canSet || busy !== null} onChange={(e) => setFromSession(e.target.value)}>
                  {sessionChoices.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
              </Field>
              <Field id="pfg-clears" label="The portal opens when" hint="The Bursar may ask for the session in full">
                <div className="row row--tight" role="radiogroup" aria-labelledby="pfg-clears" style={{ flexWrap: "wrap", gap: 12, minHeight: 34 }}>
                  <label className="row row--tight" style={{ gap: 6 }}><input type="radio" name="pfg-clears" value="FIRST_SEMESTER" checked={clearsOn === "FIRST_SEMESTER"} disabled={!canSet || busy !== null} onChange={() => setClearsOn("FIRST_SEMESTER")} />First semester paid</label>
                  <label className="row row--tight" style={{ gap: 6 }}><input type="radio" name="pfg-clears" value="PAID_IN_FULL" checked={clearsOn === "PAID_IN_FULL"} disabled={!canSet || busy !== null} onChange={() => setClearsOn("PAID_IN_FULL")} />Session paid in full</label>
                </div>
              </Field>
              {canSet ? (
                <>
                  <Field id="pfg-reason" label="Reason" hint={`Recorded with the change · at least ${REASON_MIN} characters`}><input id="pfg-reason" className="ctl" value={reason} maxLength={REASON_MAX} disabled={busy !== null} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Bursar's instruction of 11 November 2026" /></Field>
                  <Btn kind="secondary" disabled={!ruleChanged || !hasReason || busy !== null} busy={busy === "gate" && ask === null} onClick={() => void put({ fromSession, clearsOn }, `Student portal fee gate: from ${fromSession}, opens when ${clearsOnWord(clearsOn).toLowerCase()}`)}>Save the rule</Btn>
                </>
              ) : null}
            </div>
          </PBody>
          {canExcept ? (
            <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
              <div className="b600">Let a student through</div>
              <div className="sub2 mb-2">A named fresh admit opens the student portal while the gate would hold them — on an approved instalment arrangement, a waiver or the Bursary&rsquo;s decision — until a date, at most {EXCEPTION_MAX_DAYS} days away; one at a time. Revoked or ended, the gate applies again.</div>
              <div className="grid grid--4">
                <Field id="pfx-no" label="Admission number"><input id="pfx-no" className="ctl tnum" value={form.admissionNo} maxLength={40} onChange={(e) => setForm({ ...form, admissionNo: e.target.value })} /></Field>
                <Field id="pfx-basis" label="Basis">
                  <select id="pfx-basis" className="ctl" value={form.basis} onChange={(e) => setForm({ ...form, basis: e.target.value })}>
                    {EXCEPTION_BASES.map(([code, label]) => <option key={code} value={code}>{label}</option>)}
                  </select>
                </Field>
                <Field id="pfx-until" label="Until"><input id="pfx-until" type="date" className="ctl tnum" value={form.until} min={today} max={maxUntil} onChange={(e) => setForm({ ...form, until: e.target.value })} /></Field>
                <Field id="pfx-reason" label="Reason" hint={`At least ${REASON_MIN} characters`}><input id="pfx-reason" className="ctl" value={form.reason} maxLength={REASON_MAX} onChange={(e) => setForm({ ...form, reason: e.target.value })} placeholder="Why this student opens the portal now" /></Field>
              </div>
              <div className="row mt-1"><Btn kind="primary" disabled={busy !== null || !form.admissionNo.trim() || !reasoned(form.reason) || !form.until} busy={busy === "grant"} busyLabel="Granting…" onClick={() => void grant()}>Grant the exception</Btn></div>
            </PBody>
          ) : null}
          {rows.length ? (
            <DTable cols={["Student", "Basis", "Reason", "From", "Until", "Granted by", "|num"]} rows={rows.map((e) => [
              <span key="s"><b>{e.name}</b><div className="sub2 tnum">{e.matricNo ?? e.admissionNo ?? ""}</div></span>,
              <span key="b">{basisWord(e.basis)}</span>,
              <span key="r" className="sub2">{e.reason}</span>,
              <span key="f" className="sub2 tnum">{dayOnly(e.startsAt)}</span>,
              <span key="u" className="sub2 tnum">{dayOnly(e.expiresAt)}</span>,
              <span key="g" className="sub2">{e.grantedOffice} · {dayOnly(e.grantedAt)}</span>,
              canExcept ? <Btn key="x" kind="ghost" size="sm" disabled={busy !== null} onClick={() => setRevoking(e)}>Revoke</Btn> : <span key="x" />,
            ])} texts={rows.map((e) => `${e.name} ${e.admissionNo ?? ""} ${e.matricNo ?? ""} ${e.reason}`)} />
          ) : <PBody><div className="sub2">No exception stands.</div></PBody>}
          <PBody><div className="sub2">Matriculation, the register and the admission number are untouched by the gate: it only reads them. A student the gate holds signs in on the JAMB or admission number and lands on the applicant dashboard, where the school fees are paid through the payment gateway once stated.</div></PBody>
        </>
      ) : !problem ? <PBody><div className="sub2">Reading the gate…</div></PBody> : null}
      {ask === "on" ? (
        <Modal title="Turn the student portal fee gate on?" onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" disabled={busy !== null || !hasReason} busy={busy === "gate"} busyLabel="Turning on…" onClick={() => void put({ enabled: true, fromSession, clearsOn }, "Student portal fee gate turned ON")}>Turn on</Btn></>}>
          <p style={{ marginTop: 0 }}>Fresh UTME and Direct Entry admits of {fromSession} or later will be held on the applicant dashboard until their school fees are stated and paid ({clearsOnWord(clearsOn).toLowerCase()}) and the payment is verified.</p>
          <Note kind="info" title="State the fees first">A programme whose freshers have no fee line in force reads &ldquo;school fees not yet available&rdquo; on the applicant dashboard; the School fees readiness monitor lists them.</Note>
          <Field id="pfg-reason-on" label="Reason" hint={`At least ${REASON_MIN} characters`}><input id="pfg-reason-on" className="ctl" value={reason} maxLength={REASON_MAX} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Bursar's instruction" /></Field>
        </Modal>
      ) : null}
      {ask === "off" ? (
        <Modal title="Turn the student portal fee gate off?" onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy !== null || !hasReason} busy={busy === "gate"} busyLabel="Turning off…" onClick={() => void put({ enabled: false }, "Student portal fee gate turned OFF")}>Turn off</Btn></>}>
          <p style={{ marginTop: 0 }}>Every fresh admit on the register will be able to sign in to the student portal whether or not their school fees are paid.</p>
          <Field id="pfg-reason-off" label="Reason" hint={`At least ${REASON_MIN} characters`}><input id="pfg-reason-off" className="ctl" value={reason} maxLength={REASON_MAX} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {revoking ? (
        <Modal title={`Revoke ${revoking.name}'s exception?`} onClose={() => setRevoking(null)}
          foot={<><Btn kind="ghost" onClick={() => setRevoking(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy !== null} busy={busy === "revoke"} busyLabel="Revoking…" onClick={() => void revoke()}>Revoke</Btn></>}>
          <p style={{ marginTop: 0 }}>The gate applies to the student again at once while their school fees are unpaid.</p>
          <Field id="pfx-why" label="Reason (optional)"><input id="pfx-why" className="ctl" value={why} maxLength={REASON_MAX} onChange={(e) => setWhy(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
