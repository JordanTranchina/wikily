---
title: "API Rate Limits"
status: "Stable"
aliases: ["rate limit", "rate limits", "429", "throttling", "too many requests"]
tags: [api, limits, integration, errors]
notion: "https://www.notion.so/example/API-Rate-Limits"
---

# API Rate Limits

Summary: Default API rate limits, how throttling behaves, and how to request a higher quota.

Latest Update: Burst limit increased to 100 requests/second for Pro plans.

## Limits
- Free: 60 requests / minute
- Pro: 600 requests / minute, 100 requests / second burst
- A `429 Too Many Requests` response includes a `Retry-After` header.

## Raising Limits
Enterprise customers can request a custom quota via their account manager.

## Quick Links
- [API Docs ↗](https://developers.example.com/rate-limits)
