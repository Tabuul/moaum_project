import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Lookups, SignInContacts as List } from "@/lib/sign-in-contacts";
import { SignInContacts } from "./SignInContacts";

export const dynamic = "force-dynamic";

/** t/supportsignin — Sign-in help contacts (V599): the e-mails and phones the sign-in help saved to student records that held none,
 *  which reach no notice until confirmed, to confirm with the student or refuse; for the Head of the desk and the Director of ICT,
 *  the day's student-number checks on the sign-in page by connection and the figures that cap and watch them */
export default async function SignInContactsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const day = typeof p.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(p.day) ? p.day : "";
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<List>("/api/v1/helpdesk/support/sign-in-contacts")]);
  const lookups = list.ok && list.data.head
    ? await api<Lookups>(`/api/v1/helpdesk/support/sign-in-contacts/lookups${day ? `?day=${day}` : ""}`)
    : null;
  return (
    <Shell route="t/supportsignin" me={me.ok ? me.data : null}>
      {list.ok
        ? <SignInContacts list={list.data} lookups={lookups && lookups.ok ? lookups.data : null} lookupsProblem={lookups && !lookups.ok ? lookups.problem : null} />
        : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
