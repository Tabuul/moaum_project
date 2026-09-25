import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PaymentReport, type PayReport } from "./PaymentReport";
import { paymentFilters, paymentQuery, roleWord } from "./filters";

export const dynamic = "force-dynamic";

/** t/collegepayments — the College of Health Sciences' Student Payment Report, for the Finance Controller, the College and the Bursary */
export default async function CollegePaymentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = paymentFilters(await searchParams);
  const [me, report] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PayReport>(`/api/v1/college/payments?${paymentQuery(filters)}`)]);
  return (
    <Shell route="t/collegepayments" me={me.ok ? me.data : null}>
      {report.ok ? <PaymentReport report={report.data} filters={{ ...filters, session: report.data.session }} basePath="/college/payments" role={roleWord(me.ok ? me.data.activeOffice : null)} /> : <ProblemNotice problem={report.problem} />}
    </Shell>
  );
}
