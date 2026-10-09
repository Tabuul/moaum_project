import { api } from "@/lib/api";
import { ApplicationClosed, type PublicWindows } from "@/components/ApplicationClosed";
import { CceRegister } from "./CceRegister";

export const dynamic = "force-dynamic";

/** The CCE application (V379) — open to those whose names JAMB sent the University on the CCE list, who prove it with the JAMB
 *  number and the date of birth on the list. While the Director of ICT has the CCE application window closed, scheduled or
 *  expired, the closure message instead of the form; the API refuses again whatever this page shows. */
export default async function CceApplyPage() {
  const windows = await api<PublicWindows>("/api/v1/public/application-windows");
  const w = windows.ok ? windows.data.cce ?? null : null;
  if (!w || !w.open) return <ApplicationClosed title="The CCE application" eyebrow="Centre for Continuing Education" window={w} />;
  return <CceRegister session={w.session} />;
}
