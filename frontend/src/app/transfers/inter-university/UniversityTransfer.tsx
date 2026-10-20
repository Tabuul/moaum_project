"use client";

/** V588: inter-university transfer. Students coming from another university (INCOMING) and students leaving for one (OUTGOING) are
 *  recorded from a spreadsheet: an outgoing template lists a department's students as they stand, an incoming one is blank; the file
 *  comes back and every row is checked — the student found first by the matriculation or JAMB number, so no one is placed twice; an
 *  outgoing row against the record, an incoming one against its target — previewed, with an error report to correct and upload again;
 *  the valid rows are prepared as one batch (IUT/YYYY/NNNNNN) that another officer of the Academic Office or the Registry decides on
 *  this screen, transfer by transfer or all at once. Nothing on a record changes until then. The list of universities is kept here. */
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
import type { Structure } from "../bulk/TransferBulk";
import {
  ACTION, COLUMNS, DIRECTION, STATUS, TRANSFER, errorReportRows, outcome, outgoingRows, readUniversitySheet, reportRows, rowWords,
  type CheckedRow, type TemplateStudent, type Transfer, type Validation,
} from "@/lib/university-transfer";

const BASE = "/api/bff/api/v1/transfers/inter-university";
const KEEPERS = ["academic", "registrar", "dregistrar", "super"];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export interface University { code: string; name: string; country: string; active: boolean; transfers: number }
export interface Batch {
  id: string; ref: string; effective_session: string; filename: string | null; reason: string; approval_ref: string | null; total: number; prepared: number;
  left_out: number; incoming: number; outgoing: number; pending: number; completed: number; rejected: number; prepared_by: string; prepared_by_name: string | null;
  prepared_office: string; prepared_at: string; status: string;
}
type BatchDetail = Batch & { transfers: Transfer[]; leftOut: { row_no: number; uploaded: Record<string, string>; messages: { code: string; text?: string }[] }[] };

const BATCH: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  PENDING_APPROVAL: ["Waiting for a decision", "warn"], PARTLY_DECIDED: ["Partly decided", "info"], COMPLETED: ["Completed", "ok"],
  COMPLETED_WITH_EXCEPTIONS: ["Completed with exceptions", "warn"], REJECTED: ["Rejected", "bad"], NOTHING_PREPARED: ["Nothing prepared", "grey"],
};

async function answer(r: Response) {
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
  return j;
}

