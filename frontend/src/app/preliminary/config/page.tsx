import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import type { PrelimDeskRoute } from "@/lib/preliminary";
import { PrelimConfig } from "./PrelimConfig";

export const dynamic = "force-dynamic";

/** prelim/config — a preliminary or proficiency programme's settings (V446; V701 every route, chosen with ?route=, a programme's
 *  own office on its own first): the Academic Office's rule, targets or courses and documents, the Bursary's fees; the server
 *  decides who may change what */
export default async function PrelimConfigPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const [me, routes] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PrelimDeskRoute[]>("/api/v1/admissions/preliminary/routes")]);
  const office = (me.ok ? me.data.activeOffice : null) ?? "";
  const list = routes.ok ? routes.data : [];
  const asked = typeof sp.route === "string" ? sp.route : "";
  const route = list.find((r) => r.route === asked)?.route ?? list[0]?.route ?? "PRELIMINARY_SCIENCE";
  return (
    <Shell route="prelim/config" me={me.ok ? me.data : null}>
      <PrelimConfig key={route} route={route} routes={list} may={{ configure: ["academic", "super"].includes(office), fees: ["bursar", "super"].includes(office) }} />
    </Shell>
  );
}
