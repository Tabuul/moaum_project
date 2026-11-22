/** The receipt of an applicant's fee, named for what was paid: the Post-UTME application fee (UTME, Direct Entry and
 *  transfer applicants alike — the same screening), the CCE, Preliminary Science, Preliminary Technology & Industrial Studies,
 *  proficiency certificate (V701), postgraduate and inter-university transfer (V766) application fees, the admission checking fee and the acceptance fee. One name
 *  on the screen, the PDF and the public verification page. A preliminary receipt names its route; one that names only the
 *  entry mode (PRELIMINARY) is Preliminary Science's, the only one before V701. */

const ROUTE: Record<string, string> = {
  CCE: "CCE", PRELIMINARY: "Preliminary Science", POSTGRADUATE: "Postgraduate", PRELIMINARY_SCIENCE: "Preliminary Science",
  PRELIMINARY_TECHNOLOGY: "Preliminary Technology & Industrial Studies", PROFICIENCY_CERTIFICATE: "Proficiency certificate", PROFICIENCY: "Proficiency certificate",
};

/** the fee in words, sentence case: "Post-UTME application fee" */
export function applicantFeeName(kind: string | null | undefined, route?: string | null): string {
  const r = route ? ROUTE[route] : undefined;
  switch (kind) {
    case "APPLICATION": return `${r ?? "Post-UTME"} application fee`;
    case "CHECKING": return r ? `${r} admission checking fee` : "Admission checking fee";
    case "ACCEPTANCE": return r ? `${r} acceptance fee` : "Acceptance fee";
    /* V766: a student of another university applying online for an inter-university transfer */
    case "IUT_APPLICATION": return "Inter-university transfer application fee";
    default: return kind ?? "Fee";
  }
}

/** the receipt's title, sentence case: "Post-UTME application receipt" — the application fee's receipt is the application receipt */
export function applicantReceiptTitle(kind: string | null | undefined, route?: string | null): string {
  if (kind === "APPLICATION") return `${(route && ROUTE[route]) ?? "Post-UTME"} application receipt`;
  if (kind === "IUT_APPLICATION") return "Inter-university transfer application receipt";
  return `${applicantFeeName(kind, route)} receipt`;
}

/** the path (no origin) the receipt's QR opens: the public verification page, answered by the code the API signed */
export function applicantReceiptVerifyPath(reference: string, code: string): string {
  return `/verify/receipt/${encodeURIComponent(reference)}?c=${encodeURIComponent(code)}`;
}
