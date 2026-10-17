"use client";

/** V533: the account a refund is paid into — the bank from the list (or another bank by name), the name on the account and the
 *  ten-digit number, the number checked against the bank as it is typed and the name compared with the person's (a warning only).
 *  The student's fees page and the refunds desk both use it; the database applies the same rule when it is sent. */
import { useEffect, useState } from "react";
import { type BankAccountValue, type BankOption, OTHER_BANK, accountDigits, accountNumberProblem, chosenBank, namesShare } from "@/lib/banks";

/** the banks from the API (the student's /me/banks or the desk's /finance/refunds/banks), once */
export function useBanks(path: string): BankOption[] | null {
  const [banks, setBanks] = useState<BankOption[] | null>(null);
  useEffect(() => {
    let live = true;
    fetch(`/api/bff/api/v1${path}`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : []))
      .then((j: (BankOption & { active?: boolean })[]) => { if (live) setBanks(j.filter((b) => b.active !== false)); })
      .catch(() => { if (live) setBanks([]); });
    return () => { live = false; };
  }, [path]);
  return banks;
}

export function BankAccountFields({ id, value, onChange, banks, holderName, disabled }: {
  id: string;
  value: BankAccountValue;
  onChange: (v: BankAccountValue) => void;
  banks: BankOption[] | null;
  /** the person the refund is owed to, for the name warning */
  holderName?: string | null;
  disabled?: boolean;
}) {
  const bank = chosenBank(value, banks);
  const numberProblem = value.accountNumber ? accountNumberProblem(value.accountNumber, bank) : null;
  const nameDiffers = !!holderName && value.accountName.trim().length > 2 && !namesShare(value.accountName, holderName);
  const set = (patch: Partial<BankAccountValue>) => onChange({ ...value, ...patch });
  return (
    <span className="blk">
      <span className="row" style={{ flexWrap: "wrap", gap: 8 }}>
        <select aria-label="Bank" id={`${id}-bank`} className="ctl" style={{ flex: "1 1 200px", maxWidth: 260 }} disabled={disabled || banks === null}
          value={value.bankCode} onChange={(e) => set({ bankCode: e.target.value })}>
          <option value="">{banks === null ? "Loading the banks…" : "Choose the bank"}</option>
          {(banks ?? []).map((b) => <option key={b.code} value={b.code}>{b.name}</option>)}
          <option value={OTHER_BANK}>Another bank (type its name)</option>
        </select>
        {value.bankCode === OTHER_BANK ? (
          <input aria-label="The bank's name" className="ctl" style={{ flex: "1 1 180px", maxWidth: 240 }} placeholder="The bank's name" disabled={disabled}
            value={value.otherBank} onChange={(e) => set({ otherBank: e.target.value })} autoComplete="off" />
        ) : null}
        <input aria-label="Account name" className="ctl" style={{ flex: "1 1 200px", maxWidth: 260 }} placeholder="Name on the account" disabled={disabled}
          value={value.accountName} onChange={(e) => set({ accountName: e.target.value })} autoComplete="off" />
        <input aria-label="Account number" className="ctl tnum" style={{ flex: "1 1 200px", maxWidth: 220 }} placeholder="10-digit account number" inputMode="numeric"
          maxLength={14} disabled={disabled} value={value.accountNumber} onChange={(e) => set({ accountNumber: e.target.value.replace(/[^0-9 -]/g, "") })} autoComplete="off" />
      </span>
      {numberProblem ? <span className="blk sub2 ink-red" role="alert">{numberProblem}</span>
        : value.accountNumber && accountDigits(value.accountNumber).length === 10 && bank?.nuban_check ? <span className="blk sub2 ink-green">The number matches {bank.name}.</span>
        : value.accountNumber && accountDigits(value.accountNumber).length === 10 && value.bankCode ? <span className="blk sub2">The number cannot be checked against this bank; make sure it is right.</span>
        : null}
      {nameDiffers ? <span className="blk sub2" style={{ color: "var(--amber-ink)" }}>The name on the account shares no word with {holderName}. The refund is paid to the person it is owed to; check it is their account.</span> : null}
    </span>
  );
}
