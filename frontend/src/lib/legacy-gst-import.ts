/**
 * The columns of an old-portal GST payment export (V323) and how a file's headings are matched to them: by name, never by
 * position, an exact heading first and then the first heading that contains an alias, each column taken once. The mapping
 * is shown and can be changed before the rows are staged. A row needs a transaction id or a payment reference of its own.
 */
export interface LegacyRow {
  row: number; transactionId: string; reference: string; gateway: string; gatewayReference: string; legacyStudentId: string; matric: string; jamb: string;
  applicationNo: string; name: string; paymentType: string; amount: string; paidAt: string; session: string; semester: string; status: string;
}

export const LEGACY_FIELDS: { key: keyof Omit<LegacyRow, "row">; label: string; required?: boolean; aliases: string[] }[] = [
  { key: "transactionId", label: "Transaction ID", aliases: ["transaction id", "transaction_id", "txn id", "txn_id", "trans id", "transaction no", "payment id", "payment_id", "id"] },
  { key: "reference", label: "Payment reference", aliases: ["payment reference", "payment ref", "reference", "ref", "rrr", "order id", "invoice", "invoice no", "receipt no", "receipt"] },
  { key: "gateway", label: "Gateway", aliases: ["gateway", "channel", "provider", "payment gateway", "platform"] },
  { key: "gatewayReference", label: "Gateway reference", aliases: ["gateway reference", "gateway ref", "transaction reference", "trans ref", "remita rrr", "paystack ref", "interswitch ref"] },
  { key: "legacyStudentId", label: "Old-portal student ID", aliases: ["legacy student id", "old student id", "student id", "student_id", "user id", "userid"] },
  { key: "matric", label: "Matriculation number", aliases: ["matric", "matric no", "matric number", "matriculation number", "matric_no", "reg no", "registration number", "regno"] },
  { key: "jamb", label: "JAMB number", aliases: ["jamb", "jamb no", "jamb number", "jamb reg no", "jamb registration number", "utme no"] },
  { key: "applicationNo", label: "Application / admission number", aliases: ["application no", "application number", "admission no", "admission number", "form no", "application_no"] },
  { key: "name", label: "Student name", aliases: ["student name", "full name", "name", "payer", "payer name", "names"] },
  { key: "paymentType", label: "Payment type", aliases: ["payment type", "fee type", "fee", "payment_type", "purpose", "description", "item", "type", "payment for", "fee name"] },
  { key: "amount", label: "Amount", required: true, aliases: ["amount", "amount paid", "total", "amount_paid", "paid"] },
  { key: "paidAt", label: "Payment date", aliases: ["payment date", "paid on", "date paid", "date", "transaction date", "paid_at", "created", "created at"] },
  { key: "session", label: "Session", required: true, aliases: ["session", "academic session", "academic_session", "session paid"] },
  { key: "semester", label: "Semester", aliases: ["semester", "sem", "term"] },
  { key: "status", label: "Status", required: true, aliases: ["status", "payment status", "transaction status", "state", "paid status"] },
];

/** which column (0-based) feeds each field; a field absent from the file is absent from the map */
export function detectLegacyMapping(header: string[]): Record<string, number> {
  const h = header.map((x) => String(x ?? "").trim().toLowerCase().replace(/[_]+/g, " ").replace(/\s*\*$/, "").replace(/\s+/g, " "));
  const map: Record<string, number> = {};
  const used = new Set<number>();
  for (const f of LEGACY_FIELDS) {
    const i = h.findIndex((x, idx) => !used.has(idx) && f.aliases.includes(x));
    if (i >= 0) { map[f.key] = i; used.add(i); }
  }
  for (const f of LEGACY_FIELDS) {
    if (map[f.key] !== undefined) continue;
    const i = h.findIndex((x, idx) => !used.has(idx) && x && f.aliases.some((a) => a.length > 2 && x.includes(a)));
    if (i >= 0) { map[f.key] = i; used.add(i); }
  }
  return map;
}

/** the header row: the first row that names at least three of the fields, else the first row */
export function legacyHeaderRowIndex(cells: string[][]): number {
  const i = cells.findIndex((row) => Object.keys(detectLegacyMapping(row)).length >= 3);
  return i < 0 ? 0 : i;
}

/** the file's rows as the server stages them, a row number from the sheet on each, blank rows left out */
export function legacyRowsOf(cells: string[][], headerIndex: number, mapping: Record<string, number>, fallback: { session: string }): LegacyRow[] {
  const g = (r: string[], key: string) => { const i = mapping[key]; return i === undefined || i < 0 ? "" : String(r[i] ?? "").trim(); };
  return cells.slice(headerIndex + 1).map((r, i) => ({
    row: headerIndex + i + 2, transactionId: g(r, "transactionId"), reference: g(r, "reference"), gateway: g(r, "gateway"), gatewayReference: g(r, "gatewayReference"),
    legacyStudentId: g(r, "legacyStudentId"), matric: g(r, "matric"), jamb: g(r, "jamb"), applicationNo: g(r, "applicationNo"), name: g(r, "name"),
    paymentType: g(r, "paymentType"), amount: g(r, "amount"), paidAt: g(r, "paidAt"), session: g(r, "session") || fallback.session, semester: g(r, "semester"), status: g(r, "status"),
  })).filter((r) => r.transactionId || r.reference || r.matric || r.jamb || r.amount);
}
