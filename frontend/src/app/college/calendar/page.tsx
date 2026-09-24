import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Calendar, type CalendarRow } from "./Calendar";
import type { CalendarData } from "@/lib/calendar";

export const dynamic = "force-dynamic";

/** t/collegecalendar — the College's calendar: each level's semesters dated for a session (V249) */
export default async function CollegeCalendarPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
  ]);
  const sessionList = sessions.ok ? sessions.data : [];
  const current = sessionList.find((s) => s.state === "CURRENT")?.name ?? sessionList[0]?.name ?? "";
  const session = typeof p.session === "string" && p.session ? p.session : current;
  const names = sessionList.map((s) => s.name);
  const prev = names[names.indexOf(session) + 1] ?? null;
  const [calendar, previous, university] = await Promise.all([
    session ? api<{ session: string; rows: CalendarRow[] }>(`/api/v1/college/calendar?session=${encodeURIComponent(session)}`) : null,
    prev ? api<{ session: string; rows: CalendarRow[] }>(`/api/v1/college/calendar?session=${encodeURIComponent(prev)}`) : null,
    session ? api<CalendarData>(`/api/v1/calendar?session=${encodeURIComponent(session)}`) : null,
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const mayEdit = ["provost", "collegesecretary", "academic", "registrar", "dregistrar", "admin", "super"].includes(office ?? "");
  return (
    <Shell route="t/collegecalendar" me={me.ok ? me.data : null}>
      {calendar && !calendar.ok ? <ProblemNotice problem={calendar.problem} /> : (
        <Calendar sessions={names} session={session} rows={calendar && calendar.ok ? calendar.data.rows : []}
          previous={previous && previous.ok ? previous.data.rows : []} university={university && university.ok ? university.data.semesters : []} mayEdit={mayEdit} problem={null} />
      )}
    </Shell>
  );
}
