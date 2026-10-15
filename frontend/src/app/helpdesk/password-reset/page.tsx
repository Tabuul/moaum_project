import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PasswordResetDesk } from "./PasswordResetDesk";

export const dynamic = "force-dynamic";

/** t/supportpassword — Student Password Reset at the ICT Support Desk (V485): find the student within the agent's reach, read the
 *  account, and reset the password to the default student credential (or by link, or a temporary password on a ticket) */
export default async function PasswordResetPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = typeof p.q === "string" ? p.q.slice(0, 80) : "";
  const student = typeof p.student === "string" && /^[0-9a-f-]{36}$/i.test(p.student) ? p.student : "";
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/supportpassword" me={me.ok ? me.data : null}>
      <PasswordResetDesk q={q} student={student} />
    </Shell>
  );
}
