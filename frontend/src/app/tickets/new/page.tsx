import { api } from "@/lib/api";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PageHead } from "@/components/proto/ui";
import type { Category, Profile } from "@/lib/helpdesk";
import { requester } from "../who";
import { NewTicket } from "./NewTicket";

export const dynamic = "force-dynamic";

/** Submit an ICT support ticket — the account fills in who you are; the category decides what else is asked */
export default async function NewTicketPage() {
  const { me, route } = await requester();
  const [profile, categories, sessions] = await Promise.all([
    api<Profile>("/api/v1/helpdesk/my/profile"),
    api<Category[]>("/api/v1/helpdesk/categories"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
  ]);
  return (
    <Shell route={route} me={me}>
      <PageHead title="Submit an ICT Support Ticket" description="Choose what the problem is about, describe it, attach any evidence. You receive a tracking number at once." />
      {!profile.ok ? <ProblemNotice problem={profile.problem} /> : !categories.ok ? <ProblemNotice problem={categories.problem} /> : (
        <NewTicket profile={profile.data} categories={categories.data} sessions={sessions.ok ? sessions.data.map((s) => s.name) : []} />
      )}
    </Shell>
  );
}
