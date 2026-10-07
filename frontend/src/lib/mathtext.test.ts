import { test } from "node:test";
import assert from "node:assert/strict";
import { parseMathText, plainMath, type MathNode } from "./mathtext.ts";

const math = (s: string) => (parseMathText(s).find((n) => n.t === "math") as Extract<MathNode, { t: "math" }>).c;

test("text without dollars is text, and \\$ is a dollar sign", () => {
  assert.deepEqual(parseMathText("The cost is \\$5."), [{ t: "text", v: "The cost is $5." }]);
  assert.deepEqual(parseMathText("No formula here"), [{ t: "text", v: "No formula here" }]);
});

test("powers and subscripts, with or without braces", () => {
  assert.deepEqual(math("$x^2$"), [{ t: "text", v: "x" }, { t: "sup", c: [{ t: "text", v: "2" }] }]);
  assert.deepEqual(math("$H_2O$"), [{ t: "text", v: "H" }, { t: "sub", c: [{ t: "text", v: "2" }] }, { t: "text", v: "O" }]);
  assert.deepEqual(math("$e^{-kt}$"), [{ t: "text", v: "e" }, { t: "sup", c: [{ t: "text", v: "-kt" }] }]);
});

test("fractions, roots and symbols", () => {
  assert.deepEqual(math("$\\frac{1}{2}mv^2$")[0], { t: "frac", n: [{ t: "text", v: "1" }], d: [{ t: "text", v: "2" }] });
  assert.equal(plainMath("$\\sqrt{b^2 - 4ac}$"), "√(b² - 4ac)");
  assert.equal(plainMath("$\\alpha + \\beta \\to \\gamma$"), "α + β → γ");
  assert.equal(plainMath("$2H_2 + O_2 \\to 2H_2O$"), "2H₂ + O₂ → 2H₂O");
  assert.equal(plainMath("Energy $E = \\frac{1}{2}mv^2$ J"), "Energy E = 1/2mv² J");
  assert.equal(plainMath("$30^\\circ$"), "30°");
});

test("an unclosed or empty formula stays as typed; an unknown command is shown as typed", () => {
  assert.deepEqual(parseMathText("costs $5 and more"), [{ t: "text", v: "costs $5 and more" }]);
  assert.deepEqual(parseMathText("$$"), [{ t: "text", v: "$$" }]);
  assert.equal(plainMath("$\\unknown x$"), "\\unknown x");
});

test("a formula never spans lines", () => {
  assert.deepEqual(parseMathText("a $x\ny$ b"), [{ t: "text", v: "a $x\ny$ b" }]);
});
