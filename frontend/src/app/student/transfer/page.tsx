import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Transfer, type MyTransfer } from "./Transfer";

export const dynamic = "force-dynamic";

/** s/transfer — the student's own inter-departmental transfer application. */
export default async function StudentTransferPage() {
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<MyTransfer>("/api/v1/me/transfer")]);
  return (
    <Shell route="s/transfer" me={me.ok ? me.data : null}>
      {data.ok ? <Transfer d={data.data} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
