"use client";

/**
 * t/lecturers — bulk-onboard teaching staff from the "List of teaching staff"
 * sheet (V137). Each row becomes a person, a sign-in (username and first
 * password are the staff id P<PNO>, must be changed on first sign-in), the
 * lecturer office scoped to the home department, and an establishment record
 * (sex, first appointment, rank, CONUASS). ICT / Registry offices.
 *
 * Sent in small chunks: every sign-in is a bcrypt (cost 12) hash, so one large
 * request would time out. A department not on the register is reported so it
 * can be created first. Teaching another department's course is handled by
 * teaching allocation, not by this upload.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, RoleLine, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

const MAY = ["ict", "super", "admin", "registrar", "dregistrar"];
const CHUNK = 40; // bcrypt-12 is ~¼s per row; keep each request well under the timeout

interface Row { pno: string; full_names: string; sex: string; date_first_appointment: string; department: string; present_rank: string; phone: string; conuass: string }
interface Tally { rows: number; created: number; existing: number; credentialed: number; granted: number; records: number; no_department: number; skipped: number; firstError: string | null; missing: string[] }

export function Lecturers({ actingOffice }: { actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tally, setTally] = useState<Tally | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONUASS"],
      [["29", "PROF. PAUL AONDONA ANGAHAR (example — delete this row)", "M", "01/12/1992", "ACCOUNTING", "PROFESSOR", "07068010515", "7"]],
      "Teaching staff",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Teaching staff template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function upload(file: File) {
    setProblem(null); setTally(null); setProgress(null);
    let rows: Row[];
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = {
        pno: at(["pno", "staff"]),
        name: at(["full name", "name"]),
        sex: at(["sex", "gender"]),
        appt: at(["appt", "appoint", "1st"]),
        dept: at(["department", "dept"]),
        rank: at(["rank"]),
        phone: at(["phone", "mobile", "gsm"]),
        conuass: at(["conuas", "connuas", "conuass"]),
      };
      if (ci.pno < 0 || ci.name < 0 || ci.dept < 0) {
        setProblem({ status: 400, title: "That file needs PNO, Full Names and Department columns.", detail: "Download the template — it matches the List of teaching staff." });
        return;
      }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      rows = grid.slice(1)
        .filter((r) => g(r, ci.pno).replace(/\D/g, "") && !/^pno$/i.test(g(r, ci.pno)))
        .map((r) => ({
          pno: g(r, ci.pno), full_names: g(r, ci.name), sex: g(r, ci.sex),
          date_first_appointment: g(r, ci.appt), department: g(r, ci.dept),
          present_rank: g(r, ci.rank), phone: g(r, ci.phone), conuass: g(r, ci.conuass),
        }));
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet." });
      return;
    }
    if (!rows.length) { setProblem({ status: 400, title: "No teaching staff found in the file." }); return; }

    setBusy(true);
    const sum: Tally = { rows: 0, created: 0, existing: 0, credentialed: 0, granted: 0, records: 0, no_department: 0, skipped: 0, firstError: null, missing: [] };
    try {
      const chunks: Row[][] = [];
      for (let i = 0; i < rows.length; i += CHUNK) chunks.push(rows.slice(i, i + CHUNK));
      setProgress({ done: 0, total: rows.length });
      for (const chunk of chunks) {
        const r = await fetch("/api/bff/api/v1/iam/lecturers/import", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${rows.length} teaching staff uploaded`) },
          body: JSON.stringify({ rows: chunk }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); break; }
        sum.rows += Number(j.rows ?? 0);
        sum.created += Number(j.created ?? 0);
        sum.existing += Number(j.existing ?? 0);
        sum.credentialed += Number(j.credentialed ?? 0);
        sum.granted += Number(j.granted ?? 0);
        sum.records += Number(j.records ?? 0);
        sum.no_department += Number(j.no_department ?? 0);
        sum.skipped += Number(j.skipped ?? 0);
        if (!sum.firstError && j.first_error) sum.firstError = String(j.first_error);
        if (j.missing_departments) for (const d of String(j.missing_departments).split(", ")) if (d && !sum.missing.includes(d)) sum.missing.push(d);
        setProgress((p) => (p ? { done: Math.min(p.done + chunk.length, p.total), total: p.total } : p));
        setTally({ ...sum, missing: [...sum.missing] });
      }
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  return (
    <>
      <RoleLine allowed={["ict", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Onboarding teaching staff" />
      <Note kind="info" title="Upload the list of teaching staff">
        Straight from the <b>List of teaching staff</b>: PNO, full names, sex, date of first appointment, department, present
        rank, phone and CONUASS. Each row becomes a lecturer four ways at once — the person is put on record; a sign-in is
        issued where the <b>username and first password are both the staff id</b> (the PNO becomes <b>P29</b>, and they must
        set a new password on first sign-in); the <b>lecturer office is granted for the home department</b>; and the
        establishment record (sex, first appointment, rank, CONUASS) is kept. A lecturer who teaches a course in another
        department is handled by that department&rsquo;s <b>teaching allocation</b> — no second upload — and every course
        assigned to them, from any department, shows on their one dashboard for score entry. Re-uploading does not duplicate,
        and a password already set is never reset. The department must already exist (add it on the Department upload screen).
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Registry">Your office may not onboard teaching staff.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {tally ? (
        <>
          <Tiles cls="grid--4" items={[
            ["New staff", String(tally.created), null, "Added to the register"],
            ["Sign-ins issued", String(tally.credentialed), null, "Username & first password = P<PNO>"],
            ["Department grants", String(tally.granted), null, "Lecturer office at the home department"],
            ["Records kept", String(tally.records), null, "Sex · appointment · rank · CONUASS"],
          ]} />
          <Note kind={tally.no_department || tally.skipped ? "bad" : "ok"} title={tally.no_department || tally.skipped ? "Loaded with some rows set aside" : "Teaching staff loaded"}>
            {tally.rows} row(s) read · {tally.created} new · {tally.existing} already on record · {tally.granted} department grant(s)
            {tally.no_department ? ` · ${tally.no_department} with no matching department` : ""}{tally.skipped ? ` · ${tally.skipped} skipped` : ""}.
            {tally.missing.length ? <><br /><b>Create these departments first, then re-upload:</b> {tally.missing.join(", ")}.</> : null}
            {tally.firstError ? <><br />First problem: {tally.firstError}</> : null}
          </Note>
        </>
      ) : null}

      {may ? (
        <Panel title="Upload teaching staff" right="Person · sign-in · department · establishment">
          <PBody>
            <div className="sub2">
              The file needs <b>PNO</b>, <b>Full Names</b> and <b>Department</b> at least; Sex, Date of 1st Appt, Present Rank,
              Phone and CONUASS are carried when present. The PNO becomes the staff id <b>P&lt;number&gt;</b>, which is the
              username and the first password.
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginTop: 10 }}>
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--primary btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
                {busy ? "Uploading…" : "Upload teaching staff (.xlsx)"}
                <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
              </label>
              {progress ? <span className="sub2 tnum">Onboarding {progress.done} of {progress.total}…</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
