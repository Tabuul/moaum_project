"use client";
/**
 * t/staffupload — the nominal roll of non-academic staff (V253): the same sheet as the teaching staff with
 * CONTISS in place of CONUASS and the unit as the roll spells it. Check the file first: every row is resolved
 * to a unit, a department or a faculty and nothing is written; the spellings that cannot be placed are listed.
 * Then load it: each row becomes a person and an establishment record in its unit — no sign-in, no office.
 * Re-uploading never duplicates. Sent in chunks, so a slow batch never fails the whole file.
 * V656: one member of staff added by hand (the same import, one row); deleted or deactivated — the database deciding by what each
 * person is tied to — and restored from Removed staff.
 * V748: the unit register shows what a staff identity card prints as each unit's department (its card name, else its nearest
 * parent's, else its formal name); ICT sets a unit's card name, with a reason.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RemoveStaff } from "@/components/staff/RemoveStaff";
import { RemovedStaff } from "@/components/staff/RemovedStaff";
import { ddmmyyyy, deactivatedHolder, type StaffChange, type StaffPick } from "@/lib/staff-removal";

export interface NonAcademicRow {
  id: string; staff_number: string | null; name: string; surname: string; given_names: string; email: string | null; phone: string | null;
  present_rank: string | null; sex: string | null; salary_scale: string | null; contiss_step: number | null; date_first_appointment: string | null;
  unit_as_given: string | null; placed_in: string | null; placed_kind: "UNIT" | "DEPARTMENT" | "FACULTY" | null; campus: string; parent_unit: string | null; has_signin: boolean;
}
export interface Unit { code: string; name: string; kind: string; parent_code: string | null; parent: string | null; college_code: string | null; ended_on: string | null; staff: number; spellings: number;
  /** V748: the unit's own card name, and what a staff card prints for it (its own, its nearest parent's, else its name) */
  card_name?: string | null; card_prints?: string | null }

const MAY = ["registrar", "dregistrar", "hrm", "ict", "admin", "super"];
/** V748: the offices that set a unit's card name (the API's PUT /iam/units/{code}/card-name) */
const CARD_NAMERS = ["ict", "super"];
const CHUNK = 100;
interface Row { pno: string; full_names: string; sex: string; date_first_appointment: string; department: string; present_rank: string; phone: string; contiss: string }
interface Tally { rows: number; created: number; existing: number; records: number; unplaced: number; skipped: number; failedRows: number; firstError: string | null; missing: string[]; dry: boolean }
interface AddForm { pno: string; surname: string; given: string; sex: string; unit: string; rank: string; phone: string; contiss: string; appointed: string; email: string }
const EMPTY_ADD: AddForm = { pno: "", surname: "", given: "", sex: "", unit: "", rank: "", phone: "", contiss: "", appointed: "", email: "" };
const KIND: Record<string, string> = { OFFICE: "Office", DIRECTORATE: "Directorate", DIVISION: "Division", UNIT: "Unit", CENTRE: "Centre", SCHOOL: "School", FACULTY_OFFICE: "Faculty office", DEPARTMENT: "Department" };

