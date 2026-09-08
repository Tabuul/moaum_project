import { api } from "@/lib/api";
import { Register } from "./Register";

export const dynamic = "force-dynamic";

/** Post-UTME registration — open to the world, keyed on the JAMB number against the list the Academic Office loaded */
export default async function ApplyPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const asked = typeof params.session === "string" && /^\d{4}\/\d{4}$/.test(params.session) ? params.session : null;
  const sessions = await api<{ name: string; state: string }[]>("/api/v1/ref/sessions");
  const current = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? null : null;
  return <Register session={asked ?? current ?? "2026/2027"} />;
}
