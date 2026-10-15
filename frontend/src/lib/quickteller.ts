/**
 * Pay on Quickteller (V299): the payer is sent to the University's biller page
 * on quickteller.com with the portal's own payment reference in `cid`, and the
 * amount when the biller carries it — Interswitch's form:
 *
 *     https://quickteller.com/bsum?cid=<reference>&amount=<amount>
 *
 * The server builds the link (finance.quickteller_link); what is here mirrors its
 * rules so the Bursary's screen can show a link before it is saved, and reads the
 * collections report the Bursary pastes.
 */

/** the gateways as a payer sees them named; "paydirect" is Pay on Quickteller, "quickteller" the WebPAY card page */
export const PAY_LABEL: Record<string, string> = {
  paystack: "Paystack",
  flutterwave: "Flutterwave",
  quickteller: "Interswitch WebPAY",
  paydirect: "Quickteller",
};

/** what the checkout answers for Pay on Quickteller */
export interface QuicktellerCheckout {
  url: string;
  gateway: "paydirect";
  reference: string;
  amount: number | string;
  withAmount?: boolean;
  biller?: string;
  billerCode?: string;
  scope?: string;
}

export function isQuicktellerCheckout(j: unknown): j is QuicktellerCheckout {
  return !!j && typeof j === "object" && (j as { gateway?: unknown }).gateway === "paydirect" && typeof (j as { url?: unknown }).url === "string";
}

/** the amount as the link carries it: naira, whole naira without decimals (51000), else two places (51000.50) */
export function amountInLink(amount: number | string): string {
  const n = Number(amount);
  if (!Number.isFinite(n)) return "";
  return Number.isInteger(n) ? String(n) : n.toFixed(2);
}

const INTERSWITCH = /^https:\/\/([a-z0-9-]+\.)*(quickteller\.com|quickteller\.net|interswitchng\.com|interswitchgroup\.com)(\/[A-Za-z0-9._~-]+)*$/;

/**
 * A pay link as the server keeps it — the host read without regard to case, a
 * trailing slash dropped — or null when it is not an Interswitch page (https, a
 * Quickteller or Interswitch host, a path and nothing after it).
 */
