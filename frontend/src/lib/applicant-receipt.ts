/** The receipt of an applicant's fee, named for what was paid: the Post-UTME application fee (UTME, Direct Entry and
 *  transfer applicants alike — the same screening), the CCE and Preliminary Science application fees, the admission
 *  checking fee and the acceptance fee. One name on the screen, the PDF and the public verification page. */

const ROUTE: Record<string, string> = { CCE: "CCE", PRELIMINARY: "Preliminary Science" };

/** the fee in words, sentence case: "Post-UTME application fee" */
export function applicantFeeName(kind: string | null | undefined, route?: string | null): string {
  const r = route ? ROUTE[route] : undefined;
  switch (kind) {
    case "APPLICATION": return `${r ?? "Post-UTME"} application fee`;
    case "CHECKING": return r ? `${r} admission checking fee` : "Admission checking fee";
    case "ACCEPTANCE": return r ? `${r} acceptance fee` : "Acceptance fee";
    default: return kind ?? "Fee";
  }
}

/** the receipt's title, sentence case: "Post-UTME application receipt" — the application fee's receipt is the application receipt */
export function applicantReceiptTitle(kind: string | null | undefined, route?: string | null): string {
  if (kind === "APPLICATION") return `${(route && ROUTE[route]) ?? "Post-UTME"} application receipt`;
  return `${applicantFeeName(kind, route)} receipt`;
}

/** the path (no origin) the receipt's QR opens: the public verification page, answered by the code the API signed */
export function applicantReceiptVerifyPath(reference: string, code: string): string {
  return `/verify/receipt/${encodeURIComponent(reference)}?c=${encodeURIComponent(code)}`;
}
