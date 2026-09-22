import { RefereeForm } from "./RefereeForm";

export const dynamic = "force-dynamic";

/** /pg/referee/[token] — the public referee reference form, reached by the private emailed link. */
export default async function Page({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return <RefereeForm token={token} />;
}
