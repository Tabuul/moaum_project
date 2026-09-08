import { Reset } from "./Reset";

export const dynamic = "force-dynamic";

/** the reset link from the notice: the token in the address, a new password, and the applicant is signed in */
export default async function ResetPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const token = typeof params.token === "string" ? params.token : "";
  return <Reset token={token} />;
}
