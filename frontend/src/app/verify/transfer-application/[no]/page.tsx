import { Verified, one } from "../Verified";

export const dynamic = "force-dynamic";

/** /verify/transfer-application/{no}?t={code} — V766: the number as one path segment (its slashes encoded), kept for a link written
 *  that way; the acknowledgement's QR leads to /verify/transfer-application?no=… instead. The segment is read decoded whichever way
 *  Next.js hands it over, and the API is asked with the number in its query (an encoded slash in the API's path is refused). */
export default async function Page({ params, searchParams }: { params: Promise<{ no: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await params;
  const q = await searchParams;
  let no = p.no;
  try {
    no = decodeURIComponent(p.no);
  } catch {
    // a stray % left as it is
  }
  return <Verified no={no.trim()} code={one(q.t)} />;
}
