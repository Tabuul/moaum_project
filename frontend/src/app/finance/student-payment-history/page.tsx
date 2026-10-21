import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PaymentHistory } from "./PaymentHistory";

export const dynamic = "force-dynamic";

/** t/studentpaymenthistory — a student's payment history by matriculation number, for the Bursary and the Students Account Officer: every
 *  payment as the Student 360° record shows it (with the official receipt), and the student's biodata and course registration */
export default async function PaymentHistoryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const me = await api<Me>("/api/v1/iam/me");
  const number = typeof p.n === "string" ? p.n.trim() : "";
  return (
    <Shell route="t/studentpaymenthistory" me={me.ok ? me.data : null}>
      <PaymentHistory initial={number} />
    </Shell>
  );
}
