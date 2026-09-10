import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SmsSettings, type SmsConfig } from "./SmsSettings";

export const dynamic = "force-dynamic";

/** t/sms — the SMS gateway settings (eBulkSMS): username, sender ID and API key, set by the Directorate of ICT */
export default async function SmsPage() {
  const [me, config] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SmsConfig>("/api/v1/platform/sms"),
  ]);
  return (
    <Shell route="t/sms" me={me.ok ? me.data : null}>
      {config.ok ? <SmsSettings config={config.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={config.problem} />}
    </Shell>
  );
}
