import { api } from "@/lib/api";
import { sessionRows } from "@/lib/sessions-server";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PAGE_SIZE, PAYMENT_STATES, type IutPayments } from "@/lib/transfer-application";
import { TransferApplicationPayments } from "./TransferApplicationPayments";

export const dynamic = "force-dynamic";

const SESSION = /^\d{4}\/\d{4}$/;
const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : null);

/** t/iutpayments — V766: the inter-university transfer application fee's references for the Bursary: drawn, paid, waiting or expired,
 *  with the totals the database sums over the filters (never the page's rows alone); a payment made a second time for an application
 *  already settled is listed as owed back (D19), for the refund desk. The Bursar confirms a payment by hand against the bank's record.
 *  ?session= one session (every session by default), ?state= PAID, PENDING, EXPIRED or OWED_BACK, ?q= a search, ?page=. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const session = SESSION.test(one(sp.session) ?? "") ? one(sp.session) : null;
  const st = one(sp.state);
  const state = st && (PAYMENT_STATES as readonly string[]).includes(st) ? st : null;
  const q = (one(sp.q) ?? "").slice(0, 100);
  const page = /^\d{1,5}$/.test(one(sp.page) ?? "") ? Number(one(sp.page)) : 0;
  const query = new URLSearchParams({ ...(session ? { session } : {}), ...(state ? { state } : {}), ...(q.trim() ? { q: q.trim() } : {}), page: String(page), size: String(PAGE_SIZE) });
  const [me, sessions, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    sessionRows(),
    api<IutPayments>(`/api/v1/finance/transfer-applications/payments?${query}`),
  ]);
  return (
    <Shell route="t/iutpayments" me={me.ok ? me.data : null} sub={`${session ?? "Every session"} · Inter-university transfer application fee`}>
      {data.ok ? <TransferApplicationPayments data={data.data} filters={{ session, state, q, page }} sessions={sessions.map((s) => s.name)} office={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
