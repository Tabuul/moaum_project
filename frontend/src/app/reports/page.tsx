import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Reports } from "./Reports";

export const dynamic = "force-dynamic";

/** The returns desk: the statutory returns the office may take, for a session. */
export default async function ReportsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const session = typeof p.session === "string"
    ? p.session
    : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? "2026/2027";
  return (
    <Shell route="t/reports" me={me.ok ? me.data : null}>
      <Reports session={session} sessions={sessions.ok ? sessions.data : []} activeOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
