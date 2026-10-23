import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { readReallocFilters, reallocQuery, type Destination, type ReallocDetail, type ReallocList } from "@/lib/payment-reallocations";
import { Reallocations } from "./Reallocations";

export const dynamic = "force-dynamic";

/** t/paymentrealloc — Bursary payment reallocation and correction (V649): a verified payment applied to the wrong purpose, session or
 *  semester moved to the obligation it was meant for, initiated by the Students Account Officer or the Bursar and decided by another
 *  Bursar officer; Internal Audit reads. ?id= opens one. */
export default async function PaymentReallocationsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readReallocFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const id = typeof p.id === "string" && /^[0-9a-f-]{36}$/i.test(p.id) ? p.id : null;
  const [me, list, destinations, detail] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ReallocList>(`/api/v1/finance/payment-reallocations?${reallocQuery(filters, { page })}`),
    api<Destination[]>("/api/v1/finance/payment-reallocations/destinations"),
    id ? api<ReallocDetail>(`/api/v1/finance/payment-reallocations/${id}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/paymentrealloc" me={me.ok ? me.data : null}>
      {list.ok
        ? <Reallocations filters={filters} list={list.data} destinations={destinations.ok ? destinations.data : []} office={me.ok ? me.data.activeOffice ?? null : null}
            initial={detail && detail.ok ? detail.data : null} />
        : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
