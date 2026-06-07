import { describe, it, expect } from "vitest";
import { validateCurl } from "./curl-validator";

// Adding a custom AI/STT provider is a critical onboarding workflow: the user
// pastes a cURL command and we must accept valid ones and reject malformed ones
// with a helpful message.

describe("validateCurl", () => {
  it("accepts a valid curl that contains all required variables", () => {
    const curl =
      'curl https://api.example.com -H "Authorization: Bearer {{API_KEY}}" -d \'{"model":"{{MODEL}}"}\'';
    expect(validateCurl(curl, ["API_KEY", "MODEL"])).toEqual({ isValid: true });
  });

  it("accepts a valid curl when no variables are required", () => {
    expect(validateCurl("curl https://api.example.com", [])).toEqual({
      isValid: true,
    });
  });

  it("rejects a command that does not start with curl", () => {
    const result = validateCurl("wget https://example.com", []);
    expect(result.isValid).toBe(false);
    expect(result.message).toMatch(/must start with 'curl'/i);
  });

  it("tolerates leading whitespace before curl", () => {
    expect(validateCurl("   curl https://example.com", [])).toEqual({
      isValid: true,
    });
  });

  it("reports each missing required variable", () => {
    const curl = 'curl https://api.example.com -d \'{"model":"{{MODEL}}"}\'';
    const result = validateCurl(curl, ["API_KEY", "MODEL"]);
    expect(result.isValid).toBe(false);
    expect(result.message).toContain("{{API_KEY}}");
    expect(result.message).not.toContain("{{MODEL}}");
  });

  it("lists all missing variables together", () => {
    const result = validateCurl("curl https://api.example.com", [
      "API_KEY",
      "MODEL",
    ]);
    expect(result.isValid).toBe(false);
    expect(result.message).toContain("{{API_KEY}}");
    expect(result.message).toContain("{{MODEL}}");
  });
});
