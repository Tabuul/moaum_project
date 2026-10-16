import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Overview, OverviewRow, Rules } from "@/lib/registration-approval";
import { RegistrationApproval } from "./RegistrationApproval";

export const dynamic = "force-dynamic";

/** t/regapproval — Course registration approval (V491): the rule by session and semester, the figures and the registrations
 *  behind them — automatically approved, waiting, held for review, reset and registered again, the cards issued */
export default async function RegistrationApprovalPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const [me, rules] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Rules>("/api/v1/registration/approval/rules")]);
  if (!rules.ok) return <Shell route="t/regapproval" me={me.ok ? me.data : null}><ProblemNotice problem={rules.problem} /></Shell>;
  const session = /^\d{4}\/\d{4}$/.test(str("session")) ? str("session") : rules.data.current ?? rules.data.sessions[0] ?? "";
  const semester = /^[123]$/.test(str("semester")) ? Number(str("semester")) : null;
  const kind = /^[A-Z_]{2,20}$/.test(str("kind")) ? str("kind") : "REVIEW";
  const page = /^\d{1,4}$/.test(str("page")) ? Number(str("page")) : 0;
  const q = str("q").slice(0, 60);
  const sem = semester ? `&semester=${semester}` : "";
  const [overview, list] = session ? await Promise.all([
    api<Overview>(`/api/v1/registration/approval/overview?session=${encodeURIComponent(session)}${sem}`),
    api<{ kind: string; total: number; page: number; size: number; rows: OverviewRow[] }>(
      `/api/v1/registration/approval/overview/list?session=${encodeURIComponent(session)}${sem}&kind=${kind}&page=${page}&size=50${q ? `&q=${encodeURIComponent(q)}` : ""}`),
  ]) : [null, null];
  return (
    <Shell route="t/regapproval" me={me.ok ? me.data : null} sub={session ? `${session}${semester ? ` · semester ${semester}` : ""}` : undefined}>
      {overview && !overview.ok ? <ProblemNotice problem={overview.problem} />
        : list && !list.ok ? <ProblemNotice problem={list.problem} />
        : <RegistrationApproval key={`${session}|${semester ?? ""}`} rules={rules.data} session={session} semester={semester} kind={kind} q={q}
            overview={overview && overview.ok ? overview.data : null} list={list && list.ok ? list.data : null}
            mayChange={me.ok && ["academic", "registrar", "dregistrar", "ict", "super"].includes(me.data.activeOffice ?? "")}
            mayDecide={me.ok && ["academic", "registrar", "dregistrar", "super"].includes(me.data.activeOffice ?? "")} />}
    </Shell>
  );
}
