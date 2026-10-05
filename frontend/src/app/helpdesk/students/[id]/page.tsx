import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { SupportProfile as Profile } from "@/lib/support";
import { SupportProfile } from "./SupportProfile";

export const dynamic = "force-dynamic";

/** One student in support mode (V334): the record, the registration, the payments and documents the posting allows, the history, the tickets. */
export default async function SupportStudentPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const p = await searchParams;
  const ticket = typeof p.ticket === "string" ? p.ticket : "";
  const tab = typeof p.tab === "string" ? p.tab : "profile";
  const [me, profile] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Profile>(`/api/v1/helpdesk/support/students/${id}${ticket ? `?ticket=${encodeURIComponent(ticket)}` : ""}`),
  ]);
  return (
    <Shell route="t/supportstudents" me={me.ok ? me.data : null}>
      {!profile.ok ? <ProblemNotice problem={profile.problem} /> : <SupportProfile id={id} data={profile.data} tab={tab} />}
    </Shell>
  );
}
