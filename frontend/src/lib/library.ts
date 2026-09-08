/** Library circulation, as the API states it (V031). */
export interface LibrarySetting { loan_days: number; fine_per_day: number; max_loans: number; max_renewals: number }
export interface Standing { on_loan: number; overdue: number; fines_unpaid: number; clear: boolean }
export interface Loan {
  id: string; accession: string; issued_at: string; due_on: string; renewals: number; returned_at: string | null; fine: number | null;
  fine_reference: string | null; fine_settled_at: string | null; fine_waived_at: string | null; item_id: string; title: string; author: string | null;
  edition: string | null; year: number | null; days_overdue: number; days_left: number | null; student_id: string | null; number: string | null; patron: string; staff_number: string | null;
}
export interface Reservation { id: string; state: string; reserved_at: string; decided_at: string | null; item_id: string; title: string; author: string | null; ahead: number }
export interface CatalogueRow { id: string; title: string; author: string | null; edition: string | null; year: number | null; kind: string; subject: string | null; copies: number; available: number; waiting: number }
export interface StudentLibrary { setting: LibrarySetting; standing: Standing; loans: Loan[]; reservations: Reservation[]; catalogue: CatalogueRow[] }
export interface LibraryDeskData {
  setting: LibrarySetting; tiles: { stock: number; on_loan: number; overdue: number; fines_unpaid: number; waiting: number };
  today: Loan[]; overdue: Loan[]; fines: Loan[]; catalogue: CatalogueRow[];
  patron?: { student_id: string | null; person_id: string | null; number: string; name: string; programme: string } | null;
  patronStanding?: Standing; patronLoans?: Loan[];
}
