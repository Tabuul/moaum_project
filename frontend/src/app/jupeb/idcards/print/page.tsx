import { CardSheet } from "./CardSheet";

export const dynamic = "force-dynamic";

/** /jupeb/idcards/print?session=&ids=[&print=0] — the chosen students' cards on A4, without the portal around them (V349); print=0 shows them without opening the print dialog */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const ids = typeof p.ids === "string" ? p.ids.split(",").filter((x) => /^[0-9a-f-]{36}$/i.test(x)) : [];
  return <CardSheet session={session} ids={ids} autoPrint={p.print !== "0"} />;
}
