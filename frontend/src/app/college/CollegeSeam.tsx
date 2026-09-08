/**
 * The College of Health Sciences — proto/part41.html tCollege, word for
 * word. The only figures that come from the database are the College's
 * address (ref.college.url — the link is disabled until one is recorded)
 * and the number of students on its register.
 */
import type { ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { Note, Panel, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface CollegeData {
  college: { code: string; name: string; system: string | null; url: string | null };
  faculties: { code: string; name: string; students: number }[];
  students: number;
  byLevel: { level: number; students: number }[];
}

const OWN: [ReactNode, string][] = [
  ["Person, identity, credentials", "One person, one identity, however many systems"],
  ["Admission, and the admission number", "Admissions is JAMB-facing and University-wide"],
  [<b key="m">The matriculation number</b>, "Permanent, never reused. Two minting systems make two students out of one person"],
  ["Fees, invoices, the ledger, clearance", "Money is audited centrally and the Bursary is one office"],
  ["The identity card", "One photograph, one record, one card"],
  [<b key="s">Senate approval of a result</b>, "The Registrar signs one transcript from one record"],
  ["The transcript and the certificate", "A degree is the University’s award, not the College’s"],
];

const THEIRS: [ReactNode, string][] = [
  ["Academic periods, and their states", "The Third Semester, the 24- and 30-week posting levels"],
  ["Course offerings within the College", "And registration against them"],
  ["Continuous and clinical assessment", "Five components on a posting, not two"],
  ["Clinical postings", "Schedules, groups, supervisors, attendance, completion"],
  ["Promotion evaluation", "The rules recommend; the College Board decides"],
  ["Professional examinations", "Gated on completed postings"],
];

const TOUCH: [string, ReactNode, string, ReactNode][] = [
  [
    "I-1",
    <>
      <strong>Identity, at sign-in</strong>
      <div className="sub2">OIDC. The token carries the identifier, the matriculation number and the offices held.</div>
    </>,
    "CHS → here",
    <>
      New sign-ins stop. <b>No fallback to a local password store</b> — a fallback is a permanent second door
    </>,
  ],
  [
    "I-2",
    <>
      <strong>Clearance, before registration</strong>
      <div className="sub2">Asked synchronously and never cached.</div>
    </>,
    "CHS → here",
    "Registration is refused, never allowed provisionally. A provisional registration is an unpaid student holding a place",
  ],
  [
    "I-3",
    <>
      <strong>Matriculation</strong>
      <div className="sub2">
        <code>StudentMatriculated</code>. The College creates its record on receipt and never before.
      </div>
    </>,
    "here → CHS",
    "Redelivered from the outbox; handlers are idempotent",
  ],
  [
    "I-4",
    <>
      <strong>Results crossing to Senate</strong>
      <div className="sub2">A reconciliation, not a file drop.</div>
    </>,
    "CHS → here",
    <>The set does not reach Exams &amp; Records until every registered candidate is accounted for</>,
  ],
  [
    "I-5",
    <>
      <strong>Enrolment reconciliation</strong>
      <div className="sub2">Nightly, both directions.</div>
    </>,
    "Both ways",
    <>
      Discrepancies go to the College Secretary <b>and</b> the Registrar — a divergence is a records question before it is a
      technical one
    </>,
  ],
];

function OpenLink({ url, name, small }: { url: string | null; name: string; small?: boolean }) {
  const label = `Open ${name} →`;
  const cls = `btn btn--primary${small ? " btn--sm" : ""}`;
  return url ? (
    <a className={cls} href={url} target="_blank" rel="noopener">
      {label}
    </a>
  ) : (
    <button className={cls} disabled title={`No address recorded for ${name} yet`}>
      {label}
    </button>
  );
}

export function CollegeSeam({ college, problem }: { college: CollegeData | null; problem: Problem | null }) {
  const system = college?.college.system ?? "CHS-AMS";
  const url = college?.college.url ?? null;
  const students = college?.students ?? 0;
  const faculties = college?.faculties ?? [];
  const levels = college?.byLevel.length ?? 0;

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note
        kind="info"
        title="The College of Health Sciences runs a separate system, and this is the seam"
        action={<OpenLink url={url} name={system} small />}
      >
        The MBBS programme does not fit a two-semester calendar, and not marginally: 300 Level runs a twenty-week Third
        Semester, 400 and 500 run twenty-four-week clinical postings, 600 runs thirty weeks, different levels of one
        programme run to different lengths inside one session, and a level can split into an A and a B cohort mid-session. A{" "}
        <code>semester</code> column cannot hold any of that. The College therefore has <b>{system}</b>, integrated with this
        portal for identity, fees and transcripts.
      </Note>

      <Tiles
        items={[
          ["Held by this portal", "7 concerns", null, "Everything that outlives the College"],
          ["Held by CHS-AMS", "6 concerns", "var(--chrome)", "The academic machinery peculiar to it"],
          ["Integration points", "5", null, "Two synchronous, one event, two batch"],
          [
            "Students in the College",
            students.toLocaleString("en-NG"),
            null,
            students === 0
              ? "Nobody is on the College register yet"
              : `Across ${levels} ${levels === 1 ? "level" : "levels"} and ${faculties.length} ${faculties.length === 1 ? "faculty" : "faculties"}`,
          ],
        ]}
      />

      <div className="grid grid--2">
        <Panel title="This portal is the system of record for" right="Anything that outlives the College">
          <DTable cols={["Concern", "Why it sits here|num"]} rows={OWN.map((r) => [r[0], <span className="sub2" key="w">{r[1]}</span>])} />
        </Panel>
        <Panel title={`${system} holds`} right="The academic machinery peculiar to the College">
          <DTable cols={["Concern", "Why it sits there|num"]} rows={THEIRS.map((r) => [r[0], <span className="sub2" key="w">{r[1]}</span>])} />
        </Panel>
      </div>

      <Panel title="Where the two systems touch" right="Each with what happens when it fails">
        <DTable
          cols={["Ref|mid", "What it is", "Direction|mid", "On failure|num"]}
          rows={TOUCH.map((r) => [
            <b className="tnum" key="r">{r[0]}</b>,
            r[1],
            <span className="sub2" key="d">{r[2]}</span>,
            <span className="sub2" key="f">{r[3]}</span>,
          ])}
        />
      </Panel>

      <Note kind="bad" title="Why the results crossing is a reconciliation and not a file drop">
        This portal established that a score roll must be the whole register and not a filtered subset, because a filtered
        sheet <i>looks complete</i> at every desk it passes and the student finds out at graduation.{" "}
        <b>A set arriving from another system is a filtered subset by construction</b> &mdash; it contains exactly what the
        College chose to send. So the crossing counts both directions: entries matched, entries on the register with no mark,
        and entries submitted for somebody not on the register. The set waits until the last two are zero or explained.
        Without that, this boundary would reintroduce precisely the failure the University spent this month eliminating.
      </Note>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <OpenLink url={url} name={system} />
        <span className="sub2">Opens in a new tab. It is a separate system and it looks like one.</span>
      </div>
    </>
  );
}
