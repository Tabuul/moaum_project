/** V533: the banks a refund is paid into and the account number checked against the bank before it is sent — the same rule the
 *  database applies (finance.account_number_problem): ten digits, and at a checked bank the CBN's NUBAN check digit. A warning when
 *  the name on the account shares no word with the person's (finance.names_share). Node-tested. */

/** a bank on the list (finance.bank) */
export interface BankOption {
  code: string;
  name: string;
  /** whether an account number at this bank is checked by the NUBAN check digit */
  nuban_check: boolean;
}

/** the account as the form holds it: a bank from the list by its code, or another bank by its name */
export interface BankAccountValue {
  bankCode: string;
  otherBank: string;
  accountName: string;
  accountNumber: string;
}

export const OTHER_BANK = "OTHER";
export const EMPTY_ACCOUNT: BankAccountValue = { bankCode: "", otherBank: "", accountName: "", accountNumber: "" };

const WEIGHTS = [3, 7, 3, 3, 7, 3, 3, 7, 3, 3, 7, 3];

/** the NUBAN check digit of a nine-digit serial at a bank with a three-digit code (011 + 000001457 → 9) */
export function nubanCheckDigit(code: string, serial: string): number {
  const digits = (code + serial).split("").map(Number);
  const sum = digits.reduce((n, d, i) => n + d * WEIGHTS[i], 0);
  return (10 - (sum % 10)) % 10;
}

/** the account number as typed, with spaces and dashes taken out */
export const accountDigits = (v: string) => v.replace(/[\s-]/g, "");

/** what is wrong with an account number (at a bank, when it is known), or null */
export function accountNumberProblem(v: string, bank?: BankOption | null): string | null {
  const d = accountDigits(v);
  if (!d) return "Give the ten-digit account number.";
  if (!/^\d+$/.test(d)) return "An account number is digits only.";
  if (d.length !== 10) return `An account number is ten digits; this has ${d.length}.`;
  if (bank && bank.nuban_check && /^\d{3}$/.test(bank.code) && nubanCheckDigit(bank.code, d.slice(0, 9)) !== Number(d[9])) {
    return `This is not an account number at ${bank.name}. Check the number and the bank.`;
  }
  return null;
}

/** the bank chosen from the list, or null for another bank */
export function chosenBank(v: BankAccountValue, banks: BankOption[] | null): BankOption | null {
  return v.bankCode && v.bankCode !== OTHER_BANK ? (banks ?? []).find((b) => b.code === v.bankCode) ?? null : null;
}

/** the bank as it is sent: its code from the list, or the name of another bank */
export function bankToSend(v: BankAccountValue): string {
  return v.bankCode === OTHER_BANK ? v.otherBank.trim() : v.bankCode;
}

/** a bank's code from a name the account already carries (its listed name), or another bank */
export function valueFromAccount(bankName: string | null | undefined, accountName: string | null | undefined, banks: BankOption[] | null): BankAccountValue {
  if (!bankName) return { ...EMPTY_ACCOUNT, accountName: accountName ?? "" };
  const b = (banks ?? []).find((x) => x.name.toLowerCase() === bankName.toLowerCase());
  return { bankCode: b ? b.code : OTHER_BANK, otherBank: b ? "" : bankName, accountName: accountName ?? "", accountNumber: "" };
}

/** what still stops the account being sent, or null */
export function accountProblem(v: BankAccountValue, banks: BankOption[] | null): string | null {
  if (!v.bankCode || (v.bankCode === OTHER_BANK && !v.otherBank.trim())) return "Choose the bank.";
  if (!v.accountName.trim()) return "Give the name on the account.";
  return accountNumberProblem(v.accountNumber, chosenBank(v, banks));
}

/** whether two names share a word of three letters or more */
export function namesShare(a: string, b: string): boolean {
  const words = (s: string) => s.toLowerCase().split(/[^a-z]+/).filter((w) => w.length >= 3);
  const other = new Set(words(b));
  return words(a).some((w) => other.has(w));
}
