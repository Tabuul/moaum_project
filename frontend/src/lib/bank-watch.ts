/** V569: the bank matching's morning alerts as the API reads them now, and the missing payments grouped by channel and day as the
 *  Internal Audit message groups them. Node-tested. */

export interface BankWatchSetting { enabled: boolean; recon_day: number; credit_hours: number; missing_days: number; set_at?: string | null; set_office?: string | null; set_by_name?: string | null }
export interface OverdueMonth { account: string; month: string; due_on: string; days_late: number }
export interface CreditWaiting { line_id: string; statement: string; line_no: number; value_date: string | null; reference: string; amount: number; payer: string | null; number: string | null; hours: number }
export interface MissingPayment { reference: string; channel: string | null; day: string; amount: number; purpose: string | null; payer: string | null; number: string | null; confirmed_at: string }
export interface BankWatch { setting: BankWatchSetting; overdue: OverdueMonth[]; credits: CreditWaiting[]; missing: MissingPayment[] }

export interface MissingGroup { channel: string; day: string; payments: number; amount: number }

/** the missing payments by channel and day, the oldest day first — a gateway pays a day's payments in one credit */
export function bankWatchGroups(missing: MissingPayment[]): MissingGroup[] {
  const by = new Map<string, MissingGroup>();
  for (const m of missing) {
    const channel = m.channel ?? "No channel";
    const key = `${m.day}|${channel}`;
    const g = by.get(key) ?? { channel, day: m.day, payments: 0, amount: 0 };
    g.payments += 1;
    g.amount = Math.round((g.amount + Number(m.amount)) * 100) / 100;
    by.set(key, g);
  }
  return [...by.values()].sort((a, b) => a.day.localeCompare(b.day) || a.channel.localeCompare(b.channel));
}
