import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ScoreUpload } from "./ScoreUpload";

export const dynamic = "force-dynamic";

/** t/scores — bulk Post-UTME score upload, reconciled against the applicant records (ICT / Super / Academic) */
export default async function ScoresPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const session = typeof p.session === "string" ? p.session : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? "2026/2027";
  return (
    <Shell route="t/putme" me={me.ok ? me.data : null}>
      <ScoreUpload session={session} sessions={sessions.ok ? sessions.data.map((s) => s.name) : [session]} actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
