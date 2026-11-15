"use client";

/**
 * t/lecturers — bulk-onboard teaching staff from the "List of teaching staff"
 * sheet (V137), and view the staff on record. Each row becomes a person, a
 * sign-in (username the staff id P<PNO>; the stored first password is random, and the staff id opens the account until the
 * lecturer chooses one, at once — or "Forgot password"), the lecturer office scoped to the home department, and an
 * establishment record (sex, first appointment, rank, CONUASS).
 *
 * Sent in small chunks: every sign-in is a bcrypt (cost 12) hash, so one large
 * request would time out. A chunk that fails to send does not stop the rest —
 * the import is idempotent, so uploading again fills any gap. A department not
 * on the register is reported so it can be created first.
 * V750: the upload follows the nominal roll (17 columns: first, middle and last name, PNO, sex, date of birth, e-mail, phone, LGA,
 * state, first appointment, confirmation, last promotion, present rank, department, faculty), from the Excel template or the Word
 * roll as issued; checked first (a dry run), then uploaded; someone on record has only what their record lacks filled (V761), the
 * lecturer office never moved by the upload — the shared components/staff/RollUpload. The Edit form moves the office; a number on
 * record as non-teaching staff is refused (an ERROR row), on the upload as on Add.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RemoveStaff } from "@/components/staff/RemoveStaff";
import { RemovedStaff } from "@/components/staff/RemovedStaff";
import { RollUpload } from "@/components/staff/RollUpload";
import { deactivatedHolder, type StaffChange, type StaffPick } from "@/lib/staff-removal";
import { addCheck, addOutcome } from "@/lib/staff-roll";

export interface StaffRow {
  id: string; staff_number: string | null; name: string; surname: string | null; given_names: string | null;
  email: string | null; phone: string | null;
  present_rank: string | null; sex: string | null; conuass_step: number | null;
  home_department: string | null; home_dept_code: string | null; departments: string | null;
  has_signin: boolean; must_change: boolean; username: string | null; last_sign_in_at: string | null;
}

interface StaffForm { id: string | null; pno: string; surname: string; given: string; sex: string; department: string; rank: string; phone: string; conuass: string; email: string }
const EMPTY_FORM: StaffForm = { id: null, pno: "", surname: "", given: "", sex: "", department: "", rank: "", phone: "", conuass: "", email: "" };

const MAY = ["ict", "super", "admin", "registrar", "dregistrar"];
const CHUNK = 25; // bcrypt-12 is ~¼s per row; keep each request short so it never times out

export function Lecturers({ actingOffice, staff, removed }: { actingOffice: string | null; staff: StaffRow[]; removed: StaffChange[] }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [search, setSearch] = useState("");
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [delMsg, setDelMsg] = useState<string | null>(null);
  const [removing, setRemoving] = useState<StaffPick[] | null>(null);   // the delete dialog, for one person or the ticked ones
  const [form, setForm] = useState<StaffForm | null>(null);   // null = closed; form.id null = add, set = edit
  const [saveMsg, setSaveMsg] = useState<string | null>(null);
  const [renameOk, setRenameOk] = useState<string | null>(null);   // V750: an Add that renames someone on record, confirmed by a second press

  function openAdd() { setProblem(null); setRenameOk(null); setForm({ ...EMPTY_FORM }); }
  function openEdit(s: StaffRow) {
    setProblem(null);
    setForm({ id: s.id, pno: s.staff_number ?? "", surname: s.surname ?? "", given: s.given_names ?? "",
      sex: s.sex ?? "", department: s.home_dept_code ?? s.home_department ?? "", rank: s.present_rank ?? "",
      phone: s.phone ?? "", conuass: s.conuass_step != null ? String(s.conuass_step) : "", email: s.email ?? "" });
  }
  async function saveStaff() {
    if (!form) return;
    const edit = !!form.id;
    if (!form.surname.trim() || !form.given.trim() || !form.department.trim() || (!edit && !form.pno.trim().replace(/\D/g, ""))) {
      setProblem({ status: 400, title: "Staff id, surname, given names and department are all required." }); notifyProblem({ status: 400, title: "Staff id, surname, given names and department are all required." });
      return;
    }
    const held = edit ? null : deactivatedHolder(form.pno, removed);
    if (held) {
      const p = { status: 409, title: `Staff id ${held.staff_number} belongs to ${held.name}, who was deactivated.`, detail: "Restore them under Removed staff below instead of adding them again." };
      setProblem(p); notifyProblem(p);
      return;
    }
    // V750: a junior's JP number is loaded on the non-academic staff desk (never read here as the P number of its digits)
    if (!edit && /^\s*JP/i.test(form.pno)) {
      const p = { status: 400, title: `${form.pno.trim().toUpperCase()} is a junior staff number (JP-NO).`, detail: "Junior staff are loaded on the non-academic staff desk." };
      setProblem(p); notifyProblem(p);
      return;
    }
    // V750: the upload updates someone already on record — adding by hand is for someone new; Edit corrects the rest
    const digits = form.pno.replace(/\D/g, "");
    const onList = edit ? null : staff.find((s) => (s.staff_number ?? "").toUpperCase() === `P${digits}`);
    if (onList) {
      const p = { status: 409, title: `Staff id ${onList.staff_number} is already on record: ${onList.name}.`, detail: "Edit them in the list below instead." };
      setProblem(p); notifyProblem(p);
      return;
    }
    setBusy(true); setProblem(null);
    try {
      const headers = { "Content-Type": "application/json", "X-Reason": reasonHeader(edit ? `Staff ${form.pno} edited` : `Staff ${form.pno} added`) };
      let r: Response;
      if (edit) {
        r = await fetch(`/api/bff/api/v1/iam/lecturers/${form.id}`, { method: "PUT", headers, body: JSON.stringify({
          surname: form.surname.trim(), givenNames: form.given.trim(), email: form.email.trim() || null, phone: form.phone.trim() || null,
          sex: form.sex || null, rank: form.rank.trim() || null, conuass: form.conuass ? Number(form.conuass) : null, department: form.department.trim() }) });
      } else {
        // V750: one row of the roll (the names in their own cells, so a surname of two words stays whole), checked first as a dry run
        const row = { pno: form.pno.trim(), given_names: form.given.trim(), last_name: form.surname.trim(), sex: form.sex,
          department: form.department.trim(), present_rank: form.rank.trim(), phone: form.phone.trim(), conuass: form.conuass, email: form.email.trim() };
        const send = (dryRun: boolean) => fetch(`/api/bff/api/v1/iam/lecturers/import`, { method: "POST", headers, body: JSON.stringify({ rows: [row], dryRun }) });
        r = await send(true);
        const c = await r.clone().json().catch(() => null);
        if (r.ok && c) {
          if (Number(c.no_department) > 0) {
            const p = { status: 400, title: `No department matching "${form.department.trim()}".`, detail: "Ask ICT to add the department (Department upload), or check the name." }; setProblem(p); notifyProblem(p);
            return;
          }
          const v = addCheck(c);
          if (!v.ok) { const p = { status: 409, title: v.title, detail: v.detail }; setProblem(p); notifyProblem(p); return; }
          // someone on record under this number: adding renames them — said first, done on a second press
          const key = v.renames ? `P${digits}|${v.renames.to}` : null;
          if (v.renames && renameOk !== key) {
            const p = { status: 409, title: `P${digits} is on record as ${v.renames.from}: adding renames them ${v.renames.to}.`,
              detail: "Press Add staff again to rename and update them, or check the staff number." };
            setRenameOk(key); setProblem(p); notifyProblem(p); return;
          }
          r = await send(false);
        }
      }
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      if (!edit && j && Number(j.no_department) > 0) {
        setProblem({ status: 400, title: `No department matching "${form.department.trim()}".`, detail: "Ask ICT to add the department (Department upload), or check the name." }); notifyProblem({ status: 400, title: `No department matching "${form.department.trim()}".`, detail: "Ask ICT to add the department (Department upload), or check the name." });
        return;
      }
      if (!edit && j && (Number(j.skipped) > 0 || Number(j.errors) > 0)) {
        const p = { status: 400, title: "That member of staff could not be added.", detail: String(j.first_error ?? "") }; setProblem(p); notifyProblem(p);
        return;
      }
      setForm(null);
      setDelMsg(null);
      // V750: a number on record but not on this list is updated by the upload, not added — and the upload never gives someone on
      // record a sign-in or an office
      const out = edit ? null : addOutcome(j, `P${digits}`);
      setRenameOk(null);
      setSaveMsg(!out ? "Staff member updated." : out.existing
        ? `${out.text} No sign-in or lecturer office is given this way: check them on Users & roles.`
        : out.text);
      notify(!out ? "Staff member updated" : out.action === "UPDATED" ? "Staff record updated" : out.existing ? "Staff record checked" : "Staff member added");
      router.refresh();
    } finally { setBusy(false); }
  }

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? staff.filter((s) => s.name.toLowerCase().includes(q) || (s.staff_number ?? "").toLowerCase().includes(q) || (s.departments ?? "").toLowerCase().includes(q)) : staff;
  }, [staff, search]);

  function toggle(id: string) {
    setSel((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  }
  const shownIds = useMemo(() => shown.slice(0, 500).map((s) => s.id), [shown]);
  const allShownPicked = shownIds.length > 0 && shownIds.every((id) => sel.has(id));
  function toggleAll() {
    setSel((prev) => {
      const n = new Set(prev);
      if (allShownPicked) shownIds.forEach((id) => n.delete(id));
      else shownIds.forEach((id) => n.add(id));
      return n;
    });
  }

  function pick(list: StaffRow[]): StaffPick[] {
    return list.map((s) => ({ id: s.id, name: s.name, staffNumber: s.staff_number }));
  }

  return (
    <>
      <RoleLine allowed={["ict", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Onboarding teaching staff" />
      <Note kind="info" title="Upload the nominal roll of teaching staff, and see who is on record">
        From the <b>nominal roll</b> (the Word roll as issued, or the Excel template). A new lecturer gets a sign-in whose <b>username is the staff id</b>, and the <b>lecturer
        office at the home department</b>. The lecturer signs in with the <b>staff id as the first password</b> and chooses a password at once; after that
        the staff id opens nothing (<b>Forgot password</b> sends a link to the email or phone on record, or the Registry gives a new one on Users &amp; roles).
        Someone already on record has <b>only what their record is missing</b> filled from the roll (names, dates, rank, department and faculty, e-mail and phone); a detail the portal holds differently is kept and listed, and their sign-in, password and offices are never touched (the Edit form moves the lecturer office).
        Re-uploading never duplicates or resets a password. The department must exist first.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Registry">Your office may not onboard teaching staff.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {may ? (
        <RollUpload kind="ACADEMIC" templates={["ACADEMIC"]} endpoint="/api/bff/api/v1/iam/lecturers/import" chunk={CHUNK} what="teaching staff"
          onDone={() => router.refresh()} />
      ) : null}

      <Panel title="Teaching staff on record" right={`${staff.length} lecturer${staff.length === 1 ? "" : "s"}`}>
        <PBody>
          <div className="row">
            <input className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, staff id or department" style={{ maxWidth: 300 }} />
            {may ? <Btn kind="primary" onClick={openAdd}>Add staff</Btn> : null}
            {may && sel.size ? <Btn kind="urgent" disabled={busy} onClick={() => { setDelMsg(null); setRemoving(pick(staff.filter((s) => sel.has(s.id)))); }}>{`Delete selected (${sel.size})`}</Btn> : null}
            {sel.size ? <Btn kind="ghost" onClick={() => setSel(new Set())}>Clear selection</Btn> : null}
          </div>
        </PBody>
        {delMsg ? <PBody><Note kind="ok" title="Staff deleted or deactivated">{delMsg}</Note></PBody> : null}
        {saveMsg ? <PBody><Note kind="ok" title="Saved">{saveMsg}</Note></PBody> : null}
        {shown.length ? (
          <DTable cols={[...(may ? ["|mid"] : []), "Staff id", "Name", "Department", "Rank", "Sign-in", ...(may ? ["|num"] : [])]} rows={shown.slice(0, 500).map((s) => [
            ...(may ? [<input type="checkbox" key="x" checked={sel.has(s.id)} onChange={() => toggle(s.id)} aria-label={`Select ${s.name}`} />] : []),
            <span className="tnum b700" key="i">{s.staff_number ?? "—"}</span>,
            <span key="n">{s.name}{s.sex ? <span className="sub2"> · {s.sex}</span> : null}</span>,
            <span key="d">{s.departments ?? s.home_department ?? "—"}</span>,
            <span key="r" className="sub2">{s.present_rank ?? "—"}{s.conuass_step ? ` · CONUASS ${s.conuass_step}` : ""}</span>,
            s.has_signin
              ? (s.last_sign_in_at ? <Pil kind="ok" key="s">Active</Pil> : s.must_change ? <Pil kind="info" key="s">First password set</Pil> : <Pil kind="ok" key="s">Issued</Pil>)
              : <Pil kind="grey" key="s">No sign-in</Pil>,
            ...(may ? [<span key="e" className="row row--inline row--tight">
              <Btn kind="ghost" onClick={() => openEdit(s)}>Edit</Btn>
              <Btn kind="ghost" aria-label={`Delete ${s.name}`} onClick={() => { setDelMsg(null); setRemoving(pick([s])); }}>Delete</Btn>
            </span>] : []),
          ])} />
        ) : <PBody><div className="sub2">{staff.length ? "No staff match that search." : "No teaching staff on record yet. Upload the list above, or add one."}</div></PBody>}
        {may && shown.length ? (
          <PBody><label className="sub2 row row--inline row--tight" style={{ cursor: "pointer" }}>
            <input type="checkbox" checked={allShownPicked} onChange={toggleAll} /> Select all {shown.length > 500 ? "(first 500) " : ""}shown
          </label></PBody>
        ) : null}
        {shown.length > 500 ? <PBody><div className="sub2">Showing the first 500 of {shown.length}. Narrow the search to find a particular lecturer.</div></PBody> : null}
      </Panel>

      <RemovedStaff changes={removed} may={may} />

      {removing ? (
        <RemoveStaff people={removing} what="Teaching staff" onClose={() => setRemoving(null)}
          onDone={(m) => { setRemoving(null); setSel(new Set()); setSaveMsg(null); setDelMsg(m); router.refresh(); }} />
      ) : null}

      {form ? (
        <Modal title={form.id ? `Edit ${form.pno || "staff"}` : "Add a staff member"} onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !form.surname.trim() || !form.given.trim() || !form.department.trim() || (!form.id && !form.pno.trim())} onClick={() => void saveStaff()}>{busy ? "Saving…" : form.id ? "Save changes" : "Add staff"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="sub2 mb-3">
            {form.id ? "The staff id and sign-in are not changed here. Changing the department moves the lecturer office to the new one." : "The staff id becomes P<number>, and is the username and first password (must be changed on first sign-in). The department must already exist."}
          </div>
          <div className="grid grid--2">
            <Field id="lf-pno" label="Staff number (PNO)" hint={form.id ? "Cannot change here" : "Digits only — becomes P<number>"}>
              <input id="lf-pno" className="ctl tnum" value={form.pno} disabled={!!form.id} onChange={(e) => setForm({ ...form, pno: e.target.value })} placeholder="99029" />
            </Field>
            <Field id="lf-dept" label="Department" hint="Code or name">
              <input id="lf-dept" className="ctl" value={form.department} onChange={(e) => setForm({ ...form, department: e.target.value })} placeholder="ACCOUNTING" />
            </Field>
            <Field id="lf-sur" label="Surname"><input id="lf-sur" className="ctl" value={form.surname} onChange={(e) => setForm({ ...form, surname: e.target.value })} /></Field>
            <Field id="lf-giv" label="Given names"><input id="lf-giv" className="ctl" value={form.given} onChange={(e) => setForm({ ...form, given: e.target.value })} /></Field>
            <Field id="lf-sex" label="Sex">
              <select id="lf-sex" className="ctl" value={form.sex} onChange={(e) => setForm({ ...form, sex: e.target.value })}><option value="">—</option><option value="M">M</option><option value="F">F</option></select>
            </Field>
            <Field id="lf-rank" label="Present rank"><input id="lf-rank" className="ctl" value={form.rank} onChange={(e) => setForm({ ...form, rank: e.target.value })} placeholder="PROFESSOR" /></Field>
            <Field id="lf-phone" label="Phone"><input id="lf-phone" className="ctl tnum" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></Field>
            <Field id="lf-conuass" label="CONUASS"><input id="lf-conuass" className="ctl tnum" value={form.conuass} inputMode="numeric" onChange={(e) => setForm({ ...form, conuass: e.target.value })} placeholder="7" /></Field>
            <Field id="lf-email" label="Email"><input id="lf-email" className="ctl" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
