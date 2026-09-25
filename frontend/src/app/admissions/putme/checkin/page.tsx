import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { intakeSession, type SessionRow } from "@/lib/sessions";
import type { Batch } from "@/lib/putme";
import { Checkin } from "./Checkin";

export const dynamic = "force-dynamic";

/** t/putme-cbt › check-in — the door: the slip's QR, the application number or the JAMB number; the candidate's photograph and seat; checked in */
export default async function PutmeCheckinPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SessionRow[]>("/api/v1/ref/sessions")]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : intakeSession(list);
  const batches = await api<Batch[]>(`/api/v1/admissions/sessions/${session}/putme/batches`);
  return (
    <Shell route="t/putme-cbt" me={me.ok ? me.data : null}>
      <Checkin session={session} batches={batches.ok ? batches.data : []} office={me.ok ? me.data.activeOffice ?? null : null} />
    </Shell>
  );
}
