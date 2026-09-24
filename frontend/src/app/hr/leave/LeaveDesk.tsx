"use client";

/** tLeave — the office's leave queue: requests awaiting a decision, and the leave granted.
 *  A request is the member of staff's own; the decision is a second person's. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface LeaveRow {
  id: string; person_id: string; name: string; staff_no: string; grade: string; leave_type: string; type_name: string;
  from_date: string; to_date: string; days: number; cover: string | null; note: string | null; state: string;
  requested_at: string; decided_at: string | null; decision_note: string | null;
}

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  REQUESTED: ["warn", "Awaiting decision"], APPROVED: ["ok", "Approved"], DECLINED: ["grey", "Declined"], CANCELLED: ["grey", "Cancelled"],
};

export function LeaveDesk({ rows, actingOffice }: { rows: LeaveRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["hrm", "hod", "dean", "dregistrar", "registrar", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [tab, setTab] = useState("REQUESTED");

  const count = (s: string) => rows.filter((r) => r.state === s).length;
  const onLeaveToday = rows.filter((r) => r.state === "APPROVED" && r.from_date <= new Date().toISOString().slice(0, 10) && r.to_date >= new Date().toISOString().slice(0, 10)).length;
  const shown = tab === "ALL" ? rows : rows.filter((r) => r.state === tab);

  async function decide(id: string, approve: boolean, note: string | null, who: string) {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/hr/leave/${id}/decide`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${approve ? "Approve" : "Decline"} leave for ${who}`) }, body: JSON.stringify({ approve, note }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`${who}'s leave ${approve ? "approved" : "declined"}`);
      notify(`${who}'s leave ${approve ? "approved" : "declined"}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["Awaiting decision", String(count("REQUESTED")), count("REQUESTED") ? "var(--red-ink)" : null, "Requests to consider"],
        ["On leave today", String(onLeaveToday), null, "Approved and current"],
        ["Approved", String(count("APPROVED")), "var(--green-ink)", "All time"],
        ["Requests", String(rows.length), null, "All"],
      ]} />
      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          {[["REQUESTED", "Awaiting"], ["APPROVED", "Approved"], ["DECLINED", "Declined"], ["ALL", "All"]].map(([k, l]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => setTab(k)}>{l}{k !== "ALL" && count(k) ? ` (${count(k)})` : ""}</button>
          ))}
        </div>
      </div></div>
      <Panel title="Leave requests" right={may ? undefined : "You are reading this queue"}>
        {shown.length ? (
          <DTable cols={["Staff", "Type", "Period|mid", "Days|num", "Cover", "Stage", "Action|num"]} rows={shown.map((r) => [
            <Two key="s" a={r.name} b={`${r.staff_no} · ${r.grade}`} />,
            <span key="t">{r.type_name}{r.note ? <div className="sub2">{r.note}</div> : null}</span>,
            <span className="sub2 tnum" key="p">{day(r.from_date)} – {day(r.to_date)}</span>,
            <span className="tnum" key="d">{r.days}</span>,
            <span className="sub2" key="c">{r.cover ?? "—"}</span>,
            <span key="st"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.decision_note ? <div className="sub2">{r.decision_note}</div> : null}</span>,
            <span key="ac" className="row row--inline row--tight row--right">
              {may && r.state === "REQUESTED" ? <Btn kind="go" disabled={busy} onClick={() => void decide(r.id, true, null, r.name)}>Approve</Btn> : null}
              {may && r.state === "REQUESTED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is it declined? The reason is recorded."); if (w && w.trim()) void decide(r.id, false, w.trim(), r.name); }}>Decline</Btn> : null}
            </span>,
          ])} texts={shown.map((r) => `${r.name} ${r.staff_no} ${r.type_name} ${r.state}`)} />
        ) : <PBody><div className="sub2">No request in this stage.</div></PBody>}
      </Panel>
      <Note kind="info" title="Annual leave draws down a yearly entitlement">
        The balance is derived from what has been approved, never stored, so it cannot drift. Approving annual leave that would exceed the balance is refused by the database, not by anyone remembering to check.
      </Note>
    </>
  );
}
