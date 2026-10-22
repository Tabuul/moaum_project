"use client";

/** V587: bulk inter-departmental transfer. The department's students come out as a template (their current placement filled in,
 *  the new one for the office to fill); the file comes back and every row is checked against the student's current record and the
 *  target — never put right silently — and previewed, with an error report to correct and upload again; the valid rows are
 *  made as one batch of programme swaps (IDT/YYYY/NNNNNN) by the officer who uploads the file, and the students move at once (V633).
 *  A batch left pending from before is decided on this screen by any officer who may make a swap. */
import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { COLUMNS, STATUS, errorReportRows, readTransferSheet, rowWords, templateRows, type CheckedRow, type TemplateStudent, type Validation } from "@/lib/transfer-bulk";

const BASE = "/api/bff/api/v1/transfers/bulk";
const PREPARERS = ["academic", "ict", "registrar", "dregistrar", "super"];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export interface Structure { faculties: { code: string; name: string; departments: { code: string; name: string; programmes: { code: string; name: string; levels: number[] }[] }[] }[] }
export interface Batch {
  id: string; ref: string; effective_session: string; filename: string | null; reason: string; approval_ref: string | null; partial: boolean; total: number;
  prepared: number; skipped: number; pending: number; completed: number; rejected: number; failed: number; prepared_by: string; prepared_by_name: string | null;
  prepared_office: string; prepared_at: string; status: string;
}
interface BatchRow { row_no: number; status: string; messages: { code: string; text?: string }[]; student: string | null; matric_no: string | null; swap_ref: string | null; swap_status: string | null; from_programme: string | null; from_level: number | null; to_programme: string | null; to_level: number | null; failure: string | null }
type BatchDetail = Batch & { rows: BatchRow[] };

const BATCH: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  PENDING_APPROVAL: ["Waiting for a decision", "warn"], PARTLY_DECIDED: ["Partly decided", "info"], COMPLETED: ["Completed", "ok"],
  COMPLETED_WITH_EXCEPTIONS: ["Completed with exceptions", "warn"], REJECTED: ["Rejected", "bad"], FAILED: ["Failed", "bad"], NOTHING_PREPARED: ["Nothing prepared", "grey"],
};

