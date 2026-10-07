import { JupebPortal } from "./JupebPortal";

export const dynamic = "force-dynamic";

/** /jupeb/portal — the JUPEB candidate's own dashboard, from applicant to student to result (V339); ?tab= is the section the side menu opened */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  return <JupebPortal tab={typeof p.tab === "string" ? p.tab : undefined} />;
}
