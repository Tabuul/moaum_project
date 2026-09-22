/** The twenty-five offices in ref.office (db/V001), by code. */
export const OFFICE_LABELS: Record<string, string> = {
  lecturer: "Lecturer",
  hod: "Head of Department",
  siwes: "SIWES Coordinator",
  exams: "Examinations Officer",
  facultyexams: "Faculty Examinations Officer",
  facultyofficer: "Faculty Officer",
  dean: "Dean",
  records: "Exams and Records",
  academic: "Academic Officer",
  dregistrar: "Deputy Registrar (Academic Affairs)",
  registrar: "Registrar",
  dvc: "Deputy Vice-Chancellor (Academic)",
  vc: "Vice-Chancellor",
  bursar: "Bursar",
  audit: "Director of Internal Audit",
  deputyaudit: "Deputy Director of Audit",
  hrm: "Director of Human Resource Management",
  housing: "Deputy Registrar (Housing, Welfare, Passages)",
  provost: "Provost, College of Health Sciences",
  collegesecretary: "College Secretary",
  library: "Librarian",
  security: "Chief Security Officer",
  services: "Support Services",
  ict: "Director of ICT",
  admin: "System Administrator",
  super: "Super Administrator",
  pgschool: "Dean, Postgraduate School",
  pgsecretary: "Secretary, Postgraduate School",
};

export function officeLabel(code: string | null | undefined): string {
  return code ? (OFFICE_LABELS[code] ?? code) : "No office";
}

/** The cookie the shell's "Signed in as" select writes and the BFF reads. */
export const OFFICE_COOKIE = "moaum_office";

/** The prototype's staff roles (proto/part17.html ROLES): its label for each office, and the unit it sits in. */
export const ROLE_LABELS: Record<string, [string, string]> = {
  lecturer: ["Lecturer", "Computer Science"],
  hod: ["Head of Department", "Mathematics & Computer Science"],
  siwes: ["SIWES Coordinator", "Department"],
  dean: ["Dean", "Faculty of Science"],
  hrm: ["Director of Human Resource Management", "Human Resource Management"],
  housing: ["Deputy Registrar (Housing, Welfare and Passages)", "Registry"],
  audit: ["Director of Internal Audit", "Directorate of Internal Audit"],
  exams: ["Exams Officer (Programme)", "B.Sc. Computer Science"],
  academic: ["Academic Office", "Academic Affairs, Registry"],
  bursar: ["Bursar", "Bursary"],
  library: ["Librarian", "University Library"],
  security: ["Chief Security Officer", "Security Department"],
  facultyexams: ["Faculty Exams Officer", "Faculty of Science"],
  facultyofficer: ["Faculty Officer", "Faculty of Science · Registry"],
  records: ["Exams & Records", "Exams & Records Department"],
  dregistrar: ["Deputy Registrar (Academic Affairs)", "Registry"],
  dvc: ["DVC (Academic)", "Deputy Vice-Chancellor, Academic"],
  super: ["Super Administrator", "Directorate of ICT"],
  registrar: ["Registrar", "Registry"],
  ict: ["Director of ICT", "Directorate of ICT"],
  services: ["Support Services", "Health, library, hostel, procurement"],
  admin: ["System Administrator", "Directorate of ICT · administration"],
  vc: ["Vice-Chancellor", "Office of the Vice-Chancellor"],
  applicant: ["Applicant", "Admissions"],
  student: ["Student", "The register"],
  pgapplicant: ["Postgraduate applicant", "School of Postgraduate Studies"],
  pgschool: ["Dean, Postgraduate School", "School of Postgraduate Studies"],
  pgsecretary: ["Secretary, Postgraduate School", "School of Postgraduate Studies"],
};

/** What the shell calls an office: the prototype's label where it has one, the database's otherwise. */
export function roleLabel(code: string | null | undefined): string {
  return code ? (ROLE_LABELS[code]?.[0] ?? officeLabel(code)) : "No office";
}

export function roleUnit(code: string | null | undefined): string {
  return code ? (ROLE_LABELS[code]?.[1] ?? "") : "";
}
