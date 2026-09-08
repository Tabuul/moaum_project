import { api } from "@/lib/api";
import type { CertificateRegister } from "@/lib/credentials";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Certificates } from "./Certificates";

export const dynamic = "force-dynamic";

export default async function CertificatesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const convocation = typeof params.convocation === "string" ? params.convocation : "";
  const [me, register] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CertificateRegister>(`/api/v1/credentials/certificates${convocation ? `?convocation=${encodeURIComponent(convocation)}` : ""}`),
  ]);
  return (
    <Shell route="t/certificates" me={me.ok ? me.data : null}>
      {register.ok ? <Certificates register={register.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={register.problem} />}
    </Shell>
  );
}
