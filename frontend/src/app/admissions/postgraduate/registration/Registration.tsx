"use client";

/**
 * The Secretary's registration & matriculation desk (Policy 7–8), as the prototype's pgReg screen lays it
 * out: the session's figures (to register · registered · part-time · lapsed), the students admitted this
 * session with their fee and matriculation standing, and every registration of the session by semester —
 * renewed or not (Policy 7.5). Registration itself is endorsed on the registrations desk.
 */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface RegView {
  session: string;
  counts: { to_register: number; registered: number; part_time: number; lapsed: number };
  fresh: { id: string; surname: string; other_names: string; matric_no: string | null; admission_no: string | null; matriculated_at: string | null; programme_name: string; pg_award: string | null; department_name: string; mode: string | null; acceptance_paid: boolean; registered: boolean }[];
  renewals: { id: string; semester: number; mode: string; state: string; updated_at: string; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null; courses: number }[];
}

const SEM: Record<number, string> = { 1: "1st", 2: "2nd", 3: "Summer" };

export function Registration({ session, sessions, view, problem }: { session: string; sessions: { name: string; state: string }[]; view: RegView | null; problem: Problem | null }) {
  const queryNav = useQueryNav();
  const options = sessions.some((s) => s.name === session) ? sessions : [{ name: session, state: "" }, ...sessions];
  const c = view?.counts;
  return (
    <>
      <Note kind="info" title="Registration & matriculation (Policy 7–8)">
        Present originals for screening, pay the prescribed fees online, complete and endorse the online forms, then matriculate. Registration is renewed each semester; a session missed lapses the studentship (Policy 7.6).
      </Note>

      <Panel title="Session" right={<span className="sub2">The desk reads the session you choose</span>}>
        <PBody>
          <div className="row">
            <label htmlFor="reg-session" className="sub2 b600">Session</label>
            <select id="reg-session" className="ctl" style={{ maxWidth: 260 }} value={session}
              onChange={(e) => queryNav(`/admissions/postgraduate/registration?session=${encodeURIComponent(e.target.value)}`)}>
              {options.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : ""}</option>)}
            </select>
          </div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["To register", String(c?.to_register ?? 0), Number(c?.to_register) ? "var(--chrome)" : null, "admitted, not registered"],
            ["Registered", String(c?.registered ?? 0), Number(c?.registered) ? "var(--green-ink)" : null, "this session"],
            ["Part-time", String(c?.part_time ?? 0), null, "of the registered"],
            ["Lapsed", String(c?.lapsed ?? 0), Number(c?.lapsed) ? "var(--red-deep)" : null, "did not renew"],
          ]} />

          <Panel title="Fresh postgraduate students" right={`${view.fresh.length} admitted for ${session}`}>
            {view.fresh.length ? (
              <DTable cols={["Student", "Programme", "Mode|mid", "Acceptance fee|mid", "Registered|mid", "Matriculation|mid"]}
                rows={view.fresh.map((s) => [
                  <span key="n"><span className="b600">{s.surname}, {s.other_names}</span><div className="sub2 tnum">{s.matric_no ?? s.admission_no ?? "—"}</div></span>,
                  <span key="p"><span>{s.programme_name}</span><div className="sub2">{s.pg_award ?? ""}{s.department_name ? ` · ${s.department_name}` : ""}</div></span>,
                  <span key="m">{s.mode ? (s.mode === "PART_TIME" ? "Part-time" : "Full-time") : <span className="sub2">—</span>}</span>,
                  s.acceptance_paid ? <Pil key="f" kind="ok">Paid</Pil> : <span key="f" className="sub2">Owing</span>,
                  s.registered ? <Pil key="r" kind="ok">Registered</Pil> : <Pil key="r" kind="warn">Pending</Pil>,
                  s.matric_no ? <Pil key="x" kind="ok">Matriculated</Pil> : <LinkBtn key="x" kind="ghost" href="/matriculation">Matriculate</LinkBtn>,
                ])}
                texts={view.fresh.map((s) => `${s.surname} ${s.other_names} ${s.matric_no ?? ""} ${s.admission_no ?? ""} ${s.programme_name}`)} />
            ) : <PBody><div className="sub2">No postgraduate student was admitted for {session}.</div></PBody>}
          </Panel>

          <Panel title="Semester renewal" right={<span className="sub2">Policy 7.5 · <Link href="/admissions/postgraduate/results">Registrations desk</Link></span>}>
            {view.renewals.length ? (
              <DTable cols={["Student", "Programme", "Semester|mid", "Mode|mid", "Courses|num", "Status|mid"]}
                rows={view.renewals.map((r) => [
                  <span key="n"><span className="b600">{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
                  <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}</div></span>,
                  <span key="s" className="tnum">{SEM[r.semester] ?? r.semester}</span>,
                  <span key="m">{r.mode === "PART_TIME" ? "Part-time" : "Full-time"}</span>,
                  <span key="c" className="tnum">{r.courses}</span>,
                  r.state === "ENDORSED" ? <Pil key="st" kind="ok">Renewed</Pil> : r.state === "SUBMITTED" ? <Pil key="st" kind="info">Submitted</Pil> : <Pil key="st" kind="warn">Not renewed</Pil>,
                ])}
                texts={view.renewals.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
            ) : <PBody><div className="sub2">No registration has been opened for {session} yet.</div></PBody>}
          </Panel>
        </>
      ) : null}
    </>
  );
}
