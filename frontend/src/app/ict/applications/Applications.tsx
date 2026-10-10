"use client";
/** APPLICATION REGISTRATION CONTROL (V312): the Director of ICT opens, closes, reopens, schedules, extends and shortens the two
 *  application windows of a session's admission exercise — Post UTME Registration (/apply) and the Postgraduate Application
 *  (/pg/apply) — and writes the message the public reads while one is closed. A closed window stops NEW applications only: an
 *  applicant who registered before it closed signs in, pays, uploads and submits as before. The backend refuses a new application
 *  while the window is closed whatever any page shows; the login page hides the buttons, the apply pages show the message, and
 *  the University's website reads the same state from the public address below. Every act is confirmed with its reason and kept
 *  in the history. The states are the server's, from its clock. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { WindowEvent } from "../windows/Windows";

export interface AppWindow {
  type: string; session: string; path: string; configured: boolean; state: string; phase: string;
  opens_at?: string | null; closes_at?: string | null; forced?: string | null; reason?: string | null; window_id?: string | null;
  message: string; message_updated_at?: string | null; message_updated_by?: string | null; message_office?: string | null;
  total: number; today: number; week: number; paid?: number; events: WindowEvent[];
  /** V385: the Post-UTME CBT windows count who sat, who is scored and who is released */
  sat?: number; scored?: number; released?: number;
}
export interface ApplicationsPage {
  session: string; liveSessions: Record<string, string>; sessions: { name: string; state: string; registrations: number; applications: number }[];
  windows: AppWindow[]; publicPath: string; now: string;
}

/** V337: postgraduate admission status checking is the School's own window, beside its application */
const PG_CHECKING = "POSTGRADUATE_ADMISSION_STATUS_CHECKING";
/** V342: JUPEB admission status checking, beside the JUPEB application */
const JUPEB_CHECKING = "JUPEB_ADMISSION_STATUS_CHECKING";
const CHECKING = new Set([PG_CHECKING, JUPEB_CHECKING]);
/** V385: the Post-UTME CBT door and result checking — the Director's windows over the examination, closed until first opened */
const PUTME_CBT = "POST_UTME_CBT";
const PUTME_RESULTS = "POST_UTME_RESULT_CHECKING";
const PUTME = new Set([PUTME_CBT, PUTME_RESULTS]);
const WORD: Record<string, string> = { POST_UTME_REGISTRATION: "Post UTME Registration", POSTGRADUATE_APPLICATION: "Postgraduate Application", [PG_CHECKING]: "Postgraduate Admission Status Checking", JUPEB_APPLICATION: "JUPEB Application", [JUPEB_CHECKING]: "JUPEB Admission Status Checking", CCE_APPLICATION: "CCE Application", [PUTME_CBT]: "Post-UTME CBT Examination", [PUTME_RESULTS]: "Post-UTME Result Checking" };
const NOUN: Record<string, string> = { POST_UTME_REGISTRATION: "registration", POSTGRADUATE_APPLICATION: "application", [PG_CHECKING]: "checking fee", JUPEB_APPLICATION: "JUPEB application", [JUPEB_CHECKING]: "checking fee", CCE_APPLICATION: "CCE registration", [PUTME_CBT]: "examination sitting", [PUTME_RESULTS]: "result check" };
const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { OPEN: ["OPEN", "ok"], CLOSED: ["CLOSED", "bad"], SCHEDULED: ["SCHEDULED", "info"], EXPIRED: ["EXPIRED", "warn"] };
const ACTION_WORD: Record<string, string> = { OPEN: "Open", REOPEN: "Reopen", CLOSE: "Close", SCHEDULE: "Schedule", EXTEND: "Extend", SHORTEN: "Shorten", EDIT: "Edit", MESSAGE: "Message" };
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const remaining = (iso: string | null | undefined, now: string) => { if (!iso) return ""; const ms = new Date(iso).getTime() - new Date(now).getTime(); if (ms <= 0) return "passed"; const d = Math.floor(ms / 86400000), h = Math.floor((ms % 86400000) / 3600000); return d ? `${d} day${d === 1 ? "" : "s"} ${h} h left` : `${h} h left`; };
const local = (iso: string | null | undefined) => { if (!iso) return ""; const d = new Date(iso); const pad = (n: number) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };

