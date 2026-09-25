import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Category } from "@/lib/helpdesk";
import { Settings, type DeskSettings } from "./Settings";

export const dynamic = "force-dynamic";

/** t/helpdesksettings — the Director's: the categories and what each asks for, the SLA by priority, the quiet spell */
export default async function HelpdeskSettingsPage() {
  const [me, categories, settings] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Category[]>("/api/v1/helpdesk/admin/categories"),
    api<DeskSettings>("/api/v1/helpdesk/admin/settings"),
  ]);
  return (
    <Shell route="t/helpdesksettings" me={me.ok ? me.data : null}>
      {!categories.ok ? <ProblemNotice problem={categories.problem} /> : !settings.ok ? <ProblemNotice problem={settings.problem} /> : (
        <Settings categories={categories.data} settings={settings.data} />
      )}
    </Shell>
  );
}
