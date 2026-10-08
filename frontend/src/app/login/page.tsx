import { API_URL } from "@/lib/api";
import type { PublicWindows } from "@/components/ApplicationClosed";
import { Login } from "./Login";

/** the tab reads as the CMS sign-in's does, with the portal's own name */
export const metadata = { title: "MOAUM Portal: Portal Login | Rev. Fr. Moses Orshio Adasu University, Makurdi" };

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
  /* V312: the application buttons show only while the Director of ICT has that window open; the API is the authority */
  let applications: { postUtme: boolean; postgraduate: boolean } | null = null;
  try {
    const r = await fetch(`${API_URL}/api/v1/public/application-windows`, { cache: "no-store" });
    if (r.ok) {
      const w = (await r.json()) as PublicWindows;
      applications = { postUtme: w.postUtme?.open === true, postgraduate: w.postgraduate?.open === true };
    }
  } catch {
    applications = null;
  }
  return <Login next={next} sso={sso} ssoProblem={ssoProblem} applications={applications} />;
}
