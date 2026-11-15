"use client";

/** V763: the inter-university transfer form — one student registered at a time, coming in from another university or going out to
 *  one, under V588's rules. The number is looked up first, so the officer sees who the form is about before filling it: a student
 *  going out is the record the number finds (their placement read from it, never typed); a student coming in is matched by the JAMB
 *  number — a record already on the register, an applicant linked to the new record, or no one. The form is checked by the database
 *  (the row's rules and what a form must give besides) and registered as a batch of one for another officer of the Academic Office
 *  or the Registry to decide on the Inter-University Transfer page; nothing on a record changes before then. */
import Link from "next/link";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import type { Structure } from "../../bulk/TransferBulk";
import type { University } from "../UniversityTransfer";
import {
  ACTION, DIRECTION, DOCUMENTS, STATUS, emptyForm, formBody, formErrors, lookedUp, numberOf,
  type CheckedRow, type Direction, type FormField, type Lookup, type TransferForm,
} from "@/lib/university-transfer";

const BASE = "/api/bff/api/v1/transfers/inter-university";
const KEEPERS = ["academic", "registrar", "dregistrar", "super"];
const OTHER_LEVELS = [100, 200, 300, 400, 500, 600, 700];
const words = (s: string | null | undefined) => (s ? s.toLowerCase().replace(/_/g, " ") : "");
const Words = (s: string | null | undefined) => { const w = words(s); return w ? w[0].toUpperCase() + w.slice(1) : ""; };

interface Registered { id: string; ref: string; transferId: string | null; effective_session: string }

async function answer(r: Response) {
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
  return j;
}

/** a numbered part of the form */
function Part({ n, title, right, children }: { n: number; title: string; right?: ReactNode; children: ReactNode }) {
  return <Panel title={`${n} · ${title}`} right={right}><PBody>{children}</PBody></Panel>;
}

/** what a lookup wrote into the form — an applicant's name and sex, a record's placement — so that another number undoes it
 *  wherever the officer left it as it was written */
type Filled = { number: string; values: Partial<Record<"surname" | "otherNames" | "sex" | "faculty" | "dept" | "programme" | "level", string>> };

function unfill(x: TransferForm, by: Filled | null): TransferForm {
  if (!by) return x;
  const y = { ...x } as Record<string, unknown>;
  for (const [k, v] of Object.entries(by.values)) if (y[k] === v) y[k] = "";
  return y as unknown as TransferForm;
}

/** a programme the form offers: an undergraduate one (a postgraduate student is admitted by the School of Postgraduate Studies) */
const undergraduate = (p: object) => (p as { category?: string }).category === "UNDER GRADUATE";

