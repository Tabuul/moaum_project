import type { Metadata } from "next";
import { PrelimProgrammePage } from "@/components/preliminary/PrelimProgrammePage";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Proficiency Certificate Courses (Adikpo Campus)",
  description: "The proficiency certificate courses of Adikpo Campus: categories, courses, duration, entry requirement and how to apply.",
};

/** /proficiency-certificate — public, no sign-in (V701): the programme as the University's configuration states it, on the shared page */
export default async function ProficiencyCertificatePage() {
  return <PrelimProgrammePage slug="proficiency-certificate" />;
}
