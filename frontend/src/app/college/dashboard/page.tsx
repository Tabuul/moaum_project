import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export const dynamic = "force-dynamic";

/**
 * r/college — the College of Health Sciences dashboard, where the login gate lands the Provost, the College
 * Secretary and the Finance Controller: what waits on the College this session, the figures, the fees position
 * by level, the decisions confirmed most recently, and the doors to each desk.
 */
interface Waiting { kind: "board" | "results" | "registration" | "calendar" | "appeal" | "coordinator"; level?: number; session?: string; exam?: string; count?: number; text: string; href: string }
interface Dashboard {
  session: string;
  totals: { students: number; open_years: number; provisional: number; allocations: number };
  waiting: Waiting[];
  fees: { level: number; students: number; first_cleared: number; second_cleared: number; registered: number }[];
  recent: { number: string; surname: string; other_names: string; level: number; session: string; outcome: string; honours: boolean | null; confirmed_on: string | null; minute: string | null }[];
}
const ROLE: Record<string, string> = { provost: "Provost", collegesecretary: "College Secretary", financecontroller: "Finance Controller" };
const OUTCOME: Record<string, [string, "ok" | "bad" | "info" | "warn"]> = {
  PROMOTE: ["Promoted", "ok"], GRADUATE: ["Graduated", "ok"], RESIT: ["Resit", "warn"], REPEAT: ["Repeat", "warn"],
  WITHDRAW_ADVISED: ["Advised to withdraw", "bad"], WITHDRAW_REQUIRED: ["Required to withdraw", "bad"], APPEAL: ["Appeal to Senate", "bad"],
};
const KIND: Record<Waiting["kind"], [string, "ok" | "bad" | "info" | "warn" | "grey"]> = {
  board: ["The Board", "warn"], results: ["Results", "bad"], registration: ["Registration", "info"], calendar: ["Calendar", "grey"], appeal: ["Senate", "bad"], coordinator: ["Appointment", "grey"],
};
const dayOf = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export default async function CollegeDashboardPage() {
  const [me, dash] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Dashboard>("/api/v1/college/dashboard")]);
  const office = me.ok ? me.data.activeOffice : null;
  const role = ROLE[office ?? ""] ?? "College officer";
  const finance = office === "financecontroller";
  if (!dash.ok) {
    return <Shell route="r/college" me={me.ok ? me.data : null}><ProblemNotice problem={dash.problem} /></Shell>;
  }
  const d = dash.data;
  const t = d.totals;
  const pc = (n: number, of: number) => (of ? `${Math.round((100 * n) / of)}%` : "—");
  return (
    <Shell route="r/college" me={me.ok ? me.data : null}>
      <PageHead
        title={`Welcome${me.ok && me.data.name ? `, ${me.data.name}` : ""}`}
        description={`${role}, College of Health Sciences · ${d.session}. ${finance ? "The fees position of the College's students by level, and what waits on the College." : "What waits on the College, the figures, and the decisions confirmed most recently."}`}
        actions={<>
          <LinkBtn kind="primary" href="/college/examinations">Professional Examinations</LinkBtn>
          <LinkBtn href="/college/postings">Postings</LinkBtn>
          <LinkBtn href="/college/calendar">College Calendar</LinkBtn>
          <LinkBtn href="/college">College Overview</LinkBtn>
        </>}
      />
      <Tiles items={[
        ["Students", String(t.students), null, "On the register, Pre-Medical to 600 Level"],
        ["Years open", String(t.open_years), null, "College years running or at a resit"],
        ["Awaiting the Board", String(t.provisional), t.provisional ? "var(--red-ink)" : null, "Provisional decisions to confirm"],
        ["Postings this session", String(t.allocations), null, d.session],
      ]} />

      <Panel title="What waits on the College" right={d.waiting.length ? `${d.waiting.length} item${d.waiting.length === 1 ? "" : "s"}` : "Nothing outstanding"}>
        {d.waiting.length === 0 ? <PBody><div className="sub2">Every decision is confirmed, every cohort at its end has its results, every year open is registered, every level with years open is dated, and every level has its coordinator.</div></PBody> : (
          <DTable cols={["", "What", ""]} rows={d.waiting.map((w) => [
            <Pil key="k" kind={KIND[w.kind][1]}>{KIND[w.kind][0]}</Pil>,
            <span key="t">{w.text}</span>,
            <LinkBtn key="o" href={w.href}>Open</LinkBtn>,
          ])} />
        )}
      </Panel>

      {finance || d.fees.length ? (
        <Panel title={`Fees this session · ${d.session}`} right="The University's one ledger; each College year registers on its semester's fees">
          {d.fees.length === 0 ? <PBody><div className="sub2">No College student at 200 Level or above is on the register.</div></PBody> : (
            <DTable cols={["Level|mid", "Students|mid", "First semester cleared|mid", "Second semester cleared|mid", "Year registered|mid"]} rows={d.fees.map((f) => [
              <strong className="tnum" key="l">{f.level}</strong>,
              <span className="tnum" key="s">{f.students}</span>,
              <span key="a"><span className="tnum">{f.first_cleared}</span> <span className="sub2">{pc(f.first_cleared, f.students)}</span></span>,
              <span key="b"><span className="tnum">{f.second_cleared}</span> <span className="sub2">{pc(f.second_cleared, f.students)}</span></span>,
              <span key="r"><span className="tnum">{f.registered}</span> <span className="sub2">{pc(f.registered, f.students)}</span></span>,
            ])} />
          )}
          <PBody><div className="row"><span className="sub2">A student registers the first semester of a College year on its fees, and the second on the second&rsquo;s; the whole session paid at once clears both.</span><span className="grow" /><LinkBtn href="/finance/fees">Fee Setup and Schedule</LinkBtn></div></PBody>
        </Panel>
      ) : null}

      <Panel title="Decisions confirmed most recently" right="By the College Academic Board, on its minute">
        {d.recent.length === 0 ? <PBody><div className="sub2">No decision has been confirmed yet. The rule applies a provisional decision as each candidate&rsquo;s last subject is resulted; the Board confirms the set on the examinations desk.</div></PBody> : (
          <DTable cols={["Matriculation number", "Name", "Level|mid", "Cohort|mid", "Decision", "Confirmed|mid", "Minute"]} rows={d.recent.map((r) => [
            <span className="tnum" key="n">{r.number}</span>,
            <strong key="nm">{r.surname}, {r.other_names}</strong>,
            <span className="tnum" key="l">{r.level}</span>,
            <span className="tnum" key="s">{r.session}</span>,
            <Pil key="d" kind={OUTCOME[r.outcome]?.[1] ?? "info"}>{OUTCOME[r.outcome]?.[0] ?? r.outcome}{r.honours ? " · Honours" : ""}</Pil>,
            <span className="tnum" key="c">{dayOf(r.confirmed_on)}</span>,
            <span className="sub2" key="m">{r.minute ?? "—"}</span>,
          ])} />
        )}
      </Panel>

      <Note kind="info" title="The College's doors">
        The examinations desk holds each cohort&rsquo;s results, the rule&rsquo;s provisional decisions and the Board&rsquo;s confirmation; the postings desk allocates students to a block&rsquo;s postings and the supervisors keep the logbooks; the calendar dates each level&rsquo;s year; the score sheets go down to and come up from the MBBS Coordinators, one per level.
      </Note>
    </Shell>
  );
}
