import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { RegisterPage, SessionOpt } from "@/lib/programme-changes";
import { ProgrammeChanges } from "./ProgrammeChanges";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** t/programmechanges — Programme Changes (V297): every applicant now on a programme other than the one applied for, with why; and
 *  the admission corrected after the Board's decision, even after school fees. ?app= opens the correction on that application. */
export default async function ProgrammeChangesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const requested = typeof p.session === "string" ? p.session : "";
  const app = typeof p.app === "string" && UUID_PATTERN.test(p.app) ? p.app : null;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SessionOpt[]>("/api/v1/admissions/programme-changes/sessions"),
  ]);
  const latest = sessions.ok && sessions.data.length ? sessions.data[0].name : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : latest;
  const page = await api<RegisterPage>(`/api/v1/admissions/sessions/${session}/programme-changes`);
  return (
    <Shell route="t/programmechanges" me={me.ok ? me.data : null}>
      {page.ok ? <ProgrammeChanges key={`${session}:${app ?? ""}`} page={page.data} actingOffice={me.ok ? me.data.activeOffice ?? null : null} openApp={app} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
