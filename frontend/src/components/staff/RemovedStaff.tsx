"use client";
/**
 * V656: the staff deleted, deactivated and restored — who, when, why and what tied them — with Restore for a deactivation not yet
 * undone (back on the lists, able to sign in, the offices it ended reopened).
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ACTION_WORD, RESTORE_REASONS, reasonProblem, tiesText, type StaffChange } from "@/lib/staff-removal";

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });

export function RemovedStaff({ changes, may }: { changes: StaffChange[]; may: boolean }) {
  const router = useRouter();
  const [open, setOpen] = useState<StaffChange | null>(null);
  const [code, setCode] = useState("");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const why = reasonProblem(code, text, RESTORE_REASONS);

  async function restore() {
    if (!open || why) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/iam/staff/removed/${open.id}/restore`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${open.name} restored (${RESTORE_REASONS.find(([c]) => c === code)?.[1] ?? code})`) },
        body: JSON.stringify({ reasonCode: code, reason: text.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify(`${open.name} restored${j?.grants_reopened ? ` · ${j.grants_reopened} office(s) reopened` : ""}`);
      setOpen(null); setCode(""); setText("");
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <Panel title="Removed staff" right={`${changes.length} change${changes.length === 1 ? "" : "s"}`}>
      {changes.length ? (
        <DTable cols={["When", "Staff id", "Name", "What was done", "Reason", "Tied to", "By", ...(may ? ["|num"] : [])]} rows={changes.slice(0, 300).map((c) => [
          <span key="w" className="tnum sub2">{when(c.at)}</span>,
          <span key="i" className="tnum b700">{c.staff_number ?? "—"}</span>,
          <span key="n">{c.name}</span>,
          <span key="a"><Pil kind={c.action === "STAFF_REMOVED" ? "bad" : c.action === "STAFF_DEACTIVATED" ? "warn" : "ok"}>{ACTION_WORD[c.action]}</Pil>{c.restored_at ? <div className="sub2">Restored {when(c.restored_at)}</div> : null}</span>,
          <span key="r" className="sub2">{c.reason_words ?? c.reason_code}{c.reason ? `: ${c.reason}` : ""}</span>,
          <span key="t" className="sub2">{c.action === "STAFF_RESTORED" ? "—" : tiesText(c.ties ?? [])}</span>,
          <span key="b" className="sub2">{c.actor_name ?? "—"}</span>,
          ...(may ? [c.restorable ? <Btn key="x" kind="ghost" onClick={() => { setProblem(null); setOpen(c); }}>Restore</Btn> : <span key="x" />] : []),
        ])} texts={changes.slice(0, 300).map((c) => `${c.name} ${c.staff_number ?? ""} ${c.reason_words ?? ""} ${c.reason ?? ""}`)} />
      ) : <PBody><div className="sub2">Nobody has been deleted or deactivated here.</div></PBody>}
      {open ? (
        <Modal title={`Restore ${open.name}`} sub="Back on the lists, able to sign in, and the offices the deactivation ended reopened." onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !!why} onClick={() => void restore()}>{busy ? "Restoring…" : "Restore"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <Field id="rst-reason" label="Reason">
            <select id="rst-reason" className="ctl" value={code} onChange={(e) => setCode(e.target.value)}>
              <option value="">Choose…</option>
              {RESTORE_REASONS.map(([c, label]) => <option key={c} value={c}>{label}</option>)}
            </select>
          </Field>
          <Field id="rst-text" label={code === "OTHER" ? "Describe the reason" : "Note (optional)"}>
            <input id="rst-text" className="ctl" value={text} maxLength={500} onChange={(e) => setText(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
