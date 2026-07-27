# **Pricing Strategy: Wikily**

**Status:** Draft | **Author:** Product Management | **Related:** [`Product Spec Wikily.md`](./Product%20Spec%20Wikily.md), [`Tech Spec Wikily.md`](./Tech%20Spec%20Wikily.md)

## **1. Where the Value Actually Lives**

Wikily's value prop is not "an AI overlay." It's three compounding things, and each one is worth more to a different buyer:

1. **The proactive trigger** — the HUD appears *without being asked*, inside 1.5s of a client utterance. This is the "wow" moment and the whole reason a CSR keeps the app running instead of falling back to manual search.
2. **Local wiki depth & freshness** — how big, well-linked, and current the user's knowledge base is (their Obsidian/Karpathy vault or synced Notion workspace). A thin wiki produces mediocre matches regardless of the model; a deep, synced wiki is where the compounding value sits.
3. **Privacy/compliance guarantee** — 100% local audio + transcript processing, no cloud storage of call content. This matters most to *teams*, not individuals, because it's what lets a support org actually deploy the tool without legal/security pushback.

The people who "buy into the value prop the most" are therefore not casual users — they're **high-call-volume CSRs on teams with an existing knowledge base (Notion/Obsidian) and compliance sensitivity**. Pricing should be built to let a single rep try the magic moment for free, then charge scaling amounts as (a) call volume, (b) wiki/sync depth, and (c) team/compliance needs grow — because those three axes are exactly where willingness-to-pay grows too.

## **2. Free Tier (constant across all strategies below)**

Every strategy below assumes the same floor, because the free tier's job is identical regardless of monetization axis: **let a rep experience one real proactive-match HUD moment inside their first call, with zero setup friction.**

