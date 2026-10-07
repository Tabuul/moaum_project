import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PaymentRow } from "@/lib/support";
import { PaymentSearch } from "./PaymentSearch";

export const dynamic = "force-dynamic";

/** t/supportpayments — Payment Support (V346): a student's payment found by any number they hold, within the agent's reach, by the server. */
export default async function PaymentSupportPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const q = s("q").trim();
  const state = s("state");
  const ticket = s("ticket");
  const page = Math.max(1, Number(s("page") || "1") || 1);
  const qs = new URLSearchParams();
  if (q) qs.set("q", q);
  if (state) qs.set("state", state);
  qs.set("page", String(page));
  const [me, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    q ? api<{ total: number; page: number; size: number; rows: PaymentRow[] }>(`/api/v1/helpdesk/support/payments?${qs.toString()}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/supportpayments" me={me.ok ? me.data : null}>
      {list && !list.ok ? <ProblemNotice problem={list.problem} /> : (
        <PaymentSearch q={q} state={state} ticket={ticket} page={page} list={list && list.ok ? list.data : null} />
      )}
    </Shell>
  );
}
