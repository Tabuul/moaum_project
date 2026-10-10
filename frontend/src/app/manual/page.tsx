import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ManualReader } from "@/components/manual/ManualReader";
import { readerLabel, readerMenus, type ManualView } from "@/lib/manual";

export const dynamic = "force-dynamic";

/** the sidebar the portal names beside the office: a postgraduate reads the School's (as the student pages decide it) */
export async function readerMenu(me: Me | null): Promise<string | null> {
  if (!me) return null;
  if (me.menu) return me.menu;
  if (me.activeOffice === "student") {
    const mine = await api<{ entryMode?: string | null }>("/api/v1/me");
    if (mine.ok && mine.data.entryMode === "POSTGRADUATE") return "pgstudent";
  }
  return null;
}

/** t/manual — the Quick Operational Manual of the signed-in person (V387) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const initial = typeof sp.p === "string" && /^[a-z0-9-]{1,80}$/.test(sp.p) ? sp.p : null;
  const me = await api<Me>("/api/v1/iam/me");
  const who = me.ok ? { ...me.data, menu: await readerMenu(me.data) } : null;
  const menu = who?.menu ?? null;
  const data = await api<ManualView>(`/api/v1/manual${menu ? `?menu=${encodeURIComponent(menu)}` : ""}`);
  const office = who?.activeOffice ?? null;
  return (
    <Shell route="t/manual" me={who}>
      {data.ok ? (
        <ManualReader data={data.data} menus={readerMenus(office, menu)} label={readerLabel(office, menu)} initial={initial}
          pdfHref={`/manual/pdf${menu ? `?menu=${encodeURIComponent(menu)}` : ""}`} />
      ) : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