export function interswitchLink(link: string | null | undefined): string | null {
  let v = (link ?? "").trim();
  if (!v) return null;
  const host = v.match(/^[A-Za-z]+:\/\/[^/?#]+/)?.[0];
  if (host) v = host.toLowerCase() + v.slice(host.length);
  v = v.replace(/\/+$/, "");
  return INTERSWITCH.test(v) ? v : null;
}

/** the link a payer is sent to, as the server builds it: the page, cid = the reference unchanged, and the amount when carried */
export function quicktellerLink(payLink: string, reference: string, amount: number | string, withAmount: boolean): string {
  const sep = payLink.includes("?") ? "&" : "?";
  return `${payLink}${sep}cid=${encodeURIComponent(reference)}${withAmount ? `&amount=${amountInLink(amount)}` : ""}`;
}

/** a collections row as the import takes it */
export interface CollectionRow { prn: string; amount: string; rrn: string; paidAt: string; channel: string; payer: string }
type Field = keyof CollectionRow;

/** the names Interswitch's reports give each column, compared without case, spaces or punctuation — the first that matches wins */
const NAMES: Record<Field, string[]> = {
  prn: ["prn", "custreference", "customerreference", "custref", "customerref", "cid", "paymentreferencenumber", "customerid", "reference"],
  amount: ["amount", "amountpaid", "paidamount", "transactionamount"],
  rrn: ["rrn", "paymentlogid", "retrievalreferencenumber", "transactionref", "transactionreference", "receiptno", "receiptnumber", "paymentreference"],
  paidAt: ["paidat", "paymentdate", "transactiondate", "datepaid", "date"],
  channel: ["channel", "channelname", "paymentchannel", "paymentmethod"],
  payer: ["payer", "customername", "payername", "depositorname", "name"],
};
const ORDER: Field[] = ["prn", "amount", "rrn", "paidAt", "channel", "payer"];

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

function cellsOf(line: string): string[] {
  if (line.includes("\t")) return line.split("\t").map((c) => c.trim());
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { out.push(cur.trim()); cur = ""; }
    else cur += ch;
  }
  out.push(cur.trim());
  return out;
}

/** an Excel date serial (days since 1899-12-30, the fraction the time of day) as the server reads a date — the report's
 *  wall-clock time, Lagos time (UTC+1, no summer time); anything else as it is */
export function excelDate(v: string): string {
  const t = v.trim();
  if (!/^\d{5}(\.\d+)?$/.test(t)) return t;
  const n = Number(t);
  if (n < 30000 || n > 80000) return t;
  const wall = new Date(Math.round((n - 25569) * 86400) * 1000);
  const p = (x: number) => String(x).padStart(2, "0");
  return `${wall.getUTCFullYear()}-${p(wall.getUTCMonth() + 1)}-${p(wall.getUTCDate())}T${p(wall.getUTCHours())}:${p(wall.getUTCMinutes())}:${p(wall.getUTCSeconds())}+01:00`;
}

/**
 * The collections report as a grid of cells — pasted text split into lines, or a spreadsheet's rows. Interswitch's own header
 * row (Customer Reference, Amount, Payment Log Id, Payment Date, Channel, Customer Name …) is looked for in the first ten
 * lines, so the title and date-range lines a downloaded report begins with are passed over; with none, the columns are taken
 * as reference, amount, settlement reference, date, channel, payer. Rows without a reference are left out; an Excel date
 * serial becomes a date.
 */
export function collectionRowsFromGrid(grid: string[][]): CollectionRow[] {
  const lines = grid.map((r) => r.map((c) => (c ?? "").trim())).filter((r) => r.some((c) => c !== ""));
  if (!lines.length) return [];
  let headAt = -1;
  const at: Partial<Record<Field, number>> = {};
  for (let k = 0; k < Math.min(10, lines.length) && headAt < 0; k++) {
    const head = lines[k].map(norm);
    const found: Partial<Record<Field, number>> = {};
    const used = new Set<number>();
    for (const f of ORDER) {
      for (const name of NAMES[f]) {
        const i = head.findIndex((h, x) => !used.has(x) && h === name);
        if (i >= 0) { found[f] = i; used.add(i); break; }
      }
    }
    // a header is a line that names the reference column or the amount column
    if (found.prn !== undefined || found.amount !== undefined) { headAt = k; Object.assign(at, found); }
  }
  const hasHeader = headAt >= 0;
  const rows = (hasHeader ? lines.slice(headAt + 1) : lines).map((c) => {
    const pick = (f: Field, i: number) => (c[hasHeader ? at[f] ?? -1 : i] ?? "").trim();
    return {
      prn: pick("prn", 0).toUpperCase(),
      amount: pick("amount", 1).replace(/[₦,\s]|NGN/g, ""),
      rrn: pick("rrn", 2),
      paidAt: excelDate(pick("paidAt", 3)),
      channel: pick("channel", 4),
      payer: pick("payer", 5),
    };
  });
  return rows.filter((r) => r.prn !== "");
}

/** the collections report as pasted: tab- or comma-separated lines, read as a grid */
export function collectionRows(text: string): CollectionRow[] {
  return collectionRowsFromGrid(text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map(cellsOf));
}

/** a spreadsheet's rows written back as the tab-separated text the import box holds, so what is imported is what is seen */
export function gridToText(grid: string[][]): string {
  return grid.filter((r) => r.some((c) => (c ?? "").trim() !== "")).map((r) => r.map((c) => (c ?? "").replace(/[\t\r\n]+/g, " ").trim()).join("\t")).join("\n");
}

/** what a payer is told once Quickteller's page is open for them */
export const AFTER_PAYING =
  "After you pay, come back to this page. Your payment is confirmed as soon as Interswitch reports it to the University — usually within minutes. " +
  "If your network drops after paying, do not pay again: check here first, because every payment carries your reference.";