export function UniversityTransfer({ structure, batches, universities, office, me }: { structure: Structure; batches: Batch[]; universities: University[]; office: string | null; me: string | null }) {
  const router = useRouter();
  const mayKeep = KEEPERS.includes(office ?? "");
  const [tab, setTab] = useState<"upload" | "batches" | "transfers" | "universities">("upload");
  // the templates
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
  // the transfers
  const [q, setQ] = useState("");
  const [direction, setDirection] = useState("");
  const [found, setFound] = useState<Transfer[] | null>(null);
  // the universities
  const [uni, setUni] = useState<{ code: string; name: string; country: string; active: boolean; editing: boolean }>({ code: "", name: "", country: "Nigeria", active: true, editing: false });

  async function outgoingTemplate() {
    if (!fac && !dept && !prog) { notifyProblem({ status: 400, title: "Choose a faculty, department or programme", detail: "The outgoing template lists the students of the department chosen." }); return; }
    const p = new URLSearchParams();
    if (fac) p.set("faculty", fac); if (dept) p.set("department", dept); if (prog) p.set("programme", prog); if (level) p.set("level", level);
    const students = (await answer(await fetch(`${BASE}/template?${p}`, { cache: "no-store" }))) as TemplateStudent[] | null;
    if (!students) return;
    const where = [structure.faculties.find((f) => f.code === fac)?.name, departments.find((d) => d.code === dept)?.name, programmes.find((x) => x.code === prog)?.name, level ? `${level} Level` : null].filter(Boolean).join(" · ");
    downloadBlob(await brandedXlsx("Inter-University Transfer: Outgoing", COLUMNS.map(([, l]) => l), outgoingRows(students, session.trim()), {
      serial: docSerial("IUT"), sub: `${where} · ${students.length} students · generated ${new Date().toLocaleDateString("en-GB")}. Keep the rows of the students who transfer out and delete the others; leave their faculty, department, programme and level as they are; give the University Code of the destination from the list of universities.`,
    }), `iut-outgoing-${dept || fac || prog}-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function incomingTemplate() {
    downloadBlob(await brandedXlsx("Inter-University Transfer: Incoming", COLUMNS.map(([, l]) => l), [], {
      serial: docSerial("IUT"), sub: `Generated ${new Date().toLocaleDateString("en-GB")}. One row a student: Transfer Direction INCOMING, the JAMB Number (required: it is how the student is found, so no one is placed twice), the name as SURNAME, Other names, the Faculty, Department and Programme codes and the Level the student comes into, the previous university's code from the list of universities, and the programme and level there. Sex is M or F; the date of birth is written YYYY-MM-DD.`,
    }), `iut-incoming-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function upload(f: File) {
    const grid = /\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
    const read = readUniversitySheet(grid.map((r) => r.map((c) => String(c ?? ""))));
    setMade(null); setCheck(null);
    if (read.problem) { notifyProblem({ status: 400, title: "That file could not be read", detail: read.problem }); setRows(null); return; }
    setFile(f.name); setRows(read.rows);
    const j = await answer(await fetch(`${BASE}/validate`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ rows: read.rows, session: session.trim() || null }) }));
    if (!j) return;
    setCheck(j as Validation);
    setValidOnly(false);
  }

  async function errorReport() {
    if (!check) return;
    downloadBlob(await brandedXlsx("Inter-University Transfer: Error Report", ["Row", "Direction", "Student", "Matric number", "JAMB number", "University", "Status",
      "Current (faculty / department / programme / level)", "Here (faculty / department / programme / level)", "The decision would", "Why"], errorReportRows(check.rows),
      { serial: docSerial("IUE"), sub: `${file ?? "the file"} · ${check.invalid} invalid of ${check.total}; correct the invalid rows and upload the file again` }),
      `iut-errors-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function prepare() {
    if (!rows || !check) return;
    const j = (await answer(await fetch(BASE, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason.trim()) },
      body: JSON.stringify({ rows, session: session.trim() || null, reason: reason.trim(), approvalRef: approvalRef.trim() || null, filename: file, validRowsOnly: validOnly }),
    }))) as BatchDetail | null;
    if (!j) return;
    setMade(j);
    notify(`${j.ref}: ${j.prepared} transfer${j.prepared === 1 ? "" : "s"} prepared; another officer decides them`);
    router.refresh();
  }

  async function openBatch(id: string) {
    const j = (await answer(await fetch(`${BASE}/${id}`, { cache: "no-store" }))) as BatchDetail | null;
    if (j) { setOpen(j); setNote(""); }
  }

  async function decideBatch(approve: boolean) {
    if (!open) return;
    const j = (await answer(await fetch(`${BASE}/${open.id}/decide`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${open.ref} ${approve ? "approved" : "rejected"}${note.trim() ? `: ${note.trim()}` : ""}`) },
      body: JSON.stringify({ approve, note: note.trim() || null }),
    }))) as { decided: unknown[]; skipped: { row: number; why: string }[] } | null;
    if (!j) return;
    notify(`${open.ref}: ${j.decided.length} ${approve ? "approved" : "rejected"}${j.skipped.length ? `; ${j.skipped.length} not (${j.skipped.map((s) => `row ${s.row}: ${s.why}`).join("; ")})` : ""}`);
    await openBatch(open.id);
    router.refresh();
  }

  async function decideOne(t: Transfer, approve: boolean) {
    if (!open) return;
    const j = await answer(await fetch(`${BASE}/transfers/${t.id}/decide`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${t.batch_ref} row ${t.row_no} ${approve ? "approved" : "rejected"}${note.trim() ? `: ${note.trim()}` : ""}`) },
      body: JSON.stringify({ approve, note: note.trim() || null }),
    }));
    if (!j) return;
    notify(`Row ${t.row_no} (${t.student ?? t.jamb_reg_no ?? ""}): ${approve ? "approved" : "rejected"}`);
    await openBatch(open.id);
    router.refresh();
  }

  async function search() {
    const p = new URLSearchParams();
    if (q.trim()) p.set("q", q.trim()); if (direction) p.set("direction", direction);
    const j = (await answer(await fetch(`${BASE}/transfers?${p}`, { cache: "no-store" }))) as Transfer[] | null;
    if (j) setFound(j);
  }

  async function report() {
    if (!found) return;
    downloadBlob(await brandedXlsx("Inter-University Transfers", ["S/N", "Batch", "Direction", "Student", "Matric number", "JAMB number", "Other university",
      "Programme there", "Level there", "Programme here", "Level here", "Session", "Outcome", "Decided by", "Decided on"], reportRows(found),
      { serial: docSerial("IUR"), sub: `${found.length} transfer${found.length === 1 ? "" : "s"}${q.trim() ? ` matching “${q.trim()}”` : ""}${direction ? ` · ${DIRECTION[direction as "INCOMING"]}` : ""} · generated ${new Date().toLocaleDateString("en-GB")}` }),
      `iut-report-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function saveUniversity() {
    const j = await answer(await fetch(`${BASE}/universities`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${uni.editing ? "University put right" : "University added"}: ${uni.code.trim().toUpperCase()}`) },
      body: JSON.stringify({ code: uni.code.trim().toUpperCase(), name: uni.name.trim(), country: uni.country.trim() || null, active: uni.active }),
    }));
    if (!j) return;
    notify(`${uni.code.trim().toUpperCase()} ${uni.editing ? "put right" : "added to the list"}`);
    setUni({ code: "", name: "", country: "Nigeria", active: true, editing: false });
    router.refresh();
  }

  const preview = check ? check.rows : [];
  const pendingMine = open ? open.prepared_by === me : false;
  return (
    <>
      <Note kind="info" title="Students who come from, or leave for, another university">
        The student is looked for first by the matriculation or JAMB number, so no one is placed twice: a student already on the register is that record, an applicant
        under the JAMB number is linked, and only otherwise is a record made — admitted by transfer, at the level the row states, its matriculation number to follow
        under Matriculation Management. A student going out keeps the record and its history; the status becomes Transferred out. Every row is decided by another
        officer of the Academic Office or the Registry; nothing changes before then.
      </Note>
      <Tabs label="Inter-university transfer" value={tab} onChange={setTab} items={[{ id: "upload", label: "New upload" }, { id: "batches", label: "Batches", count: batches.length },
        { id: "transfers", label: "Transfers" }, { id: "universities", label: "Universities", count: universities.filter((u) => u.active).length }]} />
      {tab === "upload" ? (
        <>
          <Panel title="1 · The templates">
            <PBody>
              <div className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
                <Field id="iu-fac" label="Faculty">
                  <select id="iu-fac" className="ctl" value={fac} onChange={(e) => { setFac(e.target.value); setDept(""); setProg(""); }}>
                    <option value="">Choose…</option>
                    {structure.faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
                  </select>
                </Field>
                <Field id="iu-dept" label="Department">
                  <select id="iu-dept" className="ctl" value={dept} onChange={(e) => { setDept(e.target.value); setProg(""); }}>
                    <option value="">Any department</option>
                    {departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
                  </select>
                </Field>
                <Field id="iu-prog" label="Programme">
                  <select id="iu-prog" className="ctl" value={prog} onChange={(e) => setProg(e.target.value)} style={{ maxWidth: 280 }}>
                    <option value="">Any programme</option>
                    {programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                  </select>
                </Field>
                <Field id="iu-level" label="Level">
                  <select id="iu-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
                    <option value="">Any level</option>
                    {[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l}</option>)}
                  </select>
                </Field>
                <Field id="iu-session" label="Effective session" hint="Blank: the current session">
                  <input id="iu-session" className="ctl" value={session} onChange={(e) => setSession(e.target.value)} placeholder="2026/2027" style={{ maxWidth: 120 }} />
                </Field>
                <Btn kind="ghost" busyLabel="Generating template…" onClick={() => outgoingTemplate()}>Download outgoing template</Btn>
                <Btn kind="ghost" busyLabel="Generating template…" onClick={() => incomingTemplate()}>Download incoming template</Btn>
              </div>
              <div className="sub2 mt-1">One file may hold both directions. The other university is named by its code from the <button type="button" className="lnk" onClick={() => setTab("universities")}>list of universities</button>.</div>
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
                    ["Total rows", String(check.total), null, `${check.incoming} incoming · ${check.outgoing} outgoing`],
                    ["Valid", String(check.valid), check.valid ? "var(--green-ink)" : null, "Nothing to look at"],
                    ["Warnings", String(check.warnings), check.warnings ? "var(--amber-ink)" : null, "Valid, with points to look at"],
                    ["Invalid", String(check.invalid), check.invalid ? "var(--red-ink)" : null, `${check.duplicates} on a duplicated student`],
                    ["New records", String(check.newRecords), null, "Made at the decision"],
                  ]} />
                  {check.invalid ? <div className="row row--tight mt-1" style={{ gap: 8, alignItems: "center" }}>
                    <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => errorReport()}>Download error report</Btn>
                    <span className="sub2">Correct the invalid rows in the file and upload it again; nothing is corrected silently.</span>
                  </div> : null}
                </PBody>
                <DTable cols={["Row|num", "Direction", "Student", "Number", "University", "On the record", "Here", "The decision would", "Status", "Message"]} rows={preview.map((r: CheckedRow) => [
                  <span key="n" className="tnum sub2">{r.row}</span>,
                  <span key="d">{r.direction ? DIRECTION[r.direction] : "—"}</span>,
                  <span key="s">{r.student ?? "—"}</span>,
                  <span key="m" className="tnum">{r.matricNo ?? r.jambRegNo ?? "—"}</span>,
                  <span key="u"><span className="tnum">{r.university ?? "—"}</span>{r.universityName ? <div className="sub2">{r.universityName}</div> : null}</span>,
                  <span key="c" className="tnum">{r.current ? `${r.current.programme ?? "—"} · ${r.current.level ?? "—"}` : "—"}</span>,
                  <span key="h"><span className="tnum">{r.placement.programme ? `${r.placement.programme} · ${r.placement.level ?? "—"}` : "—"}</span>
                    {r.placement.programmeName ? <div className="sub2">{r.placement.programmeName}</div> : null}</span>,
                  <span key="a" className="sub2">{r.action && r.status !== "INVALID" ? ACTION[r.action] : "—"}</span>,
                  <Pil key="st" kind={STATUS[r.status][1]}>{STATUS[r.status][0]}</Pil>,
                  <span key="w" className="sub2">{rowWords(r)}</span>,
                ])} texts={preview.map((r) => `${r.student ?? ""} ${r.matricNo ?? ""} ${r.jambRegNo ?? ""} ${rowWords(r)}`)} />
              </>
            ) : null}
          </Panel>
          {check && mayKeep ? (
            <Panel title="3 · Prepare the transfers">
              <PBody>
                {made ? (
                  <Note kind="ok" title={`${made.ref}: ${made.prepared} transfer${made.prepared === 1 ? "" : "s"} prepared`}
                    action={<Btn kind="ghost" size="sm" onClick={() => { setTab("batches"); void openBatch(made.id); }}>Open the batch</Btn>}>
                    {made.left_out ? `${made.left_out} row${made.left_out === 1 ? "" : "s"} left out with the reason. ` : ""}Another officer of the Academic Office or the Registry decides the batch; nothing on a record changes until then.
                  </Note>
                ) : (
                  <>
                    <div className="grid grid--2">
                      <Field id="iu-reason" label="Reason" required hint="Ten characters or more: the Senate's approval, the transfer policy">
                        <input id="iu-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} />
                      </Field>
                      <Field id="iu-ref" label="Approval reference" hint="The Senate minute or memo number">
                        <input id="iu-ref" className="ctl" value={approvalRef} onChange={(e) => setApprovalRef(e.target.value)} maxLength={200} />
                      </Field>
                    </div>
                    {check.invalid ? (
                      <label className="row row--tight mt-1" style={{ alignItems: "center", gap: 8 }}>
                        <input type="checkbox" className="chk" checked={validOnly} onChange={(e) => setValidOnly(e.target.checked)} />
                        <span>Prepare the {check.valid + check.warnings} valid rows alone; the {check.invalid} invalid rows are left out and kept with the reason</span>
                      </label>
                    ) : null}
                    <div className="row row--tight mt-2" style={{ gap: 8, alignItems: "center" }}>
                      <Btn kind="primary" disabled={reason.trim().length < 10 || (check.invalid > 0 && !validOnly) || check.valid + check.warnings === 0} busyLabel="Preparing…"
                        onClick={() => prepare()}>{`Prepare ${check.valid + check.warnings} transfer${check.valid + check.warnings === 1 ? "" : "s"}`}</Btn>
                      <span className="sub2">{check.invalid && !validOnly ? "Correct the invalid rows, or choose to prepare the valid rows alone." : "Each row is checked again as it is prepared, and again when it is decided."}</span>
                    </div>
                  </>
                )}
              </PBody>
            </Panel>
          ) : null}
        </>
      ) : tab === "batches" ? (
        <Panel title="Inter-university transfers" right={`${batches.length} · the latest first`}>
          {batches.length ? (
            <DTable cols={["S/N|num", "Batch", "Session", "Incoming|num", "Outgoing|num", "Waiting|num", "Completed|num", "Status", "By", "Prepared", "|num"]} rows={batches.map((b, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <span key="r" className="tnum b600">{b.ref}</span>,
              <span key="s" className="tnum">{b.effective_session}</span>,
              <span key="i" className="tnum">{b.incoming}</span>,
              <span key="o" className="tnum">{b.outgoing}</span>,
              <span key="w" className="tnum">{b.pending}</span>,
              <span key="c" className="tnum">{b.completed}</span>,
              <Pil key="st" kind={BATCH[b.status]?.[1] ?? "grey"}>{BATCH[b.status]?.[0] ?? b.status}</Pil>,
              <span key="by" className="sub2">{b.prepared_by_name ?? b.prepared_office}</span>,
              <span key="at" className="sub2 tnum">{when(b.prepared_at)}</span>,
              <Btn key="op" kind="ghost" size="sm" onClick={() => openBatch(b.id)}>Open</Btn>,
            ])} texts={batches.map((b) => `${b.ref} ${b.filename ?? ""} ${b.reason}`)} />
          ) : <PBody><div className="sub2">No inter-university transfer has been prepared yet.</div></PBody>}
        </Panel>
      ) : tab === "transfers" ? (
        <Panel title="Transfers" right={found ? `${found.length} found` : undefined}>
          <PBody>
            <form className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void search(); }}>
              <Field id="iu-q" label="Search" hint="A batch, a matriculation or JAMB number, a name, a university">
                <input id="iu-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} style={{ minWidth: 240 }} />
              </Field>
              <Field id="iu-dir" label="Direction">
                <select id="iu-dir" className="ctl" value={direction} onChange={(e) => setDirection(e.target.value)}>
                  <option value="">Both</option><option value="INCOMING">Incoming</option><option value="OUTGOING">Outgoing</option>
                </select>
              </Field>
              <Btn kind="primary" type="submit" busyLabel="Searching…">Search</Btn>
              {found?.length ? <Btn kind="ghost" busyLabel="Preparing Excel..." onClick={() => report()}>Download report</Btn> : null}
            </form>
          </PBody>
          {found ? (found.length ? (
            <DTable cols={["S/N|num", "Batch", "Direction", "Student", "Number", "Other university", "Here", "Outcome", "Decided"]} rows={found.map((t, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <span key="b" className="tnum">{t.batch_ref}</span>,
              <span key="d">{DIRECTION[t.direction]}</span>,
              <span key="s">{t.student_id ? <Link className="lnk" href={`/students/${t.student_id}`}>{t.student ?? "—"}</Link> : (t.student ?? "—")}</span>,
              <span key="m" className="tnum">{t.matric_no ?? t.jamb_reg_no ?? "—"}</span>,
              <span key="u">{t.university}{t.other_programme ? <div className="sub2">{t.other_programme}{t.other_level ? ` · ${t.other_level}` : ""}</div> : null}</span>,
              <span key="h" className="tnum">{t.programme_code ? `${t.programme_code} · ${t.level ?? "—"}` : "—"}</span>,
              <Pil key="o" kind={TRANSFER[t.status][1]}>{outcome(t)}</Pil>,
              <span key="w" className="sub2">{t.decided_at ? `${t.decided_by_name ?? ""}, ${when(t.decided_at)}` : "—"}</span>,
            ])} texts={found.map((t) => `${t.batch_ref} ${t.student ?? ""} ${t.matric_no ?? ""} ${t.jamb_reg_no ?? ""} ${t.university}`)} />
          ) : <PBody><div className="sub2">No transfer matches.</div></PBody>) : null}
        </Panel>
      ) : (
        <Panel title="Universities" right={`${universities.length} on the list`}>
          {mayKeep ? (
            <PBody>
              <div className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
                <Field id="iu-ucode" label="Code" hint="Capital letters and digits">
                  <input id="iu-ucode" className="ctl" value={uni.code} disabled={uni.editing} onChange={(e) => setUni({ ...uni, code: e.target.value.toUpperCase() })} maxLength={16} style={{ maxWidth: 130 }} />
                </Field>
                <Field id="iu-uname" label="Name">
                  <input id="iu-uname" className="ctl" value={uni.name} onChange={(e) => setUni({ ...uni, name: e.target.value })} maxLength={200} style={{ minWidth: 280 }} />
                </Field>
                <Field id="iu-ucountry" label="Country">
                  <input id="iu-ucountry" className="ctl" value={uni.country} onChange={(e) => setUni({ ...uni, country: e.target.value })} maxLength={80} style={{ maxWidth: 140 }} />
                </Field>
                <label className="row row--tight" style={{ gap: 6, alignItems: "center", paddingBottom: 6 }}>
                  <input type="checkbox" className="chk" checked={uni.active} onChange={(e) => setUni({ ...uni, active: e.target.checked })} /><span>In use</span>
                </label>
                <Btn kind="primary" disabled={uni.code.trim().length < 2 || uni.name.trim().length < 3} busyLabel="Saving…" onClick={() => saveUniversity()}>{uni.editing ? "Save" : "Add to the list"}</Btn>
                {uni.editing ? <Btn kind="ghost" onClick={() => setUni({ code: "", name: "", country: "Nigeria", active: true, editing: false })}>Cancel</Btn> : null}
              </div>
            </PBody>
          ) : null}
          <DTable cols={["S/N|num", "Code", "Name", "Country", "Transfers|num", "Standing", "|num"]} rows={universities.map((u, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="c" className="tnum b600">{u.code}</span>,
            <span key="m">{u.name}</span>,
            <span key="k">{u.country}</span>,
            <span key="t" className="tnum">{u.transfers}</span>,
            <Pil key="a" kind={u.active ? "ok" : "grey"}>{u.active ? "In use" : "Not in use"}</Pil>,
            mayKeep ? <Btn key="e" kind="ghost" size="sm" onClick={() => setUni({ code: u.code, name: u.name, country: u.country, active: u.active, editing: true })}>Edit</Btn> : <span key="e" />,
          ])} texts={universities.map((u) => `${u.code} ${u.name} ${u.country}`)} />
        </Panel>
      )}
      {open ? (
        <Modal wide title={`${open.ref} · ${BATCH[open.status]?.[0] ?? open.status}`} sub={`${open.effective_session} · ${open.filename ?? "no file name"} · prepared by ${open.prepared_by_name ?? open.prepared_office}, ${when(open.prepared_at)}`}
          onClose={() => setOpen(null)}
          foot={<>
            {open.pending && mayKeep ? (
              pendingMine ? <span className="sub2 grow">You prepared this batch: another officer decides it.</span> : <>
                <Btn kind="ghost" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => decideBatch(false)}>Reject the waiting transfers</Btn>
                <Btn kind="primary" busyLabel="Approving…" onClick={() => decideBatch(true)}>{`Approve ${open.pending} transfer${open.pending === 1 ? "" : "s"}`}</Btn>
              </>
            ) : null}
            <Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
          </>}>
          <KvGrid cls="grid--4" pairs={[["Rows", open.total], ["Incoming", open.incoming], ["Outgoing", open.outgoing], ["Left out", open.left_out], ["Waiting", open.pending],
            ["Completed", open.completed], ["Rejected", open.rejected], ["Approval reference", open.approval_ref ?? "—"], ["Reason", open.reason]]} />
          {open.pending && mayKeep && !pendingMine ? (
            <Field id="iu-note" label="Note on the decision" hint="Required to reject (ten characters or more)">
              <input id="iu-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} maxLength={2000} />
            </Field>
          ) : null}
          <DTable cols={["Row|num", "Direction", "Student", "Number", "Other university", "Here", "Outcome", "|num"]} rows={open.transfers.map((t) => [
            <span key="n" className="tnum sub2">{t.row_no}</span>,
            <span key="d">{DIRECTION[t.direction]}</span>,
            <span key="s">{t.student_id ? <Link className="lnk" href={`/students/${t.student_id}`}>{t.student ?? "—"}</Link> : (t.student ?? "—")}</span>,
            <span key="m" className="tnum">{t.matric_no ?? t.jamb_reg_no ?? "—"}</span>,
            <span key="u">{t.university}{t.other_programme ? <div className="sub2">{t.other_programme}{t.other_level ? ` · ${t.other_level}` : ""}</div> : null}</span>,
            <span key="h" className="tnum">{t.programme_code ? `${t.programme_code} · ${t.level ?? "—"}` : "—"}</span>,
            <span key="o"><Pil kind={TRANSFER[t.status][1]}>{outcome(t)}</Pil>{t.decision_note ? <div className="sub2">{t.decision_note}</div> : null}</span>,
            t.status === "PENDING_APPROVAL" && mayKeep && !pendingMine ? (
              <span key="x" className="row row--tight" style={{ gap: 4 }}>
                <Btn kind="ghost" size="sm" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => decideOne(t, false)}>Reject</Btn>
                <Btn kind="ghost" size="sm" busyLabel="Approving…" onClick={() => decideOne(t, true)}>Approve</Btn>
              </span>
            ) : <span key="x" />,
          ])} texts={open.transfers.map((t) => `${t.student ?? ""} ${t.matric_no ?? ""} ${t.jamb_reg_no ?? ""}`)} />
          {open.leftOut.length ? (
            <>
              <div className="b600 mt-2">Left out as invalid</div>
              <DTable cols={["Row|num", "Number", "Why"]} rows={open.leftOut.map((l) => [
                <span key="n" className="tnum sub2">{l.row_no}</span>,
                <span key="m" className="tnum">{l.uploaded.matric_no ?? l.uploaded.jamb_reg_no ?? "—"}</span>,
                <span key="w" className="sub2">{l.messages.map((m) => m.text ?? m.code).join("; ")}</span>,
              ])} texts={open.leftOut.map((l) => `${l.uploaded.matric_no ?? ""} ${l.uploaded.jamb_reg_no ?? ""}`)} />
            </>
          ) : null}
        </Modal>
      ) : null}
    </>
  );
}
