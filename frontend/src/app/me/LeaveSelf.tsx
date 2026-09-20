"use client";

/** The staff member's own leave on the /me screen: the balance, a request form, and the
 *  history with the option to cancel one still pending or not yet started. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface LeaveType { code: string; name: string; max_days: number; paid: boolean }
export interface LeaveReq { id: string; leave_type: string; type_name: string; from_date: string; to_date: string; days: number; cover: string | null; state: string; decision_note: string | null }
export interface MyLeave { requests: LeaveReq[]; types: LeaveType[]; balance: number | string; isStaff: boolean }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  REQUESTED: ["warn", "Awaiting decision"], APPROVED: ["ok", "Approved"], DECLINED: ["grey", "Declined"], CANCELLED: ["grey", "Cancelled"],
};

export function LeaveSelf({ d }: { d: MyLeave }) {
  const router = useRouter();
  const [f, setF] = useState({ type: "ANNUAL", from: "", to: "", cover: "", note: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  if (!d.isStaff) {
    return (
      <Panel title="Leave">
        <PBody><Note kind="info" title="Leave is for serving staff">Your record does not carry an active employment, so there is no leave to request. If you have just been appointed, it appears here once the Human Resource office records your employment.</Note></PBody>
      </Panel>
    );
  }

  async function post(path: string, body: unknown, reason: string) {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Leave" right={`Annual balance: ${d.balance} days`}>
      {said ? <div style={{ padding: "0 16px" }}><Note kind="ok" title={said}>It waits for your office to decide.</Note></div> : null}
      {err ? <div style={{ padding: "0 16px" }}><ProblemNotice problem={err} /></div> : null}
      <PBody>
        <div className="grid grid--3">
          <Field id="lv-type" label="Type"><select id="lv-type" className="ctl" value={f.type} onChange={(e) => setF({ ...f, type: e.target.value })}>{d.types.map((t) => <option key={t.code} value={t.code}>{t.name} (max {t.max_days}d{t.paid ? "" : ", unpaid"})</option>)}</select></Field>
          <Field id="lv-from" label="From"><input id="lv-from" className="ctl" type="date" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} /></Field>
          <Field id="lv-to" label="To"><input id="lv-to" className="ctl" type="date" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></Field>
        </div>
        <div className="grid grid--2">
          <Field id="lv-cover" label="Cover" hint="Who takes your duties, if required"><input id="lv-cover" className="ctl" value={f.cover} onChange={(e) => setF({ ...f, cover: e.target.value })} /></Field>
          <Field id="lv-note" label="Note" hint="Optional"><input id="lv-note" className="ctl" value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} /></Field>
        </div>
        <div><Btn kind="primary" disabled={busy || !f.from || !f.to} onClick={async () => { if (await post("/me/leave", { type: f.type, from: f.from, to: f.to, cover: f.cover || null, note: f.note || null }, "Request leave")) { setSaid("Your leave request is with your office."); setF({ type: "ANNUAL", from: "", to: "", cover: "", note: "" }); } }}>Request leave</Btn></div>
      </PBody>
      {d.requests.length ? (
        <DTable cols={["Type", "Period|mid", "Days|num", "Stage", "Action|num"]} rows={d.requests.map((r) => [
          <span key="t">{r.type_name}</span>,
          <span className="sub2 tnum" key="p">{day(r.from_date)} – {day(r.to_date)}</span>,
          <span className="tnum" key="d">{r.days}</span>,
          <span key="s"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.decision_note ? <div className="sub2">{r.decision_note}</div> : null}</span>,
          <span key="a">{r.state === "REQUESTED" || r.state === "APPROVED" ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm("Cancel this leave request?")) void post(`/me/leave/${r.id}/cancel`, {}, "Cancel my leave request"); }}>Cancel</Btn> : null}</span>,
        ])} />
      ) : <PBody><div className="sub2">You have made no leave request.</div></PBody>}
    </Panel>
  );
}
