import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebReports } from "./JupebReports";

export const dynamic = "force-dynamic";

/** /jupeb/reports — the JUPEB Office's reports of a session, in Excel and PDF (V347); the API decides who reads it (the JUPEB Office, Super, the administrator) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="jupeb/reports" me={me.ok ? me.data : null}>
      <JupebReports />
    </Shell>
  );
}
