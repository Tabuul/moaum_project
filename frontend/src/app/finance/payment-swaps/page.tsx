import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { readSwapFilters, swapQuery, type SwapDetail, type SwapList } from "@/lib/payment-swaps";
import { PaymentSwaps } from "./PaymentSwaps";

export const dynamic = "force-dynamic";

/** t/paymentswaps — school fees payment swaps (V527): a verified school-fees payment credited to the wrong student moved to the
 *  student it belongs to, initiated by the Students Account Officer or the Bursar and decided by another Bursar officer; Internal
 *  Audit reads. ?swap= opens one. */
export default async function PaymentSwapsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readSwapFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const swap = typeof p.swap === "string" && /^[0-9a-f-]{36}$/i.test(p.swap) ? p.swap : null;
  const [me, list, detail] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SwapList>(`/api/v1/finance/payment-swaps?${swapQuery(filters, { page })}`),
    swap ? api<SwapDetail>(`/api/v1/finance/payment-swaps/${swap}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/paymentswaps" me={me.ok ? me.data : null}>
      {list.ok
        ? <PaymentSwaps filters={filters} list={list.data} office={me.ok ? me.data.activeOffice ?? null : null} initial={detail && detail.ok ? detail.data : null} />
        : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
