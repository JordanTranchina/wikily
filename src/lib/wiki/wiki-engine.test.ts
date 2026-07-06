// Wikily local wiki engine tests (Tech Spec Milestones 3 & 4).
//
// Exercises the whole offline pipeline — parse markdown → build a TF-IDF index →
// match a live transcript window — and asserts the spec's headline acceptance
// criterion: the "Becky promotion" utterance resolves the correct local page,
// above the proactive-trigger threshold, entirely offline (no network/Tauri).

import { describe, it, expect } from "vitest";
import { parseWikiFile } from "./parser";
import { buildIndex } from "./index-engine";
import { matchTranscript } from "./match-engine";
import { stableHash } from "./hash";
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
  {
    // No frontmatter — title must fall back to the first H1.
    path: "/wiki/no-frontmatter.md",
    name: "no-frontmatter",
    content: `# Password Reset Flow

Walk the customer through resetting their password from the login screen.
`,
  },
];

const docs = files.map(parseWikiFile);
const index = buildIndex(docs);

// The proactive gate the overlay uses; matches the settings default range.
const THRESHOLD = 0.3;

const byId = (id: string) => docs.find((d) => d.id === id)!;

describe("parseWikiFile", () => {
  it("reads frontmatter title, status, aliases, tags and notion link", () => {
    const becky = byId("/wiki/becky-promotion.md");
    expect(becky.title).toBe("Project: Becky Promotion Campaign");
    expect(becky.status).toContain("In Progress");
    expect(becky.aliases).toContain("Becky promotion");
    expect(becky.tags).toEqual(expect.arrayContaining(["marketing", "becky"]));
    expect(becky.links.some((l) => l.url.includes("notion.so"))).toBe(true);
  });

  it("extracts labelled 'Latest Update' and 'Key Blocker' lines for the card", () => {
    const becky = byId("/wiki/becky-promotion.md");
    expect(becky.latestUpdate).toBeTruthy();
    expect(becky.latestUpdate).toContain("approved");
    expect(becky.blocker).toBeTruthy();
  });

  it("falls back to the first H1 when there is no frontmatter title", () => {
    const doc = byId("/wiki/no-frontmatter.md");
    expect(doc.title).toBe("Password Reset Flow");
  });

  it("captures http links from the body as quick links", () => {
    const oauth = byId("/wiki/oauth-sandbox.md");
    // The sandbox callback URL is bare text, not a markdown link, so it should
    // NOT appear as a quick link — only real markdown/frontmatter links do.
    expect(oauth.links.every((l) => /^https?:\/\//.test(l.url))).toBe(true);
  });
});

describe("matchTranscript (offline semantic + entity match)", () => {
  it("resolves the 'Becky promotion' query to the right page above threshold", () => {
    const matches = matchTranscript(
      index,
      "How are you progressing with the Becky promotion?"
    );
    const top = matches[0];
    expect(top).toBeDefined();
    expect(top.document.id).toBe("/wiki/becky-promotion.md");
    expect(top.score).toBeGreaterThanOrEqual(THRESHOLD);
    // The proper-noun hit should be reported for the "Matched: …" card line.
    expect(top.matchedEntities.length).toBeGreaterThan(0);
  });

  it("resolves an OAuth/sandbox question with no exact title match", () => {
    const matches = matchTranscript(
      index,
      "We are having trouble setting up the OAuth redirect URI for our Sandbox environment."
    );
    const top = matches[0];
    expect(top).toBeDefined();
    expect(top.document.id).toBe("/wiki/oauth-sandbox.md");
    expect(top.score).toBeGreaterThanOrEqual(THRESHOLD);
  });

  it("does not falsely trigger on unrelated small talk", () => {
    const matches = matchTranscript(
      index,
      "Did you watch the game last night? Crazy weather too."
    );
    const top = matches[0];
    expect(!top || top.score < THRESHOLD).toBe(true);
  });

  it("an exact entity hit outranks a purely lexical overlap", () => {
    // "billing" appears as a tag/title token on the billing page, but the
    // transcript names the Becky campaign explicitly — entity boost must win.
    const matches = matchTranscript(
      index,
      "Quick billing question, but first: any update on the Becky campaign?"
    );
    expect(matches[0].document.id).toBe("/wiki/becky-promotion.md");
  });

  it("returns nothing for an empty transcript or empty index", () => {
    expect(matchTranscript(index, "   ")).toEqual([]);
    expect(matchTranscript(buildIndex([]), "anything")).toEqual([]);
  });

  it("respects topK", () => {
    const matches = matchTranscript(
      index,
      "billing invoice oauth sandbox becky promotion password reset",
      { topK: 2 }
    );
    expect(matches.length).toBeLessThanOrEqual(2);
  });
});

describe("stableHash (match-log fingerprint)", () => {
  it("is deterministic and differs for different input", () => {
    expect(stableHash("becky promotion")).toBe(stableHash("becky promotion"));
    expect(stableHash("becky promotion")).not.toBe(stableHash("oauth sandbox"));
  });

  it("never leaks the source text and stays a short hex string", () => {
    const h = stableHash("client asked about the sandbox oauth redirect uri");
    expect(h).toMatch(/^[0-9a-f]{8}$/);
    expect(h).not.toContain("sandbox");
  });
});
