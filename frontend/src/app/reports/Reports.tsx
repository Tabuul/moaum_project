"use client";

import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { REPORTS } from "@/lib/report";

export interface FacultyRow { faculty: string; male: number; female: number; total: number }

/** The returns desk, as the prototype's Reports & returns screen lays it out: the standard reports the
 *  office may take — each with its owner, its frequency, and a Run that opens it as a branded, printable
 *  document with a CSV beside it — and the session's enrolment by faculty, read off the register. */
export function Reports({ session, sessions, activeOffice, byFaculty }: {
  session: string; sessions: { name: string; state: string }[]; activeOffice: string | null; byFaculty: FacultyRow[] | null;
}) {
  const router = useRouter();
  const mine = REPORTS.filter((r) => activeOffice != null && r.offices.includes(activeOffice));
  const pick = (name: string) => router.push(`/reports?session=${encodeURIComponent(name)}`);
  const open = (slug: string) => router.push(`/reports/${slug}/view?session=${encodeURIComponent(session)}`);
  const stamp = new Date().toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
  const grand = byFaculty ? byFaculty.reduce((s, f) => s + f.total, 0) : 0;

  return (
    <>
      <Note kind="info" title="Every report shows the moment its data was taken">
        A return is read off the register for the session you choose — the crest, the figures, and the footing that says it is verified
        against the record. Run one to read it on screen, print it or save it as a PDF, or take the same rows as a CSV.
      </Note>

      <Panel title="Session" right={sessions.find((s) => s.name === session)?.state ?? ""}>
        <PBody>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <label htmlFor="rp-session" className="sub2" style={{ fontWeight: 600 }}>Reporting session</label>
            <select id="rp-session" className="ctl" style={{ maxWidth: 260 }} value={session} onChange={(e) => pick(e.target.value)}>
              {sessions.length ? sessions.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : ""}</option>)
                : <option value={session}>{session}</option>}
            </select>
            <span className="sub2">Financial returns read the calendar year the session opens in.</span>
          </div>
        </PBody>
      </Panel>

      <Panel title="Standard reports" right="Run against the register, never a copy of it">
        {mine.length ? (
          <DTable cols={["Report", "Owner", "Frequency|mid", "Last run|mid", "|num"]}
            rows={mine.map((r) => [
              <span key="t"><span style={{ fontWeight: 600 }}>{r.title}</span><div className="sub2">{r.purpose}</div></span>,
              <span key="o">{r.owner}</span>,
              <span key="f" className="sub2">{r.frequency}</span>,
              <span key="l" className="sub2">Live · {session}</span>,
              <Btn kind="primary" key="run" onClick={() => open(r.slug)}>Run</Btn>,
            ])}
            texts={mine.map((r) => `${r.title} ${r.owner} ${r.purpose}`)} />
        ) : <PBody><div className="sub2">This office does not take any of the portal&rsquo;s returns.</div></PBody>}
      </Panel>

      {byFaculty ? (
        <Panel title="Enrolment by faculty" right={`${session} · data as at ${stamp}`}>
          {byFaculty.length ? (
            <DTable cols={["Faculty", "Male|num", "Female|num", "Total|num", "Share|mid"]}
              rows={byFaculty.map((f) => [
                <span key="f" style={{ fontWeight: 600 }}>{f.faculty}</span>,
                <span key="m" className="tnum">{f.male.toLocaleString()}</span>,
                <span key="w" className="tnum">{f.female.toLocaleString()}</span>,
                <span key="t" className="tnum" style={{ fontWeight: 600 }}>{f.total.toLocaleString()}</span>,
                <span key="s" className="tnum">{grand ? `${((f.total / grand) * 100).toFixed(1)}%` : "—"}</span>,
              ])}
              texts={byFaculty.map((f) => f.faculty)} />
          ) : <PBody><div className="sub2">No student was admitted for {session} yet, so there is no enrolment to show.</div></PBody>}
          {byFaculty.length ? (
            <PBody>
              <div className="sub2">{grand.toLocaleString()} students in the {session} cohort across {byFaculty.length} facult{byFaculty.length === 1 ? "y" : "ies"}. Run the <b>Enrolment by programme, level and sex</b> return above for the full NUC table.</div>
            </PBody>
          ) : null}
        </Panel>
      ) : null}
    </>
  );
}
