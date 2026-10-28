"use client";
/** Applicant Passwords (V687): the Director of ICT, the Academic Office and ICT Support find a Post-UTME applicant and reset the password,
 *  saying why — a temporary password shown here once (the applicant chooses their own at the sign-in), or the applicant's own link sent to
 *  the email and phone they registered. Never a password the officer chooses; every reset written down and the applicant told. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, RoleLine } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RESET_METHOD, accountState, reasonProblem } from "@/lib/applicant-password";

/* V688: and the Database Operators (over the whole University; the server holds the scope) */
const DESK = ["ict", "academic", "ictagent", "helpdeskhead", "dbops", "super"];

interface Found {
  account_id: string; session: string; jamb_key: string | null; application_no: string | null; surname: string; other_names: string; email: string; phone: string;
  failed_attempts: number; locked: boolean; must_change: boolean; temp_expires_at: string | null; last_signed_in_at: string | null; last_reset_at: string | null;
  last_reset_method: string | null; resets: number;
}
export interface ResetRow {
  id: string; account_id: string; method: string; reason: string; sent_to: string | null; expires_at: string; was_locked: boolean; sessions_ended: number;
  reset_at: string; reset_office: string; reset_by_name: string; applicant: string; jamb_key: string | null; application_no: string | null; session: string;
}
interface Account {
  accountId: string; name: string; jambKey: string | null; applicationNo: string | null; session: string; email: string; phone: string; failedAttempts: number;
  locked: boolean; mustChange: boolean; temporaryUntil: string | null; firstSignIn: boolean; lastSignedIn: string | null; resets: ResetRow[];
}
interface Done { method: string; temporaryPassword?: string; expiresAt?: string; sentTo?: string; signInWith?: string; note: string; wasLocked?: boolean }

