"use client";

/**
 * The student's graduation — the loop the Academic Office, Senate, eight clearing
 * units and the Registry close, seen from the end where the student stands.
 * Every line is computed from the record (records.student_graduation, V029).
 */
import Link from "next/link";
import type { Graduation } from "@/lib/student-portal";
import { KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Steps } from "@/components/proto/blocks";
import { onDay } from "./common";

const OFFICE: Record<string, string> = { bursar: "Bursary", hod: "Department", dean: "Faculty", library: "Library", services: "Student Services", registrar: "Registry" };

export function GraduationScreen({ g }: { g: Graduation }) {
  const approved = g.senate_state === "APPROVED";
  const graduated = g.status === "GRADUATED";
  const printed = !!g.certificate_no;
  const collected = g.certificate_status === "COLLECTED";
  const held = g.certificate_status === "HELD";
  const clearance = g.clearance ?? [];
  const holding = clearance.filter((u) => u.state !== "CLEARED");

  const steps: ["done" | "now" | "todo", string, string][] = [
    [g.audited ? "done" : g.finalist ? "now" : "todo", "The degree audit", g.audited ? (g.unmet ? `Run for ${g.session}: ${g.unmet}` : `Run for ${g.session}: every requirement met, CGPA ${g.cgpa}`) : g.finalist ? "Computed by the Academic Office from the published record at the end of the session" : `Runs in your final year (${g.final_level} Level)`],
    [approved ? "done" : g.audited && !g.unmet ? "now" : "todo", "Senate approves the award", approved ? `Minute ${g.senate_minute} · ${g.award} · ${g.class_of_degree ?? "Pass"}` : g.senate_state === "REFERRED" ? "Referred by Senate" : "On the Registrar's minute, and not before"],
    [approved && g.cleared ? "done" : approved ? "now" : "todo", "Cleared for convocation by every unit", approved ? (g.cleared ? "All eight units have cleared you" : `${g.units_holding} unit${g.units_holding === 1 ? "" : "s"} still holding — named below`) : "Bursary, department, faculty, library, health, hostel, works, alumni"],
    [printed ? "done" : approved && g.cleared ? "now" : "todo", "The certificate is printed", printed ? `${g.certificate_no} · ${g.convocation} · printed ${onDay(g.printed_on)}` : "Printed by the Academic Office against a cleared record"],
    [collected ? "done" : printed ? "now" : "todo", "Collected, and verifiable", collected ? `Collected ${onDay(g.collected_on)}${g.verification_code ? ` · code ${g.verification_code}` : ""}` : held ? `Held: ${g.held_reason}` : "Handed over by the Academic Office; the verification code answers anybody who asks"],
  ];

  return (
    <>
      {!g.finalist && !g.audited ? (
        <Note kind="info" title={`Graduation is ${g.final_level - (g.level ?? 0) >= 100 ? `${(g.final_level - (g.level ?? 0)) / 100} year${g.final_level - (g.level ?? 0) > 100 ? "s" : ""} away` : "ahead"}`}>
          You are at {g.level} Level of a programme that ends at {g.final_level} Level. The degree audit is computed in the final year from the published record; nothing here is typed. Until then this screen shows the road, not a result.
        </Note>
      ) : graduated ? (
        <Note kind="ok" title={`Senate approved your award under ${g.senate_minute}`}>
          {g.award} — {g.class_of_degree ?? "Pass"}, CGPA {g.cgpa}. {printed ? (collected ? "Your certificate has been collected." : held ? `Your certificate is printed but held: ${g.held_reason}.` : "Your certificate is printed and waits for you at the Academic Office.") : g.cleared ? "Every unit has cleared you; the certificate is printed next." : `${g.units_holding} unit${g.units_holding === 1 ? "" : "s"} still hold${g.units_holding === 1 ? "s" : ""} your clearance for convocation — the table below names each and what it wants.`}
        </Note>
      ) : g.audited && g.unmet ? (
        <Note kind="bad" title="The degree audit found a requirement unmet">
          {g.unmet}. The Academic Office cannot present you to Senate until it is closed; the department chases it, and the audit is run again.
        </Note>
      ) : g.audited ? (
        <Note kind="info" title="The audit passed; the list is with Senate">
          Every requirement is met with a CGPA of {g.cgpa}. Senate approves the list as a body, on the Registrar&rsquo;s minute. Nothing here changes until it does.
        </Note>
      ) : (
        <Note kind="info" title="Your final year">
          The degree audit is computed at the end of the session from the published record: every compulsory course, the credit minima, every Senate-approved mark. Use the year to clear what the eight units below will ask for.
        </Note>
      )}

      <Tiles items={[
        ["CGPA", g.cgpa === null ? "—" : String(g.cgpa), null, g.class_of_degree ?? (g.audited ? "Pass" : "Computed by the audit")],
        ["Senate", approved ? "Approved" : g.senate_state === "REFERRED" ? "Referred" : g.audited ? "Awaiting" : "—", approved ? "var(--green-ink)" : null, g.senate_minute ?? "On the minute"],
        ["Units clearing you", `${clearance.length - holding.length} of ${clearance.length || 8}`, holding.length && approved ? "var(--red-ink)" : null, holding.length ? `${holding.length} holding` : "All cleared"],
        ["Certificate", printed ? g.certificate_status ?? "Printed" : "Not printed", printed ? "var(--green-ink)" : null, g.certificate_no ?? "Against a cleared record"],
      ]} />

      <div className="grid grid--2">
        <Panel title="The road to the certificate" right="Computed, step by step">
          <PBody><Steps list={steps} /></PBody>
        </Panel>
        <Panel title="Your award" right={g.session ?? ""}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Name", g.name ?? ""],
              ["Matriculation number", g.matricNo ?? "—"],
              ["Programme", g.programme ?? ""],
              ["Award", g.award ?? "As the audit states it"],
              ["Class of degree", g.class_of_degree ?? "From the classification table in force"],
              ["Status on the register", g.status.charAt(0) + g.status.slice(1).toLowerCase()],
            ]} />
          </PBody>
        </Panel>
      </div>

      <Panel title="Clearance for convocation" right="Eight units, each clearing against its own record">
        {clearance.length === 0 ? <PBody><div className="sub2">The clearance units are not on the register.</div></PBody> : (
          <DTable cols={["Unit", "Clears against", "Position", "What is outstanding", "Decided"]}
            rows={clearance.map((u) => [
              <span key="u"><strong>{u.label}</strong><div className="sub2">{u.office_code ? OFFICE[u.office_code] ?? u.office_code : ""}</div></span>,
              <span className="sub2" key="c">{u.clears_against}</span>,
              u.state === "CLEARED" ? <Pil kind="ok" key="s">Cleared</Pil> : u.decided_at ? <Pil kind="bad" key="s">Held</Pil> : <Pil kind="grey" key="s">Not yet cleared</Pil>,
              <span key="i" className={u.item ? "" : "sub2"}>{u.item ?? (u.state === "CLEARED" ? "—" : u.holds_for)}</span>,
              <span className="sub2 tnum" key="d">{u.decided_at ? onDay(u.decided_at) : "—"}</span>,
            ])} />
        )}
      </Panel>

      {printed ? (
        <Panel title="Your certificate" right={g.certificate_status ?? ""}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[
              ["Number", g.certificate_no ?? ""],
              ["Convocation", g.convocation ?? ""],
              ["Printed", onDay(g.printed_on)],
              ["Collected", g.collected_on ? onDay(g.collected_on) : "Not yet — bring your identity card to the Academic Office"],
              ["Verification code", g.verification_code ?? "Issued with the signed record"],
              ["Held", g.held_reason ?? "No"],
            ]} />
            <div className="sub2">An employer or an institution verifies the certificate by its code, without an account, and gets the same answer the University holds: issued, revoked, or not found.</div>
          </PBody>
        </Panel>
      ) : null}

      <Note kind="info" title="A transcript is requested separately, and paid for" action={<Link href="/student/transcript" className="btn btn--ghost btn--sm">Request a transcript</Link>}>
        The certificate names the award; the transcript lists every result behind it. Both are cleared by the same units, and neither is produced while any unit holds you.
      </Note>
    </>
  );
}
