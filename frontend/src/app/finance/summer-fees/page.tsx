import { api } from "@/lib/api";
import { defaultSession, sessionRows } from "@/lib/sessions-server";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SummerFees, type SummerFeesView } from "./SummerFees";

export const dynamic = "force-dynamic";

/** t/summerfees — V735: the Summer Semester fees as the Bursary states them — a programme fee once a student a Summer and a fee a
 *  course, for a session (every programme, or one) — a draft until the Bursar publishes it; a published fee withdrawn, never changed;
 *  and the collections, the programme fees and the course fees apart. */
export default async function SummerFeesPage() {
  const [me, view, sessions, current, periods] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SummerFeesView>("/api/v1/finance/summer-fees"),
    sessionRows(),
    defaultSession(),
    api<{ session: string; state: string }[]>("/api/v1/summer/periods"),
  ]);
  // the session a statement is for, unless the officer picks another: the Summer set and not closed, else the University's current session
  const initial = (periods.ok ? periods.data.find((p) => p.state !== "CLOSED")?.session : null) ?? current;
  return (
    <Shell route="t/summerfees" me={me.ok ? me.data : null}>
      {view.ok ? <SummerFees view={view.data} sessions={sessions.map((s) => s.name)} initialSession={initial}
                             actingOffice={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