export function NonAcademic({ actingOffice, staff, units, removed }: { actingOffice: string | null; staff: NonAcademicRow[]; units: Unit[]; removed: StaffChange[] }) {
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
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [removing, setRemoving] = useState<StaffPick[] | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [add, setAdd] = useState<AddForm | null>(null);
  const [addProblem, setAddProblem] = useState<Problem | null>(null);
  const [naming, setNaming] = useState<{ unit: Unit; name: string; reason: string } | null>(null);
  const [namingProblem, setNamingProblem] = useState<Problem | null>(null);
  const mayName = CARD_NAMERS.includes(actingOffice ?? "");

  /* V748: the short name a unit prints on staff identity cards (empty: its nearest parent's, else its own name) */
  async function saveCardName() {
    if (!naming) return;
    if (naming.reason.trim().length < 10) {
      const p = { status: 400, title: "Say why the card name changes, in ten characters or more." }; setNamingProblem(p); notifyProblem(p); return;
    }
    setBusy(true); setNamingProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/iam/units/${encodeURIComponent(naming.unit.code)}/card-name`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Card name of ${naming.unit.code}`) },
        body: JSON.stringify({ cardName: naming.name.trim() || null, reason: naming.reason.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setNamingProblem(p); notifyProblem(p); return; }
      setNaming(null);
      notify(`Staff cards of ${naming.unit.name} now print ${j?.cardPrints ?? "its name"}`);
      router.refresh();
    } finally { setBusy(false); }
  }

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? staff.filter((s) => `${s.name} ${s.staff_number ?? ""} ${s.placed_in ?? ""} ${s.unit_as_given ?? ""} ${s.present_rank ?? ""}`.toLowerCase().includes(q)) : staff;
  }, [staff, search]);

  const shownIds = useMemo(() => shown.slice(0, 500).map((s) => s.id), [shown]);
  const allShownPicked = shownIds.length > 0 && shownIds.every((id) => sel.has(id));
  function toggle(id: string) {
    setSel((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  }
  function toggleAll() {
    setSel((prev) => { const n = new Set(prev); if (allShownPicked) shownIds.forEach((id) => n.delete(id)); else shownIds.forEach((id) => n.add(id)); return n; });
  }
  function pick(list: NonAcademicRow[]): StaffPick[] {
    return list.map((s) => ({ id: s.id, name: s.name, staffNumber: s.staff_number }));
  }

  /* one member of staff, through the roll's own import (one row): placed in its unit by the same spellings */
  async function saveAdd() {
    if (!add) return;
    const pno = add.pno.replace(/\D/g, "");
    if (!pno || !add.surname.trim() || !add.given.trim() || !add.unit.trim()) {
      const p = { status: 400, title: "Staff number, surname, given names and unit are all required." }; setAddProblem(p); notifyProblem(p); return;
    }
    const held = deactivatedHolder(pno, removed);
    if (held) {
      const p = { status: 409, title: `Staff id ${held.staff_number} belongs to ${held.name}, who was deactivated.`, detail: "Restore them under Removed staff below instead of adding them again." };
      setAddProblem(p); notifyProblem(p); return;
    }
    if (staff.some((s) => (s.staff_number ?? "").replace(/\D/g, "") === pno)) {
      const p = { status: 409, title: `Staff id P${pno} is already on record.` }; setAddProblem(p); notifyProblem(p); return;
    }
    setBusy(true); setAddProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/iam/staff/import", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Non-academic staff P${pno} added`) },
        body: JSON.stringify({ dryRun: false, rows: [{ pno, full_names: `${add.given.trim()} ${add.surname.trim()}`, sex: add.sex, date_first_appointment: ddmmyyyy(add.appointed),
          department: add.unit.trim(), present_rank: add.rank.trim(), phone: add.phone.trim(), contiss: add.contiss.trim(), email: add.email.trim() }] }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j) { const p = j ?? { status: r.status, title: r.statusText }; setAddProblem(p); notifyProblem(p); return; }
      if (Number(j.unplaced) > 0) {
        const p = { status: 400, title: `No unit, department or faculty matching "${add.unit.trim()}".`, detail: "Pick the unit from the list, or ask ICT to add the unit or its spelling." };
        setAddProblem(p); notifyProblem(p); return;
      }
      if (Number(j.skipped) > 0 || j.first_error) {
        const p = { status: 400, title: "That member of staff could not be added.", detail: String(j.first_error ?? "") }; setAddProblem(p); notifyProblem(p); return;
      }
      setAdd(null);
      setDone(`P${pno} added.`);
      notify("Staff member added");
      router.refresh();
    } finally { setBusy(false); }
  }

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
        As the teaching-staff sheet, with <b>CONTISS</b> in place of CONUASS. Check the file first (nothing is written), then load it.
        <b> No sign-in and no office are issued.</b> Re-uploading never duplicates.
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
            {tally.failedRows ? <><br /><b>{tally.failedRows} row(s) did not send.</b> Load the same file again to fill the gap.</> : null}
            {tally.missing.length ? <><br /><b>Not placed, as spelt in the sheet:</b> {tally.missing.join(" · ")}. Correct the spelling, or ask ICT to add the unit or alias.</> : null}
            {tally.firstError ? <><br />First problem: {tally.firstError}</> : null}
            {tally.dry && !tally.unplaced ? <><br />Nothing has been written yet. Load the rows to keep them.</> : null}
          </Note>
        </>
      ) : null}

      <Panel title="On record" right={<Tabs label="Staff or units" items={[{ id: "staff", label: "Non-Academic Staff", count: staff.length }, { id: "units", label: "The Unit Register", count: unitRows.length }]} value={tab} onChange={setTab} />}>
        {tab === "staff" ? (
          <>
            <PBody>
              <div className="row">
                <input className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, staff id, unit or rank" style={{ maxWidth: 320 }} aria-label="Search staff" />
                {may ? <Btn kind="primary" onClick={() => { setAddProblem(null); setAdd({ ...EMPTY_ADD }); }}>Add staff</Btn> : null}
                {may && sel.size ? <Btn kind="urgent" onClick={() => { setDone(null); setRemoving(pick(staff.filter((s) => sel.has(s.id)))); }}>{`Delete selected (${sel.size})`}</Btn> : null}
                {sel.size ? <Btn kind="ghost" onClick={() => setSel(new Set())}>Clear selection</Btn> : null}
              </div>
            </PBody>
            {done ? <PBody><Note kind="ok" title="Done">{done}</Note></PBody> : null}
            {shown.length ? (
              <DTable cols={[...(may ? ["|mid"] : []), "Staff id", "Name", "Placed in", "As the roll spelt it", "Rank", "Scale|mid", "First appointed|mid", ...(may ? ["|num"] : [])]} rows={shown.slice(0, 500).map((s) => [
                ...(may ? [<input type="checkbox" key="x" checked={sel.has(s.id)} onChange={() => toggle(s.id)} aria-label={`Select ${s.name}`} />] : []),
                <span className="tnum b700" key="i">{s.staff_number ?? "—"}</span>,
                <span key="n">{s.name}{s.sex ? <span className="sub2"> · {s.sex}</span> : null}</span>,
                <span key="p">{s.placed_in ?? <span className="ink-red">Not placed</span>}{s.parent_unit ? <div className="sub2">{s.parent_unit}</div> : null}{s.campus === "CHS" ? <div><Pil kind="info">CHS</Pil></div> : s.placed_kind === "DEPARTMENT" ? <div><Pil kind="grey">Academic department</Pil></div> : s.placed_kind === "FACULTY" ? <div><Pil kind="grey">Faculty office</Pil></div> : null}</span>,
                <span key="g" className="sub2">{s.unit_as_given ?? "—"}</span>,
                <span key="r" className="sub2">{s.present_rank ?? "—"}</span>,
                <span key="s" className="tnum sub2">{s.salary_scale ? `${s.salary_scale}${s.contiss_step ? ` ${s.contiss_step}` : ""}` : "—"}</span>,
                <span key="d" className="tnum sub2">{s.date_first_appointment ? new Date(s.date_first_appointment).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—"}</span>,
                ...(may ? [<Btn key="del" kind="ghost" aria-label={`Delete ${s.name}`} onClick={() => { setDone(null); setRemoving(pick([s])); }}>Delete</Btn>] : []),
              ])} texts={shown.slice(0, 500).map((s) => `${s.name} ${s.staff_number ?? ""} ${s.placed_in ?? ""} ${s.unit_as_given ?? ""}`)} />
            ) : <PBody><div className="sub2">{staff.length ? "No staff match that search." : "No non-academic staff on record yet. Check a file above, then load it."}</div></PBody>}
            {may && shown.length ? (
              <PBody><label className="sub2 row row--inline row--tight" style={{ cursor: "pointer" }}>
                <input type="checkbox" checked={allShownPicked} onChange={toggleAll} /> Select all {shown.length > 500 ? "(first 500) " : ""}shown
              </label></PBody>
            ) : null}
            {shown.length > 500 ? <PBody><div className="sub2">Showing the first 500 of {shown.length}. Narrow the search.</div></PBody> : null}
          </>
        ) : (
          <DTable cols={["Unit", "Kind|mid", "Under", "Campus|mid", "Staff|mid", "Spellings known|mid", "Staff card prints"]} rows={unitRows.map((u) => [
            <span key="n"><strong>{u.name}</strong> <span className="sub2 tnum">{u.code}</span></span>,
            <span key="k" className="sub2">{KIND[u.kind] ?? u.kind}</span>,
            <span key="p" className="sub2">{u.parent ?? "—"}</span>,
            <span key="c">{u.college_code ? <Pil kind="info">{u.college_code}</Pil> : <span className="sub2">Main</span>}</span>,
            <span key="s" className="tnum">{Number(u.staff)}</span>,
            <span key="a" className="tnum sub2">{Number(u.spellings)}</span>,
            <span key="cp">
              {u.card_prints ?? u.name}
              <div className="sub2">{u.card_name ? "its card name" : u.card_prints && u.card_prints !== u.name ? "from the unit above it" : "its name"}</div>
              {mayName ? <Btn kind="ghost" size="sm" onClick={() => { setNamingProblem(null); setNaming({ unit: u, name: u.card_name ?? "", reason: "" }); }}>Card name</Btn> : null}
            </span>,
          ])} texts={unitRows.map((u) => `${u.name} ${u.code} ${u.parent ?? ""} ${u.kind} ${u.card_prints ?? ""}`)} />
        )}
      </Panel>

      <RemovedStaff changes={removed} may={may} />

      {removing ? (
        <RemoveStaff people={removing} what="Non-academic staff" onClose={() => setRemoving(null)}
          onDone={(m) => { setRemoving(null); setSel(new Set()); setDone(m); router.refresh(); }} />
      ) : null}

      {naming ? (
        <Modal title={`Card name of ${naming.unit.name}`} onClose={() => setNaming(null)}
          foot={<><Btn kind="ghost" onClick={() => setNaming(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || naming.reason.trim().length < 10} onClick={() => void saveCardName()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          {namingProblem ? <ProblemNotice problem={namingProblem} /> : null}
          <div className="sub2 mb-3">What a staff identity card prints as the department of everyone placed in this unit, and in the units under it that have no card name of their own. Leave it empty to print the unit above it&apos;s card name, or this unit&apos;s own name.</div>
          <Field id="uc-name" label="Card name" hint="Sixty characters at most, e.g. Registry, Bursary, Stores">
            <input id="uc-name" className="ctl" maxLength={60} value={naming.name} onChange={(e) => setNaming({ ...naming, name: e.target.value })} placeholder={naming.unit.name} />
          </Field>
          <Field id="uc-reason" label="Reason" hint="Ten characters or more; kept on the audit trail">
            <input id="uc-reason" className="ctl" value={naming.reason} onChange={(e) => setNaming({ ...naming, reason: e.target.value })} placeholder="The short name the University uses on staff cards" />
          </Field>
        </Modal>
      ) : null}

      {add ? (
        <Modal title="Add a member of non-academic staff" onClose={() => setAdd(null)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !add.pno.trim() || !add.surname.trim() || !add.given.trim() || !add.unit.trim()} onClick={() => void saveAdd()}>{busy ? "Adding…" : "Add staff"}</Btn></>}>
          {addProblem ? <ProblemNotice problem={addProblem} /> : null}
          <div className="sub2 mb-3">As a row of the nominal roll: placed in its unit, no sign-in and no office. The staff id becomes P&lt;number&gt;.</div>
          <div className="grid grid--2">
            <Field id="na-pno" label="Staff number (PNO)" hint="Digits only"><input id="na-pno" className="ctl tnum" value={add.pno} onChange={(e) => setAdd({ ...add, pno: e.target.value })} placeholder="539" /></Field>
            <Field id="na-unit" label="Unit" hint="As the register names it, or a known spelling">
              <input id="na-unit" className="ctl" list="na-units" value={add.unit} onChange={(e) => setAdd({ ...add, unit: e.target.value })} placeholder="OFFICE OF THE REGISTRAR" />
              <datalist id="na-units">{unitRows.map((u) => <option key={u.code} value={u.name} />)}</datalist>
            </Field>
            <Field id="na-sur" label="Surname"><input id="na-sur" className="ctl" value={add.surname} onChange={(e) => setAdd({ ...add, surname: e.target.value })} /></Field>
            <Field id="na-giv" label="Given names"><input id="na-giv" className="ctl" value={add.given} onChange={(e) => setAdd({ ...add, given: e.target.value })} /></Field>
            <Field id="na-sex" label="Sex">
              <select id="na-sex" className="ctl" value={add.sex} onChange={(e) => setAdd({ ...add, sex: e.target.value })}><option value="">—</option><option value="M">M</option><option value="F">F</option></select>
            </Field>
            <Field id="na-rank" label="Present rank"><input id="na-rank" className="ctl" value={add.rank} onChange={(e) => setAdd({ ...add, rank: e.target.value })} placeholder="SENIOR DEPUTY BURSAR" /></Field>
            <Field id="na-contiss" label="CONTISS" hint="A step, or CONSOLIDATED"><input id="na-contiss" className="ctl tnum" value={add.contiss} onChange={(e) => setAdd({ ...add, contiss: e.target.value })} placeholder="15" /></Field>
            <Field id="na-appt" label="Date of first appointment"><input id="na-appt" type="date" className="ctl" value={add.appointed} onChange={(e) => setAdd({ ...add, appointed: e.target.value })} /></Field>
            <Field id="na-phone" label="Phone"><input id="na-phone" className="ctl tnum" value={add.phone} onChange={(e) => setAdd({ ...add, phone: e.target.value })} /></Field>
            <Field id="na-email" label="Email"><input id="na-email" className="ctl" value={add.email} onChange={(e) => setAdd({ ...add, email: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
