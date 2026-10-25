import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Desk } from "./Desk";
import type { DeskData } from "./ptn-call";
import "./partnerships.css";

export const dynamic = "force-dynamic";

const TABS = ["dashboard", "proposals", "reports", "settings"] as const;

/** t/partnerships — Collaboration & Partnerships (V658): the Linkages office's desk, the reviewers' list, the VC's approvals, the reports */
export default async function PartnershipsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const [me, desk] = await Promise.all([api<Me>("/api/v1/iam/me"), api<DeskData>("/api/v1/partnerships/desk")]);
  const tab = (TABS as readonly string[]).includes(s("tab")) ? (s("tab") as (typeof TABS)[number]) : s("view") ? "proposals" : "dashboard";
  return (
    <Shell route="t/partnerships" me={me.ok ? me.data : null}>
      {desk.ok ? <Desk desk={desk.data} initialTab={tab} initialView={s("view") || null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
