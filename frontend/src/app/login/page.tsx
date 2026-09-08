import { API_URL } from "@/lib/api";
import { Login } from "./Login";

export const dynamic = "force-dynamic";

/** the office register is public, so the sign-in page can offer "Your office" */
export default async function LoginPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const next = typeof params.next === "string" && params.next.startsWith("/") ? params.next : "/";
  let offices: { code: string; label: string }[] = [];
  try {
    const r = await fetch(`${API_URL}/api/v1/auth/offices`, { cache: "no-store" });
    if (r.ok) offices = (await r.json()) as { code: string; label: string }[];
  } catch {
    offices = [];
  }
  return <Login next={next} offices={offices} />;
}
