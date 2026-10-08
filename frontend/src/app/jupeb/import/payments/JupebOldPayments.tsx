"use client";

/**
 * The payments made on the old JUPEB portal (V347), put on each student's record: the old portal's payment export judged
 * row by row first (a preview writes nothing), then each successful payment of a student found by the old App No — never by
 * name — posted once as a confirmed fee on the "Old portal" channel, its old reference kept. Failed, unreadable, unknown
 * and repeated rows are listed, never posted; a payment already on the record is skipped, so the same file may be uploaded
 * again. The JUPEB Office uploads; the Bursary's figures are not changed — the old portal's own receipts are what is
 * recorded. Once a student's old payments are on the record, the daily fee reminders resume for what is still owed.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { buildXlsx } from "@/lib/xlsx";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { FEE_KIND, day, jcall, naira, readSheet, when } from "@/lib/jupeb";

interface Row { row: number; appNo: string; reference: string; kind: string | null; amount: number | null; date: string | null; status: string; reason: string | null; applicationId: string | null; name: string | null }
interface Result { rows: Row[]; valid: number; review: number; exists: number; invalid: number; committed: boolean; ref: string | null; applied: number }
interface Posted { batch_ref: string; old_reference: string; app_no: string; kind: string; purpose: string | null; amount: number; paid_on: string; imported_at: string; reference: string; application_id: string; name: string; session: string }

const ALIASES: Record<string, string> = {
  "app no": "appNo", "application no": "appNo", "application number": "appNo", "app number": "appNo", "reg no": "appNo",
  "reference": "reference", "payment reference": "reference", "transaction reference": "reference", "ref": "reference", "rrr": "reference", "transaction id": "reference", "receipt no": "reference",
  "purpose": "purpose", "payment item": "purpose", "payment for": "purpose", "description": "purpose", "item": "purpose", "fee": "purpose",
  "amount": "amount", "amount paid": "amount", "date": "date", "payment date": "date", "date paid": "date", "transaction date": "date",
  "status": "status", "payment status": "status", "semester": "semester", "instalment": "semester", "installment": "semester",
};
const STATUS: Record<string, [string, "ok" | "warn" | "bad" | "grey"]> = {
  VALID: ["Ready", "ok"], REVIEW: ["Purpose unclear", "warn"], INVALID: ["Not posted", "bad"], UNMATCHED: ["No such student", "bad"], DUPLICATE: ["Repeated in the file", "grey"], EXISTS: ["Already on the record", "grey"],
};

export function JupebOldPayments({ canWrite }: { canWrite: boolean }) {
  const [dayFirst, setDayFirst] = useState(true);
  const [file, setFile] = useState<string | null>(null);
  const [rows, setRows] = useState<Record<string, string | number>[]>([]);
  const [preview, setPreview] = useState<Result | null>(null);
  const [done, setDone] = useState<{ applied: number; refs: string[] } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [posted, setPosted] = useState<Posted[] | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<Posted[]>("/api/v1/jupeb/office/old-portal-payments").then((r) => { if (!live) return; if (r.ok) setPosted(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [tick]);

  async function judge(list: Record<string, string | number>[], name: string | null, dmy: boolean) {
    setBusy("Checking the rows…");
    try {
      const all: Row[] = [];
      const sum = { valid: 0, review: 0, invalid: 0, exists: 0 };
      for (let i = 0; i < list.length; i += 500) {
        const r = await jcall<Result>("/api/v1/jupeb/office/old-portal-payments/import", "POST", { rows: list.slice(i, i + 500), dayFirst: dmy, commit: false, fileName: name });
        if (!r.ok) { notifyProblem(r.problem); return; }
        all.push(...r.data.rows); sum.valid += r.data.valid; sum.review += r.data.review; sum.invalid += r.data.invalid; sum.exists += r.data.exists;
      }
      setPreview({ rows: all, ...sum, committed: false, ref: null, applied: 0 });
    } finally { setBusy(null); }
  }
  async function pick(f: File | undefined) {
    if (!f) return;
    setDone(null); setPreview(null);
    const list = await readSheet(f, ALIASES);
    if (!list.length) { notifyProblem({ status: 400, title: "No rows found. The file needs a header row with App No, Reference, Purpose, Amount and Date." }); return; }
    setFile(f.name); setRows(list);
    await judge(list, f.name, dayFirst);
  }
  async function post() {
    if (!preview) return;
    const ready = new Set(preview.rows.filter((r) => r.status === "VALID").map((r) => String(r.row)));
    const toSend = rows.filter((r) => ready.has(String(r.row)));
    const refs: string[] = [];
    let applied = 0;
    try {
      for (let i = 0; i < toSend.length; i += 500) {
        setBusy(`Posting… ${Math.min(i + 500, toSend.length)} of ${toSend.length}`);
        const r = await jcall<Result>("/api/v1/jupeb/office/old-portal-payments/import", "POST", { rows: toSend.slice(i, i + 500), dayFirst, commit: true, fileName: file },
          "JUPEB payments made on the old portal put on the record");
        if (!r.ok) { notifyProblem(r.problem); break; }
        applied += r.data.applied; if (r.data.ref) refs.push(r.data.ref);
      }
    } finally { setBusy(null); }
    setDone({ applied, refs });
    if (applied) notify(`${applied} payment${applied === 1 ? "" : "s"} put on the record.`);
    setTick((t) => t + 1);
  }
  async function exportNotPosted() {
    if (!preview) return;
    const byRow = new Map(rows.map((r) => [String(r.row), r]));
    const bad = preview.rows.filter((r) => r.status !== "VALID" && r.status !== "EXISTS");
    downloadBlob(await brandedXlsx("JUPEB old-portal payments not posted", ["Row", "App No", "Reference", "Purpose", "Amount", "Date", "Status", "Why"],
      bad.map((b) => { const o = byRow.get(String(b.row)) ?? {}; return [b.row, String(o.appNo ?? ""), String(o.reference ?? ""), String(o.purpose ?? ""), String(o.amount ?? ""), String(o.date ?? ""), b.status, b.reason ?? ""]; }),
      { sheetName: "Not posted", serial: docSerial("JUPEBOLDPAY") }), "jupeb-old-payments-not-posted.xlsx");
  }
  function template() {
    downloadBlob(buildXlsx(["App No", "Reference", "Purpose", "Amount", "Date", "Status"], [["JUP/2024/0012", "OLD-1234567", "School Fees 1st Instalment", "75000", "12/11/2024", "Success"]], "Payments"),
      "jupeb-old-portal-payments-template.xlsx");
  }
  async function exportPosted() {
    if (!posted) return;
    downloadBlob(await brandedXlsx("JUPEB payments from the old portal", ["Session", "App No", "Student", "Fee", "Old reference", "Portal reference", "Amount", "Paid on", "Upload", "Uploaded"],
      posted.map((p) => [p.session, p.app_no, p.name, FEE_KIND[p.kind] ?? p.kind, p.old_reference, p.reference, Number(p.amount), p.paid_on, p.batch_ref, when(p.imported_at)]),
      { sheetName: "Old payments", serial: docSerial("JUPEBOLDPAY") }), "jupeb-old-portal-payments.xlsx");
  }
  return (
    <>
      <PageHead eyebrow={<Link href="/jupeb/import">← Old-portal students</Link>}
        description="The old JUPEB portal's payment export, put on each student's record: matched by the old App No only, each successful payment posted once as a confirmed fee with its old reference kept. Upload the students first." />
      {done ? <Note kind={done.applied ? "ok" : "info"} title={`${done.applied} payment${done.applied === 1 ? "" : "s"} put on the record`}>{done.refs.length ? `Upload ${done.refs.join(", ")}. The students' fee reminders now follow what is still owed.` : "Nothing new was posted."}</Note> : null}
      {canWrite ? (
        <Panel title="1 · The file">
          <PBody>
            <div className="grid grid--3">
              <Field id="opp-dates" label="Dates written as" hint="When both numbers are 12 or less"><select id="opp-dates" className="ctl" value={dayFirst ? "dmy" : "mdy"}
                onChange={(e) => { const dmy = e.target.value === "dmy"; setDayFirst(dmy); if (rows.length) void judge(rows, file, dmy); }}>
                <option value="dmy">Day/month/year</option><option value="mdy">Month/day/year</option></select></Field>
            </div>
            <div className="row mt-2">
              <label className="btn btn--primary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>Choose the payment export (Excel or CSV)
                <input type="file" hidden accept=".xlsx,.csv" disabled={!!busy} onChange={(e) => { void pick(e.target.files?.[0]); e.target.value = ""; }} /></label>
              <Btn kind="ghost" onClick={template}>Template</Btn>
              {file ? <span className="sub2">{file} · {rows.length} rows</span> : null}
              {busy ? <span className="sub2">{busy}</span> : null}
            </div>
            <p className="sub2 mt-2">Columns read: App No, Reference, Purpose (application, status checking, acceptance, school fees first / second instalment or full), Semester where the file has it, Amount, Date and Status.
              &ldquo;School fees&rdquo; that names no instalment is posted as the full fee only when it covers it; otherwise it is listed for you to say which.
              A row the old portal marks as failed or pending is never posted. The amount posted is the old portal&rsquo;s receipt; the Bursary&rsquo;s fee settings are not changed.</p>
          </PBody>
        </Panel>
      ) : <Note kind="info" title="The JUPEB Office uploads the old portal's payments">You may read what has been put on the record below.</Note>}
      {preview ? (
        <Panel title={`2 · Check — ${preview.valid} ready, ${preview.review} purpose unclear, ${preview.invalid} not posted, ${preview.exists} already on the record`}
          right={<span className="row">
            {preview.invalid + preview.review ? <Btn kind="ghost" onClick={() => void exportNotPosted()}>Rows not posted (Excel)</Btn> : null}
            <Btn kind="primary" disabled={!!busy || preview.valid === 0 || !!done} onClick={() => void post()}>{`Put ${preview.valid} payment${preview.valid === 1 ? "" : "s"} on the record`}</Btn>
          </span>}>
          <PBody>
            {preview.review ? <Note kind="info" title="Purpose unclear">Write what each was for in the Purpose column (application, acceptance, school fees first or second instalment) and upload the file again.</Note> : null}
            <DTable pageSize={50} cols={["Row|num", "App No", "Student", "Reference", "Fee", "Amount|num", "Date", "Status", "Why"]}
              texts={preview.rows.map((r) => `${r.appNo} ${r.name ?? ""} ${r.reference} ${r.reason ?? ""}`)}
              rows={preview.rows.map((r) => [r.row, r.appNo || "—", r.name ?? "—", r.reference || "—", r.kind ? FEE_KIND[r.kind] ?? r.kind : "—", r.amount == null ? "—" : naira(r.amount),
                r.date ? day(r.date) : "—", <Pil key="s" kind={(STATUS[r.status] ?? [r.status, "grey"])[1]}>{(STATUS[r.status] ?? [r.status])[0]}</Pil>, r.reason ?? "—"])} />
          </PBody>
        </Panel>
      ) : null}
      <Panel title={`On the record${posted ? ` — ${posted.length}` : ""}`} right={posted?.length ? <Btn kind="ghost" onClick={() => void exportPosted()}>Excel</Btn> : null}>
        <PBody>
          {!posted ? <p className="sub2">Loading…</p> : !posted.length ? <p className="sub2">No payment from the old portal is on the record yet.</p> : (
            <DTable pageSize={25} cols={["Session", "App No", "Student", "Fee", "Old reference", "Amount|num", "Paid on", "Upload"]}
              texts={posted.map((p) => `${p.app_no} ${p.name} ${p.old_reference} ${p.reference}`)}
              rows={posted.map((p) => [p.session, p.app_no, <Link key="n" href={`/jupeb/applications/${p.application_id}`}>{p.name}</Link>, FEE_KIND[p.kind] ?? p.kind, p.old_reference,
                naira(p.amount), day(p.paid_on), p.batch_ref])} />
          )}
        </PBody>
      </Panel>
    </>
  );
}
