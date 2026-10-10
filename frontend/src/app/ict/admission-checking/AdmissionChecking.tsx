"use client";
/** ADMISSION STATUS CHECKING (V295): the Director of ICT opens, closes, reopens, schedules, extends and shortens the window in which
 *  every applicant with a valid Post-UTME application of a session — admitted, not admitted or not yet decided alike — may pay the
 *  admission checking fee and check their admission status. The window runs over the whole admission exercise (no semester, no
 *  late period), is closed until first opened, and every act is confirmed with its reason, told to the applicants and kept in the
 *  history. Below it, the report the Director and the admissions offices read: who is eligible, who has paid, who has checked, and
 *  the authoritative result, filtered and exported. The states are the server's, from its clock. */
import { useState } from "react";
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
import type { WindowEvent } from "../windows/Windows";

export interface CheckingWindow { type: string; configured: boolean; state: string; phase: string; opens_at?: string | null; closes_at?: string | null; forced?: string | null; reason?: string | null; window_id?: string | null }
export interface CheckingSummary { applicants: number; eligible: number; paid: number; unpaid: number; checked: number; not_checked: number; admitted: number; not_admitted: number; waiting: number; pending: number; revenue: number; checks: number }
export interface CheckingPage {
  session: string; sessions: { name: string; state: string; applicants: number }[]; window: CheckingWindow; summary: CheckingSummary;
  fee?: { checking_fee?: number | null; stated?: boolean } | null; events: WindowEvent[]; now: string;
}
export interface CheckingRow {
  application_no: string; jamb_reg_no: string; name: string; sex?: string | null; programme?: string | null; faculty?: string | null; department?: string | null;
  valid: boolean; paid: boolean; paid_at?: string | null; reference?: string | null; amount?: number | null; checked: boolean; checks?: number | null;
  first_checked_at?: string | null; last_checked_at?: string | null; last_result?: string | null; result: "ADMITTED" | "NOT_ADMITTED" | "WAITING_LIST" | "PENDING";
}
export interface CheckingReport {
  session: string; totals: Omit<CheckingSummary, "checks">; truncated: boolean; rows: CheckingRow[];
  faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code?: string | null }[]; programmes: { code: string; name: string; dept_code?: string | null }[];
}
export type CheckingFilters = Partial<Record<"faculty" | "department" | "programme" | "sex" | "payment" | "result" | "checked" | "from" | "to", string>>;

const WORD = "Admission status checking";
const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { OPEN: ["OPEN", "ok"], CLOSED: ["CLOSED", "bad"], SCHEDULED: ["SCHEDULED", "info"], EXPIRED: ["EXPIRED", "warn"] };
const RESULT: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { ADMITTED: ["ADMITTED", "ok"], NOT_ADMITTED: ["NOT ADMITTED", "bad"], WAITING_LIST: ["WAITING LIST", "warn"], PENDING: ["PENDING", "grey"] };
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const remaining = (iso: string | null | undefined, now: string) => { if (!iso) return ""; const ms = new Date(iso).getTime() - new Date(now).getTime(); if (ms <= 0) return "passed"; const d = Math.floor(ms / 86400000), h = Math.floor((ms % 86400000) / 3600000); return d ? `${d} day${d === 1 ? "" : "s"} ${h} h left` : `${h} h left`; };
const local = (iso: string | null | undefined) => { if (!iso) return ""; const d = new Date(iso); const pad = (n: number) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };
const payWord = (r: CheckingRow) => (!r.valid ? "NOT ELIGIBLE" : r.paid ? "PAID" : "NOT PAID");
const ACTION_WORD: Record<string, string> = { OPEN: "Open", REOPEN: "Reopen", CLOSE: "Close", SCHEDULE: "Schedule", EXTEND: "Extend", SHORTEN: "Shorten", EDIT: "Edit" };

