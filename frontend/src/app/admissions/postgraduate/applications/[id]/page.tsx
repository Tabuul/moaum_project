import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note } from "@/components/proto/ui";
import { PgApplicationPage } from "../../PgAdmissions";

export const dynamic = "force-dynamic";

interface Found { found: boolean; application?: { surname: string; other_names: string; application_no: string; programme_name: string; session: string } }

/** One postgraduate application on a page of its own. The API holds a department or faculty office to its own
 *  applications, so another department's id typed into the address bar shows the refusal and nothing of the record. */
export default async function PgApplicationRoute({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const p = await searchParams;
  const [me, app] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Found>(`/api/v1/pg/applications/${encodeURIComponent(id)}`),
  ]);
  const a = app.ok && app.data.found ? app.data.application ?? null : null;
  const session = typeof p.session === "string" ? p.session : a?.session ?? null;
  return (
    <Shell route="t/pgadmissions" me={me.ok ? me.data : null}>
      {!app.ok ? <ProblemNotice problem={app.problem} />
        : !a ? <Note kind="bad" title="No such postgraduate application">The application could not be found. Go back to the list and open it from there.</Note>
        : <PgApplicationPage id={id} session={session} actingOffice={me.ok ? me.data.activeOffice : null}
            heading={{ name: `${a.surname}, ${a.other_names}`, applicationNo: a.application_no, programme: a.programme_name }} />}
    </Shell>
  );
}
