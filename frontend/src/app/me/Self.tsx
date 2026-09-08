/**
 * Leave and payslip — proto/part17.html rSelf. The record is real: the
 * person is iam.person and the offices are iam.office_assignment, each with
 * the instrument it is held under. Everything else on this screen belongs to
 * a Staff module that is not on the portal yet, so the figures are an em
 * dash and the screen says why rather than showing a plausible number.
 */
import type { Problem } from "@/lib/api";
import { roleLabel, roleUnit } from "@/lib/offices";
import { KvGrid, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { TwoCol } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { d } from "@/lib/calendar";

export interface StaffMe {
  person: { staffNumber: string | null; surname: string; givenNames: string } | null;
  offices: {
    officeCode: string;
    office: string;
    scopeKind: string;
    scopeId: string | null;
    instrument: string;
    validFrom: string;
    validTo: string | null;
  }[];
}

const NOT_YET = "Staff module, not yet on the portal";
const DASH = <span className="sub2">&mdash;</span>;

export function Self({
  staff,
  problem,
  actingOffice,
}: {
  staff: StaffMe | null;
  problem: Problem | null;
  actingOffice: string | null;
}) {
  const person = staff?.person ?? null;
  const offices = staff?.offices ?? [];
  const who = person ? `${person.surname}, ${person.givenNames}` : "Not recorded in the Registry yet";

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles
        items={[
          ["Leave taken", "—", null, NOT_YET],
          ["Leave remaining", "—", null, NOT_YET],
          ["Last payslip", "—", null, NOT_YET],
          ["Appraisal", "—", null, NOT_YET],
        ]}
      />

      <TwoCol>
        <Panel title="My record" right={who}>
          <PBody>
            <KvGrid
              cls="grid--2"
              pairs={[
                ["Staff number", person?.staffNumber ? <span className="tnum">{person.staffNumber}</span> : DASH],
                ["Office", roleLabel(actingOffice)],
                ["Unit", roleUnit(actingOffice) || DASH],
                ["Appointment", DASH],
                ["Grade", DASH],
                ["Next increment", DASH],
              ]}
            />
            {person ? null : (
              <Note kind="info" title="You are signed in, but the Registry has no record of you yet">
                Your token names an office, which is why this screen opens; the person behind it is created by the Registry,
                with the letter that appointed you. Until that is recorded, the name, the staff number and the offices below
                are empty rather than assumed.
              </Note>
            )}
          </PBody>
        </Panel>

        <Panel title="Payslips" right="Twelve months">
          <DTable cols={["Month|mid", "Net|mid", "Action|num"]} rows={[]} />
          <PBody>
            <Note kind="info" title="Payslips arrive with the Staff module">
              Payroll is not on this portal. When it is, twelve months of payslips are listed here and each one downloads as
              the document the Bursary issued &mdash; not a page rendered to look like it.
            </Note>
          </PBody>
        </Panel>
      </TwoCol>

      <Panel title="Offices held" right="Each under the instrument that granted it">
        {offices.length === 0 ? (
          <PBody>
            <Note kind="info" title="No office assignment is recorded against you">
              An office is held under a letter or a minute, and the portal holds none for you. It is granted by the
              Registrar, recorded with that instrument, and an acting one carries the date it lapses on.
            </Note>
          </PBody>
        ) : (
          <DTable
            cols={["Office|mid", "Scope", "Instrument", "From|mid", "Until|mid"]}
            rows={offices.map((o) => [
              <strong key="o">{o.office}</strong>,
              <span className="sub2" key="s">
                {o.scopeKind}
                {o.scopeId ? ` · ${o.scopeId}` : ""}
              </span>,
              <span className="sub2 tnum" key="i">{o.instrument}</span>,
              <span className="tnum" key="f">{d(o.validFrom)}</span>,
              o.validTo ? <span className="tnum" key="t">{d(o.validTo)}</span> : <span className="sub2" key="t">&mdash;</span>,
            ])}
          />
        )}
      </Panel>

      <Panel title="Leave">
        <DTable cols={["Type", "From|mid", "To|mid", "Days|mid", "Status|num"]} rows={[]} />
        <PBody>
          <Note kind="info" title="Leave arrives with the Staff module">
            Applying for leave, and approving it, is the Staff module&rsquo;s work. Nothing is shown here in the meantime,
            because a leave balance that is not the payroll&rsquo;s balance is worse than none.
          </Note>
        </PBody>
      </Panel>

      <Note kind="info" title="Leave that overlaps a teaching commitment needs a named replacement">
        The request carries the courses you teach in that window and asks who will take them. A Head of Department approving
        leave is therefore approving a specific arrangement, not a date range.
      </Note>
    </>
  );
}
