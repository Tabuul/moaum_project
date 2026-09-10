import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Applicants, type ApplicantsView, type ProgrammeOption } from "./Applicants";

export const dynamic = "force-dynamic";

/** the applicants on committed admission lists — the admitted pool, filterable by faculty,
 *  programme and entry mode, for post-UTME registration and the admission process. */
export default async function ApplicantsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const q = str("q");
  const faculty = str("faculty");
  const programme = str("programme");
  const entryMode = str("entryMode");
  const [me, sessions, programmes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
    api<ProgrammeOption[]>("/api/v1/admissions/programmes"),
  ]);
  const session = typeof p.session === "string" ? p.session : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? "2026/2027";
  const qs = new URLSearchParams({ session });
  if (q) qs.set("q", q);
  if (faculty) qs.set("faculty", faculty);
  if (programme) qs.set("programme", programme);
  if (entryMode) qs.set("entryMode", entryMode);
  const view = await api<ApplicantsView>(`/api/v1/admissions/applicants?${qs.toString()}`);
  return (
    <Shell route="t/applicants" me={me.ok ? me.data : null}>
      {view.ok ? (
        <Applicants d={view.data} session={session} q={q} faculty={faculty} programme={programme} entryMode={entryMode}
                    programmes={programmes.ok ? programmes.data : []} />
      ) : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
