import { test } from "node:test";
import assert from "node:assert/strict";
import {
  SIGNATURE_BOX, SIGNATURE_MAX_BYTES, SIGNATURE_MAX_PT_PER_PX, base64Bytes, bytesBase64, entryFor, fileSize, fitBottomLeft, imageKind, signatoryKey,
  signatureFileProblem, signatureImageOf, signatureSrc, type SignatoryEntry,
} from "./letter-signature.ts";

/** the head of a JPEG — SOI, a JFIF APP0 and a baseline SOF0 of the given size — enough for jpegSize to read its dimensions */
function fakeJpeg(w: number, h: number): Uint8Array {
  return new Uint8Array([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x11, 0x08, h >> 8, h & 0xff, w >> 8, w & 0xff, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xff, 0xd9,
  ]);
}
const PNG_HEAD = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const b64 = (b: Uint8Array) => Buffer.from(b).toString("base64");

test("base64 reads plain, from a data: address and across line breaks, and refuses what is not base64", () => {
  const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255]);
  assert.deepEqual(base64Bytes(b64(bytes)), bytes);
  assert.deepEqual(base64Bytes(`data:image/jpeg;base64,${b64(bytes)}`), bytes);
  assert.deepEqual(base64Bytes(b64(bytes).replace(/(.{4})/g, "$1\n")), bytes);
  assert.equal(base64Bytes(""), null);
  assert.equal(base64Bytes(null), null);
  assert.equal(base64Bytes("not base64!"), null);
  assert.equal(base64Bytes("abcde"), null);
});

test("a megabyte's bytes go to base64 and back unchanged", () => {
  const big = new Uint8Array(SIGNATURE_MAX_BYTES);
  for (let i = 0; i < big.length; i++) big[i] = (i * 31 + 7) & 0xff;
  const s = bytesBase64(big);
  assert.equal(s, Buffer.from(big).toString("base64"));
  assert.deepEqual(base64Bytes(s), big);
});

test("the letter's signature is read as a JPEG, its size from its own bytes; anything else leaves the space", () => {
  const img = signatureImageOf({ jpegBase64: b64(fakeJpeg(800, 265)), width: 1, height: 1 });
  assert.ok(img);
  assert.equal(img.width, 800);
  assert.equal(img.height, 265);
  assert.deepEqual(img.data, fakeJpeg(800, 265));
  assert.equal(signatureImageOf(null), null);
  assert.equal(signatureImageOf(undefined), null);
  assert.equal(signatureImageOf({ jpegBase64: b64(PNG_HEAD) }), null, "a PNG is not what the PDF writer embeds");
  assert.equal(signatureImageOf({ jpegBase64: "%%%" }), null);
  assert.equal(signatureImageOf({ jpegBase64: b64(fakeJpeg(0, 0)) }), null, "a JPEG with no size draws nothing");
});

test("a signature is fitted in its proportions, as large as the box allows, on the box's bottom-left corner", () => {
  const box = { x: 56, y: 128, w: SIGNATURE_BOX.w, h: SIGNATURE_BOX.h };
  // the University's signature, 1057 x 350: the width fills the box, the height under it
  const wide = fitBottomLeft({ width: 1057, height: 350 }, box);
  assert.ok(wide);
  assert.equal(wide.x, 56);
  assert.equal(wide.y, 128);
  assert.ok(Math.abs(wide.w - 140) < 1e-9);
  assert.ok(wide.h <= 48 && Math.abs(wide.w / wide.h - 1057 / 350) < 1e-9);
  // a square scan: the height fills the box, standing on the same corner
  const square = fitBottomLeft({ width: 600, height: 600 }, box);
  assert.deepEqual(square, { x: 56, y: 128, w: 48, h: 48 });
  // a small scan prints at 150 dots an inch at most, on the same corner, never blown up into blocks: 70 x 24 pixels is 33.6 x 11.52
  // points; 300 pixels wide is where the width is filled
  const small = fitBottomLeft({ width: 70, height: 24 }, box);
  assert.ok(small);
  assert.equal(SIGNATURE_MAX_PT_PER_PX, 72 / 150);
  assert.deepEqual([small.x, small.y], [56, 128]);
  assert.ok(Math.abs(small.w - 33.6) < 1e-9 && Math.abs(small.h - 11.52) < 1e-9, `${small.w} x ${small.h}`);
  const least = fitBottomLeft({ width: 60, height: 20 }, box);
  assert.ok(least && Math.abs(least.w - 28.8) < 1e-9 && Math.abs(least.h - 9.6) < 1e-9, "the smallest the API takes, at its own size");
  const enough = fitBottomLeft({ width: 300, height: 100 }, box);
  assert.ok(enough && Math.abs(enough.w - 140) < 1e-9, "300 pixels wide fills the space");
  assert.equal(fitBottomLeft({ width: 0, height: 10 }, box), null);
  assert.equal(fitBottomLeft({ width: 10, height: 10 }, { ...box, w: 0 }), null);
});

