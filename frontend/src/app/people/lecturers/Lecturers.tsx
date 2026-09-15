"use client";

/**
 * t/lecturers — bulk-onboard lecturers (V135). Each row becomes a person, a
 * sign-in (username and first password are the staff number, must be changed),
 * and the lecturer office scoped to the department. The same three things the
 * Users & roles screen makes one at a time. ICT / Registry offices.
 *
 * The rows are sent in small chunks: every sign-in is a bcrypt (cost 12) hash,
 * so one large request would time out. A progress line shows the run.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, RoleLine, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

const MAY = ["ict", "super", "admin", "registrar", "dregistrar"];
const CHUNK = 40; // bcrypt-12 is ~¼s per row; keep each request well under the timeout

interface Tally { rows: number; created: number; existing: number; credentialed: number; granted: number; skipped: number; firstError: string | null }

export function Lecturers({ actingOffice }: { actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tally, setTally] = useState<Tally | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Staff number", "Surname", "Given names", "Department code", "Email", "Phone"],
      [["MOAUM/STF/24/0001", "Adeyemi", "Grace (example — delete this row)", "MTC", "grace.adeyemi@example.com", "08030000000"]],
      "Lecturers",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Lecturers template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function upload(file: File) {
    setProblem(null); setTally(null); setProgress(null);
    let rows: { staff_number: string; surname: string; given_names: string; department_code: string; email: string; phone: string }[];
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = {
        staff: at(["staff", "staff number", "staffno"]),
        surname: at(["surname", "last"]),
        given: at(["given", "other", "first"]),
        dept: at(["department", "dept"]),
        email: at(["email"]),
        phone: at(["phone", "mobile", "gsm"]),
      };
      if (ci.staff < 0 || ci.surname < 0 || ci.given < 0 || ci.dept < 0) {
        setProblem({ status: 400, title: "That file needs Staff number, Surname, Given names and Department code columns.", detail: "Download the template and fill it in." });
        return;
      }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      rows = grid.slice(1)
        .filter((r) => g(r, ci.staff) && !/^staff/i.test(g(r, ci.staff)))
        .map((r) => ({
          staff_number: g(r, ci.staff), surname: g(r, ci.surname), given_names: g(r, ci.given),
          department_code: g(r, ci.dept), email: g(r, ci.email), phone: g(r, ci.phone),
        }));
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet." });
      return;
    }
    if (!rows.length) { setProblem({ status: 400, title: "No lecturers found in the file." }); return; }

    setBusy(true);
    const sum: Tally = { rows: 0, created: 0, existing: 0, credentialed: 0, granted: 0, skipped: 0, firstError: null };
    try {
      const chunks: typeof rows[] = [];
      for (let i = 0; i < rows.length; i += CHUNK) chunks.push(rows.slice(i, i + CHUNK));
      setProgress({ done: 0, total: rows.length });
      for (const chunk of chunks) {
        const r = await fetch("/api/bff/api/v1/iam/lecturers/import", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${rows.length} lecturers uploaded`) },
          body: JSON.stringify({ rows: chunk }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); break; }
        sum.rows += Number(j.rows ?? 0);
        sum.created += Number(j.created ?? 0);
        sum.existing += Number(j.existing ?? 0);
        sum.credentialed += Number(j.credentialed ?? 0);
        sum.granted += Number(j.granted ?? 0);
        sum.skipped += Number(j.skipped ?? 0);
        if (!sum.firstError && j.first_error) sum.firstError = String(j.first_error);
        setProgress((p) => (p ? { done: Math.min(p.done + chunk.length, p.total), total: p.total } : p));
        setTally({ ...sum });
      }
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  return (
    <>
      <RoleLine allowed={["ict", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Onboarding lecturers" />
      <Note kind="info" title="Upload a list of lecturers">
        Each row is turned into a lecturer three ways at once: the person is put on record, a sign-in is issued (the
        username and first password are both the staff number, and they must set a new password on first sign-in), and the
        lecturer office is granted for the department&rsquo;s code — which is what makes them available for teaching
        allocation and score entry. Uploading again does not duplicate: a lecturer already on record is left as they are,
        and a password already set is never reset. A department must already exist (add it on the Department upload screen).
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Registry">Your office may not onboard lecturers.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {tally ? (
        <>
          <Tiles cls="grid--4" items={[
            ["New lecturers", String(tally.created), null, "Added to the register"],
            ["Sign-ins issued", String(tally.credentialed), null, "Username & first password = staff number"],
            ["Department grants", String(tally.granted), null, "Lecturer office scoped to the department"],
            ["Already on record", String(tally.existing), null, "Kept as they were"],
          ]} />
          <Note kind={tally.skipped ? "bad" : "ok"} title={tally.skipped ? `${tally.skipped} row(s) skipped` : "Lecturers loaded"}>
            {tally.rows} row(s) read · {tally.created} new · {tally.granted} lecturer grant(s) · {tally.credentialed} sign-in(s) issued
            {tally.skipped ? ` · ${tally.skipped} skipped` : ""}.
            {tally.firstError ? <><br />First problem: {tally.firstError}</> : null}
          </Note>
        </>
      ) : null}

      {may ? (
        <Panel title="Upload lecturers" right="Person · sign-in · lecturer office">
          <PBody>
            <div className="sub2">
              The file needs <b>Staff number</b>, <b>Surname</b>, <b>Given names</b> and <b>Department code</b> columns; Email and
              Phone are optional. The staff number becomes the username and the first password.
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginTop: 10 }}>
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--primary btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
                {busy ? "Uploading…" : "Upload lecturers (.xlsx)"}
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