const when = (v: string | null | undefined) => (v ? new Date(v).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function ApplicantPasswords({ office, history, problem: loadProblem }: { office: string | null; history: ResetRow[]; problem: Problem | null }) {
  const router = useRouter();
  const may = DESK.includes(office ?? "");
  const [q, setQ] = useState("");
  const [found, setFound] = useState<Found[] | null>(null);
  const [acct, setAcct] = useState<Account | null>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(loadProblem);
  const [method, setMethod] = useState<"TEMPORARY" | "LINK">("TEMPORARY");
  const [reason, setReason] = useState("");
  const [done, setDone] = useState<Done | null>(null);

  async function call<T>(path: string, init?: RequestInit): Promise<T | null> {
    const r = await fetch(`/api/bff/api/v1/applicant-passwords${path}`, { cache: "no-store", ...init });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    setProblem(null);
    return j as T;
  }
  async function search() {
    if (q.trim().length < 3) { setProblem({ status: 400, title: "Type three characters or more: a JAMB or application number, an email, a phone or a name." }); return; }
    setBusy(true);
    try { setFound(await call<Found[]>(`/search?q=${encodeURIComponent(q.trim())}`) ?? []); } finally { setBusy(false); }
  }
  async function open(id: string) {
    setBusy(true); setDone(null); setReason("");
    try { setAcct(await call<Account>(`/${id}`)); } finally { setBusy(false); }
  }
  async function reset() {
    if (!acct) return;
    const why = reasonProblem(reason);
    if (why) { setProblem({ status: 400, title: why }); return; }
    setBusy(true);
    try {
      const r = await call<Done>(`/${acct.accountId}/reset`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ method, reason: reason.trim() }) });
      if (!r) return;
      setDone(r);
      notify(r.method === "TEMPORARY_PASSWORD" ? "Temporary password issued." : "Reset link sent.");
      setAcct(await call<Account>(`/${acct.accountId}`));
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <>
      <RoleLine allowed={DESK.filter((o) => o !== "super")} actingOffice={office} action="Resetting Post-UTME applicants' passwords" />
      {problem && !acct ? <ProblemNotice problem={problem} /> : null}
      {may ? (
        <Panel title="Find an applicant">
          <PBody>
            <div className="row row--inline" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
              <input className="ctl" style={{ minWidth: 320 }} value={q} placeholder="JAMB or application number, email, phone or name" aria-label="Find an applicant"
                onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void search(); }} />
              <Btn kind="primary" disabled={busy} onClick={() => void search()}>{busy ? "Searching…" : "Search"}</Btn>
            </div>
          </PBody>
          {found ? (found.length ? (
            <DTable pageSize={25} cols={["S/N|num", "Applicant", "JAMB number", "Application", "Session", "Account|mid", "Last reset", ""]}
              texts={found.map((f) => `${f.surname} ${f.other_names} ${f.jamb_key ?? ""} ${f.application_no ?? ""} ${f.email}`)}
              rows={found.map((f, i) => {
                const [word, kind] = accountState(f);
                return [
                  <span key="n" className="tnum sub2">{i + 1}</span>,
                  <span key="a"><b>{f.surname}</b>, {f.other_names}<div className="sub2">{f.email} · {f.phone}</div></span>,
                  <span key="j" className="tnum">{f.jamb_key ?? "—"}</span>, <span key="p" className="tnum">{f.application_no ?? "—"}</span>, <span key="s">{f.session}</span>,
                  <Pil key="t" kind={kind}>{word}</Pil>,
                  <span key="r" className="sub2">{f.last_reset_at ? `${RESET_METHOD[f.last_reset_method ?? ""] ?? f.last_reset_method} · ${when(f.last_reset_at)}` : "—"}</span>,
                  <Btn key="o" kind="secondary" size="sm" onClick={() => void open(f.account_id)}>Reset password</Btn>,
                ];
              })} />
          ) : <PBody><div className="sub2">No applicant matches. Try the JAMB number, the application number or the email they registered with.</div></PBody>) : null}
        </Panel>
      ) : <Note kind="info" title="The Director of ICT, the Academic Office and ICT Support reset applicants' passwords">Act in one of those offices to reset one.</Note>}

      <Panel title="Resets made" right={<span className="sub2">{history.length} most recent</span>}>
        {history.length ? (
          <DTable pageSize={25} cols={["S/N|num", "When", "Applicant", "Method", "Reason", "By"]}
            texts={history.map((h) => `${h.applicant} ${h.jamb_key ?? ""} ${h.application_no ?? ""} ${h.reason} ${h.reset_by_name}`)}
            rows={history.map((h, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>, <span key="w" className="sub2 tnum">{when(h.reset_at)}</span>,
              <span key="a">{h.applicant}<div className="sub2 tnum">{h.jamb_key ?? h.application_no ?? ""}</div></span>,
              <span key="m">{RESET_METHOD[h.method] ?? h.method}{h.sent_to ? <div className="sub2">to {h.sent_to}</div> : null}</span>,
              <span key="r" className="sub2">{h.reason}</span>, <span key="b" className="sub2">{h.reset_by_name} · {h.reset_office}</span>,
            ])} />
        ) : <PBody><div className="sub2">No applicant&rsquo;s password has been reset yet.</div></PBody>}
      </Panel>

      {acct ? (
        <Modal title={`Reset password · ${acct.name}`} sub={`${acct.jambKey ?? acct.applicationNo ?? ""} · ${acct.session}`} onClose={() => { setAcct(null); setDone(null); }}
          foot={done ? <Btn kind="primary" onClick={() => { setAcct(null); setDone(null); }}>Done</Btn>
            : <><Btn kind="ghost" onClick={() => setAcct(null)}>Back</Btn><Btn kind="primary" disabled={busy || !!reasonProblem(reason)} onClick={() => void reset()}>{busy ? "Resetting…" : method === "TEMPORARY" ? "Issue a temporary password" : "Send the reset link"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {done ? (
            done.method === "TEMPORARY_PASSWORD" ? (
              <Note kind="ok" title="Temporary password issued">
                <div className="mt-1">Sign in with <b className="tnum">{done.signInWith}</b> and the temporary password:</div>
                <div className="mt-2" style={{ fontSize: 22, fontWeight: 700, letterSpacing: 1 }}><span className="tnum">{done.temporaryPassword}</span>
                  {" "}<Btn kind="ghost" size="sm" onClick={() => { void navigator.clipboard?.writeText(done.temporaryPassword ?? ""); notify("Copied."); }}>Copy</Btn></div>
                <div className="sub2 mt-2">{done.note} Works until {when(done.expiresAt)}.{done.wasLocked ? " The account was locked; it is unlocked." : ""}</div>
              </Note>
            ) : <Note kind="ok" title="Reset link sent">{`Sent to ${done.sentTo ?? "the applicant"}. ${done.note}`}</Note>
          ) : (
            <>
              <KvGrid pairs={[["Email", acct.email], ["Phone", acct.phone], ["Application", acct.applicationNo ?? "—"],
                ["Account", accountState(acct)[0]], ["Failed sign-ins", String(acct.failedAttempts)], ["Last signed in", when(acct.lastSignedIn)]]} />
              <div className="eyebrow mt-3">How</div>
              <label className="row row--inline row--tight mt-1"><input type="radio" name="apw-m" checked={method === "TEMPORARY"} onChange={() => setMethod("TEMPORARY")} />
                <span><b>Temporary password</b> — shown here once, for an applicant with you or on the phone; works for 24 hours, and they choose their own at the sign-in.</span></label>
              <label className="row row--inline row--tight mt-1"><input type="radio" name="apw-m" checked={method === "LINK"} onChange={() => setMethod("LINK")} />
                <span><b>Reset link</b> — to the email and phone they registered; they choose a new password within the hour.</span></label>
              <Field id="apw-reason" label="Reason" required hint="Ten characters or more, e.g. “Applicant forgot password; identity checked by phone”">
                <textarea id="apw-reason" className="ctl" rows={2} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} />
              </Field>
              {acct.resets.length ? (
                <details className="mt-2"><summary className="sub2">Earlier resets ({acct.resets.length})</summary>
                  <DTable noPrint pageSize={0} cols={["When", "Method", "Reason", "By"]} rows={acct.resets.map((h) => [
                    <span key="w" className="sub2 tnum">{when(h.reset_at)}</span>, <span key="m">{RESET_METHOD[h.method] ?? h.method}</span>,
                    <span key="r" className="sub2">{h.reason}</span>, <span key="b" className="sub2">{h.reset_by_name}</span>])} />
                </details>
              ) : null}
            </>
          )}
        </Modal>
      ) : null}
    </>
  );
}
