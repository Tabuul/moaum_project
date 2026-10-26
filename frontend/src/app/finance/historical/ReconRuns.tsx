"use client";

/**
 * V665: clearance financial reconciliation runs. A run (CLEARANCE-RECON/YYYY/NNNNNN) reads the school-fee account of every student of
 * a population at once — the approved graduands awaiting final clearance, the students under final clearance, the graduates, or all
 * of them — narrowed by faculty, programme and session, and keeps each student's standing as it found it: cleared, owing, owing with a
 * payment outside school fees to look at, a period for review or awaiting the Bursar. A run changes nothing in the money; the rows
 * export to Excel and PDF with the University's header.
 */
import { useEffect, useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Spinner, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { can, naira, num, POPULATION_WORDS, RECON_HEAD, RECON_WORDS, reconRows, type Desk, type ReconPopulation, type ReconRow, type ReconRun, type ReconStatus } from "@/lib/historical-fees";
import { hfCall } from "./hf-call";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
interface RunPage { run: ReconRun; total: number; page: number; size: number; rows: ReconRow[] }

export function ReconRuns({ desk, faculties, programmes, onOpenStudent }: {
  desk: Desk; faculties: { code: string; name: string }[]; programmes: { code: string; name: string; faculty_code: string }[]; onOpenStudent: (id: string) => void;
}) {
  const [runs, setRuns] = useState<ReconRun[] | null>(null);
  const [f, setF] = useState({ population: "AWAITING_GRADUATION" as ReconPopulation, faculty: "", programme: "", admission: "", graduation: "" });
  const [open, setOpen] = useState<RunPage | null>(null);
  const [status, setStatus] = useState<ReconStatus | "">("");
  const [page, setPage] = useState(0);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tick, setTick] = useState(0);
  const mayRun = can(desk, "PROCESS_FINANCIAL_CLEARANCE");

  useEffect(() => {
    let alive = true;
    void hfCall<ReconRun[]>("/recon-runs").then((r) => { if (!alive) return; if (r.ok) setRuns(r.data); else setProblem(r.problem); });
    return () => { alive = false; };
  }, [tick]);

  async function read(id: string, st: ReconStatus | "", pg: number) {
    const qs = new URLSearchParams({ page: String(pg) });
    if (st) qs.set("status", st);
    const r = await hfCall<RunPage>(`/recon-runs/${id}?${qs}`);
    if (r.ok) { setOpen(r.data); setStatus(st); setPage(pg); setProblem(null); } else setProblem(r.problem);
  }

  async function start() {
    setProblem(null);
    const body: Record<string, string> = { population: f.population };
    for (const k of ["faculty", "programme", "admission", "graduation"] as const) if (f[k]) body[k] = f[k];
    const r = await hfCall<RunPage>("/recon-runs", { method: "POST", body, reason: `Clearance reconciliation run: ${POPULATION_WORDS[f.population].toLowerCase()}` });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(`${r.data.run.reference}: ${r.data.run.students.toLocaleString()} student(s) read`);
    setOpen(r.data); setStatus(""); setPage(0);
    setTick((n) => n + 1);
  }

  async function exportAs(format: "XLSX" | "PDF") {
    if (!open) return;
    const qs = new URLSearchParams({ export: "true" });
    if (status) qs.set("status", status);
    const r = await hfCall<RunPage>(`/recon-runs/${open.run.id}?${qs}`);
    if (!r.ok) { setProblem(r.problem); return; }
    const run = r.data.run;
    const title = "Clearance financial reconciliation";
    const meta: [string, string][] = [["Run", run.reference], ["Population", POPULATION_WORDS[run.population]], ["Run", `${when(run.run_at)} by ${run.run_by_name ?? run.run_office ?? "—"}`],
      ["Status shown", status ? RECON_WORDS[status][0] : "All"], ["Students", r.data.total.toLocaleString()],
      ["Totals", `assessed ${naira(run.assessed)} · paid ${naira(run.paid)} · waived ${naira(run.waived)} · outstanding ${naira(run.outstanding)}`]];
    const serial = docSerial("CRR");
    if (format === "XLSX") downloadBlob(await brandedXlsx(title, RECON_HEAD, reconRows(r.data.rows), { sheetName: "Reconciliation", serial, meta }), `${run.reference.replace(/\//g, "-")}.xlsx`);
    else brandedPrint(title, `${run.reference} · ${POPULATION_WORDS[run.population]}`, RECON_HEAD, reconRows(r.data.rows), serial, { meta, orientation: "landscape" });
  }

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {mayRun ? (
        <Panel title="Run a reconciliation">
          <PBody>
            <div className="sub2 mb-2">Each student&rsquo;s school fees of every session and semester are read afresh — assessed at the fees of the period, the verified
              payments, the approved waivers — and kept as found. Nothing in the money changes; a student who owes is cleared only by payment or an approved waiver.</div>
            <div className="row row--end" style={{ flexWrap: "wrap" }}>
              <Field id="crr-pop" label="Students">
                <select id="crr-pop" className="ctl" value={f.population} onChange={(e) => setF({ ...f, population: e.target.value as ReconPopulation })}>
                  {(Object.keys(POPULATION_WORDS) as ReconPopulation[]).map((k) => <option key={k} value={k}>{POPULATION_WORDS[k]}</option>)}
                </select>
              </Field>
              <Field id="crr-fac" label="Faculty">
                <select id="crr-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, programme: "" })}>
                  <option value="">Every faculty</option>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="crr-prog" label="Programme">
                <select id="crr-prog" className="ctl" value={f.programme} onChange={(e) => setF({ ...f, programme: e.target.value })}>
                  <option value="">Every programme</option>{programmes.filter((x) => !f.faculty || x.faculty_code === f.faculty).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="crr-adm" label="Admission session">
                <select id="crr-adm" className="ctl" value={f.admission} onChange={(e) => setF({ ...f, admission: e.target.value })}>
                  <option value="">Any</option>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Field>
              <Field id="crr-grad" label="Graduation session">
                <select id="crr-grad" className="ctl" value={f.graduation} onChange={(e) => setF({ ...f, graduation: e.target.value })}>
                  <option value="">Any</option>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Field>
              <Btn kind="primary" busyLabel="Reading every account…" onClick={start}>Run reconciliation</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      {open ? (
        <Panel title={open.run.reference} right={<span className="row row--tight">
          <Btn kind="ghost" busyLabel="Preparing…" onClick={() => exportAs("XLSX")}>Export (Excel)</Btn>
          <Btn kind="ghost" busyLabel="Preparing…" onClick={() => exportAs("PDF")}>PDF</Btn>
          <Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
        </span>}>
          <PBody>
            <div className="sub2 mb-1">{POPULATION_WORDS[open.run.population]} · run {when(open.run.run_at)} by {open.run.run_by_name ?? open.run.run_office ?? "—"}</div>
            {open.run.capped ? <Note kind="info" title="The first 5,000 students">The population is larger; narrow it by faculty, programme or session to read the rest.</Note> : null}
            <Tiles items={[
              ["Students", open.run.students.toLocaleString(), null, "Read in this run"],
              ["Cleared", open.run.cleared.toLocaleString(), open.run.cleared ? "var(--green-ink)" : null, "Nothing owed"],
              ["Owing", (open.run.owing + open.run.payment_review).toLocaleString(), open.run.owing + open.run.payment_review ? "var(--red-ink)" : null, `${naira(open.run.outstanding)} outstanding`],
              ["Requires review", (open.run.review + open.run.pending).toLocaleString(), open.run.review + open.run.pending ? "var(--amber-ink)" : null, "A period with no amount, or one awaiting the Bursar"],
            ]} />
            <div className="row mt-1" style={{ flexWrap: "wrap", gap: 6 }}>
              <Btn kind={status === "" ? "primary" : "ghost"} onClick={() => void read(open.run.id, "", 0)}>All</Btn>
              {(Object.keys(RECON_WORDS) as ReconStatus[]).map((k) => (
                <Btn key={k} kind={status === k ? "primary" : "ghost"} onClick={() => void read(open.run.id, k, 0)}>{RECON_WORDS[k][0]}</Btn>
              ))}
            </div>
            <div className="sub2 mt-1">Assessed {naira(open.run.assessed)} · paid {naira(open.run.paid)} · waived {naira(open.run.waived)} · outstanding {naira(open.run.outstanding)}</div>
          </PBody>
          {open.rows.length ? (
            <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Graduation", "Assessed|num", "Paid|num", "Waived|num", "Outstanding|num", "Status", "Final clearance", "|num"]}
              rows={open.rows.map((r, i) => [
                <span key="n" className="tnum sub2">{page * open.size + i + 1}</span>,
                <span key="s"><strong>{r.student}</strong><span className="blk sub2 tnum">{r.matric_no ?? "—"}{r.awaiting_graduation ? " · award approved" : r.student_status === "GRADUATED" ? " · graduated" : ""}</span></span>,
                <span key="p" className="sub2">{r.programme}</span>, <span key="g" className="tnum">{r.graduation_session ?? "—"}</span>,
                <span key="a" className="tnum">{naira(r.assessed)}</span>, <span key="pd" className="tnum">{naira(r.paid)}</span>, <span key="w" className="tnum">{naira(r.waived)}</span>,
                <span key="o" className="tnum" style={{ color: num(r.outstanding) > 0 ? "var(--red-ink)" : undefined }}>{naira(r.outstanding)}{r.owing ? <span className="blk sub2">{r.owing}</span> : null}</span>,
                <span key="st"><Pil kind={RECON_WORDS[r.status]?.[1] ?? "grey"}>{RECON_WORDS[r.status]?.[0] ?? r.status}</Pil>
                  {r.other_payments ? <span className="blk sub2">{r.other_payments} other payment(s) · {naira(r.other_amount)}</span> : null}
                  {r.review_periods || r.pending_periods ? <span className="blk sub2">{[r.review_periods, r.pending_periods].filter(Boolean).join("; ")}</span> : null}</span>,
                <span key="c" className="sub2">{r.clearance_ref ?? "Not started"}{r.bursary_state ? <span className="blk">Bursary: {r.bursary_state.replace(/_/g, " ").toLowerCase()}</span> : null}</span>,
                <Btn key="x" kind="secondary" onClick={() => onOpenStudent(r.student_id)}>Review fees</Btn>,
              ])} />
          ) : <PBody><div className="sub2">No student in this status.</div></PBody>}
          {open.total > open.size ? (
            <PBody><div className="row row--right">
              <Btn kind="ghost" disabled={page <= 0} onClick={() => void read(open.run.id, status, page - 1)}>Previous</Btn>
              <span className="sub2">Page {page + 1} of {Math.ceil(open.total / open.size)}</span>
              <Btn kind="ghost" disabled={(page + 1) * open.size >= open.total} onClick={() => void read(open.run.id, status, page + 1)}>Next</Btn>
            </div></PBody>
          ) : null}
        </Panel>
      ) : null}

      <Panel title="Runs" right={runs ? `${runs.length} kept` : undefined}>
        {!runs ? <PBody><div className="row row--tight sub2"><Spinner /> Reading…</div></PBody> : runs.length ? (
          <DTable cols={["Reference", "Students", "Run", "Students|num", "Cleared|num", "Owing|num", "Review|num", "Outstanding|num", "|num"]}
            rows={runs.map((r) => [
              <span key="r" className="tnum">{r.reference}</span>, <span key="p" className="sub2">{POPULATION_WORDS[r.population]}</span>,
              <span key="w" className="sub2">{when(r.run_at)} · {r.run_by_name ?? r.run_office ?? "—"}</span>, <span key="n" className="tnum">{r.students.toLocaleString()}</span>,
              <span key="c" className="tnum">{r.cleared.toLocaleString()}</span>, <span key="o" className="tnum">{(r.owing + r.payment_review).toLocaleString()}</span>,
              <span key="v" className="tnum">{(r.review + r.pending).toLocaleString()}</span>, <span key="a" className="tnum">{naira(r.outstanding)}</span>,
              <Btn key="x" kind="secondary" onClick={() => void read(r.id, "", 0)}>Open</Btn>,
            ])} />
        ) : <PBody><div className="sub2">No run yet.</div></PBody>}
      </Panel>
    </>
  );
}
