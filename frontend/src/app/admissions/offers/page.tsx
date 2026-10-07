import { intakeSession } from "@/lib/sessions";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Offers } from "./Offers";

export const dynamic = "force-dynamic";

/** V358: offers that lapse and a waiting list that moves — the Admissions Office decides; the API refuses the rest */
export default async function OffersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ name: string; state: string }[]>("/api/v1/ref/sessions")]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" ? p.session : intakeSession(list);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/offers" me={me.ok ? me.data : null}>
      <Offers session={session} sessions={list.map((x) => x.name)} canDecide={office === "academic" || office === "registrar"} />
    </Shell>
  );
}
