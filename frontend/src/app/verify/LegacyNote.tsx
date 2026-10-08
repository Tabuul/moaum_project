import { Note } from "@/components/proto/ui";

/** V360: a document printed before its QR's check code was signed. The page says it is genuine — the University issued
 *  it — but shows none of the person's details, because the old code could be made by anyone from the number alone.
 *  The student prints the document again from the portal, and the new QR shows the full record. */
export function LegacyNote({ document, number, session, semester }: { document: string; number?: string | number | null; session?: string | null; semester?: number | null }) {
  const sem = semester === 1 ? "first" : semester === 2 ? "second" : semester === 3 ? "third" : null;
  const what = [number, session, sem ? `${sem} semester` : null].filter(Boolean).join(" · ");
  return (
    <Note kind="info" title={`Genuine ${document}, printed before its code was made secure`}>
      {`The University issued this ${document}${what ? ` (${what})` : ""}, but it carries an older check code, so the details are not shown here. Ask the holder to print it again from the portal, then scan the new one to see the full record.`}
    </Note>
  );
}
