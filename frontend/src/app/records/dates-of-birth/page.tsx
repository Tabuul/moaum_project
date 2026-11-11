import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { DobFromFile } from "./DobFromFile";

export const dynamic = "force-dynamic";

/** /records/dates-of-birth — V721: old-portal students' dates of birth re-read from the migration file against the register */
export default async function DatesOfBirthPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/dobfromfile" me={me.ok ? me.data : null}>
      <DobFromFile actingOffice={me.ok ? me.data.activeOffice ?? null : null} />
    </Shell>
  );
}
