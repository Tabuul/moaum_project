import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PgCalendar } from "./PgCalendar";

export const dynamic = "force-dynamic";

interface CalData { sessions: { name: string; starts_on: string | null; ends_on: string | null; semesters: number; state: string; note: string | null }[]; current: string | null; looking: string | null; semesters: never[] }

/** The Postgraduate School's own session and semester calendar (V224). */
export default async function PgCalendarPage() {
  const [me, cal] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CalData>("/api/v1/pg/calendar"),
  ]);
  const initial: CalData = cal.ok ? cal.data : { sessions: [], current: null, looking: null, semesters: [] };
  return (
    <Shell route="t/pgcalendar" me={me.ok ? me.data : null}>
      <PgCalendar initial={initial} />
    </Shell>
  );
}
