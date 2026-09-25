import { Activate } from "./Activate";

export const dynamic = "force-dynamic";

/** the invitation link from the notice: the token in the address; the examiner chooses a password and the account is live */
export default async function ActivatePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const token = typeof params.token === "string" ? params.token : "";
  return <Activate token={token} />;
}
