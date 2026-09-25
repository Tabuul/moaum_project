"use client";

/**
 * The biodata — proto/part23.html: BIO_SECTIONS in the nav, the three tiers the
 * screen exists to hold apart, and a Save-and-continue bar at the foot of each
 * section. A field read from JAMB is read-only; a field of the student's own is
 * written when the section is saved; a field that changes only on evidence
 * raises a request the Registry decides. State of origin, its local government
 * and nationality are chosen from lists, not typed.
 */
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import type { BiodataField, StudentRecord, Tier } from "@/lib/student";
import { fullName, statusLabel } from "@/lib/student";
import { STATES, lgasOf, NATIONALITIES } from "@/lib/nigeria";
import type { Problem } from "@/lib/api";
import { useRouter } from "next/navigation";
import { Btn, Ico, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Passport, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const BIO_SECTIONS: [string, string, string][] = [
  ["identity", "Identity", "Read from JAMB"],
  ["personal", "Personal details", "Yours to keep current"],
  ["contact", "Contact", "How the University reaches you"],
  ["origin", "Origin & sponsorship", "State, local government, who pays"],
  ["family", "Parents or guardian", "For the record and for emergencies"],
  ["kin", "Next of kin & guarantor", "Who is called, and who stands for you"],
  ["health", "Health", "Sensitive — held under consent"],
  ["bank", "Bank account", "For refunds only"],
  ["docs", "Documents", "What the Registry holds"],
  ["history", "Change history", "Every edit, with its author"],
];
const EDITABLE = ["personal", "contact", "origin", "family", "kin", "health", "bank"];

const SECTION_NOTE: Record<string, [("info" | "bad"), string, string]> = {
  contact: ["info", "This is where every notice with a consequence is sent",
    "Results, fee deadlines, registration closing and disciplinary matters go to the phone number and email address below, and to the portal. Keep them current: a notice sent to a number no longer in use is a notice the University considers delivered."],
  origin: ["info", "A scholarship recorded here reaches the Bursary automatically",
    "The board reads its beneficiaries from this field, and the Bursary applies the award against the invoice. A scholarship not recorded here is a scholarship the invoice does not know about."],
  kin: ["bad", "The next of kin is the person the University telephones in an emergency",
    "It is not a formality. If the student is taken to the teaching hospital at two in the morning, this is the number that is dialled, and a wrong one costs time that matters. Check it at the start of every session."],
  health: ["bad", "This section is sensitive personal data under the Nigeria Data Protection Act",
    "It is held under explicit consent, and readable only by the University Health Services and by the student. It is not visible to the department, the lecturers or the Bursary."],
  bank: ["info", "The University pays money out to this account; it never takes money from it",
    "The account is used for refunds — an overpayment, a duplicate payment, a withdrawal, a scholarship credit. No fee is ever collected by direct debit, and the portal does not hold a card."],
};

/** the fields chosen from a list rather than typed */
function optionsFor(field: string, values: Record<string, string>): string[] | null {
  if (field === "nationality") return NATIONALITIES;
  if (field === "state_of_origin" || field === "state_of_residence") return STATES;
  if (field === "lga") return lgasOf(values.state_of_origin ?? "");
  if (field === "marital_status") return ["Single", "Married", "Divorced", "Widowed"];
  if (field === "father_status" || field === "mother_status") return ["Living", "Deceased"];
  return null;
}

/** one field — read-only for a JAMB field, a select where there is a list, otherwise a box.
 *  Defined at module scope so a keystroke does not remount the input and steal focus. */
function Fld({ field, value, options, may, pending, onChange }: {
  field: BiodataField; value: string; options: string[] | null; may: boolean; pending: string | undefined; onChange: (v: string) => void;
}) {
  const badge =
    field.tier === "locked" ? (
      <span className="bio__t bio__t--locked"><Ico name="shield" size={11} w={2.2} />From JAMB</span>
    ) : field.tier === "approval" ? (
      <span className="bio__t bio__t--appr"><Ico name="scale" size={11} w={2.2} />Needs approval</span>
    ) : null;
  let control: React.ReactNode;
  if (field.tier === "locked") {
    control = <div className="ctl ctl--ro">{value || "—"}<Ico name="shield" size={14} stroke="var(--faint)" w={2} /></div>;
  } else if (options) {
    const list = value && !options.includes(value) ? [value, ...options] : options;
    control = (
      <select className="ctl" value={value} disabled={!may} onChange={(e) => onChange(e.target.value)}>
        <option value="">Select…</option>
        {list.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
    );
  } else if (field.wide) {
    control = <textarea className="ctl" rows={2} value={value} disabled={!may} onChange={(e) => onChange(e.target.value)} />;
  } else {
    control = <input className="ctl" value={value} disabled={!may} autoComplete="off" onChange={(e) => onChange(e.target.value)} />;
  }
  return (
    <div className={`bio__f${field.wide ? " bio__f--wide" : ""}${field.tier === "approval" ? " is-appr" : ""}${field.tier === "locked" ? " is-locked" : ""}`}>
      <label>{field.label}{badge}</label>
      {control}
      {pending ? <div className="hint">Waiting on the Registry: &rarr; {pending}</div> : null}
      {field.hint ? <div className="hint">{field.hint}</div> : null}
    </div>
  );
}

export function Biodata({ record, may, base }: { record: StudentRecord; may: boolean; base?: string }) {
  const router = useRouter();
  const [section, setSection] = useState("identity");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState<string | null>(null);
  const [asked, setAsked] = useState(false);
  const s = record.student;
  const writeBase = base ?? `/api/bff/api/v1/student/students/${s.id}`;
  const pending = new Map(record.pendingChanges.map((c) => [c.field, c.toValue]));

  // the current value of every editable field, from the record, overlaid with what has been typed
  const original: Record<string, string> = {};
  for (const bf of record.biodata) original[bf.field] = bf.value ?? "";
  const [edits, setEdits] = useState<Record<string, string>>({});
  const val = (field: string) => (field in edits ? edits[field] : (original[field] ?? ""));
  const values: Record<string, string> = {};
  for (const bf of record.biodata) values[bf.field] = val(bf.field);

  function set(field: string, value: string) {
    setEdits((e) => ({ ...e, [field]: value }));
  }

  async function putField(field: string, value: string): Promise<"saved" | "asked" | "error"> {
    const r = await fetch(`${writeBase}/biodata/${field}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Biodata: ${field}`) },
      body: JSON.stringify({ value }),
    });
    if (r.ok) {
      const b = (await r.json().catch(() => null)) as { pending?: boolean } | null;
      return b?.pending ? "asked" : "saved";
    }
    const j = await r.json().catch(() => null);
    setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
    return "error";
  }

  /** save every changed field in the section; open fields are written, approval fields raise a request */
  async function saveSection(advance: boolean) {
    const fields = record.biodata.filter((f) => f.section === section && f.tier !== "locked");
    const changed = fields.filter((f) => (f.field in edits) && edits[f.field] !== (original[f.field] ?? ""));
    setBusy(true);
    setProblem(null);
    setSaved(null);
    setAsked(false);
    let n = 0;
    let raised = false;
    for (const f of changed) {
      const outcome = await putField(f.field, edits[f.field].trim());
      if (outcome === "error") { setBusy(false); return; }
      if (outcome === "asked") raised = true;
      n += 1;
    }
    setBusy(false);
    if (raised) setAsked(true);
    setSaved(n ? `${n} change${n === 1 ? "" : "s"} saved` : "Nothing to save on this section");
    if (n) { notify("Biodata updated"); router.refresh(); }
    if (advance) {
      const i = BIO_SECTIONS.findIndex((x) => x[0] === section);
      const next = BIO_SECTIONS.slice(i + 1).find((x) => EDITABLE.includes(x[0]) || x[0] === "docs" || x[0] === "history");
      if (next) setSection(next[0]);
    }
  }

  const identity: BiodataField[] = [
    ["Surname", s.surname],
    ["Other names", s.otherNames],
    ["Date of birth", s.dateOfBirth ? day(s.dateOfBirth) : "—"],
    ["Sex", s.sex === "F" ? "Female" : s.sex === "M" ? "Male" : "—"],
    ["JAMB registration number", s.jambRegNo ?? "—"],
    ["Matriculation number", s.matricNo ?? "Not yet matriculated"],
    ["Admission number", s.admissionNo ?? "—"],
    ["Programme", s.programmeName],
    ["Faculty", s.facultyName],
    ["Department", s.deptName],
    ["Level", String(s.currentLevel)],
    ["Entry mode", statusLabel(s.entryMode)],
    ["Session of entry", s.entrySession],
    ["Status", statusLabel(s.status)],
  ].map(([label, value], i) => ({ field: `identity-${i}`, section: "identity", label, tier: "locked" as Tier, hint: null, wide: false, ord: i, value }));

  const fields = section === "identity" ? identity : record.biodata.filter((f) => f.section === section);
  const note = SECTION_NOTE[section];
  const meta = BIO_SECTIONS.find((x) => x[0] === section) ?? BIO_SECTIONS[0];
  const sectionChanged = record.biodata.some((f) => f.section === section && f.tier !== "locked" && (f.field in edits) && edits[f.field] !== (original[f.field] ?? ""));
  const idx = BIO_SECTIONS.findIndex((x) => x[0] === section);
  const isLast = idx === BIO_SECTIONS.length - 1;

  return (
    <div className="bio">
      <div className="bio__nav">
        {BIO_SECTIONS.map((x) => (
          <button className={`bio__s${section === x[0] ? " is-on" : ""}`} key={x[0]} onClick={() => { setSection(x[0]); setSaved(null); setAsked(false); }}>
            <span className="t">{x[1]}</span>
            <span className="d">{x[2]}</span>
          </button>
        ))}
      </div>

      <div className="bio__body">
        {problem ? <ProblemNotice problem={problem} /> : null}
        {saved ? <Note kind="ok" title={saved}>{may ? "Your changes are on the record." : ""}</Note> : null}
        {asked ? (
          <Note kind="info" title="A change of an evidence field has been sent to the Registry">
            A field of this kind is not changed by the person it describes. The Registry will ask for the evidence, compare it with the record, and either make the change with the evidence attached or refuse it with a reason &mdash; both appear in the change history.
          </Note>
        ) : null}

        {section === "identity" ? (
          <Note kind="info" title="Three kinds of field, and the difference matters">
            Most of this record is the student&rsquo;s own &mdash; contact details, next of kin, health, sponsorship &mdash; and changes here whenever it changes. A few fields are read from JAMB and are corrected with JAMB, not here. A few more change only on evidence the Registry has seen, because they decide fee status, quota or who a person is on a certificate.
          </Note>
        ) : null}
        {note ? <Note kind={note[0]} title={note[1]}>{note[2]}</Note> : null}

        {section === "docs" ? (
          <Panel title="Documents the Registry holds" right="Uploaded at application and clearance">
            {record.documents.length === 0 ? (
              <PBody><Note kind="bad" title="The Registry holds no document for this student">A document appears here when it is received at application or at clearance.</Note></PBody>
            ) : (
              <DTable cols={["Document", "Source", "Received|mid", "Status|num"]} rows={record.documents.map((d) => [
                <Two a={d.kind} b={d.detail ?? ""} key="k" />,
                <span className="sub2" key="s">{d.source}</span>,
                <span className="sub2 tnum" key="r">{day(d.receivedOn)}</span>,
                <Pil kind={d.status === "NOT_SUPPLIED" || d.status === "REFUSED" ? "bad" : "ok"} key="st">{statusLabel(d.status)}</Pil>,
              ])} texts={record.documents.map((d) => `${d.kind} ${d.source} ${d.status}`)} title="Documents" />
            )}
          </Panel>
        ) : section === "history" ? (
          <Panel title="Change history" right={`${record.decidedChanges.length + record.pendingChanges.length} entries`}>
            {record.decidedChanges.length + record.pendingChanges.length === 0 ? (
              <PBody><span className="sub2">No field of this record has been asked to change on evidence. Self-service changes to open fields are kept on the audit spine; requests on evidence appear here.</span></PBody>
            ) : (
              <DTable cols={["When|mid", "Field", "From", "To", "Basis|num"]} rows={[...record.decidedChanges, ...record.pendingChanges].map((c) => [
                <span className="sub2 tnum" key="w">{day("decidedAt" in c && c.decidedAt ? (c.decidedAt as string) : c.requestedAt)}</span>,
                c.label,
                <span className="sub2" key="f">{c.fromValue ?? "—"}</span>,
                <span className="sub2" key="t">{c.toValue}</span>,
                <Pil kind={c.state === "APPROVED" ? "ok" : c.state === "REFUSED" ? "bad" : "warn"} key="b">{statusLabel(c.state)}</Pil>,
              ])} texts={[...record.decidedChanges, ...record.pendingChanges].map((c) => `${c.label} ${c.toValue} ${c.state}`)} title="Change history" />
            )}
          </Panel>
        ) : (
          <Panel title={meta[1]} right={meta[2]}>
            <PBody>
              <div className="bio__grid">{fields.map((f) => <Fld key={f.field} field={f} value={f.section === "identity" ? (f.value ?? "") : val(f.field)} options={f.section === "identity" ? null : optionsFor(f.field, values)} may={may} pending={pending.get(f.field)} onChange={(v) => set(f.field, v)} />)}</div>
            </PBody>
            {may && EDITABLE.includes(section) ? (
              <div className="card__body row" style={{ flexDirection: "row", borderTop: "1px solid var(--line-2)" }}>
                <span className="sub2">{sectionChanged ? "Unsaved changes on this section" : "No unsaved changes"}</span>
                <span className="grow" />
                <Btn kind="ghost" disabled={busy || !sectionChanged} onClick={() => void saveSection(false)}>{busy ? "Saving…" : "Save"}</Btn>
                <Btn kind="primary" disabled={busy} onClick={() => void saveSection(true)}>{busy ? "Saving…" : "Save and continue →"}</Btn>
              </div>
            ) : null}
          </Panel>
        )}

        {section === "docs" ? (
          <Panel title="Photograph" right="The one that identifies them everywhere">
            <PBody>
              <div className="row row--top" style={{ gap: "var(--s-5)" }}>
                <Passport w={104} h={128} src={`/api/bff/api/v1/student/students/${s.id}/passport`} alt={`${fullName(s)} — passport photograph`} />
                <div className="grow" style={{ minWidth: 220 }}>
                  <div className="sub2" style={{ lineHeight: 1.65 }}>This photograph is checked at the door of every examination hall, printed on the identity card, and the image on the certificate. Replacing it is a Registry decision, not a self-service change.</div>
                </div>
              </div>
            </PBody>
          </Panel>
        ) : null}

        {!may && section !== "identity" && section !== "docs" && section !== "history" ? (
          <Note kind="info" title="You are reading this record, not editing it">The biodata is the student&rsquo;s own or the Registry&rsquo;s to write. Your office may read it so it knows what the University holds.</Note>
        ) : null}
      </div>
    </div>
  );
}
