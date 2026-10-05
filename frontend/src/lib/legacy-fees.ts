/** The Old Fees History upload (/finance/legacy-fees): which column is which, matched by keyword so the portal's own
 *  template and the old portal's export ("paymentRECENT with pay_item": Matriculation Number, Session, Semester, Level,
 *  Amount, Purpose/Payment Item, Payment Date, Channel, Reference) both read. V326: the payment item is carried as the
 *  row's purpose — GST FEES is the GST fee for that session — and the old reference and channel travel with the row. */

export interface LegacyFeeRow {
  matric: string;
  session: string;
  semester: string;
  level: string;
  amount: string;
  /** the old portal's payment item (SCHOOL FEES, GST FEES, ADMISSION CHECKING…), or "" when the file has no such column */
  purpose: string;
  paidOn: string;
  receiptNo: string;
  channel: string;
  note: string;
}

export interface LegacyFeeColumns {
  matric: number; session: number; sem: number; level: number; amount: number; purpose: number; paidOn: number; receipt: number; channel: number; note: number;
}

/** the column each field is read from (−1 when the file has none), matched on the header's words */
export function legacyFeeColumns(headerCells: unknown[]): LegacyFeeColumns {
  const header = headerCells.map((c) => String(c ?? "").trim().toLowerCase());
  const at = (names: string[]) => header.findIndex((h) => names.some((n) => h.includes(n)));
  return {
    matric: at(["matric", "reg"]),
    session: at(["session"]),
    sem: at(["semester", "sem"]),
    level: at(["level"]),
    amount: at(["amount"]),
    purpose: at(["purpose", "payment item", "pay_item", "pay item", "item", "fee type", "payment type", "description"]),
    paidOn: at(["paid on", "payment date", "date"]),
    receipt: at(["receipt", "reference", "ref no", "transaction"]),
    channel: at(["channel", "gateway"]),
    note: at(["note", "remark", "comment"]),
  };
}

/** the rows the API is sent: every row with a matriculation number and a session written YYYY/YYYY */
export function legacyFeeRows(grid: unknown[][]): { columns: LegacyFeeColumns; rows: LegacyFeeRow[] } {
  const columns = legacyFeeColumns(grid[0] ?? []);
  const g = (r: unknown[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
  const rows = grid.slice(1)
    .filter((r) => g(r, columns.matric) && /^[0-9]{4}\/[0-9]{4}$/.test(g(r, columns.session)))
    .map((r) => ({
      matric: g(r, columns.matric), session: g(r, columns.session), semester: g(r, columns.sem), level: g(r, columns.level),
      amount: g(r, columns.amount), purpose: g(r, columns.purpose), paidOn: g(r, columns.paidOn), receiptNo: g(r, columns.receipt),
      channel: g(r, columns.channel), note: g(r, columns.note),
    }));
  return { columns, rows };
}

/** what a row's item will be recorded as, for the preview: the GST fee, school fees, or its own purpose */
export function legacyFeeKind(row: LegacyFeeRow): "GST" | "SCHOOL" | "OTHER" {
  const text = (row.purpose || row.note).trim();
  if (/(^|[^a-z])(gst|gns|eps)([^a-z]|$)|general\s*stud|entrepreneur/i.test(text)) return "GST";
  if (!text || /(school|tuition|semester fee|session fee)/i.test(text)) return "SCHOOL";
  if (row.purpose) return "OTHER";
  return /(^|[^a-z])(hostel|accommodation|transcript|library|deferment|transfer|wallet|acceptance|application|post-?utme|screening|medical|id card|convocation|late registration|clearance|siwes)/i.test(text) ? "OTHER" : "SCHOOL";
}
