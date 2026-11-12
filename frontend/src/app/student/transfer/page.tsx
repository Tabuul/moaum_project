import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Transfer, type MyTransfer } from "./Transfer";

export const dynamic = "force-dynamic";

/** s/transfer — the student's own inter-departmental transfer application and its fee (V727). The gateway returns the payer here with
 *  ?paid=<reference>: the reference is verified with the gateway at once, as on Fees & payments, before the page is read. */
export default async function StudentTransferPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const paid = typeof q.paid === "string" && /^[A-Z0-9-]{6,60}$/i.test(q.paid) ? q.paid.toUpperCase() : null;
  const [me] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    paid ? api("/api/v1/payments/verify", { method: "POST", body: { reference: paid }, reason: `Verify payment ${paid}` }) : null,
  ]);
  const data = await api<MyTransfer>("/api/v1/me/transfer");
  return (
    <Shell route="s/transfer" me={me.ok ? me.data : null}>
      {data.ok ? <Transfer d={data.data} paid={paid} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
