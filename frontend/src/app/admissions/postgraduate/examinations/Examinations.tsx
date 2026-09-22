"use client";

/**
 * The Secretary's course examinations desk (Policy 17), after the prototype's pgExams screen: the courses
 * sat this semester and where each one's results stand — recorded in full, or still awaited from the
 * Chief Examiner (the Head of Department). Scores are entered on the results desk; this is the Secretary's
 * view of what has come in.
 */
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ExamView {
  session: string; semester: number;
  counts: { courses: number; recorded: number; awaited: number; candidates: number };
  courses: { id: string; code: string; title: string; units: number; kind: string; programme_name: string; department_name: string; candidates: number; scored: number }[];
}

const KIND: Record<string, string> = { CORE: "Core", ELECTIVE: "Elective", DEFICIENCY: "Deficiency", RESEARCH: "Research" };
const SEM: Record<number, string> = { 1: "First semester", 2: "Second semester", 3: "Summer semester" };

export function Examinations({ session, semester, sessions, view, problem }: { session: string; semester: number; sessions: { name: string; state: string }[]; view: ExamView | null; problem: Problem | null }) {
  const router = useRouter();
  const options = sessions.some((s) => s.name === session) ? sessions : [{ name: session, state: "" }, ...sessions];
  const go = (s: string, sem: number) => router.push(`/admissions/postgraduate/examinations?session=${encodeURIComponent(s)}&semester=${sem}`);
  const c = view?.counts;
  return (
    <>
      <Note kind="info" title="Course examinations (Policy 17)">
        Heads of Department are the Chief Examiners. They submit sealed, externally-moderated question papers and the moderated results to the Secretary not later than seven days before the examination; continuous assessment is 30–40% and the examination 60–70%. There is no resit.
      </Note>

      <Panel title="Session & semester" right={<span className="sub2">The desk reads the sitting you choose</span>}>
        <PBody>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <label htmlFor="ex-session" className="sub2" style={{ fontWeight: 600 }}>Session</label>
            <select id="ex-session" className="ctl" style={{ maxWidth: 220 }} value={session} onChange={(e) => go(e.target.value, semester)}>
              {options.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : ""}</option>)}
            </select>
            <label htmlFor="ex-sem" className="sub2" style={{ fontWeight: 600 }}>Semester</label>
            <select id="ex-sem" className="ctl" style={{ maxWidth: 200 }} value={semester} onChange={(e) => go(session, Number(e.target.value))}>
              <option value={1}>First</option><option value={2}>Second</option><option value={3}>Summer</option>
            </select>
          </div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["Courses sat", String(c?.courses ?? 0), null, SEM[semester] ?? ""],
            ["Results recorded", String(c?.recorded ?? 0), Number(c?.recorded) ? "var(--green-ink)" : null, "every candidate scored"],
            ["Results awaited", String(c?.awaited ?? 0), Number(c?.awaited) ? "var(--chrome)" : null, "from the Chief Examiner"],
            ["Candidates", String(c?.candidates ?? 0), null, "registered for the sitting"],
          ]} />

          <Panel title="Results submitted" right={<span className="sub2">Appendix A format · <Link href="/admissions/postgraduate/results">Results desk</Link></span>}>
            {view.courses.length ? (
              <DTable cols={["Course", "Title", "Department", "Type|mid", "Candidates|num", "Scored|num", "Status|mid"]}
                rows={view.courses.map((r) => {
                  const done = r.candidates > 0 && r.scored >= r.candidates;
                  const part = r.scored > 0 && !done;
                  return [
                    <span key="c" className="tnum" style={{ fontWeight: 600 }}>{r.code}</span>,
                    <span key="t"><span>{r.title}</span><div className="sub2">{r.programme_name}</div></span>,
                    <span key="d">{r.department_name}</span>,
                    <span key="k" className="sub2">{KIND[r.kind] ?? r.kind}</span>,
                    <span key="n" className="tnum">{r.candidates}</span>,
                    <span key="s" className="tnum">{r.scored}</span>,
                    done ? <Pil key="st" kind="ok">Recorded</Pil> : part ? <Pil key="st" kind="info">Partly recorded</Pil> : <Pil key="st" kind="warn">Awaited</Pil>,
                  ];
                })}
                texts={view.courses.map((r) => `${r.code} ${r.title} ${r.department_name} ${r.programme_name}`)} />
            ) : <PBody><div className="sub2">No course was registered and endorsed for the {(SEM[semester] ?? "").toLowerCase()} of {session}.</div></PBody>}
          </Panel>
        </>
      ) : null}
    </>
  );
}
