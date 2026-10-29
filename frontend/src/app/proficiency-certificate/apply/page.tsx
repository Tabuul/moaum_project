import { PrelimApplyPage } from "@/components/preliminary/PrelimApplyPage";

export const dynamic = "force-dynamic";

/** /proficiency-certificate/apply — the application's first step (V701), on the shared preliminary apply page */
export default async function ProficiencyCertificateApplyPage() {
  return <PrelimApplyPage slug="proficiency-certificate" />;
}
