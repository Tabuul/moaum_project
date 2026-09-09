import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MailSettings, type MailConfig } from "./MailSettings";

export const dynamic = "force-dynamic";

/** t/mail — the mail server settings (Microsoft 365): IMAP, POP and SMTP, set by the Directorate of ICT */
export default async function MailPage() {
  const [me, config] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<MailConfig>("/api/v1/platform/mail"),
  ]);
  return (
    <Shell route="t/mail" me={me.ok ? me.data : null}>
      {config.ok ? <MailSettings config={config.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={config.problem} />}
    </Shell>
  );
}
