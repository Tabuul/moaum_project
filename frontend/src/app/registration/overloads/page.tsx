import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { OverloadList } from "@/lib/overloads";
import { Overloads } from "./Overloads";

export const dynamic = "force-dynamic";

/** t/overloads — Overload requests (V508): the students who ask for a higher maximum in a semester, granted or refused by the
 *  Head of Department of their department; read by the Dean, the Academic Office and the Registry */
export default async function OverloadsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const session = /^\d{4}\/\d{4}$/.test(str("session")) ? str("session") : "";
  const semester = /^[123]$/.test(str("semester")) ? Number(str("semester")) : null;
  const status = /^(REQUESTED|GRANTED|REFUSED|WITHDRAWN)$/.test(str("status")) ? str("status") : "";
  const q = str("q").slice(0, 60);
  const page = /^\d{1,4}$/.test(str("page")) ? Number(str("page")) : 0;
  const qs = new URLSearchParams({ page: String(page), size: "50" });
  if (session) qs.set("session", session);
  if (semester) qs.set("semester", String(semester));
  if (status) qs.set("status", status);
  if (q) qs.set("q", q);
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<OverloadList>(`/api/v1/registration/overloads?${qs.toString()}`)]);
  const office = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/overloads" me={me.ok ? me.data : null} sub={list.ok ? `${list.data.session}${list.data.semester ? ` · semester ${list.data.semester}` : ""}` : undefined}>
      {!list.ok ? <ProblemNotice problem={list.problem} />
        : <Overloads key={`${list.data.session}|${semester ?? ""}|${status}|${q}|${page}`} o={list.data} status={status} q={q}
            mayDecide={["hod", "super"].includes(office)} maySetRule={["academic", "registrar", "dregistrar", "ict", "super"].includes(office)} />}
    </Shell>
  );
}
