import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ResultsDesk } from "./ResultsDesk";
import { currentSession } from "@/lib/sessions";

export const dynamic = "force-dynamic";

const EDITORS = ["hod", "academic", "pgschool", "pgsecretary", "super"];

/** PG results desk (V211): registrations, endorsement, and CA/exam score entry. */
export default async function Page() {
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const current = currentSession(sessions.ok ? sessions.data : []);
  return (
    <Shell route="t/pgscores" me={me.ok ? me.data : null}>
      <ResultsDesk initialSession={current} mayEdit={EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
