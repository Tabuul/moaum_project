/**
 * Leave and payslip — proto/part17.html rSelf. The record is real: the
 * person is iam.person and the offices are iam.office_assignment, each with
 * the instrument it is held under. Everything else on this screen belongs to
 * a Staff module that is not on the portal yet, so the figures are an em
 * dash and the screen says why rather than showing a plausible number.
 */
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { roleLabel, roleUnit } from "@/lib/offices";
import { KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { TwoCol } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { d } from "@/lib/calendar";
import { money } from "@/lib/format";
import { LeaveSelf, type MyLeave } from "./LeaveSelf";

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

export interface Payslip {
  period: string; state: string; paid_at: string | null;
  grade: string; step: number; category: string;
  basic: number; allowances: number; gross: number; pension: number; paye: number; other_deductions: number; net: number;
}

const NOT_YET = "Staff module, not yet on the portal";
const DASH = <span className="sub2">&mdash;</span>;

function monthLabel(period: string): string {
  return new Date(period).toLocaleDateString("en-GB", { month: "long", year: "numeric" });
}

export function Self({
  staff,
  payslips,
  leave,
  problem,
  actingOffice,
}: {
  staff: StaffMe | null;
  payslips: Payslip[];
  leave: MyLeave | null;
  problem: Problem | null;
  actingOffice: string | null;
}) {
  const person = staff?.person ?? null;
  const offices = staff?.offices ?? [];
  const who = person ? `${person.surname}, ${person.givenNames}` : "Not recorded in the Registry yet";
  const latest = payslips[0] ?? null;
  const bal = leave && leave.isStaff && typeof leave.balance === "number" ? leave.balance : null;
  const taken = bal == null ? null : Math.max(0, 30 - bal);

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles
        items={[
          taken == null ? ["Leave taken", "—", null, "Annual, this year"] : ["Leave taken", `${taken} days`, null, "Annual, this year"],
          bal == null ? ["Leave remaining", "—", null, "Annual entitlement"] : ["Leave remaining", `${bal} days`, null, "Annual entitlement"],
          latest ? ["Last payslip", money(Number(latest.net)), "var(--green-ink)", `${monthLabel(latest.period)} · net`] : ["Last payslip", "—", null, "No payslip yet"],
          ["Appraisal", "—", null, NOT_YET],
        ]}
      />

      <TwoCol>
        <Panel title="My record" right={<Link href="/me/profile" className="btn btn--primary btn--sm">Edit my profile</Link>}>
          <PBody>
            <div className="sub2" style={{ marginBottom: 10 }}>{who}</div>
            <KvGrid
              cls="grid--2"
              pairs={[
                ["Staff number", person?.staffNumber ? <span className="tnum">{person.staffNumber}</span> : DASH],
                ["Office", roleLabel(actingOffice)],
                ["Unit", roleUnit(actingOffice) || DASH],
                ["Appointment", DASH],
                ["Grade", latest ? <span>{latest.grade} · {latest.step}</span> : DASH],
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

        <Panel title="Payslips" right={payslips.length ? `${payslips.length} month${payslips.length === 1 ? "" : "s"}` : "None yet"}>
          {payslips.length ? (
            <DTable cols={["Month|mid", "Gross|num", "Pension|num", "PAYE|num", "Net|num", "Stage|mid"]} rows={payslips.map((s) => [
              <span className="tnum" key="m">{monthLabel(s.period)}</span>,
              <span className="tnum sub2" key="g">{money(Number(s.gross))}</span>,
              <span className="tnum sub2" key="pe">{money(Number(s.pension))}</span>,
              <span className="tnum sub2" key="pa">{money(Number(s.paye))}</span>,
              <b className="tnum" key="n">{money(Number(s.net))}</b>,
              <Pil kind={s.state === "PAID" ? "ok" : "info"} key="s">{s.state === "PAID" ? "Paid" : "Approved"}</Pil>,
            ])} />
          ) : (
            <PBody>
              <Note kind="info" title="No payslip yet">
                A payslip appears here once the Human Resource office has built and approved the month&rsquo;s payroll and you were on the establishment for it. A draft run is not shown — only an approved or paid one.
              </Note>
            </PBody>
          )}
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

      {leave ? <LeaveSelf d={leave} /> : null}

      <Note kind="info" title="Leave that overlaps a teaching commitment needs a named replacement">
        Name who will take your duties in the Cover field. A Head of Department approving leave is therefore approving a
        specific arrangement, not a date range.
      </Note>
    </>
  );
}
