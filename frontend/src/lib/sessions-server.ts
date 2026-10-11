import { api } from "@/lib/api";
import { currentSession, intakeSession, type SessionRow } from "@/lib/sessions";

/** the sessions on the University's calendar, as /ref/sessions returns them; none when the call fails */
export async function sessionRows(): Promise<SessionRow[]> {
  const r = await api<SessionRow[]>("/api/v1/ref/sessions");
  return r.ok ? r.data : [];
}

/** a screen's session when the address names none: the intake session for admission screens, the University's current
 *  session for every other one (lib/sessions) */
export async function defaultSession(kind: "current" | "intake" = "current"): Promise<string> {
  const rows = await sessionRows();
  return kind === "intake" ? intakeSession(rows) : currentSession(rows);
}
