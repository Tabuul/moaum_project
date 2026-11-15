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
 * V750: the upload follows the nominal roll — the senior non-teaching staff's (PNO, P + digits) and the junior staff's (JP-NO,
 * JP + digits, a series of its own), 16 columns each, from the Excel templates or the Word roll as issued; someone on record
 * has only what their record lacks filled (V761) — the shared components/staff/RollUpload.
 * V754: the Offices tab — the unit each office belongs to, which a staff card prints as the department of someone the HR record
 * places nowhere who holds the office (V751); ICT sets or clears it, with a reason.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { BOUND_WORD } from "@/lib/office-scope";
import { RemoveStaff } from "@/components/staff/RemoveStaff";
import { RemovedStaff } from "@/components/staff/RemovedStaff";
import { RollUpload } from "@/components/staff/RollUpload";
import { ddmmyyyy, deactivatedHolder, type StaffChange, type StaffPick } from "@/lib/staff-removal";
import { addCheck, addOutcome } from "@/lib/staff-roll";

export interface NonAcademicRow {
  id: string; staff_number: string | null; name: string; surname: string; given_names: string; email: string | null; phone: string | null;
  present_rank: string | null; sex: string | null; salary_scale: string | null; contiss_step: number | null; date_first_appointment: string | null;
  unit_as_given: string | null; placed_in: string | null; placed_kind: "UNIT" | "DEPARTMENT" | "FACULTY" | null; campus: string; parent_unit: string | null; has_signin: boolean;
}
export interface Unit { code: string; name: string; kind: string; parent_code: string | null; parent: string | null; college_code: string | null; ended_on: string | null; staff: number; spellings: number;
  /** V748: the unit's own card name, and what a staff card prints for it (its own, its nearest parent's, else its name) */
  card_name?: string | null; card_prints?: string | null }
/** V754: an office (GET /iam/offices), the unit it belongs to, what a staff card prints for it and how many hold it today */
export interface OfficeRow { code: string; label: string; scope_kind: string; unit_code?: string | null; unit?: string | null; card_prints?: string | null; holders?: number }

const MAY = ["registrar", "dregistrar", "hrm", "ict", "admin", "super"];
/** V748: the offices that set a unit's card name (the API's PUT /iam/units/{code}/card-name) */
const CARD_NAMERS = ["ict", "super"];
const CHUNK = 100;
/** V750: cadre SENIOR (PNO, staff id P + digits) or JUNIOR (JP-NO, staff id JP + digits — a series of its own) */
interface AddForm { pno: string; cadre: "SENIOR" | "JUNIOR"; surname: string; given: string; sex: string; unit: string; rank: string; phone: string; contiss: string; appointed: string; email: string }
const EMPTY_ADD: AddForm = { pno: "", cadre: "SENIOR", surname: "", given: "", sex: "", unit: "", rank: "", phone: "", contiss: "", appointed: "", email: "" };
const KIND: Record<string, string> = { OFFICE: "Office", DIRECTORATE: "Directorate", DIVISION: "Division", UNIT: "Unit", CENTRE: "Centre", SCHOOL: "School", FACULTY_OFFICE: "Faculty office", DEPARTMENT: "Department" };

