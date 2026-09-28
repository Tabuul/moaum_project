import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Windows, type WindowsPage } from "./Windows";

export const dynamic = "force-dynamic";

/** t/portalwindows — the Director of ICT's Payment & Registration Windows (V288) */
export default async function PortalWindowsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const [me, page] = await Promise.all([api<Me>("/api/v1/iam/me"), api<WindowsPage>(`/api/v1/portal-windows${session ? `?session=${encodeURIComponent(session)}` : ""}`)]);
  return (
    <Shell route="t/portalwindows" me={me.ok ? me.data : null}>
      {page.ok ? <Windows page={page.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
