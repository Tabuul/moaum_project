import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Corrections } from "./Corrections";

export const dynamic = "force-dynamic";

/** t/regcorrection — the Director of ICT takes a wrongly counted course off one student's registration, with a reason; a course with
 *  a result is held for the Registrar or the Deputy Registrar, who confirm or decline it on the same page */
export default async function RegistrationCorrectionPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const me = await api<Me>("/api/v1/iam/me");
  const matric = typeof params.matric === "string" ? params.matric.trim() : "";
  return (
    <Shell route="t/regcorrection" me={me.ok ? me.data : null}>
      <Corrections office={me.ok ? me.data.activeOffice : null} initialMatric={matric} />
    </Shell>
  );
}
