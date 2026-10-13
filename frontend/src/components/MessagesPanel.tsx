"use client";

/**
 * V440: what the portal sent a student or a member of staff — e-mail, SMS and portal notices, newest first, with the provider's
 * word where there is one — and a message that failed, was cancelled, bounced or went undelivered sent again to the address the
 * record holds now. On Student 360 as a panel, on the staff record as a tab.
 */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Message {
  id: string; channel: string; recipient: string; subject: string; template_key: string | null; created_at: string; state: string; sent_at: string | null;
  attempts: number; last_error: string | null; cancel_reason: string | null; delivery_state: string | null; delivered_at: string | null; delivery_detail: string | null;
  resent_from: string | null; resent: boolean;
}

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "2-digit" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

/** what happened to the message, in one word, and the provider's or the portal's detail beside it */
function stateOf(m: Message): [string, "ok" | "bad" | "warn" | "grey" | "info", string] {
  if (m.state === "SENT") {
    if (m.channel === "PORTAL") return ["Delivered", "ok", "on the dashboard"];
    if (m.delivery_state === "DELIVERED") return ["Delivered", "ok", m.delivered_at ? when(m.delivered_at) : ""];
    if (m.delivery_state === "BOUNCED") return ["Bounced", "bad", m.delivery_detail ?? ""];
    if (m.delivery_state === "UNDELIVERED") return ["Undelivered", "bad", m.delivery_detail ?? ""];
    return ["Sent", "ok", m.sent_at ? `accepted ${when(m.sent_at)}` : ""];
  }
  if (m.state === "FAILED") return [m.last_error === "INVALID_EMAIL" ? "Not an e-mail" : m.last_error === "INVALID_PHONE" ? "Not a phone" : "Failed", "bad", ["INVALID_EMAIL", "INVALID_PHONE"].includes(m.last_error ?? "") ? "" : m.last_error ?? ""];
  if (m.state === "CANCELLED") return ["Cancelled", "grey", m.cancel_reason ?? ""];
  return ["Queued", "info", `${m.attempts} attempt${m.attempts === 1 ? "" : "s"}`];
}

function canResend(m: Message): boolean {
  return (m.channel === "EMAIL" || m.channel === "SMS") && !m.resent
    && (m.state === "FAILED" || m.state === "CANCELLED" || (m.state === "SENT" && (m.delivery_state === "BOUNCED" || m.delivery_state === "UNDELIVERED")));
}

/** path: the API path of the person's messages, e.g. /api/v1/students/<id>/messages; embedded: no panel chrome (a tab) */
export function MessagesPanel({ path, embedded = false }: { path: string; embedded?: boolean }) {
  const [rows, setRows] = useState<Message[] | null>(null);
  const [denied, setDenied] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`/api/bff${path}`, { cache: "no-store" });
      if (!live) return;
      if (r.status === 403) { setDenied(true); return; }
      if (!r.ok) { setRows([]); return; }
      setRows((await r.json()) as Message[]);
    })();
    return () => { live = false; };
  }, [path]);

  async function resend(m: Message) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff${path}/${m.id}/resend`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Message sent again to ${m.recipient}: ${m.subject}`) }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify("Message queued again");
      setRows((j as { messages: Message[] }).messages);
    } finally {
      setBusy(false);
    }
  }

  const body = denied
    ? <div className="sub2">The messages are read by the Registry, Records, HR and the Directorate of ICT.</div>
    : rows === null
      ? <div className="sub2">Reading…</div>
      : rows.length
        ? (
          <DTable cols={["When|mid", "Channel|mid", "To", "Message", "State|mid", "|mid"]} rows={rows.map((m) => {
            const [label, kind, detail] = stateOf(m);
            return [
              <span key="w" className="tnum sub2">{when(m.created_at)}</span>,
              <span key="c" className="sub2">{m.channel === "PORTAL" ? "Portal" : m.channel === "EMAIL" ? "E-mail" : "SMS"}</span>,
              <span key="t" className="sub2">{m.recipient}</span>,
              <span key="s">{m.subject}{m.template_key ? <div className="sub2">{m.template_key}{m.resent_from ? " · sent again" : ""}</div> : m.resent_from ? <div className="sub2">sent again</div> : null}</span>,
              <span key="x" title={detail}><Pil kind={kind}>{label}</Pil>{detail ? <div className="sub2">{detail}</div> : null}</span>,
              canResend(m) ? <Btn key="r" kind="ghost" size="sm" disabled={busy} onClick={() => void resend(m)}>Send again</Btn> : m.resent ? <span key="r" className="sub2">sent again</span> : "",
            ];
          })} texts={rows.map((m) => `${m.recipient} ${m.subject} ${m.state} ${m.template_key ?? ""}`)} />
        )
        : <div className="sub2">Nothing has been sent to this person yet.</div>;

  if (embedded) return <div>{body}</div>;
  return (
    <Panel title="Messages" right="E-mail, SMS and portal notices, newest first; the provider's word where there is one">
      {rows !== null && rows.length ? body : <PBody>{body}</PBody>}
    </Panel>
  );
}
