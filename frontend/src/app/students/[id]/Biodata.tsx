"use client";

/**
 * The biodata — proto/part23.html: BIO_SECTIONS in the nav, fld() in the
 * grid, and the three tiers the whole screen exists to hold apart. A field
 * read from JAMB is read-only and says so; a field of the student's own is
 * written where it stands, on leaving it; a field that changes only on
 * evidence raises a request the Registry decides, and says that too.
 */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import type { BiodataField, StudentRecord, Tier } from "@/lib/student";
import { statusLabel } from "@/lib/student";
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

/** fld(label, value, tier, hint, wide) */
function Fld({
  field,
  pending,
  may,
  onWrite,
}: {
  field: BiodataField;
  pending: string | null;
  may: boolean;
  onWrite: (field: BiodataField, value: string) => void;
}) {
  const value = field.value ?? "";
  const badge =
    field.tier === "locked" ? (
      <span className="bio__t bio__t--locked">
        <Ico name="shield" size={11} w={2.2} />
        From JAMB
      </span>
    ) : field.tier === "approval" ? (
      <span className="bio__t bio__t--appr">
        <Ico name="scale" size={11} w={2.2} />
        Needs approval
      </span>
    ) : null;

  const control =
    field.tier === "locked" ? (
      <div className="ctl ctl--ro">
        {value || "—"}
        <Ico name="shield" size={14} stroke="var(--faint)" w={2} />
      </div>
    ) : field.wide ? (
      <textarea
        className="ctl"
        rows={2}
        defaultValue={value}
        disabled={!may}
        onBlur={(e) => e.target.value !== value && onWrite(field, e.target.value)}
      />
    ) : (
      <input
        className="ctl"
        defaultValue={value}
        disabled={!may}
        autoComplete="off"
        onBlur={(e) => e.target.value !== value && onWrite(field, e.target.value)}
      />
    );

  return (
    <div
      className={`bio__f${field.wide ? " bio__f--wide" : ""}${field.tier === "approval" ? " is-appr" : ""}${
        field.tier === "locked" ? " is-locked" : ""
      }`}
    >
      <label>
        {field.label}
        {badge}
      </label>
      {control}
      {pending ? <div className="hint">Waiting on the Registry: &rarr; {pending}</div> : null}
      {field.hint ? <div className="hint">{field.hint}</div> : null}
    </div>
  );
}

