/** V570: Interswitch's per-transaction settlement report read from its CSV or Excel file — the header row found among the first
 *  forty, each column named by what Interswitch's reports call it (Settlement Date, Customer Reference, Transaction Reference,
 *  Payment Log Id, Amount, Fee, Settlement Amount …), each row's days and amounts read as written — for the database to match every
 *  row to the portal. A report without a settlement-date column is read with the day the Bursary gives. Node-tested. */
import { readAmount, readDate } from "./bank-statement.ts";

/** one row as it is sent */
export interface SettlementRow {
  settledOn: string; paidOn: string; reference: string; txnRef: string; logId: string; paymentRef: string; channel: string; payer: string;
  amount: string; fee: string; net: string;
}
export interface SettlementRead {
  rows: SettlementRow[]; header: string[]; columns: Record<string, number>; skipped: number;
  /** the report names no settlement day and none was given */
  needsDay: boolean; problem: string | null;
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z]/g, "");
const HEADS: Record<keyof SettlementRow, string[]> = {
  settledOn: ["settlementdate", "settledate", "datesettled", "settlementday", "settleddate", "valuedate", "settlementvaluedate"],
  paidOn: ["transactiondate", "paymentdate", "datepaid", "txndate", "trandate", "transdate", "date"],
  reference: ["customerreference", "custreference", "custref", "customerref", "cid", "customerid", "prn", "customerreferencenumber", "billreference"],
  txnRef: ["transactionreference", "txnref", "transactionref", "merchantreference", "merchanttxnref", "merchanttransactionreference", "txnreference"],
  logId: ["paymentlogid", "logid", "paymentlog", "rrn", "retrievalreferencenumber", "retrievalref"],
  paymentRef: ["paymentreference", "payref", "paymentref", "interswitchreference", "receiptno", "receiptnumber"],
  channel: ["channel", "channelname", "paymentchannel", "paymentmethod"],
  payer: ["customername", "payername", "payer", "depositorname", "name"],
  amount: ["amount", "transactionamount", "amountpaid", "grossamount", "totalamount", "paidamount"],
  fee: ["fee", "fees", "charge", "charges", "commission", "transactionfee", "servicecharge", "msc", "processingfee", "settlementfee", "interswitchfee"],
  net: ["settlementamount", "settledamount", "netamount", "amountsettled", "merchantamount", "nettamount", "amountdue", "payableamount", "netsettlement"],
};
const KEYS = Object.keys(HEADS) as (keyof SettlementRow)[];

/** the column of each field in a header row, or -1 */
function columnsOf(row: string[]): Record<string, number> {
  const cells = row.map((c) => norm(c ?? ""));
  const out: Record<string, number> = {};
  for (const k of KEYS) out[k] = cells.findIndex((c) => HEADS[k].includes(c));
  return out;
}

/** the report's rows from its grid: the header is the first row naming an amount column and a reference, transaction reference or
 *  Payment Log Id column; a row with no amount is left out; the day settled is the row's own, or the one given */
export function readSettlement(grid: string[][], day = ""): SettlementRead {
  const hi = grid.slice(0, 40).findIndex((r) => { const c = columnsOf(r); return c.amount >= 0 && (c.reference >= 0 || c.txnRef >= 0 || c.logId >= 0); });
  if (hi < 0) {
    return { rows: [], header: [], columns: {}, skipped: 0, needsDay: false,
      problem: "No header row naming an amount and a customer reference, transaction reference or Payment Log Id was found in the first 40 rows." };
  }
  const columns = columnsOf(grid[hi]);
  const given = readDate(day);
  const rows: SettlementRow[] = [];
  let skipped = 0;
  for (const r of grid.slice(hi + 1)) {
    const cell = (k: keyof SettlementRow) => (columns[k] >= 0 ? String(r[columns[k]] ?? "").trim() : "");
    const amount = readAmount(cell("amount"));
    if (!amount || Number(amount) === 0) { if (r.some((c) => String(c ?? "").trim())) skipped++; continue; }
    const fee = readAmount(cell("fee")).replace(/^-/, "");
    rows.push({
      settledOn: readDate(cell("settledOn")) || given, paidOn: readDate(cell("paidOn")),
      reference: cell("reference").slice(0, 120), txnRef: cell("txnRef").slice(0, 120), logId: cell("logId").slice(0, 120), paymentRef: cell("paymentRef").slice(0, 200),
      channel: cell("channel").slice(0, 120), payer: cell("payer").slice(0, 200), amount, fee, net: readAmount(cell("net")),
    });
  }
  const needsDay = rows.some((x) => !x.settledOn);
  return {
    rows, header: grid[hi], columns, skipped, needsDay,
    problem: rows.length ? (needsDay ? "The report names no settlement date for every row: give the day it was settled." : null) : "The file has a header but no row with an amount.",
  };
}
