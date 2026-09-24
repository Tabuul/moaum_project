import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Supervision, type Logbook, type Requirements, type Supervised } from "./Supervision";

export const dynamic = "force-dynamic";

/** t/supervision — the supervisor's logbook: the postings the acting person supervises this session, and for a
 *  chosen student the procedures, cases, attendance and mandatory events the posting asks for */
export default async function SupervisionPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ name: string; state?: string }[]>("/api/v1/ref/sessions")]);
  const sessionList = sessions.ok ? sessions.data : [];
  const current = sessionList.find((s) => s.state === "CURRENT")?.name ?? sessionList[0]?.name ?? "";
  const session = typeof p.session === "string" && p.session ? p.session : current;
  const office = me.ok ? me.data.activeOffice : null;
  const desk = office === "provost" || office === "collegesecretary" || office === "academic" || office === "registrar" || office === "dregistrar" || office === "super" || office === "admin";
  const allocation = typeof p.allocation === "string" ? p.allocation : "";
  const [mine, logbook, requirements] = await Promise.all([
    session ? api<Supervised[]>(`/api/v1/college/my-supervision?session=${encodeURIComponent(session)}${desk ? "&all=true" : ""}`) : null,
    allocation ? api<Logbook>(`/api/v1/college/allocations/${encodeURIComponent(allocation)}/logbook`) : null,
    api<Requirements>("/api/v1/college/requirements"),
  ]);
  return (
    <Shell route="t/supervision" me={me.ok ? me.data : null}>
      {mine && !mine.ok ? <ProblemNotice problem={mine.problem} /> : (
        <Supervision sessions={sessionList.map((s) => s.name)} session={session} rows={mine && mine.ok ? mine.data : []} allocation={allocation}
          logbook={logbook && logbook.ok ? logbook.data : null} problem={logbook && !logbook.ok ? logbook.problem : null} desk={desk}
          requirements={requirements.ok ? requirements.data : null} />
      )}
    </Shell>
  );
}
