"use client";
/** V369: a course passes between the GST and EPS offices only by request. The office that wants a course asks, with a reason; the
 *  office that holds it accepts, or declines and says why; the Academic Office and the Super Administrator may decide any request;
 *  the office that asked may withdraw it while it waits. A request lapses when the course moves some other way first. The server
 *  decides who may answer — these buttons only show the doors it will open. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { dayOf, num } from "@/lib/gst";

export interface GeneralTransfer {
  id: string; course_code: string; title: string; office_now: string | null; department: string | null;
  from_office: "GST" | "EPS"; to_office: "GST" | "EPS"; reason: string;
  state: "PENDING" | "ACCEPTED" | "DECLINED" | "WITHDRAWN" | "LAPSED";
  requested_at: string; requested_office: string | null; requested_by: string | null;
  decided_at: string | null; decided_office: string | null; decided_by: string | null; decision_note: string | null;
  /** V370: when the holding office was reminded, and when the request was put to the Academic Office */
  reminded_at?: string | null; escalated_at?: string | null;
}

/** V370: after how many days an unanswered request is reminded, and after how many it goes to the Academic Office */
export interface ChaseSettings { remind_after_days: number; escalate_after_days: number; updated_at?: string | null; updated_by?: string | null }

const STATE: Record<GeneralTransfer["state"], [string, "warn" | "ok" | "bad" | "grey"]> = {
  PENDING: ["Waiting for an answer", "warn"], ACCEPTED: ["Accepted", "ok"], DECLINED: ["Declined", "bad"], WITHDRAWN: ["Withdrawn", "grey"], LAPSED: ["Lapsed", "grey"],
};
const CENTRAL = ["academic", "super"];

/** office: the GST or EPS office whose courses page this is, or null on the Academic Office's page (which also sets the chase days) */
export function GstTransfers({ office, actingOffice, transfers, settings }: { office: "GST" | "EPS" | null; actingOffice: string | null; transfers: GeneralTransfer[]; settings?: ChaseSettings | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [days, setDays] = useState({ remind: String(settings?.remind_after_days ?? ""), escalate: String(settings?.escalate_after_days ?? "") });
  const acting = (actingOffice ?? "").toLowerCase();
  const central = CENTRAL.includes(acting);
  const waiting = transfers.filter((t) => t.state === "PENDING");
  const toAnswer = waiting.filter((t) => (office ? t.from_office === office : true));

  async function call(path: string, body: unknown, reason: string, done: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/gst${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(done);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function saveDays() {
    const remind = Number(days.remind), escalate = Number(days.escalate);
    if (!Number.isInteger(remind) || !Number.isInteger(escalate) || remind < 1 || escalate <= remind) {
      notifyProblem({ status: 422, title: "Remind after at least one day, and send to the Academic Office later than that." });
      return;
    }
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/gst/transfers/settings", { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Requests between the GST and EPS offices: remind after ${remind} days, to the Academic Office after ${escalate}`) }, body: JSON.stringify({ remindAfterDays: remind, escalateAfterDays: escalate }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify("Reminder days saved");
      router.refresh();
    } finally { setBusy(false); }
  }

  // the Academic Office's page keeps the panel for its setting even when no request waits
  const showSettings = office === null && settings && central;
  if (!transfers.length && !showSettings) return null;
  return (
    <Panel title="Requests between the GST and EPS offices" right={<span className="sub2">{waiting.length ? `${num(waiting.length)} waiting` : "none waiting"}</span>}>
      {settings ? (
        <PBody>
          {showSettings ? (
            <form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); void saveDays(); }}>
              <Field id="gt-remind" label="Remind the office that holds the course after (days)"><input id="gt-remind" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 90 }} value={days.remind} onChange={(e) => setDays({ ...days, remind: e.target.value })} /></Field>
              <Field id="gt-escalate" label="Send to the Academic Office after (days)"><input id="gt-escalate" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 90 }} value={days.escalate} onChange={(e) => setDays({ ...days, escalate: e.target.value })} /></Field>
              <Btn kind="secondary" size="sm" type="submit" disabled={busy}>Save</Btn>
            </form>
          ) : null}
          <div className="sub2">An unanswered request is reminded to the office that holds the course after {settings.remind_after_days} day{settings.remind_after_days === 1 ? "" : "s"}, and goes to the Academic Office after {settings.escalate_after_days}.</div>
        </PBody>
      ) : null}
      {toAnswer.length ? (
        <PBody>
          <Note kind="info" title={office ? `The other office asks for ${toAnswer.length === 1 ? "a course" : "courses"} this office holds` : "Requests the two offices have not settled"}>
            {office
              ? <>Accept to pass the course, or decline and say why. If the offices disagree, the Academic Office decides.</>
              : <>The office that holds the course answers first; the Academic Office may decide a request the two offices cannot settle.</>}
          </Note>
        </PBody>
      ) : null}
      <DTable pageSize={20} cols={["Course", "Request", "Reason", "State", "|mid"]} rows={transfers.map((t) => {
        const holder = acting === t.from_office.toLowerCase();
        const asker = acting === t.to_office.toLowerCase();
        const [word, kind] = STATE[t.state];
        return [
          <span key="c"><b className="tnum">{t.course_code}</b><div className="sub2">{t.title}{t.department ? ` · ${t.department}` : ""}</div></span>,
          <span key="r" className="sub2">The {t.to_office} office asks the {t.from_office} office<div>{dayOf(t.requested_at)}{t.requested_by ? ` · ${t.requested_by}` : ""}</div></span>,
          <span key="w" className="sub2">{t.reason}</span>,
          <span key="s"><Pil kind={kind}>{word}</Pil>{t.decided_at ? <div className="sub2">{dayOf(t.decided_at)}{t.decided_office ? ` · ${t.decided_office.toUpperCase()}` : ""}{t.decision_note ? ` · ${t.decision_note}` : ""}</div> : null}
            {t.state === "PENDING" && t.escalated_at ? <div className="sub2">With the Academic Office since {dayOf(t.escalated_at)}</div> : t.state === "PENDING" && t.reminded_at ? <div className="sub2">Reminded {dayOf(t.reminded_at)}</div> : null}</span>,
          t.state === "PENDING" ? <span key="a" className="row row--inline row--tight">
            {holder || central ? <>
              <Btn kind="secondary" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Pass ${t.course_code} to the ${t.to_office} office? Its offerings, score sheets and CBT examinations go with it.`)) void call(`/transfers/${t.id}/decide`, { accept: true }, `${t.course_code} passed to the ${t.to_office} office`, `${t.course_code} is now the ${t.to_office} office's`); }}>Accept</Btn>
              <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Decline the ${t.to_office} office's request for ${t.course_code}? Say why:`); if (why && why.trim()) void call(`/transfers/${t.id}/decide`, { accept: false, note: why.trim() }, `Request for ${t.course_code} declined: ${why.trim()}`, `Request for ${t.course_code} declined`); }}>Decline</Btn>
            </> : null}
            {asker || central ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Withdraw the request for ${t.course_code}?`)) void call(`/transfers/${t.id}/withdraw`, {}, `Request for ${t.course_code} withdrawn`, `Request for ${t.course_code} withdrawn`); }}>Withdraw</Btn> : null}
          </span> : <span key="a" />,
        ];
      })} />
    </Panel>
  );
}
