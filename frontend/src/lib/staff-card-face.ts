/**
 * What a staff identity card prints of its holder (V439, V622; V698 shared by the print of one card and the print of them all): the
 * name, the staff number, the rank, the category (Teaching or Non-teaching), the department, the date of appointment and the blood
 * group. The University's layout of 12 November 2026 prints DEPARTMENT in place of the unit, the faculty and the office, and no
 * validity: the department is the academic department or administrative office the API reads from the HR record
 * (credentials.staff_card_department, V748), else the portal office the person holds. The desk prints from the card register, never
 * from the HR record's other fields. Node-tested.
 */
import type { CardFace } from "./idcard-design.ts";

/** what the card shows of the person, as the API gives it */
export interface StaffFace {
  staff_number: string | null; surname: string; given_names: string; rank: string | null; department: string | null; faculty: string | null;
  category: string | null; date_first_appointment: string | null; appointment_date: string | null; has_photo: boolean;
  /** V622: the blood group set at the card desk */
  blood_group?: string | null;
}
/** a card in force, with what it prints */
export interface LiveStaffCard {
  card_no: string; valid_to: string; verify_path: string; face: StaffFace; offices: { office_code: string; office: string }[];
  person_id?: string;
}

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "—");
export const rankCase = (r: string | null) => (r ? r.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase()).replace(/\bIi\b/g, "II") : "");

/** the card's face — null for a person with no staff number (a card carries it) */
export function staffCardFace(card: LiveStaffCard): CardFace | null {
  const s = card.face;
  if (!s.staff_number) return null;
  const live = card.offices ?? [];
  const office = live.find((o) => o.office_code !== "lecturer")?.office ?? live[0]?.office ?? "";
  const academic = s.category === "ACADEMIC" || (!s.category && live.some((o) => ["lecturer", "hod", "dean"].includes(o.office_code)));
  // two to a row (the left column takes the first of each pair): the department and the date of appointment, the longest, in the
  // wider left column; the category and the blood group, short, on the right
  return {
    kind: "staff", name: `${s.surname}, ${s.given_names}`, number: s.staff_number,
    fields: [
      ["Rank", rankCase(s.rank) || office || "—"], ["Category", academic ? "Teaching" : s.category ? "Non-teaching" : "Staff"],
      ["Department", s.department || office || "—"], ["Blood group", s.blood_group ?? "—"],
      ["Appointed", day(s.date_first_appointment ?? s.appointment_date)],
    ],
    foot: [],
    serial: card.card_no,
  };
}
