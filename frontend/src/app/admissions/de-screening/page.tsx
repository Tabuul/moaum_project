import { intakeSession } from "@/lib/sessions";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { DeScreening, type DeView, type ProgrammeOption } from "./DeScreening";

export const dynamic = "force-dynamic";

/** Direct Entry screening for a programme — DE applicants checked against the programme's DE subject set,
 *  with inline capture of each candidate's prior-qualification subjects (V200). Separate from UTME merit. */
export default async function DeScreeningPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const programme = typeof p.programme === "string" ? p.programme : "";
  const [me, sessions, programmes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
    api<ProgrammeOption[]>("/api/v1/admissions/programmes"),
  ]);
  const session = typeof p.session === "string" ? p.session : intakeSession(sessions.ok ? sessions.data : []);
  const view = programme
    ? await api<DeView>(`/api/v1/admissions/de-screening?session=${encodeURIComponent(session)}&programme=${encodeURIComponent(programme)}`)
    : null;
  return (
    <Shell route="t/de-screening" me={me.ok ? me.data : null}>
      <DeScreening
        session={session}
        programme={programme}
        programmes={programmes.ok ? programmes.data : []}
        view={view && view.ok ? view.data : null}
        problem={view && !view.ok ? view.problem : null}
        actingOffice={me.ok ? me.data.activeOffice : null}
      />
    </Shell>
  );
}