- Full manual-trigger overlay (Pluely's inherited hotkey search), system audio capture, screenshots, voice input — unchanged from Pluely today.
- Local wiki directory pointing (one vault, capped size — e.g. ≤50 files / ≤5MB indexed).
- Proactive HUD triggering **capped** (see Strategy A) or **rate-limited** (see Strategy B) rather than fully absent — a free tier that never shows the core magic will not convert.
- BYOK required (user supplies their own OpenAI/Anthropic/Ollama key), matching Pluely's existing local-first, zero-server-dependency architecture.
- No Notion cloud sync, no team/admin features, no priority support.

## **3. Candidate Pricing Strategies**

### **Strategy A — Feature-Gated: Free Trigger, Paid Proactivity**

Free tier gets *manual* search only (Pluely's existing hotkey flow); the **proactive, hands-free HUD trigger — Wikily's actual differentiator — is the paid unlock.**

- **Free:** Manual search overlay, unlimited use, BYOK.
- **Pro ($15–20/mo/seat):** Proactive triggering unabled, full-size local wiki index, faster (larger) local embedding model.
- **Why it captures the right payers:** Only reps who actually run enough calls to feel the pain of manual searching will bother upgrading — casual/trial users self-select out. Directly monetizes the single feature the product spec calls the core hypothesis (§1.4).
- **Risk:** Free tier is close to plain Pluely, so the upgrade trigger relies entirely on the user *wanting* proactivity, which they may not discover without ever seeing it. Mitigate with a limited free trial of proactive mode (e.g., first 20 proactive matches, ever).

### **Strategy B — Usage-Based: Proactive Match Credits**

Instead of a hard feature wall, meter the proactive engine itself, like an API.

- **Free:** 30 proactive HUD triggers/month (roughly one real call's worth), unlimited manual search.
- **Pay-as-you-grow:** $0.15–0.25 per proactive match beyond the free quota, or bundled packs (500 matches/mo ≈ $39).
- **Pro flat-rate ($29/mo/seat):** Unlimited proactive matches for reps doing 8–10 calls/day (per persona in §2.1 of the product spec), where metered pricing would otherwise exceed flat-rate cost.
- **Why it captures the right payers:** Directly ties spend to the KPI Wikily already tracks — "implicit engagement" clicks on proactive cards (§7.2 of the product spec). Heavy users (the ideal persona) naturally graduate to flat-rate Pro; light users stay cheap or free. This is the closest fit to "price on the value received."
- **Risk:** Metered pricing adds billing complexity and can create anxiety ("will this trigger cost me money?") that suppresses the exact proactive behavior you want reps to trust. Best combined with a generous free quota and a clear flat-rate off-ramp.

### **Strategy C — Per-Seat Team/Enterprise Tiers (Compliance & Sync as the Upsell)**

Individual usage stays free or cheap; the real monetization axis is **team deployment and the Notion Cloud Sync Engine** (§6 of the product spec, currently roadmapped post-MVP).

- **Free:** Full proactive HUD, single local vault, BYOK, individual use only.
- **Team ($39/seat/mo, 3+ seats):** Notion OAuth sync (auto-compiles workspace into the local wiki schema), shared/managed wiki directories across a support team, seat management, usage dashboards.
- **Enterprise (custom):** SSO, audit logs/compliance attestation for the "audio never leaves the device" guarantee, dedicated support, on-prem/self-hosted LLM defaults (Ollama-first configs), procurement/DPA support.
- **Why it captures the right payers:** A support *org* rolling this out to a team is worth vastly more than one rep, and the two things only an org needs — synced shared knowledge and compliance sign-off — are exactly what's gated. This monetizes the buyer (VP of Support / IT) rather than the individual user, which matches how CS tooling (Zendesk, Intercom, Gorgias) is actually procured.
- **Risk:** Individual power users pay nothing under this model alone; best used as a second axis layered on top of Strategy A or B, not standalone.

### **Strategy D — BYOK (Free) vs. Managed Infra (Paid)**

Mirrors Pluely's existing "Dev Pro" license pattern almost exactly, so it reuses infrastructure already in the codebase (`GetLicense`, `hasActiveLicense` in `src/pages/dashboard/index.tsx`).

- **Free:** Full feature set, but the user must supply their own LLM/STT API keys (or run local Ollama/whisper.cpp) and accept default-speed local embeddings.
- **Pro ($10–15/mo or a one-time lifetime license, echoing Pluely's $120 lifetime Dev Pro precedent):** Wikily-hosted/optimized transcription and embedding pipeline (no key setup required), faster response times, priority support — "unlock faster responses... premium features" per the existing dashboard copy.
- **Why it captures the right payers:** Zero-setup-friction is worth real money to non-technical CSRs and support-team admins who don't want to manage API keys across a whole team; technical/cost-sensitive users keep BYOK free forever.
- **Risk:** Weakest alignment with the *core* value prop (proactive matching) — it monetizes convenience, not the feature that drives the core hypothesis. Best as a complement to Strategy A/B, not the primary lever.

### **Strategy E — Outcome/Value-Metric Pricing**

Price against the business metric Wikily is meant to move — handle time and first-contact resolution — rather than a product mechanic.

- **Free:** Full functionality, capped at one active rep, no reporting.
- **Team ($X/resolved-call-assisted or a per-seat price justified by measured handle-time reduction):** Includes an analytics layer showing time saved / FCR lift per rep, which is also the artifact that justifies the price to a support-org buyer's finance team.
- **Why it captures the right payers:** Aligns price with the literal ROI story ("cut handle time by N seconds/call across 10 calls/day/rep") — easiest strategy to defend in a procurement conversation.
- **Risk:** Requires building call-outcome analytics (not in MVP scope, §3) before this is credible; treat as a v2 add-on layered onto whichever tier structure ships first, not a v1 strategy.

## **4. Recommendation: A/C Hybrid**

Ship **Strategy A (feature-gated proactivity) as the individual monetization axis** and **Strategy C (team/Notion-sync/compliance tiers) as the org monetization axis**, on top of the shared free floor in §2. This is the combination most consistent with the MVP roadmap already in the product spec: proactive triggering is Milestone 5 (the "full loop"), and Notion Cloud Sync is the named post-MVP roadmap item (§6) — so the paywall boundaries fall exactly on features that don't exist yet in the free-forever Pluely fork today, meaning no existing behavior needs to be clawed back from users.

| Tier | Price | Unlocks | Targets |
|---|---|---|---|
| **Free** | $0 | Manual search HUD, single local vault (≤50 files), BYOK | Trial users, individual evaluators |
| **Pro** | $19/seat/mo (or ~$180/yr) | Proactive HUD triggering, full-size local wiki index, faster local embeddings | Individual CSRs doing 8–10 calls/day — the core persona |
| **Team** | $39/seat/mo, 3+ seats | Everything in Pro + Notion Cloud Sync, shared/managed vaults, seat admin, usage dashboards | Support team leads/managers rolling out org-wide |
| **Enterprise** | Custom | Everything in Team + SSO, compliance attestation, on-prem/local-LLM defaults, dedicated support | IT/Security-gated enterprise support orgs |

Layer in a light version of **Strategy D** (bring-your-own-key stays free forever; a managed-inference add-on is a small incremental charge on any paid tier) since that infrastructure already exists in the codebase and costs little to extend. Treat **Strategy B**'s usage metering as the fallback if Pro's flat $19/seat proves mispriced once real proactive-trigger volumes are observed post-launch, and revisit **Strategy E** once call-outcome analytics exist to make an ROI-based price defensible.

## **5. What to Instrument Before Committing to Exact Numbers**

- Proactive triggers per rep per day (validates Strategy A/B pricing math).
- Wiki vault size/sync frequency distribution (validates the Free-tier vault cap in §2).
- % of installs that are solo vs. multi-seat within the same workspace/domain (validates Team tier seat minimum).
- Click-through on proactive cards ("Copy," "Open Notion Task") as the leading indicator for §7.2's KPI — this is the signal that should gate any future move toward Strategy E.