test("the browser checks the type by the file's first bytes and the size before it sends", () => {
  assert.equal(imageKind(PNG_HEAD), "image/png");
  assert.equal(imageKind(fakeJpeg(10, 10)), "image/jpeg");
  assert.equal(imageKind(new TextEncoder().encode("GIF89a")), null);
  assert.equal(imageKind(new TextEncoder().encode("%PDF-1.4")), null);
  assert.equal(imageKind(new Uint8Array([0xff, 0xd8])), null);
  assert.equal(signatureFileProblem({ size: 120_000 }, PNG_HEAD), null);
  assert.equal(signatureFileProblem({ size: SIGNATURE_MAX_BYTES }, fakeJpeg(10, 10)), null, "exactly 1 MB is taken");
  // the size in the limit's own unit, rounded up: a file just over the limit never reads as "1.0 MB" of a 1 MB limit
  assert.match(signatureFileProblem({ size: SIGNATURE_MAX_BYTES + 1 }, PNG_HEAD) ?? "",
    /^The file is 1\.01 MB \(1,000,001 bytes\); the limit is 1 MB \(1,000,000 bytes\)\. /);
  assert.match(signatureFileProblem({ size: 1_048_576 }, PNG_HEAD) ?? "", /^The file is 1\.05 MB \(1,048,576 bytes\);/);
  assert.match(signatureFileProblem({ size: 2_400_000 }, PNG_HEAD) ?? "", /^The file is 2\.40 MB \(2,400,000 bytes\);/);
  assert.equal(fileSize(1_000_001), "1.01 MB (1,000,001 bytes)", "as the API words it");
  assert.match(signatureFileProblem({ size: 5_000 }, new TextEncoder().encode("%PDF-1.4")) ?? "", /PNG or a JPEG/);
  assert.match(signatureFileProblem({ size: 0 }, new Uint8Array()) ?? "", /empty/);
});

test("a signatory is the same person whatever the case, the spacing or the spaces about a punctuation mark — as credentials.signatory_key", () => {
  const live = "Andrew Aondoakaa Anjah, MAUA, MIMC";
  assert.equal(signatoryKey(live), "andrew aondoakaa anjah,maua,mimc");
  assert.equal(signatoryKey("  andrew  AONDOAKAA\tAnjah , MAUA,  MIMC "), signatoryKey(live));
  assert.equal(signatoryKey("andrew  aondoakaa anjah ,maua,mimc"), signatoryKey(live), "V759's own example");
  assert.equal(signatoryKey("Andrew\u00a0Aondoakaa Anjah,\u202fMAUA, MIMC"), signatoryKey(live), "a no-break space pasted from a word processor");
  assert.equal(signatoryKey("Prof. A. B. Ochai"), "prof.a.b.ochai");
  assert.notEqual(signatoryKey("Andrew Anjah"), signatoryKey(live));
  assert.equal(signatoryKey(null), "");
  assert.equal(signatoryKey("   "), "");
});

test("a Yoruba or Hausa name is the same signatory in capitals or typed with combining marks — as the database keys it, whatever its locale", () => {
  // the keys credentials.signatory_key gives on a database in the C locale (checked there): OLA ADEWALE with a dotted O and acute
  // accents, in capitals, as usually written, and typed as letters and combining marks; DAN BAKO in Hausa's hooked letters
  const ola = "\u1ecdl\u00e1 ad\u00e9w\u00e1l\u00e9";
  assert.equal(signatoryKey("\u1eccL\u00c1 AD\u00c9W\u00c1L\u00c9"), ola);
  assert.equal(signatoryKey("\u1eccl\u00e1 Ad\u00e9w\u00e1l\u00e9"), ola);
  assert.equal(signatoryKey("O\u0323la\u0301 Ade\u0301wa\u0301le\u0301"), ola);
  assert.equal(signatoryKey("\u018aAN \u0181A\u0198O"), "\u0257an \u0253a\u0199o");
  // only ASCII marks lose their spaces, and only these spaces run together, as in the database's C collation
  assert.equal(signatoryKey("Ngozi O\u2019Neil , MNIM"), "ngozi o\u2019neil,mnim");
  assert.equal(signatoryKey("A\u2003B"), "a\u2003b", "an em space is not one the key runs together");
  // a capital outside the Latin alphabets is left as it is, as translate() leaves it
  assert.equal(signatoryKey("\u0391\u0392"), "\u0391\u0392");
  assert.equal(signatoryKey("\u0130"), "\u0130", "a capital whose small letter is two characters is left as it is");
});

test("the settings screen finds the template's signatory — the same name first, else the same key — and reads the printed image by version", () => {
  const entries: SignatoryEntry[] = [
    { name: "The Registrar", hasSignature: false },
    { name: "andrew aondoakaa anjah, maua, mimc", hasSignature: true, version: 2 },
    { name: "Andrew Aondoakaa Anjah, MAUA, MIMC", hasSignature: true, version: 3, signatureUrl: "/api/v1/documents/signatures/image?name=Andrew%20Aondoakaa%20Anjah%2C%20MAUA%2C%20MIMC" },
  ];
  assert.equal(entryFor(entries, "Andrew Aondoakaa Anjah, MAUA, MIMC")?.version, 3);
  assert.equal(entryFor(entries.slice(0, 2), "Andrew Aondoakaa Anjah, MAUA, MIMC")?.version, 2);
  assert.equal(entryFor(entries, "Someone Else"), null);
  // the JPEG the letter prints (upright, on white), not the file as uploaded; the version once in the address
  assert.equal(signatureSrc(entries[2]), "/api/bff/api/v1/documents/signatures/image?name=Andrew%20Aondoakaa%20Anjah%2C%20MAUA%2C%20MIMC&format=jpeg&v=3");
  assert.equal(signatureSrc({ name: "A. B. Ochai, MNIM", hasSignature: true, version: 1 }), "/api/bff/api/v1/documents/signatures/image?name=A.%20B.%20Ochai%2C%20MNIM&format=jpeg&v=1");
  assert.equal(signatureSrc({ name: "A. B. Ochai, MNIM", hasSignature: true, version: 4, signatureUrl: "/api/v1/documents/signatures/image?name=A.+B.+Ochai%2C+MNIM&v=4" }),
    "/api/bff/api/v1/documents/signatures/image?name=A.+B.+Ochai%2C+MNIM&v=4&format=jpeg", "as the API gives the address");
});