export function NonAcademic({ actingOffice, staff, units, removed, offices }: { actingOffice: string | null; staff: NonAcademicRow[]; units: Unit[]; removed: StaffChange[]; offices: OfficeRow[] }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [search, setSearch] = useState("");
  const [tab, setTab] = useState<"staff" | "units" | "offices">("staff");
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [removing, setRemoving] = useState<StaffPick[] | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [add, setAdd] = useState<AddForm | null>(null);
  const [addProblem, setAddProblem] = useState<Problem | null>(null);
  const [renameOk, setRenameOk] = useState<string | null>(null);   // V750: an Add that renames someone on record, confirmed by a second press
  const [naming, setNaming] = useState<{ unit: Unit; name: string; reason: string } | null>(null);
  const [namingProblem, setNamingProblem] = useState<Problem | null>(null);
  const mayName = CARD_NAMERS.includes(actingOffice ?? "");
  const [placing, setPlacing] = useState<{ office: OfficeRow; unit: string; reason: string } | null>(null);
  const [placingProblem, setPlacingProblem] = useState<Problem | null>(null);

  /* V754: the unit an office belongs to (empty: none), read by a staff card for someone the HR record places nowhere */
  async function saveOfficeUnit() {
    if (!placing) return;
    if (placing.reason.trim().length < 10) {
      const p = { status: 400, title: "Say why the office's unit changes, in ten characters or more." }; setPlacingProblem(p); notifyProblem(p); return;
    }
    setBusy(true); setPlacingProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/iam/offices/${encodeURIComponent(placing.office.code)}/unit`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Unit of the ${placing.office.label} office`) },
        body: JSON.stringify({ unitCode: placing.unit || null, reason: placing.reason.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setPlacingProblem(p); notifyProblem(p); return; }
      setPlacing(null);
      notify(j?.cardPrints ? `${placing.office.label}: a staff card now prints ${j.cardPrints}` : `${placing.office.label} now belongs to no unit: a staff card prints no department from it`);
      router.refresh();
    } finally { setBusy(false); }
  }

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

  /* one member of staff, through the roll's own import (one row): placed in its unit by the same spellings. V750: a senior's
     number is P + digits, a junior's JP + digits (typed JP858, or 858 with Junior picked); the row is checked first (a dry run),
     and someone on record as teaching staff is not moved here (lib/staff-roll addCheck) */
  async function saveAdd() {
    if (!add) return;
    const pno = add.pno.replace(/\D/g, "");
    const junior = add.cadre === "JUNIOR" || /^\s*JP/i.test(add.pno);
    const id = `${junior ? "JP" : "P"}${pno}`;
    if (!pno || !add.surname.trim() || !add.given.trim() || !add.unit.trim()) {
      const p = { status: 400, title: "Staff number, surname, given names and unit are all required." }; setAddProblem(p); notifyProblem(p); return;
    }
    const held = deactivatedHolder(id, removed);
    if (held) {
      const p = { status: 409, title: `Staff id ${held.staff_number} belongs to ${held.name}, who was deactivated.`, detail: "Restore them under Removed staff below instead of adding them again." };
      setAddProblem(p); notifyProblem(p); return;
    }
    if (staff.some((s) => (s.staff_number ?? "").toUpperCase() === id)) {   // V750: JP858 (a junior) is not P858
      const p = { status: 409, title: `Staff id ${id} is already on record.` }; setAddProblem(p); notifyProblem(p); return;
    }
    setBusy(true); setAddProblem(null);
    try {
      // one row of the roll: the names in their own cells, so a surname of two words stays whole
      const row = { [junior ? "jp_no" : "pno"]: pno, given_names: add.given.trim(), last_name: add.surname.trim(), sex: add.sex,
        date_first_appointment: ddmmyyyy(add.appointed), posting: add.unit.trim(), present_rank: add.rank.trim(), phone: add.phone.trim(),
        contiss: add.contiss.trim(), email: add.email.trim() };
      const send = (dryRun: boolean) => fetch("/api/bff/api/v1/iam/staff/import", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(dryRun ? `Non-academic staff ${id} checked` : `Non-academic staff ${id} added`) },
        body: JSON.stringify({ dryRun, rows: [row] }),
      });
      let r = await send(true);
      let j = await r.json().catch(() => null);
      if (r.ok && j && !(Number(j.unplaced) > 0)) {
        const v = addCheck(j);
        if (!v.ok) { const p = { status: 409, title: v.title, detail: v.detail }; setAddProblem(p); notifyProblem(p); return; }
        // someone on record under this number: adding renames them — said first, done on a second press
        const key = v.renames ? `${id}|${v.renames.to}` : null;
        if (v.renames && renameOk !== key) {
          const p = { status: 409, title: `${id} is on record as ${v.renames.from}: adding renames them ${v.renames.to}.`,
            detail: "Press Add staff again to rename and update them, or check the staff number." };
          setRenameOk(key); setAddProblem(p); notifyProblem(p); return;
        }
        r = await send(false);
        j = await r.json().catch(() => null);
      }
      if (!r.ok || !j) { const p = j ?? { status: r.status, title: r.statusText }; setAddProblem(p); notifyProblem(p); return; }
      if (Number(j.unplaced) > 0) {
        const p = { status: 400, title: `No unit, department or faculty matching "${add.unit.trim()}".`, detail: "Pick the unit from the list, or ask ICT to add the unit or its spelling." };
        setAddProblem(p); notifyProblem(p); return;
      }
      if (Number(j.skipped) > 0 || Number(j.errors) > 0 || j.first_error) {
        const p = { status: 400, title: "That member of staff could not be added.", detail: String(j.first_error ?? "") }; setAddProblem(p); notifyProblem(p); return;
      }
      setAdd(null);
      const out = addOutcome(j, id);
      setRenameOk(null);
      setDone(out.text);
      notify(out.action === "UPDATED" ? "Staff record updated" : out.existing ? "Staff record checked" : "Staff member added");
      router.refresh();
    } finally { setBusy(false); }
  }

  const unitRows = units.filter((u) => !u.ended_on);
  return (
    <>
      <RoleLine allowed={["registrar", "dregistrar", "hrm", "ict"]} actingOffice={actingOffice} canAct={may} action="Loading non-academic staff" />
      <Note kind="info" title="Upload the nominal roll of non-academic staff">
        The <b>senior non-teaching staff</b> roll (PNO, staff id P and the digits) or the <b>junior staff</b> roll (JP-NO, staff id JP and the
        digits, never merged with a P number). Check the file first (nothing is written), then upload it. A new member of staff is placed in their
        posting; <b>no sign-in and no office are issued.</b> Someone already on record has <b>only what their record is missing</b> filled
        from the roll; a detail the portal holds differently is kept and listed, and their sign-in, password and offices are never touched.
        Re-uploading never duplicates.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Registry, Human Resources and the Directorate of ICT">Your office may not load staff.</Note> : null}

      {may ? (
        <RollUpload kind="NON_ACADEMIC" templates={["SENIOR", "JUNIOR"]} endpoint="/api/bff/api/v1/iam/staff/import" chunk={CHUNK} what="non-academic staff"
          onDone={() => router.refresh()} />
      ) : null}

      <Panel title="On record" right={<Tabs label="Staff, units or offices" items={[{ id: "staff", label: "Non-Academic Staff", count: staff.length }, { id: "units", label: "The Unit Register", count: unitRows.length }, { id: "offices", label: "Offices", count: offices.length }]} value={tab} onChange={setTab} />}>
        {tab === "staff" ? (
          <>
            <PBody>
              <div className="row">
                <input className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, staff id, unit or rank" style={{ maxWidth: 320 }} aria-label="Search staff" />
                {may ? <Btn kind="primary" onClick={() => { setAddProblem(null); setRenameOk(null); setAdd({ ...EMPTY_ADD }); }}>Add staff</Btn> : null}
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
        ) : tab === "offices" ? (
          <>
            {/* V754: the unit each office belongs to, set by ICT */}
            <PBody><div className="sub2">A staff card prints the unit an office belongs to as the department of someone the HR record places nowhere who holds the office.</div></PBody>
            {offices.length ? (
              <DTable cols={["Office", "Scope", "Belongs to", "Staff card prints", "Holders|mid", ...(mayName ? ["|num"] : [])]} rows={offices.map((o) => {
                const bound = BOUND_WORD[o.scope_kind];
                return [
                  <span key="o"><strong>{o.label}</strong> <span className="sub2 tnum">{o.code}</span></span>,
                  <span key="s" className="sub2">{bound ? bound.charAt(0).toUpperCase() + bound.slice(1) : o.scope_kind}</span>,
                  <span key="u">{o.unit ?? o.unit_code ?? "—"}{o.unit_code ? <span className="sub2 tnum"> {o.unit_code}</span> : null}</span>,
                  <span key="cp">{o.card_prints ?? <span className="sub2">—</span>}</span>,
                  <span key="h" className="tnum">{Number(o.holders ?? 0)}</span>,
                  ...(mayName ? [<Btn key="pu" kind="ghost" size="sm" aria-label={`Unit of ${o.label}`} onClick={() => { setPlacingProblem(null); setPlacing({ office: o, unit: o.unit_code ?? "", reason: "" }); }}>Unit</Btn>] : []),
                ];
              })} texts={offices.map((o) => `${o.label} ${o.code} ${o.unit ?? ""} ${o.unit_code ?? ""} ${o.card_prints ?? ""}`)} />
            ) : <PBody><div className="sub2">The offices could not be read.</div></PBody>}
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

      {placing ? (
        <Modal title={`Unit of ${placing.office.label}`} onClose={() => setPlacing(null)}
          foot={<><Btn kind="ghost" onClick={() => setPlacing(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || placing.reason.trim().length < 10} onClick={() => void saveOfficeUnit()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          {placingProblem ? <ProblemNotice problem={placingProblem} /> : null}
          <div className="sub2 mb-3">The unit this office belongs to. A staff card prints it as the department of someone who holds the office and whom the HR record places in no unit, department or faculty. Choose No unit to clear it.</div>
          <Field id="ou-unit" label="Unit" hint="From the unit register">
            <SearchSelect id="ou-unit" value={placing.unit} onChange={(v) => setPlacing({ ...placing, unit: v })} allLabel="No unit"
              valueLabel={placing.office.unit ?? placing.office.unit_code ?? undefined} placeholder="Type to search the units"
              options={unitRows.map((u) => ({ value: u.code, label: u.name, sub: [u.code, u.parent].filter(Boolean).join(" · ") }))} />
          </Field>
          <Field id="ou-reason" label="Reason" hint="Ten characters or more; kept on the audit trail">
            <input id="ou-reason" className="ctl" value={placing.reason} onChange={(e) => setPlacing({ ...placing, reason: e.target.value })} placeholder="The unit the University places this office in" />
          </Field>
        </Modal>
      ) : null}

      {add ? (
        <Modal title="Add a member of non-academic staff" onClose={() => setAdd(null)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !add.pno.trim() || !add.surname.trim() || !add.given.trim() || !add.unit.trim()} onClick={() => void saveAdd()}>{busy ? "Adding…" : "Add staff"}</Btn></>}>
          {addProblem ? <ProblemNotice problem={addProblem} /> : null}
          <div className="sub2 mb-3">As a row of the nominal roll: placed in its unit, no sign-in and no office. The staff id becomes P&lt;number&gt; for senior staff and JP&lt;number&gt; for junior staff.</div>
          <div className="grid grid--2">
            <Field id="na-pno" label={add.cadre === "JUNIOR" ? "Staff number (JP-NO)" : "Staff number (PNO)"} hint={add.cadre === "JUNIOR" ? "Digits — becomes JP<number>" : "Digits — becomes P<number>"}>
              <input id="na-pno" className="ctl tnum" value={add.pno} onChange={(e) => setAdd({ ...add, pno: e.target.value, cadre: /^\s*JP/i.test(e.target.value) ? "JUNIOR" : add.cadre })} placeholder={add.cadre === "JUNIOR" ? "99858" : "99539"} />
            </Field>
            <Field id="na-cadre" label="Cadre" hint="Junior staff are numbered JP, a series of their own">
              <select id="na-cadre" className="ctl" value={add.cadre} onChange={(e) => setAdd({ ...add, cadre: e.target.value === "JUNIOR" ? "JUNIOR" : "SENIOR" })}>
                <option value="SENIOR">Senior staff (PNO)</option><option value="JUNIOR">Junior staff (JP-NO)</option>
              </select>
            </Field>
            <Field id="na-unit" label="Unit" hint="As the register names it, or a known spelling">
              <input id="na-unit" className="ctl" list="na-units" value={add.unit} onChange={(e) => setAdd({ ...add, unit: e.target.value })} placeholder="OFFICE OF THE REGISTRAR" />
              <datalist id="na-units">{unitRows.map((u) => <option key={u.code} value={u.name} />)}</datalist>
            </Field>
            <Field id="na-sur" label="Surname"><input id="na-sur" className="ctl" value={add.surname} onChange={(e) => setAdd({ ...add, surname: e.target.value })} /></Field>
            <Field id="na-giv" label="Given names"><input id="na-giv" className="ctl" value={add.given} onChange={(e) => setAdd({ ...add, given: e.target.value })} /></Field>
            <Field id="na-sex" label="Sex">
              <select id="na-sex" className="ctl" value={add.sex} onChange={(e) => setAdd({ ...add, sex: e.target.value })}><option value="">—</option><option value="M">M</option><option value="F">F</option></select>
            </Field>
            <Field id="na-rank" label="Present rank"><input id="na-rank" className="ctl" value={add.rank} onChange={(e) => setAdd({ ...add, rank: e.target.value })} placeholder="EXECUTIVE OFFICER" /></Field>
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
