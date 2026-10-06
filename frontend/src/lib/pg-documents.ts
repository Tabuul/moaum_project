/**
 * What each postgraduate applicant's document is, by its kind, in the words the applicant chose it by — for the
 * School's view of an application and the printed application summary.
 */
const DOC_LABEL: Record<string, string> = {
  PASSPORT: "Passport photograph",
  HIGHER_DEGREE: "Higher degree certificate",
  UNDERGRAD_CERT: "Undergraduate certificate",
  OLEVEL: "O’Level result",
  BIRTH_CERTIFICATE: "Birth certificate / declaration of age",
  NYSC: "NYSC certificate",
  LGA_CERTIFICATE: "LGA / indigene certificate",
  NAME_CHANGE: "Change of name / marriage certificate",
  TRANSCRIPT: "Transcript",
  DEGREE_CERTIFICATE: "Degree certificate",
  CV: "Curriculum vitae",
  PROPOSAL: "Research proposal",
  CREDENTIALS: "Credentials",
  OTHER: "Other document",
};

/** a document's name by its kind; a kind not listed reads in sentence case */
export function docLabel(kind: string): string {
  return DOC_LABEL[kind] ?? kind.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase());
}
