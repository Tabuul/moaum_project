import { api } from "@/lib/api";
import type { CalendarData } from "@/lib/calendar";
import { Shell, type Me } from "@/components/proto/Shell";
import { SessionSetup } from "./SessionSetup";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function CalendarPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const asked = typeof params.session === "string" && SESSION_PATTERN.test(params.session) ? params.session : null;

  const [me, calendar] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CalendarData>(`/api/v1/calendar${asked ? `?session=${encodeURIComponent(asked)}` : ""}`),
  ]);

  return (
    <Shell route="t/session" me={me.ok ? me.data : null}>
      <SessionSetup
        calendar={calendar.ok ? calendar.data : null}
        problem={calendar.ok ? null : calendar.problem}
        actingOffice={me.ok ? me.data.activeOffice : null}
      />
    </Shell>
  );
}
