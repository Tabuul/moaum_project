import { api } from "@/lib/api";
import { ApplicationClosed, type PublicWindows } from "@/components/ApplicationClosed";
import { JupebApply } from "./JupebApply";

export const dynamic = "force-dynamic";

/** /jupeb/apply — the public JUPEB application (V339), no JAMB number; while the Director of ICT has the JUPEB application window
 *  closed, the closure message instead of the form */
export default async function Page() {
  const windows = await api<PublicWindows>("/api/v1/public/application-windows");
  const w = windows.ok ? windows.data.jupeb ?? null : null;
  if (!w || !w.open) {
    return <ApplicationClosed title="JUPEB application" eyebrow="JUPEB programme" window={w} />;
  }
  return <JupebApply />;
}
