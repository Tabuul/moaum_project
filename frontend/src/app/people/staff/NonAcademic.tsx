"use client";
/**
 * t/staffupload — the nominal roll of non-academic staff (V253): the same sheet as the teaching staff with
 * CONTISS in place of CONUASS and the unit as the roll spells it. Check the file first: every row is resolved
 * to a unit, a department or a faculty and nothing is written; the spellings that cannot be placed are listed.
 * Then load it: each row becomes a person and an establishment record in its unit — no sign-in, no office.
 * Re-uploading never duplicates. Sent in chunks, so a slow batch never fails the whole file.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface NonAcademicRow {
  id: string; staff_number: string | null; name: string; surname: string; given_names: string; email: string | null; phone: string | null;
  present_rank: string | null; sex: string | null; salary_scale: string | null; contiss_step: number | null; date_first_appointment: string | null;
  unit_as_given: string | null; placed_in: string | null; placed_kind: "UNIT" | "DEPARTMENT" | "FACULTY" | null; campus: string; parent_unit: string | null; has_signin: boolean;
}
export interface Unit { code: string; name: string; kind: string; parent_code: string | null; parent: string | null; college_code: string | null; ended_on: string | null; staff: number; spellings: number }

const MAY = ["registrar", "dregistrar", "hrm", "ict", "admin", "super"];
const CHUNK = 100;
interface Row { pno: string; full_names: string; sex: string; date_first_appointment: string; department: string; present_rank: string; phone: string; contiss: string }
interface Tally { rows: number; created: number; existing: number; records: number; unplaced: number; skipped: number; failedRows: number; firstError: string | null; missing: string[]; dry: boolean }
const KIND: Record<string, string> = { OFFICE: "Office", DIRECTORATE: "Directorate", DIVISION: "Division", UNIT: "Unit", CENTRE: "Centre", SCHOOL: "School", FACULTY_OFFICE: "Faculty office", DEPARTMENT: "Department" };

export function NonAcademic({ actingOffice, staff, units }: { actingOffice: string | null; staff: NonAcademicRow[]; units: Unit[] }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tally, setTally] = useState<Tally | null>(null);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [fileName, setFileName] = useState("");
  const [search, setSearch] = useState("");
  const [tab, setTab] = useState<"staff" | "units">("staff");

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? staff.filter((s) => `${s.name} ${s.staff_number ?? ""} ${s.placed_in ?? ""} ${s.unit_as_given ?? ""} ${s.present_rank ?? ""}`.toLowerCase().includes(q)) : staff;
  }, [staff, search]);

  function downloadTemplate() {
    const blob = buildXlsx(["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONTISS"],
      [["539", "BARNABAS TERFA HEMBA", "M", "04/01/2001", "OFFICE OF THE REGISTRAR", "REGISTRAR", "07038367476", "CONSOLIDATED"],
       ["563", "JOHN ELAIGWU AUDU", "M", "26/03/2001", "BUR-DIRECTORATE OF BAEC", "SENIOR DEPUTY BURSAR", "08055673634", "15"]], "Non-academic staff");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Non-academic staff template.xlsx";
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function read(file: File) {
    setProblem(null); setTally(null); setRows(null); setFileName(file.name);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = {
        pno: at(["pno", "staff"]), name: at(["full name", "name"]), sex: at(["sex", "gender"]), appt: at(["appt", "appoint", "1st"]),
        dept: at(["department", "unit", "dept"]), rank: at(["rank"]), phone: at(["phone", "mobile", "gsm"]), contiss: at(["contiss", "conuass", "scale", "grade"]),
      };
      if (ci.pno < 0 || ci.name < 0 || ci.dept < 0) {
        const p = { status: 400, title: "That file needs PNO, Full Names and Department columns.", detail: "Download the template; it matches the nominal roll." };
        setProblem(p); notifyProblem(p); return;
      }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const out = grid.slice(1)
        .filter((r) => g(r, ci.pno).replace(/\D/g, "") && !/^pno$/i.test(g(r, ci.pno)))
        .map((r) => ({ pno: g(r, ci.pno), full_names: g(r, ci.name), sex: g(r, ci.sex), date_first_appointment: g(r, ci.appt), department: g(r, ci.dept), present_rank: g(r, ci.rank), phone: g(r, ci.phone), contiss: g(r, ci.contiss) }));
      if (!out.length) { const p = { status: 400, title: "No staff found in the file." }; setProblem(p); notifyProblem(p); return; }
      setRows(out);
      await send(out, true);
    } catch {
      const p = { status: 400, title: "That file could not be read as a spreadsheet." }; setProblem(p); notifyProblem(p);
    }
  }

  async function send(all: Row[], dry: boolean) {
    setBusy(true); setProblem(null);
    const sum: Tally = { rows: 0, created: 0, existing: 0, records: 0, unplaced: 0, skipped: 0, failedRows: 0, firstError: null, missing: [], dry };
    try {
      const chunks: Row[][] = [];
      for (let i = 0; i < all.length; i += CHUNK) chunks.push(all.slice(i, i + CHUNK));
      setProgress({ done: 0, total: all.length });
      for (const chunk of chunks) {
        try {
          const r = await fetch("/api/bff/api/v1/iam/staff/import", {
            method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(dry ? `${all.length} non-academic staff rows checked` : `${all.length} non-academic staff uploaded`) },
            body: JSON.stringify({ rows: chunk, dryRun: dry }),
          });
          const j = await r.json().catch(() => null);
          if (!r.ok || !j) { sum.failedRows += chunk.length; if (!sum.firstError && j?.title) sum.firstError = String(j.title); }
          else {
            sum.rows += Number(j.rows ?? 0); sum.created += Number(j.created ?? 0); sum.existing += Number(j.existing ?? 0); sum.records += Number(j.records ?? 0);
            sum.unplaced += Number(j.unplaced ?? 0); sum.skipped += Number(j.skipped ?? 0);
            if (!sum.firstError && j.first_error) sum.firstError = String(j.first_error);
            if (j.unplaced_units) for (const u of String(j.unplaced_units).split(", ")) if (u && !sum.missing.includes(u)) sum.missing.push(u);
          }
        } catch { sum.failedRows += chunk.length; }
        setProgress((p) => (p ? { done: Math.min(p.done + chunk.length, p.total), total: p.total } : p));
        setTally({ ...sum, missing: [...sum.missing] });
      }
      if (!dry) { notify(`${sum.created} staff added · ${sum.existing} already on record`); router.refresh(); }
    } finally { setBusy(false); setProgress(null); }
  }

  const unitRows = units.filter((u) => !u.ended_on);
  return (
    <>
      <RoleLine allowed={["registrar", "dregistrar", "hrm", "ict"]} actingOffice={actingOffice} canAct={may} action="Loading non-academic staff" />
      <Note kind="info" title="Upload the nominal roll of non-academic staff">
        The same sheet as the teaching staff, with <b>CONTISS</b> in place of CONUASS: PNO, full names, sex, date of first appointment, the
        department or unit <b>as the roll spells it</b>, present rank and phone. Check the file first: every row is placed in its unit,
        department or faculty and nothing is written; the spellings that cannot be placed are listed for you to correct or to add to the unit
        register. Then load it. Each row becomes the person on record (the PNO becomes the staff id <b>P&lt;number&gt;</b>) and an establishment
        record in its unit. <b>No sign-in and no office are issued</b>: a non-academic member of staff has no desk on the portal yet, and a
        login with no office cannot act. Re-uploading never duplicates.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Registry, Human Resources and the Directorate of ICT">Your office may not load staff.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {may ? (
        <Panel title="Load the roll" right={fileName ? `${fileName}${rows ? ` · ${rows.length} rows` : ""}` : "Person · establishment record · unit"}>
          <PBody>
            <div className="row">
              <Btn kind="ghost" onClick={downloadTemplate}>Download Template</Btn>
              <label className={`btn btn--secondary btn--sm m-0${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer" }}>
                {busy && tally?.dry ? "Checking…" : "Check a File (.xlsx)"}
                <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
              </label>
              {rows && tally?.dry && !busy ? <Btn kind="primary" onClick={() => void send(rows, false)}>{tally.unplaced ? `Load the ${tally.rows - tally.unplaced} Placed Rows` : `Load All ${tally.rows} Rows`}</Btn> : null}
              {progress ? <span className="sub2 tnum">{tally?.dry ? "Checking" : "Loading"} {progress.done} of {progress.total}…</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      {tally ? (
        <>
          <Tiles items={[
            [tally.dry ? "Rows read" : "Rows loaded", String(tally.rows), null, fileName],
            [tally.dry ? "Would be added" : "Added", String(tally.created), null, "New people on the register"],
            [tally.dry ? "Already on record" : "Already on record", String(tally.existing), null, "Matched by staff id; the record refreshed"],
            ["Not placed", String(tally.unplaced), tally.unplaced ? "var(--red-ink)" : null, tally.unplaced ? "No unit, department or faculty matched" : "Every row placed"],
          ]} />
          <Note kind={tally.unplaced || tally.skipped || tally.failedRows ? "bad" : "ok"} title={tally.dry ? (tally.unplaced ? "Checked: some spellings could not be placed" : "Checked: every row can be placed") : (tally.unplaced || tally.skipped || tally.failedRows ? "Loaded, with rows to follow up" : "Non-academic staff loaded")}>
            {tally.rows} row(s) read · {tally.created} {tally.dry ? "new" : "added"} · {tally.existing} already on record{tally.unplaced ? ` · ${tally.unplaced} not placed` : ""}{tally.skipped ? ` · ${tally.skipped} skipped` : ""}.
            {tally.failedRows ? <><br /><b>{tally.failedRows} row(s) did not send.</b> The upload is idempotent: load the same file again to fill the gap.</> : null}
            {tally.missing.length ? <><br /><b>Not placed, as spelt in the sheet:</b> {tally.missing.join(" · ")}. Correct the spelling to one the register knows, or ask ICT to add the unit or the alias.</> : null}
            {tally.firstError ? <><br />First problem: {tally.firstError}</> : null}
            {tally.dry && !tally.unplaced ? <><br />Nothing has been written yet. Load the rows to keep them.</> : null}
          </Note>
        </>
      ) : null}

      <Panel title="On record" right={<Tabs label="Staff or units" items={[{ id: "staff", label: "Non-Academic Staff", count: staff.length }, { id: "units", label: "The Unit Register", count: unitRows.length }]} value={tab} onChange={setTab} />}>
        {tab === "staff" ? (
          <>
            <PBody><input className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, staff id, unit or rank" style={{ maxWidth: 320 }} aria-label="Search staff" /></PBody>
            {shown.length ? (
              <DTable cols={["Staff id", "Name", "Placed in", "As the roll spelt it", "Rank", "Scale|mid", "First appointed|mid"]} rows={shown.slice(0, 500).map((s) => [
                <span className="tnum b700" key="i">{s.staff_number ?? "—"}</span>,
                <span key="n">{s.name}{s.sex ? <span className="sub2"> · {s.sex}</span> : null}</span>,
                <span key="p">{s.placed_in ?? <span className="ink-red">Not placed</span>}{s.parent_unit ? <div className="sub2">{s.parent_unit}</div> : null}{s.campus === "CHS" ? <div><Pil kind="info">CHS</Pil></div> : s.placed_kind === "DEPARTMENT" ? <div><Pil kind="grey">Academic department</Pil></div> : s.placed_kind === "FACULTY" ? <div><Pil kind="grey">Faculty office</Pil></div> : null}</span>,
                <span key="g" className="sub2">{s.unit_as_given ?? "—"}</span>,
                <span key="r" className="sub2">{s.present_rank ?? "—"}</span>,
                <span key="s" className="tnum sub2">{s.salary_scale ? `${s.salary_scale}${s.contiss_step ? ` ${s.contiss_step}` : ""}` : "—"}</span>,
                <span key="d" className="tnum sub2">{s.date_first_appointment ? new Date(s.date_first_appointment).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—"}</span>,
              ])} texts={shown.slice(0, 500).map((s) => `${s.name} ${s.staff_number ?? ""} ${s.placed_in ?? ""} ${s.unit_as_given ?? ""}`)} />
            ) : <PBody><div className="sub2">{staff.length ? "No staff match that search." : "No non-academic staff on record yet. Check a file above, then load it."}</div></PBody>}
            {shown.length > 500 ? <PBody><div className="sub2">Showing the first 500 of {shown.length}. Narrow the search.</div></PBody> : null}
          </>
        ) : (
          <DTable cols={["Unit", "Kind|mid", "Under", "Campus|mid", "Staff|mid", "Spellings known|mid"]} rows={unitRows.map((u) => [
            <span key="n"><strong>{u.name}</strong> <span className="sub2 tnum">{u.code}</span></span>,
            <span key="k" className="sub2">{KIND[u.kind] ?? u.kind}</span>,
            <span key="p" className="sub2">{u.parent ?? "—"}</span>,
            <span key="c">{u.college_code ? <Pil kind="info">{u.college_code}</Pil> : <span className="sub2">Main</span>}</span>,
            <span key="s" className="tnum">{Number(u.staff)}</span>,
            <span key="a" className="tnum sub2">{Number(u.spellings)}</span>,
          ])} texts={unitRows.map((u) => `${u.name} ${u.code} ${u.parent ?? ""} ${u.kind}`)} />
        )}
      </Panel>
    </>
  );
}
