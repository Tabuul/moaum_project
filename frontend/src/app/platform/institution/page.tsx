import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { normaliseInstitution, type Institution } from "@/lib/document/institution";
import { InstitutionProfile } from "./InstitutionProfile";

export const dynamic = "force-dynamic";

/** t/institution — the University's official identity on every document (V320): name, motto, address, contacts, logo
 *  and the document defaults, kept by the Directorate of ICT and the Registry */
export default async function InstitutionPage() {
  const [me, profile] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Record<string, unknown>>("/api/v1/public/institution")]);
  const inst: Institution | null = profile.ok ? normaliseInstitution(profile.data) : null;
  return (
    <Shell route="t/institution" me={me.ok ? me.data : null}>
      {inst ? <InstitutionProfile initial={inst} actingOffice={me.ok ? me.data.activeOffice : null} actorName={me.ok ? me.data.name ?? null : null} /> : <ProblemNotice problem={profile.ok ? { status: 500, title: "Unreadable" } : profile.problem} />}
    </Shell>
  );
}
