import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Reports, type DueRow, type FacultyRow, type KeptRow } from "./Reports";
import { Trends, type MonthTrend, type SessionTrend } from "./Trends";

export const dynamic = "force-dynamic";

interface EnrolmentRow { faculty: string; programme: string; level: number; male: number; female: number; unstated: number; total: number }

/** The returns desk: the standard reports the office may take, for a session, and the enrolment by faculty. */
export default async function ReportsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const me = await api<Me>("/api/v1/iam/me");
  /* the School of Postgraduate Studies keeps its own calendar (V224): its desk reads PG sessions, and the
     undergraduate enrolment panel does not apply to it */
  const pg = me.ok && (me.data.activeOffice === "pgschool" || me.data.activeOffice === "pgsecretary");
  const sessions = pg
    ? await api<{ sessions: { name: string; state: string }[] }>("/api/v1/pg/calendar").then((r) => (r.ok ? { ok: true as const, data: r.data.sessions } : r))
    : await api<{ name: string; state: string }[]>("/api/v1/ref/sessions");
  const session = typeof p.session === "string"
    ? p.session
    : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? (pg ? "2025/2026" : "2026/2027");
  /* the enrolment by faculty shown on the desk itself (proto gReports): the return's rows, rolled up */
  const enrol = pg ? null : await api<{ rows: EnrolmentRow[] }>(`/api/v1/reports/enrolment?session=${encodeURIComponent(session)}`);
  /* the due register and the copies kept (V229) */
  const trends = api<{ sessions: SessionTrend[]; months: MonthTrend[] }>("/api/v1/reports/trends");
  const [due, kept] = await Promise.all([
    api<{ asAt: string; rows: DueRow[]; overdue: number; dueSoon: number }>("/api/v1/reports/due"),
    api<KeptRow[]>("/api/v1/reports/snapshots?limit=12"),
  ]);
  const byFaculty: FacultyRow[] = [];
  if (enrol && enrol.ok) {
    const m = new Map<string, FacultyRow>();
    for (const r of enrol.data.rows) {
      const f = m.get(r.faculty) ?? { faculty: r.faculty, male: 0, female: 0, total: 0 };
      f.male += Number(r.male); f.female += Number(r.female); f.total += Number(r.total);
      m.set(r.faculty, f);
    }
    byFaculty.push(...[...m.values()].sort((a, b) => b.total - a.total));
  }
  return (
    <Shell route="t/reports" me={me.ok ? me.data : null}>
      <Reports session={session} sessions={sessions.ok ? sessions.data : []} activeOffice={me.ok ? me.data.activeOffice : null} byFaculty={enrol && enrol.ok ? byFaculty : null}
        due={due.ok ? due.data : null} kept={kept.ok ? kept.data : []}
        trends={await trends.then((t) => (t.ok ? <Trends sessions={t.data.sessions} months={t.data.months} /> : null))} />
    </Shell>
  );
}
