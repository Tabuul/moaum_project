import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Fees } from "@/lib/student-portal";
import { FeesScreen } from "../Screens2";
import { PaymentCorrections, type PaymentCorrection } from "@/components/finance/PaymentCorrections";
import { PaymentsUnderReview } from "@/components/finance/PaymentsUnderReview";
import type { MyArchive } from "@/lib/payment-archive";
import { HistoricalFeesStudent, type HistoricalFees } from "./HistoricalFeesStudent";
import type { OutstandingFees } from "@/lib/outstanding-fees";
import { OutstandingFeesCard } from "../OutstandingFees";

/** s/fees — the charge computed from the schedule, the payments, and what the scheme releases */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/fees" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  // on return from the gateway, verify with the gateway and confirm at once — no Bursary step, no wait for a webhook
  if (typeof q.paid === "string" && q.paid) {
    await api("/api/v1/payments/verify", { method: "POST", body: { reference: q.paid }, reason: `Verify payment ${q.paid}` });
  }
  const [fees, corrections, historical, archives, outstanding] = await Promise.all([
    api<Fees>(`/api/v1/me/fees?session=${encodeURIComponent(session)}`),
    api<PaymentCorrection[]>("/api/v1/me/payment-corrections"),   // V527: payments the Bursary reallocated on this account
    api<HistoricalFees>("/api/v1/me/historical-fees"),   // V654: the historical school fees of any student's record
    api<MyArchive[]>("/api/v1/me/payment-archives"),   // V670: payments on this account archived for review by the Bursary
    api<OutstandingFees>("/api/v1/me/outstanding-fees"),   // V720: every outstanding fee of the record, past and current, each payable
  ]);
  return (
    <Shell route="s/fees" me={loaded.me} sub={`${fees.ok ? fees.data.session : session} session`}>
      {archives.ok ? <PaymentsUnderReview items={archives.data} /> : null}
      {corrections.ok ? <PaymentCorrections items={corrections.data} /> : null}
      {outstanding.ok ? <OutstandingFeesCard data={outstanding.data} generatedBy={loaded.me?.name ?? null} /> : null}
      {historical.ok && historical.data.periods.length ? <HistoricalFeesStudent data={historical.data} /> : null}
      {fees.ok ? <FeesScreen s={loaded.student} fees={fees.data} paid={typeof q.paid === "string" ? q.paid : null} /> : <ProblemNotice problem={fees.problem} />}
    </Shell>
  );
}