export function TransferBulk({ structure, batches, office }: { structure: Structure; batches: Batch[]; office: string | null; me: string | null }) {
  const router = useRouter();
  const mayPrepare = PREPARERS.includes(office ?? "");
  /** V633: who may make a swap decides a batch left pending from before, the officer who uploaded it included */
  const mayDecide = mayPrepare;
  const [tab, setTab] = useState<"upload" | "batches">("upload");
  // the template
  const [fac, setFac] = useState("");
  const [dept, setDept] = useState("");
  const [prog, setProg] = useState("");
  const [level, setLevel] = useState("");
  const [session, setSession] = useState("");
  const departments = useMemo(() => (fac ? structure.faculties.find((f) => f.code === fac)?.departments ?? [] : structure.faculties.flatMap((f) => f.departments)), [structure, fac]);
  const programmes = useMemo(() => (dept ? departments.find((d) => d.code === dept)?.programmes ?? [] : departments.flatMap((d) => d.programmes)), [departments, dept]);
  // the upload
  const [file, setFile] = useState<string | null>(null);
  const [rows, setRows] = useState<Record<string, string>[] | null>(null);
  const [check, setCheck] = useState<Validation | null>(null);
  const [reason, setReason] = useState("");
  const [approvalRef, setApprovalRef] = useState("");
  const [validOnly, setValidOnly] = useState(false);
  const [made, setMade] = useState<BatchDetail | null>(null);
  // a batch
  const [open, setOpen] = useState<BatchDetail | null>(null);
  const [note, setNote] = useState("");

  async function template() {
    const q = new URLSearchParams();
    if (fac) q.set("faculty", fac); if (dept) q.set("department", dept); if (prog) q.set("programme", prog); if (level) q.set("level", level);
    if (!fac && !dept && !prog) { notifyProblem({ status: 400, title: "Choose a faculty, department or programme", detail: "The template lists the students of the department chosen." }); return; }
    const r = await fetch(`${BASE}/template?${q}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    const students = j as TemplateStudent[];
    const where = [structure.faculties.find((f) => f.code === fac)?.name, departments.find((d) => d.code === dept)?.name, programmes.find((p) => p.code === prog)?.name, level ? `${level} Level` : null].filter(Boolean).join(" · ");
    downloadBlob(await brandedXlsx("Bulk Inter-Departmental Transfer", COLUMNS.map(([, l]) => l), templateRows(students, session.trim()), {
      serial: docSerial("IDT"), sub: `${where} · ${students.length} students · template 1 · generated ${new Date().toLocaleDateString("en-GB")}. Leave the Old columns as they are; fill the New Faculty, Department and Programme codes and the New Level for each student who transfers, and delete the rows of those who do not. A lower level needs the Reason.`,
    }), `transfer-template-${dept || fac || prog}-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function upload(f: File) {
    const grid = /\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
    const read = readTransferSheet(grid.map((r) => r.map((c) => String(c ?? ""))));
    setMade(null); setCheck(null);
    if (read.problem) { notifyProblem({ status: 400, title: "That file could not be read", detail: read.problem }); setRows(null); return; }
    setFile(f.name); setRows(read.rows);
    const r = await fetch(`${BASE}/validate`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ rows: read.rows, session: session.trim() || null }) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setCheck(j as Validation);
    setValidOnly(false);
  }

  async function errorReport() {
    if (!check) return;
    downloadBlob(await brandedXlsx("Bulk Transfer: Error Report", ["Row", "Student", "Matric number", "Status", "Current (department / programme / level)", "Uploaded old", "New", "Why"],
      errorReportRows(check.rows), { serial: docSerial("IDE"), sub: `${file ?? "the file"} · ${check.invalid} invalid of ${check.total}; correct the invalid rows and upload the file again` }),
      `transfer-errors-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function prepare() {
    if (!rows || !check) return;
    const r = await fetch(BASE, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason.trim()) },
      body: JSON.stringify({ rows, session: session.trim() || null, reason: reason.trim(), approvalRef: approvalRef.trim() || null, filename: file, validRowsOnly: validOnly }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setMade(j as BatchDetail);
    notify(`${(j as BatchDetail).ref}: ${(j as BatchDetail).completed} student${(j as BatchDetail).completed === 1 ? "" : "s"} transferred`);
    router.refresh();
  }

  async function openBatch(id: string) {
    const r = await fetch(`${BASE}/${id}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (r.ok) { setOpen(j as BatchDetail); setNote(""); } else notifyProblem(j ?? { status: r.status, title: r.statusText });
  }

  async function decide(approve: boolean) {
    if (!open) return;
    const r = await fetch(`/api/bff/api/v1/programme-swaps/batches/${open.id}/decide`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${open.ref} ${approve ? "approved" : "rejected"}${note.trim() ? `: ${note.trim()}` : ""}`) },
      body: JSON.stringify({ approve, note: note.trim() || null }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    const res = j as { decided: unknown[]; skipped: { student?: string; why?: string }[] };
    notify(`${open.ref}: ${res.decided.length} ${approve ? "approved" : "rejected"}${res.skipped.length ? `; ${res.skipped.length} not (${res.skipped.map((s) => `${s.student ?? ""}: ${s.why ?? ""}`).join("; ")})` : ""}`);
    await openBatch(open.id);
    router.refresh();
  }

  const preview = check ? check.rows : [];
  return (
    <>
      <Note kind="info" title="Students who moved department, recorded from a spreadsheet">
        Each row must name the student&rsquo;s current faculty, department, programme and level exactly as the record holds them; a row that does not is
        refused (SOURCE PROGRAMME MISMATCH), never put right. The valid rows become programme swaps under one batch, made at once by the officer who uploads
        the file: each student is on the new programme when the upload is done. Registrations, results, payments and the matriculation number stay as they are;
        a matriculation number that must follow is corrected separately under Matriculation Correction.
      </Note>
      <Tabs label="Bulk transfer" value={tab} onChange={setTab} items={[{ id: "upload", label: "New upload" }, { id: "batches", label: "Batches", count: batches.length }]} />
      {tab === "upload" ? (
        <>
          <Panel title="1 · The template: the department's students as they stand">
            <PBody>
              <div className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
                <Field id="tb-fac" label="Faculty">
                  <select id="tb-fac" className="ctl" value={fac} onChange={(e) => { setFac(e.target.value); setDept(""); setProg(""); }}>
                    <option value="">Choose…</option>
                    {structure.faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
                  </select>
                </Field>
                <Field id="tb-dept" label="Department">
                  <select id="tb-dept" className="ctl" value={dept} onChange={(e) => { setDept(e.target.value); setProg(""); }}>
                    <option value="">Any department</option>
                    {departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
                  </select>
                </Field>
                <Field id="tb-prog" label="Programme">
                  <select id="tb-prog" className="ctl" value={prog} onChange={(e) => setProg(e.target.value)} style={{ maxWidth: 280 }}>
                    <option value="">Any programme</option>
                    {programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                  </select>
                </Field>
                <Field id="tb-level" label="Level">
                  <select id="tb-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
                    <option value="">Any level</option>
                    {[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l}</option>)}
                  </select>
                </Field>
                <Field id="tb-session" label="Effective session" hint="Blank: the current session">
                  <input id="tb-session" className="ctl" value={session} onChange={(e) => setSession(e.target.value)} placeholder="2026/2027" style={{ maxWidth: 120 }} />
                </Field>
                <Btn kind="ghost" busyLabel="Generating template…" onClick={() => template()}>Download template</Btn>
              </div>
            </PBody>
          </Panel>
          <Panel title="2 · Upload the filled template">
            <PBody>
              <label className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>Choose the file (.xlsx or .csv)
                <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
              </label>
              {file ? <span className="sub2" style={{ marginLeft: 8 }}>{file}{rows ? ` · ${rows.length} row${rows.length === 1 ? "" : "s"} read` : ""}</span> : null}
            </PBody>
            {check ? (
              <>
                <PBody>
                  <Tiles items={[
                    ["Total rows", String(check.total), null, file ?? ""], ["Valid", String(check.valid), check.valid ? "var(--green-ink)" : null, "Nothing to look at"],
                    ["Warnings", String(check.warnings), check.warnings ? "var(--amber-ink)" : null, "Valid, with points to look at"],
                    ["Invalid", String(check.invalid), check.invalid ? "var(--red-ink)" : null, `${check.duplicates} on a duplicated student`],
                  ]} />
                  {check.invalid ? <div className="row row--tight mt-1" style={{ gap: 8, alignItems: "center" }}>
                    <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => errorReport()}>Download error report</Btn>
                    <span className="sub2">Correct the invalid rows in the file and upload it again; nothing is corrected silently.</span>
                  </div> : null}
                </PBody>
                <DTable cols={["Row|num", "Student", "Matric number", "Current department", "Uploaded old department", "New department", "Current programme", "New programme",
                  "Current level|num", "New level|num", "Status", "Message"]} rows={preview.map((r: CheckedRow) => [
                  <span key="n" className="tnum sub2">{r.row}</span>,
                  <span key="s">{r.student ?? "—"}</span>,
                  <span key="m" className="tnum">{r.matricNo ?? "—"}</span>,
                  <span key="cd">{r.current?.dept ?? "—"}</span>,
                  <span key="ud" className={r.current && r.uploadedOld.dept !== r.current.dept ? "ink-red b600" : ""}>{r.uploadedOld.dept ?? "—"}</span>,
                  <span key="nd">{r.new.dept ?? "—"}</span>,
                  <span key="cp" className="tnum">{r.current?.programme ?? "—"}</span>,
                  <span key="np"><span className="tnum">{r.new.programme ?? "—"}</span>{r.new.programmeName ? <div className="sub2">{r.new.programmeName}</div> : null}</span>,
                  <span key="cl" className="tnum">{r.current?.level ?? "—"}</span>,
                  <span key="nl" className="tnum">{r.new.level ?? "—"}</span>,
                  <Pil key="st" kind={STATUS[r.status][1]}>{STATUS[r.status][0]}</Pil>,
                  <span key="w" className="sub2">{rowWords(r) || (r.transferType === "INTER_FACULTY_TRANSFER" ? "Inter-faculty transfer" : "")}</span>,
                ])} texts={preview.map((r) => `${r.student ?? ""} ${r.matricNo ?? ""} ${rowWords(r)}`)} />
              </>
            ) : null}
          </Panel>
          {check && mayPrepare ? (
            <Panel title="3 · Transfer the students">
              <PBody>
                {made ? (
                  <Note kind="ok" title={`${made.ref}: ${made.completed} student${made.completed === 1 ? "" : "s"} transferred`}
                    action={<Btn kind="ghost" size="sm" onClick={() => { setTab("batches"); void openBatch(made.id); }}>Open the batch</Btn>}>
                    {made.skipped ? `${made.skipped} row${made.skipped === 1 ? "" : "s"} left out with the reason. ` : ""}Each student transferred is on the new programme now; the batch keeps every row with its result.
                  </Note>
                ) : (
                  <>
                    <div className="grid grid--2">
                      <Field id="tb-reason" label="Reason" required hint="Ten characters or more: the Senate's approval, the memo">
                        <input id="tb-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} />
                      </Field>
                      <Field id="tb-ref" label="Approval reference" hint="The Senate minute or memo number">
                        <input id="tb-ref" className="ctl" value={approvalRef} onChange={(e) => setApprovalRef(e.target.value)} maxLength={200} />
                      </Field>
                    </div>
                    {check.invalid ? (
                      <label className="row row--tight mt-1" style={{ alignItems: "center", gap: 8 }}>
                        <input type="checkbox" className="chk" checked={validOnly} onChange={(e) => setValidOnly(e.target.checked)} />
                        <span>Transfer the {check.valid + check.warnings} valid rows alone; the {check.invalid} invalid rows are left out and kept with the reason</span>
                      </label>
                    ) : null}
                    <div className="row row--tight mt-2" style={{ gap: 8, alignItems: "center" }}>
                      <Btn kind="primary" disabled={reason.trim().length < 10 || (check.invalid > 0 && !validOnly) || check.valid + check.warnings === 0} busyLabel="Transferring…"
                        onClick={() => prepare()}>{`Transfer ${check.valid + check.warnings} student${check.valid + check.warnings === 1 ? "" : "s"}`}</Btn>
                      <span className="sub2">{check.invalid && !validOnly ? "Correct the invalid rows, or choose to transfer the valid rows alone." : "Each row is checked again as its student is transferred."}</span>
                    </div>
                  </>
                )}
              </PBody>
            </Panel>
          ) : null}
        </>
      ) : (
        <Panel title="Bulk transfers" right={`${batches.length} · the latest first`}>
          {batches.length ? (
            <DTable cols={["S/N|num", "Batch", "Session", "Rows|num", "Prepared|num", "Waiting|num", "Completed|num", "Status", "By", "Prepared", "|num"]} rows={batches.map((b, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <span key="r" className="tnum b600">{b.ref}</span>,
              <span key="s" className="tnum">{b.effective_session}</span>,
              <span key="t" className="tnum">{b.total}</span>,
              <span key="p" className="tnum">{b.prepared}</span>,
              <span key="w" className="tnum">{b.pending}</span>,
              <span key="c" className="tnum">{b.completed}</span>,
              <Pil key="st" kind={BATCH[b.status]?.[1] ?? "grey"}>{BATCH[b.status]?.[0] ?? b.status}</Pil>,
              <span key="by" className="sub2">{b.prepared_by_name ?? b.prepared_office}</span>,
              <span key="at" className="sub2 tnum">{when(b.prepared_at)}</span>,
              <Btn key="o" kind="ghost" size="sm" onClick={() => openBatch(b.id)}>Open</Btn>,
            ])} texts={batches.map((b) => `${b.ref} ${b.filename ?? ""} ${b.reason}`)} />
          ) : <PBody><div className="sub2">No bulk transfer has been prepared yet.</div></PBody>}
        </Panel>
      )}
      {open ? (
        <Modal wide title={`${open.ref} · ${BATCH[open.status]?.[0] ?? open.status}`} sub={`${open.effective_session} · ${open.filename ?? "no file name"} · prepared by ${open.prepared_by_name ?? open.prepared_office}, ${when(open.prepared_at)}`}
          onClose={() => setOpen(null)}
          foot={<>
            {open.pending && mayDecide ? (
              <>
                <Btn kind="ghost" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => decide(false)}>Reject the waiting transfers</Btn>
                <Btn kind="primary" busyLabel="Approving…" onClick={() => decide(true)}>{`Approve ${open.pending} transfer${open.pending === 1 ? "" : "s"}`}</Btn>
              </>
            ) : null}
            <Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
          </>}>
          <KvGrid cls="grid--4" pairs={[["Rows", open.total], ["Prepared", open.prepared], ["Left out", open.skipped], ["Waiting", open.pending], ["Completed", open.completed], ["Rejected", open.rejected],
            ["Reason", open.reason], ["Approval reference", open.approval_ref ?? "—"]]} />
          {open.pending && mayDecide ? (
            <Field id="tb-note" label="Note on the decision" hint="Required to reject (ten characters or more)">
              <input id="tb-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} maxLength={2000} />
            </Field>
          ) : null}
          <DTable cols={["Row|num", "Student", "Matric number", "From", "To", "Swap", "Result", "Why"]} rows={open.rows.map((r) => [
            <span key="n" className="tnum sub2">{r.row_no}</span>,
            <span key="s">{r.student ?? "—"}</span>,
            <span key="m" className="tnum">{r.matric_no ?? "—"}</span>,
            <span key="f" className="tnum">{r.from_programme ? `${r.from_programme} · ${r.from_level}` : "—"}</span>,
            <span key="t" className="tnum">{r.to_programme ? `${r.to_programme} · ${r.to_level}` : "—"}</span>,
            <span key="w">{r.swap_ref ? <Link className="lnk tnum" href="/programme-swap">{r.swap_ref}</Link> : "—"}</span>,
            <Pil key="r" kind={r.status === "PREPARED" ? (r.swap_status === "COMPLETED" ? "ok" : r.swap_status === "PENDING_APPROVAL" ? "warn" : "bad") : "bad"}>
              {r.status === "PREPARED" ? (r.swap_status === "COMPLETED" ? "Transferred" : r.swap_status === "PENDING_APPROVAL" ? "Waiting" : r.swap_status ?? "—") : r.status === "SKIPPED" ? "Left out" : "Invalid"}</Pil>,
            <span key="y" className="sub2">{r.failure ?? r.messages.map((m) => m.text ?? m.code).join("; ")}</span>,
          ])} texts={open.rows.map((r) => `${r.student ?? ""} ${r.matric_no ?? ""}`)} />
        </Modal>
      ) : null}
    </>
  );
}
