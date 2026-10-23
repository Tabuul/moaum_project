"use client";

/**
 * V648: removing a fee line, or several. The database decides first (POST …/schedule/remove/preview): a line never used — no student
 * charged by it, no invoice, payment or ledger entry made under it — may be removed permanently; any other is archived (deactivated):
 * ended, kept on record, no longer charged. The screen never decides. A reason is required. Nothing financial is touched: payments,
 * invoices (payment references), receipts and the ledger stay as they are.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Pil, Spinner } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { notify, toast } from "@/components/proto/Toast";
import { semesterText } from "@/lib/student-portal";
import { REMOVE_REASONS, USED_WORDS, previewWords, reasonReady, type RemovalAnswer, type RemoveMode } from "@/lib/fee-setup";

export interface RemoveLine {
  id: string; item: string; amount: number | string; level: number | null; faculty_name: string | null; department_name?: string | null;
  programme_name: string | null; semester: number | null; spillover?: boolean; spill_year?: number | null; entry_mode?: string | null;
}

const naira = (n: number | string | null | undefined) => (n == null ? "—" : `₦${Number(n).toLocaleString("en-NG")}`);

export function FeeLineRemove({ session, lines, permissions, onClose, onDone }: {
  session: string; lines: RemoveLine[]; permissions: string[]; onClose: () => void; onDone: (a: RemovalAnswer) => void;
}) {
  const mayRemove = permissions.includes("REMOVE_FEE_STRUCTURE");
  const mayDeactivate = permissions.includes("DEACTIVATE_FEE_STRUCTURE");
  const [preview, setPreview] = useState<RemovalAnswer | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [words, setWords] = useState("");
  const [applying, setApplying] = useState<RemoveMode | null>(null);
  const ids = lines.map((l) => l.id);
  const idKey = ids.join(",");

  // the backend's answer first: "Checking financial dependencies…" until it is in
  useEffect(() => {
    let alive = true;
    fetch(`/api/bff/api/v1/finance/sessions/${session}/schedule/remove/preview`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ids: idKey.split(","), mode: "AUTO" }),
    }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setFailed((j as Problem | null)?.detail ?? r.statusText); return; }
      setPreview(j as RemovalAnswer);
    }).catch(() => { if (alive) setFailed("The portal could not reach the server."); });
    return () => { alive = false; };
  }, [session, idKey]);

  const single = lines.length === 1 ? lines[0] : null;
  const row = single && preview ? preview.rows.find((r) => r.line_id === single.id) ?? null : null;
  const removable = !!row && row.outcome === "REMOVED";
  const archivedAlready = !!row && row.outcome === "ALREADY_ARCHIVED";
  const financial = !!row && (row.used_by === "INVOICE" || row.used_by === "PAYMENT" || row.used_by === "LEDGER");

  async function apply(mode: RemoveMode) {
    setApplying(mode);
    try {
      const label = REMOVE_REASONS.find(([c]) => c === code)?.[1] ?? code;
      const r = await fetch(`/api/bff/api/v1/finance/sessions/${session}/schedule/remove`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${label}${words.trim() ? `: ${words.trim()}` : ""}`) },
        body: JSON.stringify({ ids, mode, reasonCode: code, reason: words.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p = j as Problem | null;
        toast.error("Fee structure could not be removed.", `No financial records were changed.${p?.detail ? ` ${p.detail}` : ""}`);
        return;
      }
      const a = j as RemovalAnswer;
      const n = (k: number, one: string, many: string) => `${k.toLocaleString()} ${k === 1 ? one : many}`;
      if (a.REMOVED + a.ARCHIVED === 0) {
        toast.error("Fee structure could not be removed.", "No financial records were changed.");
      } else if (lines.length === 1) {
        notify(a.REMOVED ? "Fee structure removed successfully." : "Fee structure archived successfully.");
      } else {
        notify([a.REMOVED ? `${n(a.REMOVED, "fee structure", "fee structures")} removed` : null, a.ARCHIVED ? `${n(a.ARCHIVED, "fee structure", "fee structures")} archived` : null]
          .filter(Boolean).join(", ") + " successfully.");
      }
      onDone(a);
    } finally {
      setApplying(null);
    }
  }

  const reason = (
    <>
      <Field id="rm-reason" label="Reason" hint="Required. Kept with the change and in the audit trail">
        <select id="rm-reason" className="ctl" value={code} onChange={(e) => setCode(e.target.value)}>
          <option value="">— choose the reason —</option>
          {REMOVE_REASONS.map(([c, w]) => <option key={c} value={c}>{w}</option>)}
        </select>
      </Field>
      <Field id="rm-words" label={code === "OTHER" ? "Describe the reason" : "Note (optional)"} hint={code === "OTHER" ? "Ten characters at least" : "e.g. 600 Level was added in error"}>
        <input id="rm-words" className="ctl" value={words} maxLength={400} onChange={(e) => setWords(e.target.value)} />
      </Field>
    </>
  );
  const ready = reasonReady(code, words) && applying === null;
  const protects = <div className="sub2 mt-2">Removing this configuration will not delete existing payments, invoices, receipts or financial history.</div>;
  const cancel = <Btn kind="ghost" onClick={onClose} disabled={applying !== null}>Cancel</Btn>;
  const busyWord = applying === "REMOVE" ? "Removing fee structure…" : applying === "DEACTIVATE" ? "Archiving fee structure…" : "Removing and archiving…";

  const details = single ? <FeeLineDetails session={session} line={single} /> : null;

  if (!preview) {
    return (
      <Modal title={single ? "Remove fee structure?" : "Remove the selected fee structures?"} sub={session} onClose={onClose} foot={<>{cancel}</>}>
        {details}
        {failed ? <Note kind="bad" title="The financial dependencies could not be checked">{failed} Nothing was changed.</Note>
          : <div className="row row--tight mt-2 sub2" role="status" aria-live="polite"><Spinner /> Checking financial dependencies…</div>}
      </Modal>
    );
  }

  if (single && row) {
    if (archivedAlready) {
      return (
        <Modal title="Already archived" sub={session} onClose={onClose} foot={<Btn kind="ghost" onClick={onClose}>Close</Btn>}>
          {details}
          <Note kind="info" title="This fee structure is archived already">{row.message}</Note>
        </Modal>
      );
    }
    if (removable && mayRemove) {
      return (
        <Modal title="Remove fee structure?" sub={session} onClose={onClose}
          foot={<>{cancel}<span className="grow" /><Btn kind="urgent" disabled={!ready} busy={applying === "REMOVE"} busyLabel={busyWord} onClick={() => apply("REMOVE")}>Remove fee structure</Btn></>}>
          <div className="sub2">You are about to remove this fee structure:</div>
          {details}
          <Note kind="ok" title="Never used">{row.message.replace(" It is removed permanently.", "")} It is removed permanently.</Note>
          {protects}
          {reason}
        </Modal>
      );
    }
    return (
      <Modal title={removable ? "Deactivate fee structure?" : financial ? "Remove not permitted — used by financial records" : "Remove not permitted — charged to students"} sub={session} onClose={onClose}
        foot={<>{cancel}<span className="grow" />{mayDeactivate ? <Btn kind="primary" disabled={!ready} busy={applying === "DEACTIVATE"} busyLabel={busyWord} onClick={() => apply("DEACTIVATE")}>Deactivate fee structure</Btn> : null}</>}>
        {details}
        {removable
          ? <Note kind="info" title="Your office deactivates fee structures">This line was never used, but removing it permanently is the Bursar&rsquo;s. Deactivating archives it: it stays on record and is no longer charged.</Note>
          : <Note kind="bad" title={financial ? "Used by financial records" : "Part of what students owe now"}>{row.message.replace(/ It cannot be permanently deleted; you may deactivate \(archive\) it instead\.$/, "")} It cannot be permanently deleted{mayDeactivate ? "; deactivate (archive) it instead: it stays on record and is no longer charged" : ""}.</Note>}
        {protects}
        {mayDeactivate ? reason : <div className="sub2 mt-2">Your office may not deactivate fee structures.</div>}
      </Modal>
    );
  }

  // several lines: what each will be, then one confirmation
  const mode: RemoveMode | null = mayRemove && mayDeactivate ? "AUTO" : mayDeactivate ? "DEACTIVATE" : null;
  return (
    <Modal wide title="Remove the selected fee structures?" sub={session} onClose={onClose}
      foot={<>{cancel}<span className="grow" />{mode ? <Btn kind="urgent" disabled={!ready} busy={applying !== null} busyLabel={busyWord} onClick={() => apply(mode)}>{mode === "AUTO" ? "Remove selected" : "Deactivate selected"}</Btn> : null}</>}>
      <Note kind={preview.ARCHIVED || preview.CANNOT_REMOVE ? "info" : "ok"} title={previewWords(preview)[0]}>
        <ul className="m-0">{previewWords(preview).slice(1).map((w) => <li key={w}>{w}</li>)}</ul>
        {mode === "DEACTIVATE" ? <div className="mt-2">Your office deactivates: every selected line is archived, the ones never used included.</div> : null}
      </Note>
      <DTable pageSize={10} cols={["Item", "Level", "Programme / faculty", "Amount|num", "Use", "Will be"]} rows={preview.rows.map((r) => {
        const l = lines.find((x) => x.id === r.line_id);
        const will = mode === "DEACTIVATE" && r.outcome === "REMOVED" ? "ARCHIVED" : r.outcome;
        return [
          <span key="i">{r.item ?? l?.item ?? "—"}</span>,
          <span key="l" className="tnum">{r.level ? `${r.level}` : "Every"}</span>,
          <span key="p" className="sub2">{l?.programme_name ?? l?.faculty_name ?? "Every student"}</span>,
          <span key="a" className="tnum">{naira(r.amount)}</span>,
          r.used_by ? <Pil key="u" kind={USED_WORDS[r.used_by][1]} title={r.message}>{USED_WORDS[r.used_by][0]}</Pil> : <span key="u" className="sub2">—</span>,
          <Pil key="w" kind={will === "REMOVED" ? "bad" : will === "ARCHIVED" ? "warn" : "grey"}>{will === "REMOVED" ? "Removed" : will === "ARCHIVED" ? "Archived" : will === "ALREADY_ARCHIVED" ? "Archived already" : will === "NOT_FOUND" ? "Not on the schedule" : "Kept"}</Pil>,
        ];
      })} />
      {protects}
      {mode ? reason : <div className="sub2 mt-2">Your office may not remove or deactivate fee structures.</div>}
    </Modal>
  );
}

/** the line as the confirmation and the view show it */
export function FeeLineDetails({ session, line, status }: { session: string; line: RemoveLine; status?: string }) {
  return (
    <dl className="mt-2 mb-0" style={{ display: "grid", gridTemplateColumns: "max-content 1fr", gap: "var(--s-1) var(--s-4)" }}>
      <dt className="sub2">Item</dt><dd className="m-0">{line.item}</dd>
      <dt className="sub2">Faculty</dt><dd className="m-0">{line.faculty_name ?? "Every faculty"}</dd>
      {line.department_name ? <><dt className="sub2">Department</dt><dd className="m-0">{line.department_name}</dd></> : null}
      <dt className="sub2">Programme</dt><dd className="m-0">{line.programme_name ?? "Every programme"}</dd>
      <dt className="sub2">Level</dt><dd className="m-0">{line.level ? `${line.level} Level${line.spillover ? (line.spill_year ? ` (SP${line.spill_year})` : " (spillover)") : ""}` : "Every level"}</dd>
      <dt className="sub2">Session</dt><dd className="m-0">{session}</dd>
      <dt className="sub2">Semester</dt><dd className="m-0">{line.semester ? semesterText(line.semester).replace("Semester: ", "") : "Whole session"}</dd>
      {line.entry_mode ? <><dt className="sub2">Entry mode</dt><dd className="m-0">{line.entry_mode === "CCE" ? "CCE (part-time)" : line.entry_mode}</dd></> : null}
      <dt className="sub2">Amount</dt><dd className="m-0 tnum">{naira(line.amount)}</dd>
      {status ? <><dt className="sub2">Status</dt><dd className="m-0">{status}</dd></> : null}
    </dl>
  );
}
