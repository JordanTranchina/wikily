// Standalone functional test for the Wikily matching engine (spec Milestone 4).
// Run with:  node_modules/.bin/esbuild src/lib/wiki/selftest.ts --bundle \
//              --platform=node --format=esm | node --input-type=module
//
// Asserts that a mock conversational transcript resolves the correct local
// wiki page entirely offline, above the proactive-trigger threshold.

import { parseWikiFile } from "./parser";
import { buildIndex } from "./index-engine";
import { matchTranscript } from "./match-engine";
import { RawWikiFile } from "./types";

const files: RawWikiFile[] = [
  {
    path: "/wiki/becky-promotion.md",
    name: "Project: Becky Promotion Campaign",
    content: `---
title: "Project: Becky Promotion Campaign"
status: "In Progress (Deployment phase)"
aliases: ["Becky promotion", "Becky campaign"]
tags: [marketing, campaign, becky]
notion: "https://notion.so/becky-promotion"
---

# Project: Becky Promotion Campaign

Latest Update: Visual assets approved by design team yesterday. Launch scheduled for next Tuesday.

Key Blocker: None (previously waiting on design asset approval, resolved).

Summary: Marketing push for the Becky product line. Deployment phase underway.
`,
  },
  {
    path: "/wiki/oauth-sandbox.md",
    name: "OAuth Redirect URI Setup",
    content: `---
title: "OAuth Redirect URI (Sandbox)"
tags: [oauth, sandbox, auth]
---

# OAuth Redirect URI (Sandbox)

To configure the OAuth redirect URI for the Sandbox environment, set it to
https://sandbox.example.com/oauth/callback in your app settings.
`,
  },
  {
    path: "/wiki/billing.md",
    name: "Billing & Invoices",
    content: `---
title: "Billing and Invoices"
tags: [billing, payments]
---

# Billing and Invoices

How to view invoices and update payment methods.
`,
  },
];

const docs = files.map(parseWikiFile);
const index = buildIndex(docs);

const THRESHOLD = 0.3;
let failures = 0;

function check(name: string, cond: boolean, detail = "") {
  if (cond) {
    console.log(`  PASS  ${name}`);
  } else {
    failures++;
    console.log(`  FAIL  ${name} ${detail}`);
  }
}

console.log("Wikily engine self-test");
console.log(
  `Indexed ${index.stats.documentCount} docs, ${index.stats.tokenCount} tokens\n`
);

// Case 1: the spec's headline "Becky promotion" query.
{
  const m = matchTranscript(index, "How are you progressing with the Becky promotion?");
  const top = m[0];
  console.log(
    `Q1 "Becky promotion" -> ${top?.document.title} (${top?.score.toFixed(3)})`
  );
  check("Q1 resolves Becky Promotion page", top?.document.id === "/wiki/becky-promotion.md");
  check("Q1 clears proactive threshold", (top?.score ?? 0) >= THRESHOLD, `score=${top?.score}`);
  check("Q1 reports the matched entity", (top?.matchedEntities.length ?? 0) > 0);
}

// Case 2: semantic match without an exact title (OAuth/sandbox).
{
  const m = matchTranscript(
    index,
    "We are having trouble setting up the OAuth redirect URI for our Sandbox environment."
  );
  const top = m[0];
  console.log(`Q2 "OAuth sandbox" -> ${top?.document.title} (${top?.score.toFixed(3)})`);
  check("Q2 resolves OAuth page", top?.document.id === "/wiki/oauth-sandbox.md");
  check("Q2 clears proactive threshold", (top?.score ?? 0) >= THRESHOLD, `score=${top?.score}`);
}

// Case 3: unrelated chatter should NOT cross the threshold.
{
  const m = matchTranscript(index, "Did you watch the game last night? Crazy weather too.");
  const top = m[0];
  console.log(`Q3 unrelated -> ${top ? top.document.title + " " + top.score.toFixed(3) : "(no match)"}`);
  check("Q3 does not falsely trigger", !top || top.score < THRESHOLD, `score=${top?.score}`);
}

// Case 4: structured fields parsed for the HUD card.
{
  const becky = docs.find((d) => d.id === "/wiki/becky-promotion.md")!;
  check("Status parsed", !!becky.status && becky.status.includes("In Progress"));
  check("Latest update parsed", !!becky.latestUpdate && becky.latestUpdate.includes("approved"));
  check("Notion quick-link parsed", becky.links.some((l) => l.url.includes("notion.so")));
}

console.log(`\n${failures === 0 ? "ALL PASSED" : failures + " FAILED"}`);
if (failures > 0) process.exit(1);
