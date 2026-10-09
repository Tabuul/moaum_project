import { notFound } from "next/navigation";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { CCE_TABS, type CceTab } from "@/lib/cce";
import { CceDesk } from "../CceDesk";

export const dynamic = "force-dynamic";

/** /cce — the CCE desk (V379): the Academic Office's CCE Management and the Centre for Continuing Education's desk, one screen
 *  per tab (/cce/upload, /cce/applications/{id}, …). What each office may do is the server's rule; the page shows the acts the
 *  acting office has. */
export default async function Page({ params, searchParams }: { params: Promise<{ tab?: string[] }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { tab } = await params;
  const q = await searchParams;
  const first = tab?.[0] ?? "dashboard";
  if (!(CCE_TABS as readonly string[]).includes(first) || (tab && tab.length > (first === "applications" ? 2 : 1))) notFound();
  const id = first === "applications" && tab?.[1] && /^[0-9a-f-]{36}$/.test(tab[1]) ? tab[1] : null;
  if (first === "applications" && tab?.[1] && !id) notFound();
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice ?? null : null;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : null;
  const status = typeof q.status === "string" ? q.status : null;
  return (
    <Shell route={`cce/${first}`} me={me.ok ? me.data : null}>
      <CceDesk tab={first as CceTab} id={id} office={office} initialSession={session} initialStatus={status} />
    </Shell>
  );
}
