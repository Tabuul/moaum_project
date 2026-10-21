"use client";

/** V607: the Students Account Officer's Old Fees History uploads, held for the Bursar's approval. The officer sees each upload
 *  sent and what became of it, and may withdraw one not yet decided; the Bursar reads it (its summary and rows, the rows as
 *  Excel), checks what approving would do (the import run and undone — nothing written), then approves it (loaded a few parts at a
 *  time, as the Bursar's own upload is) or rejects it with the reason. Nothing of an upload is on the records before the approval. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { addTotals, mayDecide, mayWithdraw, STATE_WORD, type ImportTotals, type OldFeesUpload } from "@/lib/old-fees-uploads";

const API = "/api/bff/api/v1/finance/legacy-fees/uploads";
const naira = (n: number | string | null | undefined) => (n == null ? "—" : `₦${Number(n).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`);
const when = (s: string | null | undefined) => (s ? new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
type Row = Record<string, string | number | null | undefined>;
const cell = (r: Row, ...keys: string[]) => { for (const k of keys) { const v = r[k]; if (v != null && String(v).trim() !== "") return String(v); } return ""; };

async function post(path: string, body: unknown, reason: string): Promise<Record<string, unknown>> {
  const r = await fetch(`${API}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw (j ?? { status: r.status, title: r.statusText || "The portal refused the request" }) as Problem;
  return (j ?? {}) as Record<string, unknown>;
}

function TotalsTiles({ t }: { t: ImportTotals }) {
  return (
    <Tiles items={[
      ["Rows", String(t.rows ?? 0), null, "Read"],
      ["Settled", String(t.cleared ?? 0), "var(--green-ink)", "Payments recorded"],
      ["No such student", String(t.no_student ?? 0), (t.no_student ?? 0) ? "var(--red-ink)" : null, "The number is not on the register"],
      ["Nothing to settle", String(t.no_due ?? 0), null, "No amount and no fee schedule"],
      ["Already on record", String((t.duplicates ?? 0) + (t.matched ?? 0)), null, "Skipped, not overwritten"],
      ["Added beside another", String(t.separate ?? 0), null, "A make-up or second part-payment"],
      ["Taken over", String(t.taken_over ?? 0), null, "Recorded by Payment History Upload"],
      ["No usable date", String(t.undated ?? 0), (t.undated ?? 0) ? "var(--red-ink)" : null, "Loaded, dated that day"],
    ]} />
  );
}

/** office: the office acting on the page; tick: a change made elsewhere on the page; onChanged: told when an approval loads payments */
export function OldFeesUploads({ office, tick: changed = 0, onChanged }: { office: string | null; tick?: number; onChanged?: () => void }) {
  const [list, setList] = useState<{ counts: { state: string; n: number }[]; rows: OldFeesUpload[] } | null>(null);
  const [tick, setTick] = useState(0);
  const [open, setOpen] = useState<OldFeesUpload | null>(null);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [check, setCheck] = useState<{ totals: ImportTotals; parts: number } | null>(null);
  const [note, setNote] = useState("");
  const [rejecting, setRejecting] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [progress, setProgress] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`${API}?size=100`, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      if (!r || !r.ok) { if (r?.status !== 403) notifyProblem((j ?? { status: r?.status ?? 0, title: "The uploads could not be read" }) as Problem); return; }
      setList(j);
    })();
    return () => { alive = false; };
  }, [tick, changed]);

  const waiting = Number(list?.counts.find((c) => c.state === "PENDING")?.n ?? 0);
  const bursar = office === "bursar";
  if (!list || (!list.rows.length && !bursar && office !== "studentaccounts")) return null;

  async function show(u: OldFeesUpload) {
    setOpen(u); setRows(null); setCheck(null); setNote(""); setRejecting(false);
    const r = await fetch(`${API}/${u.id}/rows?limit=200`, { cache: "no-store" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (r?.ok) setRows((j as { rows: Row[] }).rows);
  }

  function close() { if (!busy) { setOpen(null); setRows(null); setCheck(null); } }

  async function excel(u: OldFeesUpload) {
    setBusy("excel");
    try {
      const all: Row[] = [];
      for (let off = 0; off < u.row_count; off += 5000) {
        const r = await fetch(`${API}/${u.id}/rows?offset=${off}&limit=5000`, { cache: "no-store" });
        if (!r.ok) { notifyProblem({ status: r.status, title: "The rows could not be read" }); return; }
        all.push(...((await r.json()) as { rows: Row[] }).rows);
      }
      const blob = await brandedXlsx(`Old fees upload ${u.ref}`, ["Matriculation Number", "Session", "Semester", "Level", "Amount Paid", "Purpose / Payment Item", "Paid On", "Payment number", "Channel", "Note"],
        all.map((x) => [cell(x, "matric", "matric_no", "matno"), cell(x, "session"), cell(x, "semester", "sem"), cell(x, "level"), cell(x, "amount", "paid"),
          cell(x, "purpose", "item"), cell(x, "paidOn", "paid_on", "date"), cell(x, "receiptNo", "payref", "reference", "receipt"), cell(x, "channel"), cell(x, "note")]),
        { sheetName: "Upload rows", serial: docSerial("OFU"), sub: `${u.ref} · ${u.file_name ?? "file"} · ${STATE_WORD[u.state][0]}` });
      downloadBlob(blob, `old-fees-upload-${u.ref}.xlsx`);
    } finally { setBusy(null); }
  }

  async function runCheck(u: OldFeesUpload) {
    setBusy("check"); setCheck(null);
    let totals: ImportTotals = {};
    try {
      for (let from = 1; from <= u.parts; from += 2) {
        setProgress(`Checking part ${from} of ${u.parts}…`);
        const j = await post(`/${u.id}/check`, { fromPart: from, parts: 2 }, `Old fees upload ${u.ref} checked before approval (nothing written)`);
        totals = addTotals(totals, j.totals as ImportTotals);
      }
      setCheck({ totals, parts: u.parts });
    } catch (e) { notifyProblem(e as Problem); }
    finally { setBusy(null); setProgress(null); }
  }

  async function approve(u: OldFeesUpload) {
    setBusy("approve");
    try {
      for (let round = 0; round < 10000; round++) {
        const j = await post(`/${u.id}/approve`, { note: note.trim() || null, parts: 2 }, `Old fees upload ${u.ref} approved and loaded${note.trim() ? `: ${note.trim()}` : ""}`);
        const left = Number(j.remaining ?? 0);
        setProgress(`Loading: ${Number(j.applied_parts ?? 0)} of ${Number(j.parts ?? u.parts)} parts${left ? `, ${left} to go` : ""}`);
        if (j.state === "APPROVED" || !left) {
          const t = (j.result ?? {}) as ImportTotals;
          notify(`Upload ${u.ref} approved: ${Number(t.cleared ?? 0).toLocaleString()} payments recorded`);
          break;
        }
      }
      setOpen(null); setTick((t) => t + 1); onChanged?.();
    } catch (e) { notifyProblem(e as Problem); setTick((t) => t + 1); }
    finally { setBusy(null); setProgress(null); }
  }

  async function reject(u: OldFeesUpload) {
    if (note.trim().length < 10) { notifyProblem({ status: 400, title: "Say why the upload is rejected, in ten characters or more — the officer is told." }); return; }
    setBusy("reject");
    try {
      await post(`/${u.id}/reject`, { reason: note.trim() }, `Old fees upload ${u.ref} rejected: ${note.trim()}`);
      notify(`Upload ${u.ref} rejected; the officer is told`);
      setOpen(null); setTick((t) => t + 1);
    } catch (e) { notifyProblem(e as Problem); }
    finally { setBusy(null); }
  }

  async function withdraw(u: OldFeesUpload) {
    setBusy("withdraw");
    try {
      await post(`/${u.id}/withdraw`, { reason: note.trim() || null }, `Old fees upload ${u.ref} withdrawn`);
      notify(`Upload ${u.ref} withdrawn`);
      setOpen(null); setTick((t) => t + 1);
    } catch (e) { notifyProblem(e as Problem); }
    finally { setBusy(null); }
  }

  return (
    <>
      <Panel title="Uploads for the Bursar's approval" right={waiting ? `${waiting} waiting` : `${list.rows.length} on record`}>
        <PBody>
          <div className="sub2">
            {bursar
              ? <>The Students Account Officer&rsquo;s uploads wait here: nothing of them is on the records until you approve. Open one to read its rows, check what approving would do, then approve or reject it.</>
              : <>An upload you send waits here for the Bursar: nothing of it is on the records until the Bursar approves it. You are told when it is approved or rejected.</>}
          </div>
        </PBody>
        {list.rows.length ? (
          <DTable cols={["Upload", "Sent by", "Rows|num", "Sessions", "Amount stated|num", "State", "|num"]} rows={list.rows.map((u) => [
            <span key="u"><b className="tnum">{u.ref}</b><div className="sub2">{u.file_name ?? "—"}</div></span>,
            <span key="b">{u.uploaded_by_name ?? "—"}<div className="sub2">{when(u.submitted_at ?? u.uploaded_at)}</div></span>,
            <span key="r" className="tnum">{u.row_count.toLocaleString()}{u.students != null ? <div className="sub2">{u.students} student{u.students === 1 ? "" : "s"}</div> : null}</span>,
            <span key="s" className="sub2">{u.sessions ?? "—"}</span>,
            <span key="a" className="tnum">{naira(u.amount)}</span>,
            <span key="st"><Pil kind={STATE_WORD[u.state][1]}>{STATE_WORD[u.state][0]}</Pil>
              {u.decided_at ? <div className="sub2">{u.decided_by_name ?? ""} {when(u.decided_at)}</div> : null}
              {u.decision_note && (u.state === "REJECTED" || u.state === "APPROVED") ? <div className="sub2">{u.decision_note}</div> : null}</span>,
            <Btn key="o" kind={mayDecide(office, u) ? "primary" : "ghost"} size="sm" onClick={() => void show(u)}>{mayDecide(office, u) ? "Review" : "Open"}</Btn>,
          ])} />
        ) : <PBody><div className="sub2">No upload has been sent for approval.</div></PBody>}
      </Panel>

      {open ? (
        <Modal wide title={`Old fees upload ${open.ref}`} sub={`${open.file_name ?? "file"} · ${STATE_WORD[open.state][0]}`} onClose={close}
          foot={<>
            <Btn kind="ghost" disabled={!!busy} onClick={close}>Close</Btn>
            <Btn kind="ghost" disabled={!!busy} busy={busy === "excel"} onClick={() => void excel(open)}>Rows as Excel</Btn>
            {mayWithdraw(office, open) ? <Btn kind="secondary" disabled={!!busy} busy={busy === "withdraw"} onClick={() => void withdraw(open)}>Withdraw</Btn> : null}
            {mayDecide(office, open) && open.state === "PENDING" ? <Btn kind="secondary" disabled={!!busy} busy={busy === "reject"} onClick={() => (rejecting ? void reject(open) : setRejecting(true))}>{rejecting ? "Reject with this reason" : "Reject"}</Btn> : null}
            {mayDecide(office, open) && !rejecting ? <Btn kind="primary" disabled={!!busy} busy={busy === "approve"} busyLabel={progress ?? "Loading…"} onClick={() => void approve(open)}>{open.state === "APPROVING" ? "Carry on loading" : `Approve and load ${open.row_count.toLocaleString()} rows`}</Btn> : null}
          </>}>
          <Tiles items={[
            ["Rows", open.row_count.toLocaleString(), null, `${open.parts} part${open.parts === 1 ? "" : "s"}${open.item_codes ? ` · ${open.item_codes} item codes` : ""}`],
            ["Students", String(open.students ?? "—"), null, "By the number given"],
            ["Amount stated", naira(open.amount), null, "A blank amount is cleared in full"],
            ["Sent by", open.uploaded_by_name ?? "—", null, when(open.submitted_at ?? open.uploaded_at)],
          ]} />
          {open.sessions ? <div className="sub2 mt-1">Sessions: {open.sessions}</div> : null}
          {open.note ? <div className="sub2 mt-1">The officer&rsquo;s note: {open.note}</div> : null}
          {open.state === "APPROVED" && open.result ? <><Note kind="ok" title={`Approved and loaded ${when(open.completed_at)}`}>{open.decision_note ?? ""}</Note><TotalsTiles t={open.result} /></> : null}
          {open.state === "REJECTED" ? <Note kind="bad" title={`Rejected ${when(open.decided_at)}`}>{open.decision_note}</Note> : null}
          {open.state === "APPROVING" ? <Note kind="info" title="Being loaded">{open.applied_parts} of {open.parts} parts are on the records; carry on to load the rest.</Note> : null}

          {mayDecide(office, open) && open.state === "PENDING" ? (
            <div className="mt-2">
              <Btn kind="secondary" size="sm" disabled={!!busy} busy={busy === "check"} busyLabel={progress ?? "Checking…"} onClick={() => void runCheck(open)}>Check what approving would do</Btn>
              <span className="sub2" style={{ marginLeft: 8 }}>The import is run on the rows and undone: nothing is written.</span>
              {check ? <><div className="sub2 mt-1">Each part is checked on its own, so a payment repeated in two parts reads as new in each.</div><TotalsTiles t={check.totals} /></> : null}
            </div>
          ) : null}

          {rows ? (
            <div className="tablewrap mt-2" tabIndex={0} style={{ maxHeight: 280, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl--data">
                <thead><tr><th>Matric</th><th>Session</th><th>Sem</th><th>Amount</th><th>For</th><th>Paid on</th><th>Payment number</th></tr></thead>
                <tbody>{rows.map((x, i) => (
                  <tr key={i}><td className="tnum">{cell(x, "matric", "matric_no", "matno")}</td><td className="tnum">{cell(x, "session")}</td><td className="tnum">{cell(x, "semester", "sem") || "—"}</td>
                    <td className="tnum">{cell(x, "amount", "paid") || "cleared in full"}</td><td className="sub2">{cell(x, "purpose", "item") || "School fees"}</td>
                    <td className="sub2">{cell(x, "paidOn", "paid_on", "date") || "—"}</td><td className="sub2 tnum">{cell(x, "receiptNo", "payref", "reference", "receipt") || "—"}</td></tr>
                ))}</tbody>
              </table>
              {open.row_count > rows.length ? <div className="sub2" style={{ padding: 6 }}>The first {rows.length.toLocaleString()} of {open.row_count.toLocaleString()} rows; take every row as Excel.</div> : null}
            </div>
          ) : <div className="sub2 mt-2">Reading the rows…</div>}

          {mayDecide(office, open) || mayWithdraw(office, open) ? (
            <Field id="ofu-note" label={rejecting ? "Why it is rejected (the officer is told)" : mayWithdraw(office, open) ? "Why it is withdrawn (optional)" : "Note with the approval (optional)"} required={rejecting}>
              <textarea id="ofu-note" className="ctl" rows={2} maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} disabled={!!busy} />
            </Field>
          ) : null}
          {progress && busy !== "check" ? <div className="sub2 tnum">{progress}</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
