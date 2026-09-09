import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Merit, type MeritView, type ProgrammeOption } from "./Merit";

export const dynamic = "force-dynamic";

/** the merit list for a programme — the eligible pool ranked, with the proposed offer that fills the quota */
export default async function MeritPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const programme = typeof p.programme === "string" ? p.programme : "";
  const [me, sessions, programmes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
    api<ProgrammeOption[]>("/api/v1/admissions/programmes"),
  ]);
  const session = typeof p.session === "string" ? p.session : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? "2026/2027";
  const view = programme
    ? await api<MeritView>(`/api/v1/admissions/merit?session=${encodeURIComponent(session)}&programme=${encodeURIComponent(programme)}`)
    : null;
  return (
    <Shell route="t/merit" me={me.ok ? me.data : null}>
      <Merit
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