export function AdmissionChecking({ page, report, filters, actingOffice }: { page: CheckingPage; report: CheckingReport | null; filters: CheckingFilters; actingOffice: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const may = actingOffice === "ict";
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [act, setAct] = useState<string | null>(null);
  const [opens, setOpens] = useState(""); const [closes, setCloses] = useState(""); const [reason, setReason] = useState("");
  const session = page.session;
  const w = page.window;
  const s = page.summary;
  const fee = Number(page.fee?.checking_fee ?? 0);
  const [word, kind] = STATE[w.state] ?? [w.state, "grey"];

  const start = (action: string) => {
    setAct(action);
    setOpens(action === "SCHEDULE" ? "" : local(w.opens_at)); setCloses(local(w.closes_at)); setReason("");
    setProblem(null);
  };
  const submit = async () => {
    if (!act) return;
    if (["CLOSE", "REOPEN", "SHORTEN"].includes(act) && !reason.trim()) { setProblem({ status: 422, title: "Give the reason; it goes on the record and in the applicants' notice." }); return; }
    setBusy(true);
    try {
      const body: Record<string, unknown> = { session, semester: null, action: act, reason: reason.trim() || null, lateFeeEnabled: false };
      if (opens) body.opensAt = new Date(opens).toISOString();
      if (closes) body.closesAt = new Date(closes).toISOString();
      const r = await fetch("/api/bff/api/v1/portal-windows/ADMISSION_STATUS_CHECKING", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${WORD} ${session}: ${act.toLowerCase()}`) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(`${WORD}: ${act.toLowerCase()} recorded${j?.told ? ` · ${j.told} applicant notice${j.told === 1 ? "" : "s"} queued` : ""}`);
      setAct(null); router.refresh();
    } finally { setBusy(false); }
  };

  /* the report's filters travel in the address, so a filtered report is a link and the server reads it again */
  const withFilter = (k: keyof CheckingFilters | "session", v: string) => {
    const q = new URLSearchParams();
    q.set("session", k === "session" ? v : session);
    if (k !== "session") {
      for (const [fk, fv] of Object.entries(filters)) if (fv) q.set(fk, fv);
      if (v) q.set(k, v); else q.delete(k);
      if (k === "faculty") { q.delete("department"); q.delete("programme"); }
      if (k === "department") q.delete("programme");
    }
    return `/ict/admission-checking?${q.toString()}`;
  };
  const filtered = Object.values(filters).some(Boolean);
  const departments = (report?.departments ?? []).filter((d) => !filters.faculty || d.faculty_code === filters.faculty);
  const programmes = (report?.programmes ?? []).filter((p) => !filters.department || p.dept_code === filters.department);

  const rows = report?.rows ?? [];
  const HEAD = ["S/N", "Application no.", "JAMB no.", "Name", "Sex", "Programme", "Faculty", "Department", "Checking fee", "Paid on", "Reference", "Amount", "Checks", "First checked", "Last checked", "Admission status"];
  const body = () => rows.map((r, i) => [i + 1, r.application_no, r.jamb_reg_no, r.name, r.sex ?? "", r.programme ?? "", r.faculty ?? "", r.department ?? "", payWord(r), when(r.paid_at), r.reference ?? "", r.amount != null ? Number(r.amount) : "", r.checks ?? 0, when(r.first_checked_at), when(r.last_checked_at), (RESULT[r.result] ?? [r.result])[0]]);
  const sub = `${session}${filtered ? " · filtered" : ""}`;
  const excel = async () => { const blob = await brandedXlsx("Admission Status Checking Report", HEAD, body(), { sheetName: "Checking", serial: docSerial("ASC"), sub }); downloadBlob(blob, `admission-status-checking-${session.replace("/", "-")}.xlsx`); };
  const pdf = () => brandedPrint("Admission Status Checking Report", sub, HEAD, body());
  const EHEAD = ["S/N", "Action", "Previous status", "New status", "Opens", "Closes", "Reason", "Changed by", "Changed at"];
  const ebody = () => page.events.map((e, i) => [i + 1, e.action, e.previous_state ?? "", e.new_state ?? "", when(e.new_opens_at), when(e.new_closes_at), e.reason ?? "", `${e.officer ?? ""}${e.office ? ` (${e.office})` : ""}`, when(e.at)]);
  const eExcel = async () => { const blob = await brandedXlsx("Admission Status Checking History", EHEAD, ebody(), { sheetName: "History", serial: docSerial("ASH"), sub: session }); downloadBlob(blob, `admission-status-checking-history-${session.replace("/", "-")}.xlsx`); };

  const sel = (id: string, label: string, k: keyof CheckingFilters, options: [string, string][]) => (
    <Field id={id} label={label}>
      <select id={id} className="ctl" value={filters[k] ?? ""} onChange={(e) => go(withFilter(k, e.target.value))}>
        <option value="">All</option>
        {options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
    </Field>
  );

  return (
    <>
      <PageHead title="Admission status checking" description="Whether applicants with a submitted, paid Post-UTME application may pay the admission checking fee and check their status. Opened and closed by the Director of ICT; the fee is the Bursary's."
        actions={<span className="row row--inline row--tight"><label htmlFor="asc-session" className="sub2">Session</label><select id="asc-session" className="ctl" value={session} onChange={(e) => go(withFilter("session", e.target.value))}>{page.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}{Number(x.applicants) ? ` — ${Number(x.applicants).toLocaleString()} applications` : ""}</option>)}</select></span>} />
      {problem && !act ? <ProblemNotice problem={problem} /> : null}
      {!may ? <Note kind="info" title="Read only">Opened and closed by the Director of ICT alone.</Note> : null}
      {!w.configured ? <Note kind="bad" title={`Admission status checking has not been opened for ${session}`}>No applicant of the session can pay the checking fee or check their status.</Note> : null}
      <Tiles items={[
        ["STATUS", word, w.state === "OPEN" ? "var(--green-ink)" : "var(--red-ink)", w.state === "OPEN" ? (w.closes_at ? `Closes ${when(w.closes_at)}` : "No closing date") : w.state === "SCHEDULED" ? `Opens ${when(w.opens_at)}` : w.configured ? "Closed by the Director" : "Closed until first opened"],
        ["CHECKING FEE", fee ? money(fee) : "—", null, page.fee?.stated ? "As the Bursary stated it for the session" : fee ? "The standing amount" : "No fee stated: checking is free"],
        ["ELIGIBLE APPLICANTS", Number(s.eligible).toLocaleString(), null, `Valid applications · ${Number(s.applicants).toLocaleString()} in all`],
        ["PAID", Number(s.paid).toLocaleString(), "var(--green-ink)", `${Number(s.unpaid).toLocaleString()} eligible not yet paid`],
        ["CHECKED", Number(s.checked).toLocaleString(), null, `${Number(s.not_checked).toLocaleString()} not yet · ${Number(s.checks).toLocaleString()} checks in all`],
        ["ADMITTED", Number(s.admitted).toLocaleString(), null, `${Number(s.not_admitted).toLocaleString()} not admitted · ${Number(s.waiting).toLocaleString()} waiting · ${Number(s.pending).toLocaleString()} pending`],
        ["REVENUE", money(Number(s.revenue)), null, "Admission checking fees confirmed"],
        ["LAST ACT", page.events[0] ? page.events[0].action : "None", null, page.events[0] ? `${when(page.events[0].at)}${page.events[0].officer ? ` · ${page.events[0].officer}` : ""}` : "No act on this session yet"],
      ]} />

      <Panel title={`ADMISSION STATUS CHECKING · ${session}`} right={<Pil kind={kind}>{word}{!w.configured ? " · by default" : ""}</Pil>}>
        <PBody>
          <div className="sub2">Closing stops new checking-fee payments and checks; a fee already paid stands, and an applicant who has read an offer continues to acceptance.</div>
          <KvGrid cls="grid--3" pairs={[
            ["Opens", w.opens_at ? when(w.opens_at) : w.configured ? "Immediately" : "—"], ["Closes", w.closes_at ? `${when(w.closes_at)} · ${remaining(w.closes_at, page.now)}` : w.configured ? "No closing date" : "—"],
            ["Rule", w.forced === "CLOSED" ? "Closed by the Director" : w.forced === "OPEN" ? "Opened by the Director" : w.configured ? "By the dates" : "Not configured: closed"], ["Reason", w.reason ?? "—"],
            ["Checking fee", fee ? money(fee) : "Not charged"], ["Scope", "Whole admission exercise"],
          ]} />
          {may ? (
            <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
              {w.state === "OPEN" ? <Btn kind="urgent" size="sm" onClick={() => start("CLOSE")}>Close now</Btn> : <Btn kind="go" size="sm" onClick={() => start(w.configured ? "REOPEN" : "OPEN")}>{w.configured ? "Reopen now" : "Open now"}</Btn>}
              <Btn kind="secondary" size="sm" onClick={() => start("SCHEDULE")}>Schedule</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start("EXTEND")}>Extend</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start("SHORTEN")}>Shorten</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start("EDIT")}>Edit window</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="REPORT" right={<span className="row row--inline row--tight">{report ? <span className="sub2">{rows.length.toLocaleString()} application{rows.length === 1 ? "" : "s"}{report.truncated ? " (first 5,000)" : ""}</span> : null}<Btn kind="secondary" size="sm" disabled={!rows.length} onClick={() => void excel()}>Excel</Btn><Btn kind="ghost" size="sm" disabled={!rows.length} onClick={pdf}>PDF</Btn></span>}>
        <PBody>
          <div className="grid grid--4">
            {sel("asc-fac", "Faculty", "faculty", (report?.faculties ?? []).map((f) => [f.code, f.name]))}
            {sel("asc-dept", "Department", "department", departments.map((d) => [d.code, d.name]))}
            {sel("asc-prog", "Programme", "programme", programmes.map((p) => [p.code, p.name]))}
            {sel("asc-sex", "Gender", "sex", [["F", "Female"], ["M", "Male"]])}
            {sel("asc-pay", "Payment status", "payment", [["PAID", "Paid"], ["UNPAID", "Not paid"], ["NOT_ELIGIBLE", "Not eligible (application incomplete)"]])}
            {sel("asc-res", "Admission status", "result", [["ADMITTED", "Admitted"], ["NOT_ADMITTED", "Not admitted"], ["WAITING_LIST", "Waiting list"], ["PENDING", "Pending"]])}
            {sel("asc-chk", "Checked", "checked", [["CHECKED", "Checked"], ["NOT_CHECKED", "Not yet checked"]])}
            <div className="row row--inline row--tight">
              <Field id="asc-from" label="Paid or checked from"><input id="asc-from" type="date" className="ctl" value={filters.from ?? ""} onChange={(e) => go(withFilter("from", e.target.value))} /></Field>
              <Field id="asc-to" label="to"><input id="asc-to" type="date" className="ctl" value={filters.to ?? ""} onChange={(e) => go(withFilter("to", e.target.value))} /></Field>
            </div>
          </div>
          {filtered ? <div className="mt-1"><Btn kind="ghost" size="sm" onClick={() => go(withFilter("session", session))}>Clear the filters</Btn></div> : null}
          {report ? (
            <KvGrid cls="grid--4" pairs={[
              ["Eligible", <b key="e" className="tnum">{Number(report.totals.eligible).toLocaleString()}</b>], ["Paid", <b key="p" className="tnum">{Number(report.totals.paid).toLocaleString()}</b>],
              ["Checked", <b key="c" className="tnum">{Number(report.totals.checked).toLocaleString()}</b>], ["Revenue", <b key="r" className="tnum">{money(Number(report.totals.revenue))}</b>],
            ]} />
          ) : <Note kind="bad" title="The report could not be read">Try again in a moment.</Note>}
        </PBody>
        {rows.length ? <DTable pageSize={50} cols={["S/N|num", "Applicant", "Programme", "Checking fee|mid", "Paid on|mid", "Checks|num", "Last checked|mid", "Admission status|mid"]} rows={rows.map((r, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>,
          <span key="a"><b>{r.name}</b><div className="sub2 tnum">{r.application_no} · {r.jamb_reg_no}{r.sex ? ` · ${r.sex}` : ""}</div></span>,
          <span key="p">{r.programme ?? "—"}<div className="sub2">{[r.faculty, r.department].filter(Boolean).join(" · ")}</div></span>,
          <Pil key="f" kind={!r.valid ? "grey" : r.paid ? "ok" : "warn"}>{payWord(r)}</Pil>,
          <span key="d" className="tnum sub2">{when(r.paid_at)}{r.reference ? <div>{r.reference}</div> : null}</span>,
          <span key="k" className="tnum">{r.checks ?? 0}</span>,
          <span key="l" className="tnum sub2">{when(r.last_checked_at)}</span>,
          <Pil key="r" kind={(RESULT[r.result] ?? [r.result, "grey"])[1]}>{(RESULT[r.result] ?? [r.result])[0]}</Pil>,
        ])} /> : report ? <PBody><div className="sub2">No application of {session} matches{filtered ? " these filters" : ""}.</div></PBody> : null}
      </Panel>

      <Panel title="HISTORY" right={<Btn kind="secondary" size="sm" disabled={!page.events.length} onClick={() => void eExcel()}>Excel</Btn>}>
        {page.events.length ? <DTable pageSize={30} cols={["S/N|num", "Action|mid", "Before|mid", "After|mid", "Opens|mid", "Closes|mid", "Reason", "Changed by", "At|mid"]} rows={page.events.map((e, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <b key="a">{e.action}</b>, <span key="b" className="sub2">{e.previous_state ?? ""}</span>, <Pil key="c" kind={(STATE[e.new_state ?? ""] ?? ["", "grey"])[1]}>{e.new_state}</Pil>,
          <span key="o" className="tnum sub2">{when(e.new_opens_at)}</span>, <span key="e" className="tnum sub2">{when(e.new_closes_at)}</span>,
          <span key="r" className="sub2">{e.reason ?? ""}</span>, <span key="w" className="sub2">{e.officer ?? ""}{e.office ? ` (${e.office})` : ""}</span>, <span key="t" className="tnum sub2">{when(e.at)}</span>,
        ])} /> : <PBody><div className="sub2">No act yet; closed until the Director of ICT opens it.</div></PBody>}
      </Panel>

      {act ? (
        <Modal title={`${ACTION_WORD[act] ?? act} admission status checking`} sub={`${session} · the whole admission exercise`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Back</Btn><Btn kind={act === "CLOSE" ? "urgent" : "primary"} disabled={busy} onClick={() => void submit()}>{act === "CLOSE" ? "Yes, close it now" : act === "REOPEN" || act === "OPEN" ? "Open it" : "Record"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {act === "CLOSE" ? (
            <Note kind="bad" title={`Are you sure you want to close admission status checking for ${session}?`}>
              It takes effect at once. No applicant can pay the checking fee or check their status until it is reopened; a fee already paid stands. The applicants are told.
            </Note>
          ) : (
            <>
              <div className="sub2 mb-2">{act === "OPEN" || act === "REOPEN" ? "Leave the dates blank to open now with no closing; or give the closing the window runs to. The session's valid applicants are told it is open." : act === "SCHEDULE" ? "Checking opens and closes by these dates, on the server's clock in Africa/Lagos." : act === "EXTEND" ? "Move the closing later; the applicants are told. The previous dates stay in the history." : act === "SHORTEN" ? "Move the closing earlier." : "Change either date; the rule before is kept in the history."}</div>
              <div className="grid grid--2">
                <Field id="asc-o" label="Opens"><input id="asc-o" type="datetime-local" className="ctl" value={opens} onChange={(e) => setOpens(e.target.value)} /></Field>
                <Field id="asc-c" label="Closes"><input id="asc-c" type="datetime-local" className="ctl" value={closes} onChange={(e) => setCloses(e.target.value)} /></Field>
              </div>
            </>
          )}
          <Field id="asc-r" label="Reason" required={["CLOSE", "REOPEN", "SHORTEN"].includes(act)} hint="On the record and in the applicants' notice"><textarea id="asc-r" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
