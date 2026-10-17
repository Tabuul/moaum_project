import { test } from "node:test";
import assert from "node:assert/strict";
import { EMPTY_ACCOUNT, OTHER_BANK, accountNumberProblem, accountProblem, bankToSend, namesShare, nubanCheckDigit, valueFromAccount, type BankOption } from "./banks.ts";

const banks: BankOption[] = [
  { code: "011", name: "First Bank of Nigeria", nuban_check: true },
  { code: "058", name: "Guaranty Trust Bank", nuban_check: true },
  { code: "999992", name: "OPay", nuban_check: false },
];

test("the CBN's own example: bank 011, serial 000001457 has check digit 9", () => {
  assert.equal(nubanCheckDigit("011", "000001457"), 9);
});

test("an account number is ten digits, and at a checked bank its last digit matches the bank", () => {
  assert.equal(accountNumberProblem("0000014579", banks[0]), null);
  assert.equal(accountNumberProblem("0000 0145-79", banks[0]), null);
  assert.match(accountNumberProblem("0000014578", banks[0]) ?? "", /not an account number at First Bank of Nigeria/);
  assert.match(accountNumberProblem("0000014579", banks[1]) ?? "", /not an account number at Guaranty Trust Bank/);
  assert.equal(accountNumberProblem("8012345678", banks[2]), null, "a payment service bank is not checked");
  assert.equal(accountNumberProblem("8012345678", null), null, "another bank: ten digits only");
  assert.match(accountNumberProblem("12345") ?? "", /ten digits; this has 5/);
  assert.match(accountNumberProblem("01234abc89") ?? "", /digits only/);
  assert.match(accountNumberProblem("") ?? "", /Give the ten-digit/);
});

test("the form says what still stops it, and sends the bank's code or the other bank's name", () => {
  assert.equal(accountProblem(EMPTY_ACCOUNT, banks), "Choose the bank.");
  assert.equal(accountProblem({ ...EMPTY_ACCOUNT, bankCode: OTHER_BANK }, banks), "Choose the bank.");
  assert.equal(accountProblem({ ...EMPTY_ACCOUNT, bankCode: "011" }, banks), "Give the name on the account.");
  assert.equal(accountProblem({ bankCode: "011", otherBank: "", accountName: "Ada", accountNumber: "0000014579" }, banks), null);
  assert.equal(bankToSend({ bankCode: "011", otherBank: "", accountName: "", accountNumber: "" }), "011");
  assert.equal(bankToSend({ bankCode: OTHER_BANK, otherBank: " Rubies MFB ", accountName: "", accountNumber: "" }), "Rubies MFB");
  assert.deepEqual(valueFromAccount("First Bank of Nigeria", "Ada Check", banks), { bankCode: "011", otherBank: "", accountName: "Ada Check", accountNumber: "" });
  assert.deepEqual(valueFromAccount("Rubies MFB", null, banks), { bankCode: OTHER_BANK, otherBank: "Rubies MFB", accountName: "", accountNumber: "" });
});

test("the name on the account shares a word with the person's, or it is warned of", () => {
  assert.equal(namesShare("ADA CHECK", "Check, Ada Ngozi"), true);
  assert.equal(namesShare("Someone Else", "Check, Ada Ngozi"), false);
  assert.equal(namesShare("Al Bo", "Al Bo"), false, "words of three letters or more");
});