export function UniversityTransferForm({ structure, universities, sessions, office }: {
  structure: Structure; universities: University[]; sessions: { name: string; state: string }[]; office: string | null;
}) {
  const mayRegister = KEEPERS.includes(office ?? "");
  const [f, setF] = useState<TransferForm>(emptyForm("INCOMING"));
  const [found, setFound] = useState<Lookup | null>(null);
  const [filled, setFilled] = useState<Filled | null>(null);
  /** the field errors are shown once the form is checked (the reason too once it is registered) */
  const [shown, setShown] = useState<false | "check" | "register">(false);
  const [check, setCheck] = useState<{ key: string; row: CheckedRow } | null>(null);
  const [done, setDone] = useState<Registered | null>(null);
  const [unis, setUnis] = useState<University[]>(universities);
  const [adding, setAdding] = useState<{ code: string; name: string; country: string } | null>(null);
  const top = useRef<HTMLDivElement>(null);
  /** the Find last asked (direction and number): an answer to an older one is dropped */
  const asked = useRef("");
  /** the form as it stands now, for an answer that arrives after the officer has typed on */
  const latest = useRef(f);
  useEffect(() => { latest.current = f; });

  const set = <K extends FormField>(k: K, v: TransferForm[K]) => setF((x) => ({ ...x, [k]: v }));
  const lookup = lookedUp(f, found);
  const body = useMemo(() => formBody(f, lookup), [f, lookup]);
  const key = JSON.stringify([body, f.session]);
  const errors = formErrors(f, lookup, shown === "register");
  const err = (k: FormField) => (shown ? errors[k] : undefined);
  const checked = check && check.key === key ? check.row : null;
  const incoming = f.direction === "INCOMING";
  const onRecord = incoming && !!lookup?.student;

  const faculties = structure.faculties;
  const departments = useMemo(() => (f.faculty ? faculties.find((x) => x.code === f.faculty)?.departments ?? [] : []), [faculties, f.faculty]);
  const programmes = useMemo(() => (f.dept ? (departments.find((d) => d.code === f.dept)?.programmes ?? []).filter(undergraduate) : []), [departments, f.dept]);
  const levels = programmes.find((p) => p.code === f.programme)?.levels ?? [];
  const open = unis.filter((u) => u.active);
  const chosen = unis.find((u) => u.code === f.universityCode);
  const usable = sessions.filter((s) => !["DRAFT", "CANCELLED"].includes(s.state));

  function direction(d: Direction) {
    if (d === f.direction) return;
    asked.current = "";
    setF({ ...emptyForm(d), session: f.session, reason: f.reason, approvalRef: f.approvalRef });
    setFound(null); setFilled(null); setCheck(null); setShown(false);
  }

  /** the number edited: a lookup for another number no longer stands, and what it filled in goes with it */
  function number(v: string) {
    setCheck(null);
    asked.current = "";
    if (filled && numberOf(v) !== filled.number) {
      const by = filled;
      setF((x) => ({ ...unfill(x, by), number: v }));
      setFilled(null);
    } else {
      set("number", v);
    }
  }

  async function find() {
    const n = numberOf(f.number);
    const d = f.direction;
    if (n.length < 4) {
      notifyProblem({ status: 400, title: d === "INCOMING" ? "Give the JAMB number" : "Give the matriculation or JAMB number", detail: "The student is found by the number first, so no one is placed twice." });
      return;
    }
    const ask = `${d}:${n}`;
    asked.current = ask;
    const j = (await answer(await fetch(`${BASE}/lookup?number=${encodeURIComponent(n)}&direction=${d}`, { cache: "no-store" }))) as Lookup | null;
    if (!j || asked.current !== ask) return;
    // what the last lookup filled in and the officer left as it was is undone; then this one's: coming in, a record's placement
    // (fixed: the transfer is recorded on the record only on its own placement), or an applicant's name and sex where blank
    const base = unfill(latest.current, filled);
    const values: Filled["values"] = {};
    if (d === "INCOMING" && j.student) {
      Object.assign(values, { faculty: j.student.faculty ?? "", dept: j.student.dept ?? "", programme: j.student.programme ?? "", level: j.student.level ? String(j.student.level) : "" });
    } else if (d === "INCOMING" && j.applicant) {
      const a = j.applicant;
      const sex = a.sex === "M" || a.sex === "F" ? a.sex : "";
      if (!base.surname && a.surname) values.surname = a.surname;
      if (!base.otherNames && a.otherNames) values.otherNames = a.otherNames;
      if (!base.sex && sex) values.sex = sex;
    }
    setF({ ...base, ...values } as TransferForm);
    setFilled({ number: n, values });
    setFound({ ...j, direction: d }); setCheck(null);
  }

  /** a university added to the list from the form, and chosen (the Academic Office and the Registry keep the list) */
  async function addUniversity() {
    if (!adding) return;
    const code = adding.code.trim().toUpperCase();
    const j = (await answer(await fetch(`${BASE}/universities`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`University added from the transfer form: ${code}`) },
      body: JSON.stringify({ code, name: adding.name.trim(), country: adding.country.trim() || null, active: true }),
    }))) as University | null;
    if (!j) return;
    setUnis((xs) => [...xs.filter((u) => u.code !== j.code), { ...j, transfers: 0 }]);
    set("universityCode", j.code);
    setAdding(null);
    notify(`${j.code} added to the list of universities`);
  }

  function incomplete(registering: boolean): boolean {
    const e = formErrors(f, lookup, registering);
    const first = Object.keys(e)[0] as FormField | undefined;
    if (!first) return false;
    setShown(registering ? "register" : shown === "register" ? "register" : "check");
    notifyProblem({ status: 400, title: "The form is not complete", detail: e[first] ?? "" });
    document.getElementById(`iutf-${first}`)?.focus();
    return true;
  }

  async function runCheck(): Promise<CheckedRow | null> {
    if (incomplete(false)) return null;
    const j = (await answer(await fetch(`${BASE}/form/check`, { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ form: body, session: f.session || null }) }))) as CheckedRow | null;
    if (!j) return null;
    setCheck({ key, row: j });
    return j;
  }

  async function register() {
    if (incomplete(true)) return;
    if (!checked || checked.status === "INVALID") return;
    const j = (await answer(await fetch(`${BASE}/form`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Inter-university transfer registered on the form: ${f.reason.trim()}`) },
      body: JSON.stringify({ form: body, session: f.session || null, reason: f.reason.trim(), approvalRef: f.approvalRef.trim() || null }),
    }))) as Registered | null;
    if (!j) return;
    setDone(j);
    notify(`${j.ref}: registered; another officer decides it`);
    top.current?.scrollIntoView({ block: "start" });
  }

  function another() {
    asked.current = "";
    setF({ ...emptyForm(f.direction), session: f.session });
    setFound(null); setFilled(null); setCheck(null); setShown(false); setDone(null);
  }

  if (!mayRegister) {
    return (
      <Note kind="info" title="Registered by the Academic Office and the Registry">
        An inter-university transfer is registered on this form by the Academic Office, the Registrar or the Deputy Registrar, and decided by another of them.
        The transfers already recorded are on the <Link className="lnk" href="/transfers/inter-university">Inter-University Transfer</Link> page.
      </Note>
    );
  }

  if (done) {
    return (
      <div ref={top}>
        <Note kind="ok" title={`${done.ref}: registered`}
          action={<span className="row row--tight" style={{ gap: 8 }}>
            <LinkBtn kind="primary" href={`/transfers/inter-university?batch=${encodeURIComponent(done.id)}`}>Open the transfer</LinkBtn>
            <Btn kind="ghost" onClick={() => another()}>Register another</Btn>
          </span>}>
          {checked?.student ?? "The student"} — {DIRECTION[f.direction].toLowerCase()}, {chosen?.name ?? f.universityCode}, session {done.effective_session}. Another officer of the
          Academic Office or the Registry decides it on the Inter-University Transfer page; nothing on the student&apos;s record changes until then.
        </Note>
      </div>
    );
  }

  const student = lookup?.student ?? null;
  return (
    <div ref={top} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <Note kind="info" title="One student at a time, under the rules of the transfer upload">
        Find the student by the number first, so no one is placed twice; fill in the transfer as the Senate approved it; check the form, then register it. Another officer
        of the Academic Office or the Registry decides it; nothing on a record changes before then. Many students at once are uploaded on the{" "}
        <Link className="lnk" href="/transfers/inter-university">Inter-University Transfer</Link> page.
      </Note>

      <Part n={1} title="The transfer">
        <div className="row" role="radiogroup" aria-label="Direction of the transfer" style={{ gap: 10, flexWrap: "wrap" }}>
          {(["INCOMING", "OUTGOING"] as Direction[]).map((d) => (
            <label key={d} style={{ display: "flex", flexDirection: "row", gap: 10, alignItems: "flex-start", cursor: "pointer", padding: "10px 12px", borderRadius: 8, flex: "1 1 260px",
              border: `1px solid ${f.direction === d ? "var(--chrome)" : "var(--line)"}`, background: f.direction === d ? "var(--tint)" : "transparent" }}>
              <input type="radio" name="iutf-direction" checked={f.direction === d} onChange={() => direction(d)} style={{ marginTop: 3 }} />
              <span>
                <span className="b600">{d === "INCOMING" ? "Coming in from another university" : "Going out to another university"}</span>
                <span className="sub2" style={{ display: "block" }}>
                  {d === "INCOMING" ? "Admitted here by transfer: a record is made at the decision, or the one the register holds named"
                    : "Transferred out at the decision: the record and its history kept, the status Transferred out"}
                </span>
              </span>
            </label>
          ))}
        </div>
      </Part>

      <Part n={2} title="The student">
        <form className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-start" }} onSubmit={(e) => { e.preventDefault(); void find(); }}>
          <Field id="iutf-number" label={incoming ? "JAMB registration number" : "Matriculation or JAMB number"} required error={err("number")}
            hint={incoming ? "How the student is matched, so no one is placed twice" : "The record the number finds is the one transferred out"}>
            <input id="iutf-number" className="ctl" value={f.number} maxLength={40} autoComplete="off" style={{ minWidth: 240 }}
              onChange={(e) => number(e.target.value)} />
          </Field>
          <div style={{ paddingTop: 22 }}><Btn kind="ghost" type="submit" busyLabel="Finding…">Find</Btn></div>
        </form>

        {lookup ? (
          <div className="mt-1">
            {lookup.pendingRef ? (
              <Note kind="bad" title={`A transfer of this student awaits a decision already (${lookup.pendingRef})`}>
                It is decided on the Inter-University Transfer page before another is registered.
              </Note>
            ) : null}
            {student ? (
              <>
                <Note kind={student.live ? (incoming ? "info" : "ok") : "bad"}
                  title={incoming ? `On the register already: ${student.name}` : student.live ? `${student.name}` : `${student.name}: the record is ${words(student.status)}`}>
                  {incoming
                    ? student.live
                      ? "The transfer is recorded on this record, on its own placement (filled in below); a change of placement is a programme swap, never a second record."
                      : "A closed record is taken up again by the Registry, never made a second time."
                    : student.live
                      ? "The transfer is made on this record; the faculty, department, programme and level are the record's own."
                      : "Only a live record is transferred out."}
                </Note>
                <KvGrid cls="grid--4" pairs={[
                  ["Matriculation number", student.matricNo ?? "—"], ["JAMB number", student.jambRegNo ?? "—"],
                  ["Programme", student.programmeName ?? student.programme ?? "—"], ["Level", student.level ?? "—"],
                  ["Faculty / department", `${student.faculty ?? "—"} / ${student.dept ?? "—"}`], ["Status", <Pil key="s" kind={student.live ? "ok" : "bad"}>{Words(student.status)}</Pil>],
                  ["Found by", lookup.matchedBy === "FORMER_MATRIC" ? "a former matriculation number" : lookup.matchedBy === "JAMB" ? "the JAMB number" : "the matriculation number"],
                  ["Record", <Link key="r" className="lnk" href={`/students/${student.id}`}>Open the record</Link>],
                ]} />
              </>
            ) : incoming && lookup.applicant ? (
              <Note kind="info" title={`An applicant under this JAMB number: ${lookup.applicant.surname ?? ""}${lookup.applicant.otherNames ? `, ${lookup.applicant.otherNames}` : ""}`}>
                {lookup.applicant.session} · {lookup.applicant.programmeName ?? lookup.applicant.programme ?? "no programme"} · {lookup.applicant.offerState ? words(lookup.applicant.offerState) : "no offer"}.
                The new record is linked to the application, never made twice. The name and sex the application holds are filled in where the form had none;
                put them right only from the student&apos;s documents.
              </Note>
            ) : incoming ? (
              <Note kind="info" title="No student or applicant holds this JAMB number">A record is made for the student when the transfer is approved.</Note>
            ) : (
              <Note kind="bad" title="No student holds that number">Check the matriculation or JAMB number; a student going out is always on the register.</Note>
            )}
          </div>
        ) : f.number.trim() ? <div className="sub2 mt-1">Press Find to see who the number belongs to.</div> : null}

        {incoming && !onRecord ? (
          <div className="grid grid--2 mt-2">
            <Field id="iutf-surname" label="Surname" required error={err("surname")}>
              <input id="iutf-surname" className="ctl" value={f.surname} maxLength={120} onChange={(e) => set("surname", e.target.value)} />
            </Field>
            <Field id="iutf-otherNames" label="Other names" required error={err("otherNames")}>
              <input id="iutf-otherNames" className="ctl" value={f.otherNames} maxLength={160} onChange={(e) => set("otherNames", e.target.value)} />
            </Field>
            <Field id="iutf-sex" label="Sex" required error={err("sex")}>
              <select id="iutf-sex" className="ctl" value={f.sex} onChange={(e) => set("sex", e.target.value as TransferForm["sex"])}>
                <option value="">Choose…</option><option value="F">Female</option><option value="M">Male</option>
              </select>
            </Field>
            <Field id="iutf-dateOfBirth" label="Date of birth" required error={err("dateOfBirth")}>
              <input id="iutf-dateOfBirth" type="date" className="ctl" value={f.dateOfBirth} max={new Date().toISOString().slice(0, 10)} onChange={(e) => set("dateOfBirth", e.target.value)} />
            </Field>
            <Field id="iutf-email" label="E-mail" error={err("email")} hint="Optional: the student's own address">
              <input id="iutf-email" type="email" className="ctl" value={f.email} maxLength={200} onChange={(e) => set("email", e.target.value)} />
            </Field>
            <Field id="iutf-phone" label="Phone" error={err("phone")} hint="Optional: 0803 000 0000 or +234 803 000 0000">
              <input id="iutf-phone" type="tel" className="ctl" value={f.phone} maxLength={20} onChange={(e) => set("phone", e.target.value)} />
            </Field>
          </div>
        ) : null}
      </Part>

      <Part n={3} title={incoming ? "The previous university" : "The receiving university"}
        right={adding ? undefined : <button type="button" className="lnk sub2" onClick={() => setAdding({ code: "", name: "", country: "Nigeria" })}>Not on the list? Add it</button>}>
        {adding ? (
          <div style={{ border: "1px solid var(--line)", borderRadius: 8, padding: "10px 12px", marginBottom: 12 }}>
            <div className="b600">Add a university to the list</div>
            <div className="sub2">Added for every transfer, coming in or going out; a code is never renamed. The form keeps what is filled in.</div>
            <div className="row row--tight mt-1" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-start" }}>
              <Field id="iutf-newCode" label="Code" hint="Capital letters and digits, such as UNIJOS">
                <input id="iutf-newCode" className="ctl" value={adding.code} maxLength={16} style={{ maxWidth: 140 }}
                  onChange={(e) => setAdding({ ...adding, code: e.target.value.toUpperCase() })} />
              </Field>
              <Field id="iutf-newName" label="Name" style={{ flex: "1 1 240px" }}>
                <input id="iutf-newName" className="ctl" value={adding.name} maxLength={200} onChange={(e) => setAdding({ ...adding, name: e.target.value })} />
              </Field>
              <Field id="iutf-newCountry" label="Country">
                <input id="iutf-newCountry" className="ctl" value={adding.country} maxLength={80} style={{ maxWidth: 140 }} onChange={(e) => setAdding({ ...adding, country: e.target.value })} />
              </Field>
              <div className="row row--tight" style={{ gap: 6, paddingTop: 22 }}>
                <Btn kind="primary" disabled={!/^[A-Z][A-Z0-9]{1,15}$/.test(adding.code.trim()) || adding.name.trim().length < 3} busyLabel="Adding…" onClick={() => addUniversity()}>Add and choose it</Btn>
                <Btn kind="ghost" onClick={() => setAdding(null)}>Cancel</Btn>
              </div>
            </div>
          </div>
        ) : null}
        <div className="grid grid--2">
          <Field id="iutf-universityCode" label="University" required error={err("universityCode")}>
            <SearchSelect id="iutf-universityCode" value={f.universityCode} onChange={(v) => set("universityCode", v)} placeholder="Choose the university…"
              options={open.map((u) => ({ value: u.code, label: u.name, sub: u.code }))} />
          </Field>
          <Field id="iutf-otherProgramme" label={incoming ? "Programme studied there" : "Programme there"} required error={err("otherProgramme")}
            hint={incoming ? "As the transcript names it" : "As the letter of acceptance names it"}>
            <input id="iutf-otherProgramme" className="ctl" value={f.otherProgramme} maxLength={200} onChange={(e) => set("otherProgramme", e.target.value)} />
          </Field>
          <Field id="iutf-otherLevel" label={incoming ? "Level reached there" : "Level there"} required={incoming} error={err("otherLevel")} hint={incoming ? undefined : "Optional"}>
            <select id="iutf-otherLevel" className="ctl" value={f.otherLevel} onChange={(e) => set("otherLevel", e.target.value)}>
              <option value="">{incoming ? "Choose…" : "Not stated"}</option>
              {OTHER_LEVELS.map((l) => <option key={l} value={l}>{l} Level</option>)}
            </select>
          </Field>
          <Field id="iutf-otherMatricNo" label="Matriculation number there" required={incoming} error={err("otherMatricNo")} hint={incoming ? undefined : "Optional: when the receiving university has given one"}>
            <input id="iutf-otherMatricNo" className="ctl" value={f.otherMatricNo} maxLength={40} autoComplete="off" onChange={(e) => set("otherMatricNo", e.target.value)} />
          </Field>
          {incoming ? (
            <>
              <Field id="iutf-otherEntrySession" label="Session entered there" error={err("otherEntrySession")} hint="Optional: 2022/2023">
                <input id="iutf-otherEntrySession" className="ctl" value={f.otherEntrySession} maxLength={9} placeholder="2022/2023" onChange={(e) => set("otherEntrySession", e.target.value)} />
              </Field>
              <div className="row row--tight" style={{ gap: 8, alignItems: "flex-start" }}>
                <Field id="iutf-otherCgpa" label="CGPA there" error={err("otherCgpa")} hint="Optional: as the transcript states it" style={{ flex: 1 }}>
                  <input id="iutf-otherCgpa" className="ctl" value={f.otherCgpa} maxLength={4} inputMode="decimal" placeholder="3.45" onChange={(e) => set("otherCgpa", e.target.value)} />
                </Field>
                <Field id="iutf-otherCgpaScale" label="Scale">
                  <select id="iutf-otherCgpaScale" className="ctl" value={f.otherCgpaScale} onChange={(e) => set("otherCgpaScale", e.target.value as TransferForm["otherCgpaScale"])}>
                    <option value="5">5-point</option><option value="4">4-point</option>
                  </select>
                </Field>
              </div>
            </>
          ) : null}
        </div>
      </Part>

      <Part n={4} title={incoming ? "Where the student comes in" : "Where the student is now"}>
        {incoming && onRecord && student ? (
          <>
            <KvGrid cls="grid--4" pairs={[["Faculty", student.faculty ?? "—"], ["Department", student.dept ?? "—"], ["Programme", student.programmeName ?? student.programme ?? "—"],
              ["Level", student.level ?? "—"]]} />
            <div className="sub2 mt-1">The record&apos;s own placement: the transfer is recorded on the record only there. A change of placement is a programme swap.</div>
          </>
        ) : incoming ? (
          <div className="grid grid--2">
            <Field id="iutf-faculty" label="Faculty" required error={err("faculty")}>
              <select id="iutf-faculty" className="ctl" value={f.faculty}
                onChange={(e) => setF((x) => ({ ...x, faculty: e.target.value, dept: "", programme: "", level: "" }))}>
                <option value="">Choose…</option>
                {faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="iutf-dept" label="Department" required error={err("dept")}>
              <select id="iutf-dept" className="ctl" value={f.dept} disabled={!f.faculty}
                onChange={(e) => setF((x) => ({ ...x, dept: e.target.value, programme: "", level: "" }))}>
                <option value="">{f.faculty ? "Choose…" : "Choose the faculty first"}</option>
                {departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
              </select>
            </Field>
            <Field id="iutf-programme" label="Programme" required error={err("programme")}
              hint={f.dept && !programmes.length ? "The department has no undergraduate programme" : "Undergraduate programmes: a postgraduate student is admitted by the School of Postgraduate Studies"}>
              <select id="iutf-programme" className="ctl" value={f.programme} disabled={!f.dept || !programmes.length}
                onChange={(e) => setF((x) => ({ ...x, programme: e.target.value, level: "" }))}>
                <option value="">{f.dept ? "Choose…" : "Choose the department first"}</option>
                {programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
              </select>
            </Field>
            <Field id="iutf-level" label="Level" required error={err("level")} hint={f.programme && !levels.length ? "The programme has no levels set" : "The programme's own levels"}>
              <select id="iutf-level" className="ctl" value={f.level} disabled={!f.programme} onChange={(e) => set("level", e.target.value)}>
                <option value="">{f.programme ? "Choose…" : "Choose the programme first"}</option>
                {levels.map((l) => <option key={l} value={l}>{l} Level</option>)}
              </select>
            </Field>
          </div>
        ) : student ? (
          <KvGrid cls="grid--4" pairs={[["Faculty", student.faculty ?? "—"], ["Department", student.dept ?? "—"], ["Programme", student.programmeName ?? student.programme ?? "—"],
            ["Level", student.level ?? "—"]]} />
        ) : <div className="sub2">Read from the record once the student is found.</div>}
      </Part>

      <Part n={5} title="Documents seen">
        <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
          {DOCUMENTS.filter((d) => d.direction === f.direction).map((d) => (
            <label key={d.code} className="row row--tight" style={{ gap: 8, alignItems: "center", cursor: "pointer" }}>
              <input type="checkbox" className="chk" checked={f.documents.includes(d.code)}
                onChange={(e) => set("documents", e.target.checked ? [...f.documents, d.code] : f.documents.filter((x) => x !== d.code))} />
              <span>{d.label}</span>
            </label>
          ))}
        </div>
        <div className="sub2 mt-1">
          {incoming ? "Tick what the officer saw. A form without the transcript or the letter of release can be registered, with the point noted for the officer who decides it."
            : "Tick what the officer saw. A form without the letter of acceptance can be registered, with the point noted for the officer who decides it."}
        </div>
      </Part>

      <Part n={6} title="The approval">
        <div className="grid grid--2">
          <Field id="iutf-session" label="Effective session" hint="The session the transfer takes effect in">
            <select id="iutf-session" className="ctl" value={f.session} onChange={(e) => set("session", e.target.value)}>
              <option value="">The current session</option>
              {usable.map((s) => <option key={s.name} value={s.name}>{s.name}</option>)}
            </select>
          </Field>
          <Field id="iutf-approvalRef" label="Approval reference" hint="Optional: the Senate minute or memo number">
            <input id="iutf-approvalRef" className="ctl" value={f.approvalRef} maxLength={200} onChange={(e) => set("approvalRef", e.target.value)} />
          </Field>
          <Field id="iutf-reason" label="Reason" required full error={err("reason")} hint="Ten characters or more: the Senate's approval, the University's transfer policy">
            <input id="iutf-reason" className="ctl" value={f.reason} maxLength={2000} onChange={(e) => set("reason", e.target.value)} />
          </Field>
          <Field id="iutf-remarks" label="Remarks" full hint="Optional">
            <textarea id="iutf-remarks" className="ctl" rows={2} value={f.remarks} maxLength={2000} onChange={(e) => set("remarks", e.target.value)} />
          </Field>
        </div>
      </Part>

      {checked ? (
        <Panel title="The check" right={<Pil kind={STATUS[checked.status][1]}>{STATUS[checked.status][0]}</Pil>}>
          <PBody>
            {checked.student ? (
              <div>About <span className="b600">{checked.student}</span>{checked.matricNo ? <span className="tnum"> · {checked.matricNo}</span> : null}
                {checked.jambRegNo ? <span className="tnum"> · JAMB {checked.jambRegNo}</span> : null}</div>
            ) : null}
            {checked.status !== "INVALID" && checked.action ? <div className="b600">The decision would: {ACTION[checked.action].toLowerCase()}.</div> : null}
            {checked.problems.length ? (
              <Note kind="bad" title={checked.problems.length === 1 ? "One thing to put right" : `${checked.problems.length} things to put right`}>
                <ul style={{ margin: 0, paddingLeft: 18 }}>{checked.problems.map((p, i) => <li key={i}>{p.text || p.code}</li>)}</ul>
              </Note>
            ) : null}
            {checked.warnings.length ? (
              <Note kind="info" title="Points for the officer who decides it">
                <ul style={{ margin: 0, paddingLeft: 18 }}>{checked.warnings.map((p, i) => <li key={i}>{p.text || p.code}</li>)}</ul>
              </Note>
            ) : null}
            {checked.status === "VALID" ? <div className="sub2 mt-1">Nothing to look at.</div> : null}
          </PBody>
        </Panel>
      ) : null}

      <div className="row row--tight" style={{ gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <Btn kind="ghost" busyLabel="Checking…" onClick={() => runCheck()}>Check the form</Btn>
        <Btn kind="primary" busyLabel="Registering…" disabled={!checked || checked.status === "INVALID"} onClick={() => register()}>Register the transfer</Btn>
        <span className="sub2">
          {!checked ? (check ? "The form has changed since it was checked: check it again." : "Check the form first; it is checked again when it is registered and when it is decided.")
            : checked.status === "INVALID" ? "Put right what the check names, then check the form again."
              : "Another officer of the Academic Office or the Registry decides it; nothing on a record changes until then."}
        </span>
      </div>
    </div>
  );
}
