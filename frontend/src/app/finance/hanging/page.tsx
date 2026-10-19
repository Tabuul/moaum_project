import { api } from "@/lib/api";
import type { DeskFigure, DeskRow, PaymentsDesk } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Hanging } from "./Hanging";

export const dynamic = "force-dynamic";

const FIGURES: DeskFigure[] = ["hanging", "resolved", "needs"];

/** t/hanging — successful at the gateway, pending here: asked about, not argued about. A figure opened (?show=hanging, resolved or
 *  needs) lists the transactions behind it with who paid. */
export default async function HangingPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const show = FIGURES.find((f) => f === sp.show) ?? null;
  const [me, d, shown] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PaymentsDesk>("/api/v1/payments/bursary"),
    show ? api<{ kind: DeskFigure; rows: DeskRow[] }>(`/api/v1/payments/bursary/transactions?kind=${show}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/hanging" me={me.ok ? me.data : null}>
      {d.ok
        ? <Hanging d={d.data} actingOffice={me.ok ? me.data.activeOffice : null} shown={shown && shown.ok ? shown.data : null} />
        : <ProblemNotice problem={d.problem} />}
      {shown && !shown.ok ? <ProblemNotice problem={shown.problem} /> : null}
    </Shell>
  );
}
