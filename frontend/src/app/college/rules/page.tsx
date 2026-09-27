import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Rules, type RulesData, type Level100, type CarryOvers } from "./Rules";

export const dynamic = "force-dynamic";

/** t/collegerules — the College's rules as the regulations state them, read and set on the audit spine; the Board's 100 Level act; the carry-overs (V285) */
export default async function CollegeRulesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions, rules, carry] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
    api<RulesData>("/api/v1/college/rules"),
    api<CarryOvers>("/api/v1/college/carry-overs"),
  ]);
  const names = sessions.ok ? sessions.data.map((s) => s.name) : [];
  const current = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? names[0] ?? "" : "";
  const session = typeof p.session === "string" && p.session ? p.session : current;
  const l100 = session ? await api<Level100>(`/api/v1/college/level100?session=${encodeURIComponent(session)}`) : null;
  const office = me.ok ? me.data.activeOffice : null;
  const mayEdit = ["provost", "collegesecretary", "academic", "registrar", "dregistrar", "super"].includes(office ?? "");
  const mayAct = ["provost", "collegesecretary", "academic", "registrar", "dregistrar", "admin", "super"].includes(office ?? "");
  return (
    <Shell route="t/collegerules" me={me.ok ? me.data : null}>
      {!rules.ok ? <ProblemNotice problem={rules.problem} /> : (
        <Rules data={rules.data} sessions={names} session={session} level100={l100 && l100.ok ? l100.data : { session, rows: [] }} carry={carry.ok ? carry.data : { rows: [] }} mayEdit={mayEdit} mayAct={mayAct} />
      )}
    </Shell>
  );
}
