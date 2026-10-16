import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { BelowRow, LoadRules } from "@/lib/registration-load";
import { RegistrationSettings } from "./RegistrationSettings";

export const dynamic = "force-dynamic";

/** t/regsettings — Course registration settings (V495): the minimum course registration load by curriculum (CCMAS, BMAS), by
 *  session and semester, set by the Directorate of ICT with a reason; the changes made; the registrations below the minimum */
export default async function RegistrationSettingsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const session = /^\d{4}\/\d{4}$/.test(str("session")) ? str("session") : "";
  const semester = /^[123]$/.test(str("semester")) ? Number(str("semester")) : null;
  const page = /^\d{1,4}$/.test(str("page")) ? Number(str("page")) : 0;
  const q = `${session ? `session=${encodeURIComponent(session)}` : ""}${semester ? `&semester=${semester}` : ""}`;
  const [me, rules] = await Promise.all([api<Me>("/api/v1/iam/me"), api<LoadRules>(`/api/v1/registration/load/rules?${q}`)]);
  if (!rules.ok) return <Shell route="t/regsettings" me={me.ok ? me.data : null}><ProblemNotice problem={rules.problem} /></Shell>;
  const s = rules.data.session ?? "";
  const below = s ? await api<{ total: number; page: number; size: number; rows: BelowRow[] }>(
    `/api/v1/registration/load/below-minimum?session=${encodeURIComponent(s)}${semester ? `&semester=${semester}` : ""}&page=${page}&size=50`) : null;
  return (
    <Shell route="t/regsettings" me={me.ok ? me.data : null} sub={s ? `${s}${semester ? ` · semester ${semester}` : ""}` : undefined}>
      {below && !below.ok ? <ProblemNotice problem={below.problem} />
        : <RegistrationSettings key={`${s}|${semester ?? ""}`} rules={rules.data} session={s} semester={semester} below={below && below.ok ? below.data : null}
            mayChange={me.ok && ["ict", "super"].includes(me.data.activeOffice ?? "")} />}
    </Shell>
  );
}
