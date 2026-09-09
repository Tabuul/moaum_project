/** University Health Services, as the API states it (V032). */
export interface HealthProfile { blood_group: string | null; genotype: string | null; allergies: string | null; consented_at: string | null; restricted_at: string | null; fitness: string; fitness_on: string | null }
export interface Appointment { id: string; reason: string; preferred_at: string; booked_at: string; state: string; cancelled_why: string | null }
export interface Visit { id: string; arrived_at: string; presenting: string; triage: string; state: string; outcome: string | null; referred_to: string | null; concluded_at: string | null; clinician: string | null }
export interface Access { at: string; what: string; office: string; who: string | null }
export interface StudentHealth { profile: HealthProfile | null; appointments: Appointment[]; visits: Visit[]; access: Access[] }

export interface WaitingRow { id: string; arrived_at: string; presenting: string; triage: string; state: string; seen_at: string | null; student_id: string; patient: string; number: string; clinician: string | null }
export interface BookedRow { id: string; reason: string; preferred_at: string; state: string; student_id: string; patient: string; number: string }
export interface ConcludedRow { id: string; concluded_at: string; presenting: string; outcome: string; referred_to: string | null; patient: string; number: string; clinician: string | null }
export interface ClinicDesk {
  tiles: { encounters_today: number; waiting: number; longest_wait_min: number; referrals_month: number; fitness_recorded: number; booked_today: number };
  waiting: WaitingRow[]; booked: BookedRow[]; concluded: ConcludedRow[];
  patron?: { student_id: string; number: string; name: string; programme: string } | null;
}
export interface OpenVisit {
  id: string; student_id: string; arrived_at: string; presenting: string; triage: string; state: string; outcome: string | null; referred_to: string | null;
  patient: string; number: string; sex: string | null; date_of_birth: string | null; programme: string; profile: HealthProfile | null;
  history: { id: string; arrived_at: string; presenting: string; outcome: string | null; referred_to: string | null; concluded_at: string | null; clinician: string | null; notes: string | null }[];
}
