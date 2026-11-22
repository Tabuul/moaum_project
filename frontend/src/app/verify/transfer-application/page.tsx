import { Verified, one } from "./Verified";

export const dynamic = "force-dynamic";

/** /verify/transfer-application?no={applicationNo}&t={code} — V766: where the acknowledgement's QR leads (its verifyPath): the number in
 *  the query, never in the path, so its slashes reach the API as they are */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  return <Verified no={one(q.no).trim()} code={one(q.t)} />;
}
