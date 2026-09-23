import assert from "node:assert/strict";
import { test } from "node:test";
import { blockReason, normalise } from "./chat.js";

test("ordinary chat about the law gets through", () => {
  for (const text of [
    "good luck!", "Caparo v Dickman [1990] 2 AC 605 — that one caught me out", "rematch? 3-2 was close",
    "section 18 OAPA 1861", "gg, see you at the weekly quiz", "is Woollin evidence or substantive law?",
  ]) {
    assert.equal(blockReason(text), null, text);
  }
});

test("contact details are blocked however they're written", () => {
  for (const text of [
    "07700 900123", "+44 7700-900-123", "call me on 0 7 7 0 0 9 0 0 1 2 3",
    "amara@example.com", "amara (at) example (dot) com", "www.example.com", "https://t.co/x", "find me at amara.co.uk",
    "@amara_law", "snap: amara.law", "insta amaralaw",
  ]) {
    assert.equal(blockReason(text), "contact", text);
  }
});

test("abuse is blocked through common disguises", () => {
  for (const text of ["you tw4t", "F U C K off", "shiiiit", "go kys"]) {
    assert.equal(blockReason(text), "abuse", text);
  }
});

test("words containing a blocked term aren't caught", () => {
  for (const text of ["Scunthorpe", "a classic assessment", "cocktail", "Dickman"]) {
    assert.equal(blockReason(text), null, text);
  }
});

test("normalising undoes leetspeak and squeezes repeats", () => {
  assert.equal(normalise("5h1ttt!!"), "shit");
});
