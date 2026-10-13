import { test } from "node:test";
import assert from "node:assert/strict";
import { blocks, legalPdf, type LegalDocument } from "./legal.ts";
import { DEFAULT_INSTITUTION } from "./document/institution.ts";

test("a section's body is read as paragraphs and lists", () => {
  const b = blocks("One paragraph\nstill the same.\n\n- first\n- second\n\nLast.");
  assert.deepEqual(b, [{ kind: "p", text: "One paragraph still the same." }, { kind: "ul", items: ["first", "second"] }, { kind: "p", text: "Last." }]);
});

test("the policy is one PDF with the letterhead, every section and the contact", () => {
  const doc: LegalDocument = {
    id: "x", kind: "PRIVACY_POLICY", version: 2, status: "PUBLISHED", title: "Privacy Policy", summary: "What we hold — and why.",
    effectiveOn: "2026-10-13", publishedAt: "2026-10-13T10:00:00Z", updatedAt: "2026-10-13T09:00:00Z", requiresAcceptance: true,
    sections: [
      { no: 1, key: "introduction", heading: "Introduction", body: "The University “holds” personal data.\n\n- a list item\n- another" },
      { no: 2, key: "cookies", heading: "Cookies", body: "Essential cookies only." },
    ],
    institution: { name: "Invented University", shortName: "IU", address: "PMB 1, Town", phone: "0800", email: "info@example.edu", website: "example.edu" },
    contact: { name: "Dr Invented", title: "Data Protection Officer", office: "Registry", email: "dpo@example.edu", phone: "0801", address: "PMB 1, Town", requestDays: 30 },
  };
  const bytes = legalPdf(doc, DEFAULT_INSTITUTION);
  const text = new TextDecoder("latin1").decode(bytes);
  assert.ok(text.startsWith("%PDF-1.4"));
  assert.ok(text.includes("(1. INTRODUCTION) Tj") || text.includes("1. INTRODUCTION"));
  assert.ok(text.includes("Essential cookies only."));
  assert.ok(text.includes("dpo@example.edu"));
  assert.ok(text.includes('"holds"'), "typographic quotes are given their plain form");
});
