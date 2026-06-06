---
title: "OAuth Redirect URI (Sandbox)"
status: "Stable"
aliases: ["OAuth redirect URI", "sandbox redirect", "OAuth callback"]
tags: [oauth, sandbox, auth, integration]
notion: "https://www.notion.so/example/OAuth-Sandbox-Setup"
---

# OAuth Redirect URI (Sandbox)

Summary: How to configure the OAuth redirect URI for the Sandbox environment when setting up a new integration.

Latest Update: Sandbox callback domain migrated to sandbox.example.com on June 1.

## Configuration
Set the redirect URI in your app settings to:

`https://sandbox.example.com/oauth/callback`

The sandbox client id and secret are available in the developer portal under
Settings → Sandbox. Production uses a separate redirect URI.

## Quick Links
- [Developer Portal ↗](https://developers.example.com/sandbox)
