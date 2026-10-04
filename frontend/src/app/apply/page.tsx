import { api } from "@/lib/api";
import { ApplicationClosed, type PublicWindows } from "@/components/ApplicationClosed";
import { Register } from "./Register";

export const dynamic = "force-dynamic";

/** Post-UTME registration — open to the world, keyed on the JAMB number against the list the Academic Office loaded.
 *  The session and whether registration is open are the API's to say (V312): while the Director of ICT has the window
 *  closed, scheduled or expired, the closure message instead of the form. */
export default async function ApplyPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const asked = typeof params.session === "string" && /^\d{4}\/\d{4}$/.test(params.session) ? params.session : null;
  const windows = await api<PublicWindows>(`/api/v1/public/application-windows${asked ? `?session=${encodeURIComponent(asked)}` : ""}`);
  if (!windows.ok || !windows.data.postUtme.open) {
    return <ApplicationClosed title="Post-UTME registration" eyebrow="Admissions" window={windows.ok ? windows.data.postUtme : null} />;
  }
  return <Register session={windows.data.postUtme.session} />;
}
