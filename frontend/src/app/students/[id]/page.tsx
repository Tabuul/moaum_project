import { cookies } from "next/headers";
import { api } from "@/lib/api";
import { readScope, SCOPE_COOKIE } from "@/lib/scope";
import type { StudentRecord } from "@/lib/student";
import type { Me as Portal } from "@/lib/student-portal";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Student360 } from "./Student360";
import type { Classification } from "./ClassificationPanel";
import type { Overview } from "./FullRecord";
import { MessagesPanel } from "@/components/MessagesPanel";
import { PaymentCorrections, type PaymentCorrection } from "@/components/finance/PaymentCorrections";
import { defaultSession } from "@/lib/sessions-server";

export const dynamic = "force-dynamic";

export default async function StudentPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  const scope = readScope(sp, (await cookies()).get(SCOPE_COOKIE)?.value, await defaultSession());

  /* V360: the student's own figures — the session's school fees (for the offices that read them) and the CGPA from the
     published results — as the student sees them, beside the record */
  const [me, record, portal, classification, overview] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StudentRecord>(`/api/v1/student/students/${id}?session=${encodeURIComponent(scope.session)}`),
    api<Portal>(`/api/v1/student/students/${id}/portal`),
    api<Classification>(`/api/v1/student/students/${id}/classification`),
    // the full record's overview (Student 360°): the other tabs are read when opened
    api<Overview>(`/api/v1/student/students/${id}/full/overview`),
  ]);

  // V440: what the portal sent the student, for the offices that read the whole University's records
  const office = me.ok ? me.data.activeOffice ?? "" : "";
  const mayMessages = ["ict", "admin", "super", "registrar", "dregistrar", "records", "academic", "dsa"].includes(office);
  // V527: the school-fees payments the Bursary reallocated on this account, for the offices that read them
  const maySwaps = ["bursar", "studentaccounts", "audit", "deputyaudit", "super", "registrar", "dregistrar", "ict", "admin"].includes(office);
  const swaps = maySwaps && record.ok ? await api<PaymentCorrection[]>(`/api/v1/finance/payment-swaps/of/${id}`) : null;

  return (
    <Shell route="t/student" me={me.ok ? me.data : null}>
      {!record.ok ? (
        <ProblemNotice problem={record.problem} />
      ) : (
        <>
          <Student360 record={record.data} portal={portal.ok ? portal.data : null} session={scope.session} actingOffice={me.ok ? me.data.activeOffice : null}
            classification={classification.ok ? classification.data : null}
            full={overview.ok ? { overview: overview.data, swaps: swaps && swaps.ok ? swaps.data : null, messages: mayMessages, initialTab: typeof sp.tab === "string" ? sp.tab : null } : null} />
          {!overview.ok && swaps && swaps.ok ? <PaymentCorrections items={swaps.data} staff /> : null}
          {!overview.ok && mayMessages ? <MessagesPanel path={`/api/v1/students/${id}/messages`} /> : null}
        </>
      )}
    </Shell>
  );
}
