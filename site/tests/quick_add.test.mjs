// Mirrors Tests/DayBarTests/QuickAddParserTests.swift. Run: node --test site/tests/quick_add.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseQuickAdd as parse } from "../quick-add.js";

const projects = ["Client work", "Clinic", "Home"];

test("plain title collapses whitespace", () => {
  const result = parse("  Buy   coffee beans ");
  assert.equal(result.title, "Buy coffee beans");
  assert.equal(result.priority, null);
  assert.equal(result.day, null);
  assert.deepEqual(result.tokens, []);
});

test("priority marks", () => {
  assert.equal(parse("A !").priority, 1);
  assert.equal(parse("A !!").priority, 2);
  assert.equal(parse("!!! A").priority, 3);
  assert.equal(parse("A !!").title, "A");
});

test("exclamation inside a word is title", () => {
  const result = parse("Hello! world");
  assert.equal(result.title, "Hello! world");
  assert.equal(result.priority, null);
});

test("day words in English and Indonesian", () => {
  assert.equal(parse("Call mom tomorrow").day, "tomorrow");
  assert.equal(parse("Call mom tmr").day, "tomorrow");
  assert.equal(parse("Call mom BESOK").day, "tomorrow");
  assert.equal(parse("besok call mom").title, "call mom");
  assert.equal(parse("Call mom today").day, "today");
  const hariIni = parse("Bayar listrik hari ini ya");
  assert.equal(hariIni.day, "today");
  assert.equal(hariIni.title, "Bayar listrik ya");
});

test("hari alone is title", () => {
  const result = parse("Hari raya prep");
  assert.equal(result.day, null);
  assert.equal(result.title, "Hari raya prep");
});

test("project exact then unique prefix", () => {
  assert.equal(parse("Invoice #clientwork", projects).project, "Client work");
  assert.equal(parse("Invoice #Client-Work", projects).project, "Client work");
  assert.equal(parse("Invoice #clie", projects).project, "Client work");
  assert.equal(parse("Clean #home", projects).project, "Home");
});

test("ambiguous or unknown tag stays in title", () => {
  const ambiguous = parse("Book #cli", projects);
  assert.equal(ambiguous.project, null);
  assert.equal(ambiguous.title, "Book #cli");
  const unknown = parse("Fix bug #123", projects);
  assert.equal(unknown.project, null);
  assert.equal(unknown.title, "Fix bug #123");
});

test("combined syntax", () => {
  const result = parse("Send invoice !!! #client besok", projects);
  assert.equal(result.title, "Send invoice");
  assert.equal(result.priority, 3);
  assert.equal(result.day, "tomorrow");
  assert.equal(result.project, "Client work");
  assert.equal(result.tokens.length, 3);
});

test("last token of a kind wins", () => {
  const result = parse("Plan ! !!! today besok");
  assert.equal(result.priority, 3);
  assert.equal(result.day, "tomorrow");
});

test("backslash escapes a token", () => {
  const result = parse("Read \\besok novel \\!!!");
  assert.equal(result.title, "Read besok novel !!!");
  assert.equal(result.day, null);
  assert.equal(result.priority, null);
});

test("only syntax is null", () => {
  assert.equal(parse("!!! besok"), null);
  assert.equal(parse("   "), null);
});

test("prototype keys are plain words", () => {
  assert.equal(parse("constructor toString").title, "constructor toString");
});
