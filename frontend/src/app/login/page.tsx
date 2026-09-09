import { API_URL } from "@/lib/api";
import { Login } from "./Login";

export const dynamic = "force-dynamic";

/** one door; whether single sign-on is connected is the API's to say */
export default async function LoginPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const next = typeof params.next === "string" && params.next.startsWith("/") ? params.next : "/";
  let sso: { enabled: boolean; label: string } | null = null;
  try {
    const r = await fetch(`${API_URL}/api/v1/auth/sso`, { cache: "no-store" });
    if (r.ok) sso = (await r.json()) as { enabled: boolean; label: string };
  } catch {
    sso = null;
  }
  const ssoProblem = typeof params.sso === "string" && params.sso ? params.sso : null;
  return <Login next={next} sso={sso} ssoProblem={ssoProblem} />;
}