export function Biodata({ record, may, base }: { record: StudentRecord; may: boolean; base?: string }) {
  const router = useRouter();
  const [section, setSection] = useState("identity");
  const [asked, setAsked] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const s = record.student;
  const pending = new Map(record.pendingChanges.map((c) => [c.field, c.toValue]));
  // the Registry writes at /student/students/{id}; the student writes their own at /me
  const writeBase = base ?? `/api/bff/api/v1/student/students/${s.id}`;

  async function write(field: BiodataField, value: string) {
    setProblem(null);
    const response = await fetch(`${writeBase}/biodata/${field.field}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Biodata: ${field.label}`) },
      body: JSON.stringify({ value }),
    });
    if (response.ok) {
      const body = (await response.json().catch(() => null)) as { pending?: boolean } | null;
      if (body?.pending) setAsked(true);
      router.refresh();
      return;
    }
    const json = await response.json().catch(() => null);
    setProblem(
      json && typeof json === "object" && "status" in json
        ? (json as Problem)
        : { status: response.status, title: response.statusText },
    );
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
  ].map(([label, value], i) => ({
    field: `identity-${i}`,
    section: "identity",
    label,
    tier: "locked" as Tier,
    hint: label === "Matriculation number" ? "Never changes, for the rest of their life" : null,
    wide: false,
    ord: i,
    value,
  }));

  const fields = section === "identity" ? identity : record.biodata.filter((f) => f.section === section);
  const note = SECTION_NOTE[section];
  const meta = BIO_SECTIONS.find((x) => x[0] === section) ?? BIO_SECTIONS[0];

  return (
    <div className="bio">
      <div className="bio__nav">
        {BIO_SECTIONS.map((x) => (
          <button className={`bio__s${section === x[0] ? " is-on" : ""}`} key={x[0]} onClick={() => setSection(x[0])}>
            <span className="t">{x[1]}</span>
            <span className="d">{x[2]}</span>
          </button>
        ))}
      </div>

      <div className="bio__body">
        {problem ? <ProblemNotice problem={problem} /> : null}

        {asked ? (
          <Note
            kind="info"
            title="That change has been sent to the Registry"
            action={
              <Btn kind="ghost" onClick={() => setAsked(false)}>
                Dismiss
              </Btn>
            }
          >
            A field of this kind is not changed by the person it describes. The Registry will ask for the evidence,
            compare it with the record, and either make the change with the evidence attached or refuse it with a reason
            &mdash; both of which appear in the change history.
          </Note>
        ) : null}

        {section === "identity" ? (
          <Note kind="info" title="Three kinds of field, and the difference matters">
            Most of this record is the student&rsquo;s own &mdash; contact details, next of kin, health, sponsorship
            &mdash; and changes here whenever it changes. A few fields are read from JAMB and are corrected with JAMB,
            not here. A few more change only on evidence the Registry has seen, because they decide fee status, quota or
            who a person is on a certificate.
          </Note>
        ) : null}

        {note ? (
          <Note kind={note[0]} title={note[1]}>
            {note[2]}
          </Note>
        ) : null}

        {section === "docs" ? (
          <Panel title="Documents the Registry holds" right="Uploaded at application and clearance">
            {record.documents.length === 0 ? (
              <PBody>
                <Note kind="bad" title="The Registry holds no document for this student">
                  A document appears here when it is received at application or at clearance. Nothing is listed as held
                  until it is.
                </Note>
              </PBody>
            ) : (
              <DTable
                cols={["Document", "Source", "Received|mid", "Status|num"]}
                rows={record.documents.map((d) => [
                  <Two a={d.kind} b={d.detail ?? ""} key="k" />,
                  <span className="sub2" key="s">
                    {d.source}
                  </span>,
                  <span className="sub2 tnum" key="r">
                    {day(d.receivedOn)}
                  </span>,
                  <Pil kind={d.status === "NOT_SUPPLIED" || d.status === "REFUSED" ? "bad" : "ok"} key="st">
                    {statusLabel(d.status)}
                  </Pil>,
                ])}
                texts={record.documents.map((d) => `${d.kind} ${d.source} ${d.status}`)}
                title="Documents"
              />
            )}
          </Panel>
        ) : section === "history" ? (
          <>
            <Note kind="info" title="Every change to this record is kept, with who made it and when">
              Nothing is overwritten silently, which is what lets a question about this record years from now be answered
              rather than argued.
            </Note>
            <Panel title="Change history" right={`${record.decidedChanges.length + record.pendingChanges.length} entries`}>
              {record.decidedChanges.length + record.pendingChanges.length === 0 ? (
                <PBody>
                  <span className="sub2">
                    No field of this record has been asked to change. Self-service changes to open fields are kept on the
                    audit spine, and requests on evidence appear here.
                  </span>
                </PBody>
              ) : (
                <DTable
                  cols={["When|mid", "Field", "From", "To", "Basis|num"]}
                  rows={[...record.decidedChanges, ...record.pendingChanges].map((c) => [
                    <span className="sub2 tnum" key="w">
                      {day("decidedAt" in c && c.decidedAt ? (c.decidedAt as string) : c.requestedAt)}
                    </span>,
                    c.label,
                    <span className="sub2" key="f">
                      {c.fromValue ?? "—"}
                    </span>,
                    <span className="sub2" key="t">
                      {c.toValue}
                    </span>,
                    <Pil kind={c.state === "APPROVED" ? "ok" : c.state === "REFUSED" ? "bad" : "warn"} key="b">
                      {statusLabel(c.state)}
                    </Pil>,
                  ])}
                  texts={[...record.decidedChanges, ...record.pendingChanges].map((c) => `${c.label} ${c.toValue} ${c.state}`)}
                  title="Change history"
                />
              )}
            </Panel>
          </>
        ) : (
          <Panel title={meta[1]} right={meta[2]}>
            <PBody>
              <div className="bio__grid">
                {fields.map((f) => (
                  <Fld key={f.field} field={f} pending={pending.get(f.field) ?? null} may={may} onWrite={write} />
                ))}
              </div>
            </PBody>
          </Panel>
        )}

        {section === "docs" ? (
          <Panel title="Photograph" right="The one that identifies them everywhere">
            <PBody>
              <div style={{ display: "flex", gap: 20, alignItems: "flex-start", flexWrap: "wrap" }}>
                <Passport w={104} h={128} />
                <div style={{ flexGrow: 1, minWidth: 220 }}>
                  <div className="sub2" style={{ lineHeight: 1.65 }}>
                    This photograph is checked at the door of every examination hall and again at the seat, it is printed
                    on the identity card, and it is the image on the certificate. Replacing it is therefore a Registry
                    decision, not a self-service change. No photograph is held for this student yet.
                  </div>
                </div>
              </div>
            </PBody>
          </Panel>
        ) : null}

        {!may && section !== "identity" ? (
          <Note kind="info" title="You are reading this record, not editing it">
            The biodata is written by the Academic Office or the Registry. Your office may read it so that it knows what
            the University holds.
          </Note>
        ) : null}
      </div>
    </div>
  );
}
