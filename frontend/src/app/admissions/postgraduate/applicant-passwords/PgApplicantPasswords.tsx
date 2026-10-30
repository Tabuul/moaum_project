"use client";
/** Postgraduate Applicant Passwords (V706): the Dean and the Secretary of the School of Postgraduate Studies, the Director of ICT and ICT
 *  Support — V710: and the Academic Office and the Database Operators — find a postgraduate applicant and reset the password, saying why:
 *  back to the application number (the applicant chooses their own at the sign-in), or (V710) the applicant's own link to the email and
 *  phone they applied with; or many at once from a list. Never a password the officer chooses; every reset written down, the applicant told. */
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, RoleLine } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PG_RESET_METHOD, pgAccountState, reasonProblem } from "@/lib/applicant-password";
import { BulkPasswordReset } from "@/components/applicant/BulkPasswordReset";

/* V710: and the Academic Office and the Database Operators (over the whole University; the server holds the scope) */
export const PG_PASSWORD_DESK = ["pgschool", "pgsecretary", "ict", "ictagent", "helpdeskhead", "academic", "dbops", "super"];

interface Found {
  applicant_id: string; session: string; application_no: string | null; legacy_application_no: string | null; surname: string; other_names: string;
  email: string; phone: string | null; programme: string | null; state: string | null; failed_attempts: number; locked: boolean; must_change: boolean;
  last_signed_in_at: string | null; last_reset_at: string | null; resets: number;
}
export interface PgResetRow {
  id: string; applicant_id: string; method: string; application_no: string; reason: string; was_locked: boolean; sessions_ended: number;
  reset_at: string; reset_office: string; reset_by_name: string; applicant: string; email: string; session: string;
  sent_to?: string | null; bulk_ref?: string | null;
}
interface Account {
  applicantId: string; name: string; applicationNo: string | null; legacyApplicationNo: string | null; session: string; email: string; phone: string | null;
  programme: string | null; state: string | null; failedAttempts: number; locked: boolean; mustChange: boolean; lastSignedIn: string | null; resets: PgResetRow[];
}
interface Done { method: string; applicationNo: string; note: string; wasLocked?: boolean; sentTo?: string; expiresAt?: string }

