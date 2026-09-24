import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export const dynamic = "force-dynamic";

/** r/mbbscoordinator — the MBBS Coordinator's dashboard (V250): the level held, its examination, every cohort with a year at
 *  the level and what each waits on — registration, the year's end, results, the Board — and the doors to the score sheet,
 *  the examination desk and the students. */
interface Summary {
  level: number; department: string | null; nextSession: string;
  exam: { id?: string; code?: string; name?: string; level?: number; papers?: string[]; min_attendance_pct?: number | null; on_failure?: string; resit_allowed?: boolean; appeal_to_senate?: boolean };
  cohorts: { session: string; students: number; registered: number; open: number; resit: number; closed: number; with_results: number; provisional: number; confirmed: number; year_reached_final: boolean; year_starts_on: string | null; year_ends_on: string | null }[];
  waiting: { kind: "board" | "results" | "registration" | "calendar"; level?: number; session?: string; exam?: string; count?: number; text: string; href: string }[];
  subjects: { session: string; subject: string; ordinal: number; cohort: number; resulted: number; passed: number; barred: number }[];
}
const KIND: Record<string, [string, "ok" | "bad" | "info" | "warn" | "grey"]> = { board: ["The Board", "warn"], results: ["Results", "bad"], registration: ["Registration", "info"], calendar: ["Calendar", "grey"] };
const dayOf = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export default async function CoordinatorPage() {
  const [me, sum] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Summary>("/api/v1/college/coordinator")]);
  if (!sum.ok || !sum.data) {
    return <Shell route="r/mbbscoordinator" me={me.ok ? me.data : null}><ProblemNotice problem={sum.ok ? { status: 502, title: "The College API answered with nothing", detail: "The coordinator's summary came back empty; reload, and if it persists the API is restarting." } : sum.problem} /></Shell>;
  }
  const s = sum.data;
  const ex = s.exam;
  const running = s.cohorts.filter((c) => c.open + c.resit > 0);
  const waiting = (c: Summary["cohorts"][number]) =>
    c.registered < c.students ? `${c.students - c.registered} not fully registered`
      : !c.year_reached_final ? `The year runs${c.year_ends_on ? ` to ${dayOf(c.year_ends_on)}` : ""}; results open at the final semester`
      : c.with_results < c.students ? `${c.students - c.with_results} without results`
      : c.provisional > 0 ? `${c.provisional} provisional decision${c.provisional === 1 ? "" : "s"} for the Board`
      : c.resit > 0 ? `${c.resit} resit${c.resit === 1 ? "" : "s"} pending` : c.closed === c.students ? "Closed" : "Decided";
  return (
    <Shell route="r/mbbscoordinator" me={me.ok ? me.data : null}>
      <Note kind="info" title={`Welcome${me.ok && me.data.name ? `, ${me.data.name}` : ""} — MBBS Coordinator, ${s.level} Level`}>
        You coordinate the College&rsquo;s students at {s.level} Level{s.department ? `, from the Department of ${s.department}` : ""}: their cohorts, their score sheet, their results and CA, and their years. {ex.code ? `The examination at this level is the ${ex.name}${ex.min_attendance_pct != null ? `, with attendance of at least ${ex.min_attendance_pct}%` : ""}.` : ""} The Board&rsquo;s confirmation, the calendar and Senate appeals are the College Secretary&rsquo;s.
      </Note>
      <Tiles items={[
        ["Level", `${s.level}`, null, ex.code ? `${ex.code} — ${ex.name}` : "No examination"],
        ["Cohorts running", String(running.length), null, running.map((c) => c.session).join(" · ") || "None open"],
        ["Students at the level", String(running.reduce((n, c) => n + c.open + c.resit, 0)), null, `${running.reduce((n, c) => n + c.registered, 0)} fully registered`],
        ["Awaiting the Board", String(s.cohorts.reduce((n, c) => n + c.provisional, 0)), s.cohorts.some((c) => c.provisional) ? "var(--red-ink)" : null, "Provisional decisions"],
      ]} />
      <Panel title="Your doors">
        <PBody>
          <div className="row">
            <LinkBtn href="/college/scoresheets" kind="primary">Score sheet</LinkBtn>
            <LinkBtn href={`/college/examinations${ex.code ? `?exam=${encodeURIComponent(ex.code)}` : ""}`} kind="ghost">Professional examination</LinkBtn>
            <LinkBtn href={`/college/postings?level=${s.level}`} kind="ghost">Postings</LinkBtn>
            <LinkBtn href="/college/calendar" kind="ghost">College calendar</LinkBtn>
            <LinkBtn href="/college" kind="ghost">College overview</LinkBtn>
          </div>
        </PBody>
      </Panel>
      <Panel title="What waits on you" right={s.waiting?.length ? `${s.waiting.length} item${s.waiting.length === 1 ? "" : "s"}` : "Nothing outstanding at your level"}>
        {!s.waiting?.length ? <PBody><div className="sub2">Every cohort at {s.level} Level is registered, every candidate at the end of a year has a result in every subject, and every decision is with the Board or confirmed.</div></PBody> : (
          <DTable cols={["", "What", ""]} rows={s.waiting.map((w, i) => [
            <Pil key={"k" + i} kind={KIND[w.kind]?.[1] ?? "info"}>{KIND[w.kind]?.[0] ?? w.kind}</Pil>,
            <span key={"t" + i}>{w.text}</span>,
            <LinkBtn key={"o" + i} href={w.href}>Open</LinkBtn>,
          ])} />
        )}
      </Panel>
      {s.subjects?.length ? (
        <Panel title={`Results by subject · ${ex.code ?? ""}`} right="Each open cohort: how many have a result, how many passed, how many were barred">
          <DTable cols={["Cohort|mid", "Subject", "Resulted|mid", "Passed|mid", "Barred|mid", "Progress"]} rows={s.subjects.map((x, i) => {
            const pct = x.cohort ? Math.round((100 * x.resulted) / x.cohort) : 0;
            return [
              <strong className="tnum" key={"s" + i}>{x.session}</strong>,
              <span key={"n" + i}>{x.subject}</span>,
              <span className="tnum" key={"r" + i}>{x.resulted} of {x.cohort}</span>,
              <span className="tnum ink-green" key={"p" + i}>{x.passed}</span>,
              <span className={`tnum${x.barred ? " ink-red" : ""}`} key={"b" + i}>{x.barred}</span>,
              <span key={"g" + i} className="meter" title={`${pct}%`}><span className="meter__bar"><span className="meter__fill" style={{ width: `${pct}%` }} /></span></span>,
            ];
          })} />
        </Panel>
      ) : null}
      <Panel title={`Cohorts at ${s.level} Level`} right={`The next year opens in ${s.nextSession}`}>
        {s.cohorts.length === 0 ? <PBody><div className="sub2">No student has a {s.level} Level year yet. A year opens when the student registers from their dashboard, or when you open it for them on the examination desk.</div></PBody> : (
          <DTable cols={["Cohort|mid", "Students|mid", "Registered|mid", "Year|mid", "Runs", "With results|mid", "Decisions|mid", "Waiting on"]} rows={s.cohorts.map((c) => [
            <strong className="tnum" key="s">{c.session}</strong>,
            <span className="tnum" key="n">{c.students}</span>,
            <span className="tnum" key="r">{c.registered}</span>,
            <span key="y">{c.open + c.resit > 0 ? <Pil kind={c.year_reached_final ? "warn" : "ok"}>{c.year_reached_final ? "At its end" : "Running"}</Pil> : <Pil kind="grey">Closed</Pil>}</span>,
            <span className="sub2" key="d">{c.year_starts_on ? `${dayOf(c.year_starts_on)} to ${dayOf(c.year_ends_on)}` : "Not dated"}</span>,
            <span className="tnum" key="w">{c.with_results}</span>,
            <span key="dc"><span className="tnum">{c.confirmed}</span> confirmed{c.provisional ? <> · <b className="ink-red">{c.provisional}</b> provisional</> : null}</span>,
            <span key="wt">{waiting(c)}</span>,
          ])} />
        )}
      </Panel>
    </Shell>
  );
}
