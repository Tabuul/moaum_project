import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Uploads } from "./Uploads";

export const dynamic = "force-dynamic";

/** t/legacyuploads — the confirmed old-portal uploads of course registration and past results, and (with ?id=) one upload's
 *  report: every change it made with what was there before, the students whose CGPA moved, the Senate-approved graduates, the
 *  rows that did not load or were left as they were; the person who opened a running upload closes it, and the Directorate of ICT
 *  rolls a confirmed one back */
export default async function OldPortalUploadsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const id = typeof params.id === "string" && params.id.trim() ? params.id.trim() : null;
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/legacyuploads" me={me.ok ? me.data : null}>
      <Uploads id={id} viewer={me.ok ? { actorId: me.data.actorId ?? null, office: me.data.activeOffice ?? null } : null} />
    </Shell>
  );
}