const when = (v: string | null | undefined) => (v ? new Date(v).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function PgApplicantPasswords({ office, history, problem: loadProblem, initialQuery = "" }: {
  office: string | null; history: PgResetRow[]; problem: Problem | null; initialQuery?: string;
}) {
  const router = useRouter();
  const may = PG_PASSWORD_DESK.includes(office ?? "");
  const [q, setQ] = useState(initialQuery);
  const [found, setFound] = useState<Found[] | null>(null);
  const [acct, setAcct] = useState<Account | null>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(loadProblem);
  const [reason, setReason] = useState("");
  const [method, setMethod] = useState<"DEFAULT" | "LINK">("DEFAULT");
  const [done, setDone] = useState<Done | null>(null);

  async function call<T>(path: string, init?: RequestInit): Promise<T | null> {
    const r = await fetch(`/api/bff/api/v1/pg/applicant-passwords${path}`, { cache: "no-store", ...init });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    setProblem(null);
    return j as T;
  }
  async function search(text = q) {
    if (text.trim().length < 3) { setProblem({ status: 400, title: "Type three characters or more: an application number, an email, a phone or a name." }); return; }
    setBusy(true);
    try { setFound(await call<Found[]>(`/search?q=${encodeURIComponent(text.trim())}`) ?? []); } finally { setBusy(false); }
  }
  /* the School's dashboard opens the desk with ?q=: the search runs once, on opening */
  const searched = useRef(false);
  useEffect(() => {
    if (searched.current || !may || initialQuery.trim().length < 3) return;
    searched.current = true;
    void search(initialQuery);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [may, initialQuery]);
  async function open(id: string) {
    setBusy(true); setDone(null); setReason(""); setMethod("DEFAULT");
    try { setAcct(await call<Account>(`/${id}`)); } finally { setBusy(false); }
  }
  async function reset() {
    if (!acct) return;
    const why = reasonProblem(reason);
    if (why) { setProblem({ status: 400, title: why }); return; }
    setBusy(true);
    try {
      const r = await call<Done>(`/${acct.applicantId}/reset`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ method, reason: reason.trim() }) });
      if (!r) return;
      setDone(r);
      notify(r.method === "RESET_LINK" ? "Reset link sent." : "Password reset to the application number.");
      setAcct(await call<Account>(`/${acct.applicantId}`));
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <>
      <RoleLine allowed={PG_PASSWORD_DESK.filter((o) => o !== "super")} actingOffice={office} action="Resetting postgraduate applicants' passwords" />
      {problem && !acct ? <ProblemNotice problem={problem} /> : null}
      {may ? (
        <Panel title="Find a postgraduate applicant">
          <PBody>
            <div className="row row--inline" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
              <input className="ctl" style={{ minWidth: 320 }} value={q} placeholder="Application number, email, phone or name" aria-label="Find a postgraduate applicant"
                onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void search(); }} />
              <Btn kind="primary" disabled={busy} onClick={() => void search()}>{busy ? "Searching…" : "Search"}</Btn>
            </div>
            <div className="sub2 mt-2">The password becomes the applicant&rsquo;s application number; they sign in with it and choose their own at once.</div>
          </PBody>
          {found ? (found.length ? (
            <DTable pageSize={25} cols={["S/N|num", "Applicant", "Application", "Programme", "Session", "Account|mid", "Last reset", ""]}
              texts={found.map((f) => `${f.surname} ${f.other_names} ${f.application_no ?? ""} ${f.legacy_application_no ?? ""} ${f.email}`)}
              rows={found.map((f, i) => {
                const [word, kind] = pgAccountState(f);
                return [
                  <span key="n" className="tnum sub2">{i + 1}</span>,
                  <span key="a"><b>{f.surname}</b>, {f.other_names}<div className="sub2">{f.email}{f.phone ? ` · ${f.phone}` : ""}</div></span>,
                  <span key="p" className="tnum">{f.application_no ?? "—"}{f.legacy_application_no ? <div className="sub2">old portal {f.legacy_application_no}</div> : null}</span>,
                  <span key="g" className="sub2">{f.programme ?? "—"}</span>, <span key="s">{f.session}</span>,
                  <Pil key="t" kind={kind}>{word}</Pil>,
                  <span key="r" className="sub2">{f.last_reset_at ? when(f.last_reset_at) : "—"}</span>,
                  <Btn key="o" kind="secondary" size="sm" disabled={!f.application_no} onClick={() => void open(f.applicant_id)}>Reset password</Btn>,
                ];
              })} />
          ) : <PBody><div className="sub2">No postgraduate applicant matches. Try the application number, the old portal&rsquo;s number or the email they applied with.</div></PBody>) : null}
        </Panel>
      ) : <Note kind="info" title="The School of Postgraduate Studies, the Director of ICT, ICT Support, the Academic Office and the Database Operators reset postgraduate applicants' passwords">Act in one of those offices to reset one.</Note>}
      {may ? <BulkPasswordReset endpoint="/api/v1/pg/applicant-passwords" postgraduate onDone={() => router.refresh()} /> : null}

      <Panel title="Resets made" right={<span className="sub2">{history.length} most recent</span>}>
        {history.length ? (
          <DTable pageSize={25} cols={["S/N|num", "When", "Applicant", "Method", "Reason", "By"]}
            texts={history.map((h) => `${h.applicant} ${h.application_no} ${h.email} ${h.reason} ${h.reset_by_name}`)}
            rows={history.map((h, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>, <span key="w" className="sub2 tnum">{when(h.reset_at)}</span>,
              <span key="a">{h.applicant}<div className="sub2 tnum">{h.application_no}</div></span>,
              <span key="m">{PG_RESET_METHOD[h.method] ?? h.method}{h.sent_to ? <div className="sub2">to {h.sent_to}</div> : null}{h.bulk_ref ? <div className="sub2 tnum">{h.bulk_ref}</div> : null}</span>,
              <span key="r" className="sub2">{h.reason}</span>, <span key="b" className="sub2">{h.reset_by_name} · {h.reset_office}</span>,
            ])} />
        ) : <PBody><div className="sub2">No postgraduate applicant&rsquo;s password has been reset yet.</div></PBody>}
      </Panel>

      {acct ? (
        <Modal title={`Reset password · ${acct.name}`} sub={`${acct.applicationNo ?? ""} · ${acct.session}`} onClose={() => { setAcct(null); setDone(null); }}
          foot={done ? <Btn kind="primary" onClick={() => { setAcct(null); setDone(null); }}>Done</Btn>
            : <><Btn kind="ghost" onClick={() => setAcct(null)}>Back</Btn><Btn kind="primary" disabled={busy || !!reasonProblem(reason) || !acct.applicationNo} onClick={() => void reset()}>{busy ? "Resetting…" : method === "LINK" ? "Send the reset link" : "Reset to the application number"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {done ? (
            done.method === "RESET_LINK" ? <Note kind="ok" title="Reset link sent">{`Sent to ${done.sentTo ?? "the applicant"}. ${done.note}`}</Note> : (
            <Note kind="ok" title="Password reset to the application number">
              <div className="mt-1">The password is now the applicant&rsquo;s application number: <b className="tnum">{done.applicationNo}</b></div>
              <div className="sub2 mt-2">{done.note}{done.wasLocked ? " The account was locked; it is unlocked." : ""} The applicant was told by email and SMS.</div>
            </Note>)
          ) : (
            <>
              <KvGrid pairs={[["Email", acct.email], ["Phone", acct.phone ?? "—"], ["Application", acct.applicationNo ?? "—"],
                ["Old portal number", acct.legacyApplicationNo ?? "—"], ["Programme", acct.programme ?? "—"], ["Account", pgAccountState(acct)[0]],
                ["Failed sign-ins", String(acct.failedAttempts)], ["Last signed in", when(acct.lastSignedIn)]]} />
              <div className="eyebrow mt-3">How</div>
              <label className="row row--inline row--tight mt-1"><input type="radio" name="pgpw-m" checked={method === "DEFAULT"} onChange={() => setMethod("DEFAULT")} />
                <span><b>Back to the application number</b>{acct.applicationNo ? <> (<span className="tnum">{acct.applicationNo}</span>)</> : null} — the applicant signs in with their email or application number and that password, then chooses their own before anything else. Their open sessions end and a locked account is unlocked.</span></label>
              <label className="row row--inline row--tight mt-1"><input type="radio" name="pgpw-m" checked={method === "LINK"} onChange={() => setMethod("LINK")} />
                <span><b>Reset link</b> — to the email and phone they applied with; they choose a new password within the hour.</span></label>
              <Field id="pgpw-reason" label="Reason" required hint="Ten characters or more, e.g. “Applicant forgot password; identity checked by phone”">
                <textarea id="pgpw-reason" className="ctl" rows={2} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} />
              </Field>
              {acct.resets.length ? (
                <details className="mt-2"><summary className="sub2">Earlier resets ({acct.resets.length})</summary>
                  <DTable noPrint pageSize={0} cols={["When", "Reason", "By"]} rows={acct.resets.map((h) => [
                    <span key="w" className="sub2 tnum">{when(h.reset_at)}</span>, <span key="r" className="sub2">{h.reason}</span>,
                    <span key="b" className="sub2">{h.reset_by_name}</span>])} />
                </details>
              ) : null}
            </>
          )}
        </Modal>
      ) : null}
    </>
  );
}