export function Applications({ page, actingOffice }: { page: ApplicationsPage; actingOffice: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const may = actingOffice === "ict";
  const session = page.session;
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [act, setAct] = useState<{ type: string; action: string } | null>(null);
  const [opens, setOpens] = useState(""); const [closes, setCloses] = useState(""); const [reason, setReason] = useState("");
  const [drafts, setDrafts] = useState<Record<string, string>>(() => Object.fromEntries(page.windows.map((w) => [w.type, w.message ?? ""])));
  const [saving, setSaving] = useState<string | null>(null);

  const start = (w: AppWindow, action: string) => {
    setAct({ type: w.type, action });
    setOpens(action === "SCHEDULE" ? "" : local(w.opens_at)); setCloses(local(w.closes_at)); setReason("");
    setProblem(null);
  };
  const submit = async () => {
    if (!act) return;
    if (["CLOSE", "REOPEN", "SHORTEN"].includes(act.action) && !reason.trim()) { setProblem({ status: 422, title: "Give the reason; it goes on the record." }); return; }
    setBusy(true);
    try {
      const body: Record<string, unknown> = { session, semester: null, action: act.action, reason: reason.trim() || null, lateFeeEnabled: false };
      if (opens) body.opensAt = new Date(opens).toISOString();
      if (closes) body.closesAt = new Date(closes).toISOString();
      const r = await fetch(`/api/bff/api/v1/portal-windows/${act.type}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${WORD[act.type]} ${session}: ${act.action.toLowerCase()}`) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(`${WORD[act.type]}: ${act.action.toLowerCase()} recorded · now ${String(j?.after?.state ?? "").toLowerCase()}`);
      setAct(null); router.refresh();
    } finally { setBusy(false); }
  };
  const saveMessage = async (w: AppWindow) => {
    const text = (drafts[w.type] ?? "").trim();
    if (!text) { notifyProblem({ status: 422, title: "The closure message cannot be blank." }); return; }
    setSaving(w.type);
    try {
      const r = await fetch(`/api/bff/api/v1/portal-windows/applications/${w.type}/message?session=${encodeURIComponent(session)}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${WORD[w.type]}: closure message`) }, body: JSON.stringify({ message: text }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; notifyProblem(pr); return; }
      notify(`${WORD[w.type]}: closure message saved`);
      router.refresh();
    } finally { setSaving(null); }
  };

  const EHEAD = ["S/N", "Window", "Action", "Previous status", "New status", "Opens", "Closes", "Reason", "Changed by", "Changed at"];
  const allEvents = page.windows.flatMap((w) => w.events.map((e) => ({ ...e, window: WORD[w.type] ?? w.type }))).sort((a, b) => (a.at < b.at ? 1 : -1));
  const excel = async () => {
    const rows = allEvents.map((e, i) => [i + 1, e.window, e.action, e.previous_state ?? "", e.new_state ?? "", when(e.new_opens_at), when(e.new_closes_at), e.reason ?? "", `${e.officer ?? ""}${e.office ? ` (${e.office})` : ""}`, when(e.at)]);
    const blob = await brandedXlsx("Application Registration Control History", EHEAD, rows, { sheetName: "History", serial: docSerial("ARC"), sub: session });
    downloadBlob(blob, `application-control-history-${session.replace("/", "-")}.xlsx`);
  };

  const card = (w: AppWindow) => {
    const [word, kind] = STATE[w.state] ?? [w.state, "grey"];
    const live = page.liveSessions[w.type];
    const noun = NOUN[w.type];
    const checking = CHECKING.has(w.type);
    const putme = PUTME.has(w.type);
    const closedByDefault = putme || w.type === "JUPEB_APPLICATION" || checking || w.type === "CCE_APPLICATION";
    return (
      <Panel key={w.type} title={`${WORD[w.type].toUpperCase()} · ${session}`} right={<Pil kind={kind}>{word}{!w.configured ? " · by default" : ""}</Pil>}>
        <PBody>
          <Tiles items={[
            ["STATUS", word, w.state === "OPEN" ? "var(--green-ink)" : "var(--red-ink)", w.state === "OPEN" ? (w.closes_at ? `Closes ${when(w.closes_at)}` : "No closing date") : w.state === "SCHEDULED" ? `Opens ${when(w.opens_at)}` : w.state === "EXPIRED" ? `Closed ${when(w.closes_at)}` : "Closed by the Director"],
            putme
              ? [w.type === PUTME_CBT ? "SUBMITTED APPLICANTS" : "SCORES RELEASED", Number(w.type === PUTME_CBT ? w.total : w.released ?? 0).toLocaleString(), null,
                 w.type === PUTME_CBT ? `${Number(w.sat ?? 0).toLocaleString()} sat the CBT · ${Number(w.today).toLocaleString()} today · ${Number(w.week).toLocaleString()} in 7 days` : `${Number(w.scored ?? 0).toLocaleString()} scored on the record · ${Number(w.total).toLocaleString()} submitted applicants`]
              : checking
              ? ["VALID APPLICANTS", Number(w.total).toLocaleString(), null, `${Number(w.paid ?? 0).toLocaleString()} paid to check · ${Number(w.today).toLocaleString()} today · ${Number(w.week).toLocaleString()} in 7 days`]
              : [`${noun.toUpperCase()}S`, Number(w.total).toLocaleString(), null, `${Number(w.today).toLocaleString()} today · ${Number(w.week).toLocaleString()} in the last 7 days`],
            putme
              ? ["PUBLIC PAGE", w.path, null, w.state === "OPEN" ? (w.type === PUTME_CBT ? "Candidates verify by JAMB number and the examination's second factor, then sit" : "Verified candidates read the score the Academic Office released") : "The closure message"]
              : checking
              ? ["WHERE", w.path, null, w.state === "OPEN" ? "Valid applicants pay once and check, as often as they like" : "No new checking fee; a paid applicant waits for it to reopen"]
              : ["PUBLIC PAGE", w.path, null, w.state === "OPEN" ? "The form; the login page shows its button" : "The closure message; the login page hides its button"],
            ["LAST ACT", w.events[0] ? w.events[0].action : "None", null, w.events[0] ? `${when(w.events[0].at)}${w.events[0].officer ? ` · ${w.events[0].officer}` : ""}` : closedByDefault ? "Closed by default until the Director first opens it" : `Open by default until the Director first acts`],
          ]} />
          <KvGrid cls="grid--3" pairs={[
            ["Opens", w.state === "CLOSED" ? "—" : w.opens_at ? when(w.opens_at) : w.configured ? "Immediately" : "—"], ["Closes", w.state === "CLOSED" ? "Closed now" : w.closes_at ? `${when(w.closes_at)} · ${remaining(w.closes_at, page.now)}` : w.configured ? "No closing date" : "—"],
            ["Rule", w.forced === "CLOSED" ? "Closed by the Director" : w.forced === "OPEN" ? "Opened by the Director" : w.configured ? "By the dates" : closedByDefault ? "Not configured: closed" : "Not configured: open"], ["Reason", w.reason ?? "—"],
            ["Scope", "Whole admission exercise of the session"],
            putme ? ["Who may use it", w.type === PUTME_CBT ? "Submitted applicants of the session, eligible on the record, verified by JAMB number and the second factor the examination names" : "Verified applicants whose Post-UTME score the Academic Office has released"]
              : checking ? ["Who checks", w.type === JUPEB_CHECKING ? "JUPEB applicants of the session who submitted with the application fee confirmed" : "Applicants of the session whose application fee is confirmed"] : ["Applications today go to", live === session ? session : `${live} — this is the rule for ${session}`],
          ]} />
          {live && live !== session ? <Note kind="info" title={`New ${noun}s today are filed under ${live}, not ${session}`}>To change what applicants meet today, choose {live} above.</Note> : null}
          {may ? (
            <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
              {w.state === "OPEN" ? <Btn kind="urgent" size="sm" onClick={() => start(w, "CLOSE")}>Close now</Btn> : <Btn kind="go" size="sm" onClick={() => start(w, w.configured ? "REOPEN" : "OPEN")}>{w.configured ? "Reopen now" : "Open now"}</Btn>}
              <Btn kind="secondary" size="sm" onClick={() => start(w, "SCHEDULE")}>Schedule</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start(w, "EXTEND")}>Extend</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start(w, "SHORTEN")}>Shorten</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start(w, "EDIT")}>Edit window</Btn>
            </div>
          ) : null}
        </PBody>
        {checking ? null : <PBody>
          <Field id={`msg-${w.type}`} label="Closure message" hint={`Shown at ${w.path} and on the University's website while closed. Blank lines make paragraphs.${w.message_updated_at ? ` Last changed ${when(w.message_updated_at)}${w.message_updated_by ? ` by ${w.message_updated_by}` : ""}.` : ""}`}>
            <textarea id={`msg-${w.type}`} className="ctl" rows={6} maxLength={2000} value={drafts[w.type] ?? ""} disabled={!may} onChange={(e) => setDrafts({ ...drafts, [w.type]: e.target.value })} />
          </Field>
          {may ? (
            <div className="row row--inline row--tight">
              <Btn kind="primary" size="sm" disabled={saving === w.type || (drafts[w.type] ?? "") === (w.message ?? "")} onClick={() => void saveMessage(w)}>{saving === w.type ? "Saving…" : "Save message"}</Btn>
              {(drafts[w.type] ?? "") !== (w.message ?? "") ? <Btn kind="ghost" size="sm" onClick={() => setDrafts({ ...drafts, [w.type]: w.message ?? "" })}>Discard changes</Btn> : null}
            </div>
          ) : null}
        </PBody>}
        {w.events.length ? <DTable pageSize={10} cols={["S/N|num", "Action|mid", "Before|mid", "After|mid", "Opens|mid", "Closes|mid", "Reason", "Changed by", "At|mid"]} rows={w.events.map((e, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <b key="a">{ACTION_WORD[e.action] ?? e.action}</b>, <span key="b" className="sub2">{e.previous_state ?? ""}</span>, <Pil key="c" kind={(STATE[e.new_state ?? ""] ?? ["", "grey"])[1]}>{e.new_state}</Pil>,
          <span key="o" className="tnum sub2">{when(e.new_opens_at)}</span>, <span key="e" className="tnum sub2">{when(e.new_closes_at)}</span>,
          <span key="r" className="sub2">{e.reason ?? ""}</span>, <span key="w" className="sub2">{e.officer ?? ""}{e.office ? ` (${e.office})` : ""}</span>, <span key="t" className="tnum sub2">{when(e.at)}</span>,
        ])} /> : <PBody><div className="sub2">No act on {WORD[w.type]} for {session} yet: it is {closedByDefault ? "closed" : "open"} by default.</div></PBody>}
      </Panel>
    );
  };

  const acting = act ? page.windows.find((w) => w.type === act.type) ?? null : null;

  return (
    <>
      <PageHead title="Application registration control" description="Whether a new Post UTME registration, postgraduate application or JUPEB application may be started. Closing stops new applications only; applicants already registered continue."
        actions={<span className="row row--inline row--tight"><label htmlFor="arc-session" className="sub2">Session</label><select id="arc-session" className="ctl" value={session} onChange={(e) => go(`/ict/applications?session=${encodeURIComponent(e.target.value)}`)}>{page.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}{Number(x.registrations) || Number(x.applications) ? ` — ${Number(x.registrations).toLocaleString()} UG · ${Number(x.applications).toLocaleString()} PG` : ""}</option>)}</select></span>} />
      {problem && !act ? <ProblemNotice problem={problem} /> : null}
      {!may ? <Note kind="info" title="Read only">Application windows are opened and closed by the Director of ICT alone.</Note> : null}
      {page.windows.map(card)}

      <Panel title="FOR THE UNIVERSITY'S WEBSITE">
        <PBody>
          <div className="sub2">The website reads the same state the portal enforces, with no sign-in, from <code>GET {page.publicPath}</code> on the portal&rsquo;s API. It answers <code>postUtme</code> and <code>postgraduate</code>, each with <code>status</code> (OPEN, CLOSED, SCHEDULED or EXPIRED), <code>open</code>, <code>session</code>, <code>opensAt</code>, <code>closesAt</code>, the closure <code>message</code> while not open, and <code>applicationUrl</code> to send an applicant to. Cached for one minute.</div>
        </PBody>
      </Panel>

      <Panel title="HISTORY · BOTH WINDOWS" right={<Btn kind="secondary" size="sm" disabled={!allEvents.length} onClick={() => void excel()}>Excel</Btn>}>
        {allEvents.length ? <DTable pageSize={30} cols={["S/N|num", "Window", "Action|mid", "Before|mid", "After|mid", "Reason", "Changed by", "At|mid"]} rows={allEvents.map((e, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <span key="w">{e.window}</span>, <b key="a">{ACTION_WORD[e.action] ?? e.action}</b>, <span key="b" className="sub2">{e.previous_state ?? ""}</span>,
          <span key="c" className="sub2">{e.new_state ?? ""}</span>, <span key="r" className="sub2">{e.reason ?? ""}</span>, <span key="o" className="sub2">{e.officer ?? ""}{e.office ? ` (${e.office})` : ""}</span>, <span key="t" className="tnum sub2">{when(e.at)}</span>,
        ])} /> : <PBody><div className="sub2">No act on either window for {session} yet.</div></PBody>}
      </Panel>

      {act && acting ? (
        <Modal title={`${ACTION_WORD[act.action] ?? act.action} ${WORD[act.type]}`} sub={`${session} · the whole admission exercise`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Back</Btn><Btn kind={act.action === "CLOSE" ? "urgent" : "primary"} disabled={busy} onClick={() => void submit()}>{act.action === "CLOSE" ? "Yes, close it now" : act.action === "REOPEN" || act.action === "OPEN" ? "Open it" : "Record"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {act.action === "CLOSE" ? (
            <Note kind="bad" title={`Are you sure you want to close ${WORD[act.type]} for ${session}?`}>
              {CHECKING.has(act.type)
                ? <>It takes effect at once. No checking fee is taken and no status read until it is reopened; a fee already paid stands. Nothing is deleted.</>
                : <>It takes effect at once. No new {NOUN[act.type]} can be started until it is reopened; {acting.path} shows your closure message. Applicants already registered continue. Nothing is deleted.</>}
            </Note>
          ) : (
            <>
              <div className="sub2 mb-2">{act.action === "OPEN" || act.action === "REOPEN" ? "Leave the dates blank to open now with no closing; or give the closing the window runs to." : act.action === "SCHEDULE" ? `${WORD[act.type]} opens and closes by these dates, on the server's clock in Africa/Lagos. Until it opens, ${acting.path} shows the closure message.` : act.action === "EXTEND" ? "Move the closing later. The previous dates stay in the history." : act.action === "SHORTEN" ? "Move the closing earlier." : "Change either date; the rule before is kept in the history."}</div>
              <div className="grid grid--2">
                <Field id="arc-o" label="Opens"><input id="arc-o" type="datetime-local" className="ctl" value={opens} onChange={(e) => setOpens(e.target.value)} /></Field>
                <Field id="arc-c" label="Closes"><input id="arc-c" type="datetime-local" className="ctl" value={closes} onChange={(e) => setCloses(e.target.value)} /></Field>
              </div>
            </>
          )}
          <Field id="arc-r" label="Reason" required={["CLOSE", "REOPEN", "SHORTEN"].includes(act.action)} hint="On the record"><textarea id="arc-r" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
