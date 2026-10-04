import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Applications, type ApplicationsPage } from "./Applications";

export const dynamic = "force-dynamic";

/** t/applicationwindows — Application Registration Control (V312): the Director of ICT opens, closes, schedules, extends and
 *  reopens Post UTME Registration and the Postgraduate Application for a session, writes the message the public reads while
 *  one is closed, and reads the history of every act */
export default async function ApplicationsControlPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : "";
  const [me, page] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ApplicationsPage>(`/api/v1/portal-windows/applications${session ? `?session=${encodeURIComponent(session)}` : ""}`),
  ]);
  return (
    <Shell route="t/applicationwindows" me={me.ok ? me.data : null}>
      {page.ok ? <Applications page={page.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
