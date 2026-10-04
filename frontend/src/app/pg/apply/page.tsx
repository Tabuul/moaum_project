import { api } from "@/lib/api";
import { ApplicationClosed, type PublicWindows } from "@/components/ApplicationClosed";
import { PgApply } from "./PgApply";

export const dynamic = "force-dynamic";

/** /pg/apply — the public postgraduate application, open to the world (no JAMB number); while the Director of ICT has the
 *  window closed (V312), the closure message instead of the form */
export default async function Page() {
  const windows = await api<PublicWindows>("/api/v1/public/application-windows");
  if (!windows.ok || !windows.data.postgraduate.open) {
    return <ApplicationClosed title="Postgraduate application" eyebrow="Postgraduate admissions" window={windows.ok ? windows.data.postgraduate : null} />;
  }
  return <PgApply />;
}
