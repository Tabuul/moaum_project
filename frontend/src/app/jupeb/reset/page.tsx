import { JupebReset } from "./JupebReset";

export const dynamic = "force-dynamic";

/** /jupeb/reset — a JUPEB candidate's forgotten password: ask for a link, or (with the link's token) choose a new password */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  return <JupebReset token={typeof params.token === "string" ? params.token : ""} />;
}
