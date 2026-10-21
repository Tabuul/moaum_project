/**
 * V605: the Security Unit's student identity card desk — the words for the card's states, the eligibility reading, the replacement
 * reasons and the history. The server decides everything (credentials.id_card_eligibility, print, collect, end); this only says it.
 */
export type Kind = "ok" | "warn" | "bad" | "info" | "grey";

export interface Eligibility {
  eligible: boolean; reasons: string[];
  checks?: { in_study: boolean; matric: boolean; photo: boolean; fees: boolean };
  fees?: { session: string | null; stated: boolean | null; released: boolean | null; earlier: { session: string; due: number; paid: number; balance: number; paid_in_full: boolean }[]; short: string[] };
  card?: { card_no: string; state: string; version: number } | null;
}

export interface SearchRow {
  student_id: string; name: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null; faculty: string | null;
  department: string | null; programme: string | null; level: number | null; entry_session: string | null; status: string;
  card_no: string | null; card_state: string | null; card_version: number | null; eligible: boolean; fees_ok: boolean | null; photo: boolean | null; reasons: string[];
}

export interface CardRow {
  id: string; card_no: string; state: string; version: number; print_count: number; made_at: string; printed_at: string | null; collected_at: string | null;
  valid_to: string; ended_at: string | null; ended_reason: string | null; replacement_reason: string | null; previous_card_id: string | null;
  previous_card_no: string | null; printed_by: string | null; issued_by: string | null; verify_path?: string;
}

export interface CardEvent { action: string; from_state: string | null; to_state: string | null; note: string | null; at: string; actor: string | null; actor_office: string | null }

export interface DeskStudent {
  student: {
    student_id: string; name: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null; sex: string | null; faculty: string | null;
    department: string | null; programme: string | null; programme_code: string | null; level: number | null; entry_session: string | null; entry_mode: string | null;
    status: string; matriculated_at: string | null; current_session: string | null; reach_phone: string | null;
    /** V622: the blood group the card prints (the biodata's, else the health profile's) */
    blood_group?: string | null;
  };
  photo: boolean; eligibility: Eligibility; card: CardRow | null; cards: CardRow[]; events: CardEvent[];
}

/** V622: the blood groups a card prints; the server reads the common spellings ("O positive") as one of these */
export const BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] as const;

/** the card's state in words: the lifecycle the brief names — not printed, printed, issued, then the ways a card ends */
export const CARD_STATE: Record<string, [string, Kind]> = {
  NOT_PRINTED: ["Not printed", "grey"],
  PRINTED: ["Printed — awaiting collection", "warn"],
  ISSUED: ["Issued — in force", "ok"],
  LOST: ["Lost", "bad"],
  DAMAGED: ["Damaged", "bad"],
  REPLACED: ["Replaced", "grey"],
  RETURNED: ["Returned", "grey"],
  REVOKED: ["Revoked", "bad"],
  CANCELLED: ["Cancelled", "grey"],
};

export function cardStateWord(state: string | null | undefined): [string, Kind] {
  if (!state) return CARD_STATE.NOT_PRINTED;
  return CARD_STATE[state] ?? [state.charAt(0) + state.slice(1).toLowerCase(), "grey"];
}

export const REPLACE_REASONS: [string, string][] = [
  ["LOST", "Lost card"], ["DAMAGED", "Damaged card"], ["NAME_CORRECTION", "Name correction"], ["PROGRAMME_CHANGE", "Programme change"],
  ["MATRIC_CORRECTION", "Matriculation correction"], ["PHOTOGRAPH_UPDATE", "Photograph update"], ["SECURITY_REPLACEMENT", "Security replacement"],
  ["EXPIRED", "Expired card"], ["OTHER", "Other"],
];

export const END_STATES: [string, string][] = [["LOST", "Lost"], ["DAMAGED", "Damaged"], ["RETURNED", "Returned"], ["REVOKED", "Revoked"], ["CANCELLED", "Cancelled"]];

export function reasonWord(code: string | null | undefined): string {
  if (!code) return "";
  return REPLACE_REASONS.find((r) => r[0] === code)?.[1] ?? code.toLowerCase().replace(/_/g, " ");
}

/** the eligibility in words: the heading and the lines under it — the reasons when not eligible, the checks met when eligible */
export function eligibilityWords(e: Eligibility): { title: string; kind: "ok" | "bad"; lines: string[] } {
  if (e.eligible) {
    const lines = ["Valid matriculation number", "Official photograph available", "School-fee eligibility satisfied"];
    if (e.fees?.session) lines[2] = `School-fee eligibility satisfied (${e.fees.session} released by the scheme in force${e.fees.earlier?.length ? `; ${e.fees.earlier.length} earlier session${e.fees.earlier.length === 1 ? "" : "s"} paid in full` : ""})`;
    return { title: "ID card eligible", kind: "ok", lines };
  }
  return { title: "ID card not eligible", kind: "bad", lines: e.reasons.length ? e.reasons : ["The record does not meet the card's conditions"] };
}

/** the words on the actions: what each button does, and the busy word while it runs */
export const ACTION_WORDS = {
  print: ["PRINT ID CARD", "PREPARING ID CARD..."],
  reprint: ["PRINT AGAIN", "PREPARING ID CARD..."],
  collect: ["ISSUE ID CARD", "RECORDING HANDOVER..."],
  replace: ["REPLACE CARD", "PROCESSING REPLACEMENT..."],
  end: ["END CARD", "RECORDING..."],
} as const;

export function eventWord(e: CardEvent): string {
  const w: Record<string, string> = {
    ID_CARD_PRINTED: "Printed", ID_CARD_ISSUED: "Issued", ID_CARD_REPLACED: "Replaced", ID_CARD_LOST: "Reported lost", ID_CARD_DAMAGED: "Damaged",
    ID_CARD_RETURNED: "Returned", ID_CARD_REVOKED: "Revoked", ID_CARD_CANCELLED: "Cancelled", ID_CARD_VIEWED: "Viewed",
  };
  return w[e.action] ?? e.action.replace(/^ID_CARD_/, "").toLowerCase().replace(/^./, (c) => c.toUpperCase());
}

/** what the desk may do with a student, by the card's state and the eligibility — the server refuses the rest anyway */
export function actionsFor(e: Eligibility, card: { state: string } | null, may: boolean): { print: boolean; collect: boolean; replace: boolean; end: boolean } {
  if (!may) return { print: false, collect: false, replace: false, end: false };
  const live = !!card && (card.state === "PRINTED" || card.state === "ISSUED");
  return { print: e.eligible, collect: !!card && card.state === "PRINTED", replace: live && e.eligible, end: live };
}
