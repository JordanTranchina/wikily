import { describe, it, expect } from "vitest";
import {
  getByPath,
  setByPath,
  extractVariables,
  processUserMessageTemplate,
  buildDynamicMessages,
  deepVariableReplacer,
  getStreamingContent,
} from "./common.function";

// These functions are the core of the "send a message to a custom AI provider"
// workflow: they turn the user's cURL template + conversation history into a
// concrete request body, and parse provider responses back out. Bugs here break
// chat for every provider, so they get the heaviest coverage.

describe("getByPath", () => {
  const obj = {
    choices: [{ message: { content: "hello" }, delta: { content: "hi" } }],
    candidates: [{ content: { parts: [{ text: "gem" }] } }],
  };

  it("resolves a simple dotted path", () => {
    expect(getByPath(obj, "choices[0].message.content")).toBe("hello");
  });

  it("resolves nested array+object paths", () => {
    expect(getByPath(obj, "candidates[0].content.parts[0].text")).toBe("gem");
  });

  it("returns the whole object when path is empty", () => {
    expect(getByPath(obj, "")).toBe(obj);
  });

  it("returns undefined for a missing path instead of throwing", () => {
    expect(getByPath(obj, "choices[5].message.content")).toBeUndefined();
    expect(getByPath(obj, "nope.not.here")).toBeUndefined();
  });
});

describe("setByPath", () => {
  it("sets a nested value, creating intermediate objects", () => {
    const obj: any = {};
    setByPath(obj, "a.b.c", 42);
    expect(obj.a.b.c).toBe(42);
  });

  it("creates arrays when the next key is numeric", () => {
    const obj: any = {};
    setByPath(obj, "items.0", "first");
    expect(Array.isArray(obj.items)).toBe(true);
    expect(obj.items[0]).toBe("first");
  });

  it("overwrites existing values", () => {
    const obj: any = { a: { b: 1 } };
    setByPath(obj, "a.b", 2);
    expect(obj.a.b).toBe(2);
  });
});

describe("extractVariables", () => {
  it("extracts unique uppercase {{VARS}} excluding reserved ones by default", () => {
    const curl =
      'curl -H "Authorization: Bearer {{API_KEY}}" -d \'{"model":"{{MODEL}}","text":"{{TEXT}}","sys":"{{SYSTEM_PROMPT}}"}\'';
    const result = extractVariables(curl);
    const keys = result.map((r) => r.value);
    expect(keys).toContain("API_KEY");
    expect(keys).toContain("MODEL");
    // Reserved placeholders are filled by the engine, not the user.
    expect(keys).not.toContain("TEXT");
    expect(keys).not.toContain("SYSTEM_PROMPT");
  });

  it("includes reserved variables when includeAll=true", () => {
    const curl = 'curl -d \'{"text":"{{TEXT}}","img":"{{IMAGE}}"}\'';
    const result = extractVariables(curl, true).map((r) => r.value);
    expect(result).toContain("TEXT");
    expect(result).toContain("IMAGE");
  });

  it("de-duplicates repeated variables", () => {
    const curl = "curl {{API_KEY}} {{API_KEY}} {{API_KEY}}";
    expect(extractVariables(curl)).toHaveLength(1);
  });

  it("returns an empty array for non-string input", () => {
    // @ts-expect-error exercising the runtime guard
    expect(extractVariables(null)).toEqual([]);
    // @ts-expect-error exercising the runtime guard
    expect(extractVariables(undefined)).toEqual([]);
  });

  it("returns an empty array when there are no variables", () => {
    expect(extractVariables("curl https://example.com")).toEqual([]);
  });
});

describe("processUserMessageTemplate", () => {
  it("substitutes the user text into the template", () => {
    const template = { role: "user", content: "{{TEXT}}" };
    const result = processUserMessageTemplate(template, "hello world");
    expect(result).toEqual({ role: "user", content: "hello world" });
  });

  it("escapes text so JSON-breaking characters don't corrupt the body", () => {
    const template = { role: "user", content: "{{TEXT}}" };
    const tricky = 'she said "hi"\nand left\t';
    const result = processUserMessageTemplate(template, tricky);
    expect(result.content).toBe(tricky);
  });

  it("expands an image placeholder into one entry per image", () => {
    const template = {
      role: "user",
      content: [
        { type: "text", text: "{{TEXT}}" },
        { type: "image_url", image_url: { url: "{{IMAGE}}" } },
      ],
    };
    const result = processUserMessageTemplate(template, "look", [
      "imgA",
      "imgB",
    ]);
    expect(result.content).toHaveLength(3); // text + 2 images
    expect(result.content[1].image_url.url).toBe("imgA");
    expect(result.content[2].image_url.url).toBe("imgB");
  });

  it("removes the image placeholder entirely when no images are provided", () => {
    const template = {
      role: "user",
      content: [
        { type: "text", text: "{{TEXT}}" },
        { type: "image_url", image_url: { url: "{{IMAGE}}" } },
      ],
    };
    const result = processUserMessageTemplate(template, "no pics", []);
    expect(result.content).toHaveLength(1);
    expect(result.content[0].type).toBe("text");
  });
});

describe("buildDynamicMessages", () => {
  const userTemplate = { role: "user", content: "{{TEXT}}" };

  it("inserts history before the current user message", () => {
    const history = [
      { role: "user", content: "earlier" },
      { role: "assistant", content: "reply" },
    ] as any;
    const result = buildDynamicMessages([userTemplate], history, "now");
    expect(result).toEqual([
      { role: "user", content: "earlier" },
      { role: "assistant", content: "reply" },
      { role: "user", content: "now" },
    ]);
  });

  it("preserves system/prefix and suffix messages around history", () => {
    const template = [
      { role: "system", content: "be nice" },
      userTemplate,
      { role: "system", content: "trailing rule" },
    ];
    const result = buildDynamicMessages(template, [], "hi");
    expect(result[0]).toEqual({ role: "system", content: "be nice" });
    expect(result[1]).toEqual({ role: "user", content: "hi" });
    expect(result[2]).toEqual({ role: "system", content: "trailing rule" });
  });

  it("falls back to history + plain user message when no {{TEXT}} slot exists", () => {
    const history = [{ role: "assistant", content: "prev" }] as any;
    const result = buildDynamicMessages(
      [{ role: "system", content: "x" }],
      history,
      "fallback"
    );
    expect(result).toEqual([
      { role: "assistant", content: "prev" },
      { role: "user", content: "fallback" },
    ]);
  });
});

describe("deepVariableReplacer", () => {
  it("replaces variables anywhere in a nested structure", () => {
    const node = {
      url: "https://api/{{MODEL}}",
      headers: { auth: "Bearer {{API_KEY}}" },
      list: ["{{MODEL}}", "static"],
    };
    const result = deepVariableReplacer(node, {
      MODEL: "gpt",
      API_KEY: "secret",
    });
    expect(result.url).toBe("https://api/gpt");
    expect(result.headers.auth).toBe("Bearer secret");
    expect(result.list[0]).toBe("gpt");
  });

  it("leaves non-string leaves untouched", () => {
    const node = { count: 3, enabled: true, name: "{{X}}" };
    const result = deepVariableReplacer(node, { X: "y" });
    expect(result.count).toBe(3);
    expect(result.enabled).toBe(true);
    expect(result.name).toBe("y");
  });

  it("replaces every occurrence of a repeated variable", () => {
    expect(deepVariableReplacer("{{A}}-{{A}}", { A: "x" })).toBe("x-x");
  });
});

describe("getStreamingContent", () => {
  it("extracts OpenAI-style delta content", () => {
    const chunk = { choices: [{ delta: { content: "tok" } }] };
    expect(getStreamingContent(chunk, "choices[0].message.content")).toBe(
      "tok"
    );
  });

  it("extracts Claude-style delta.text", () => {
    const chunk = { delta: { text: "claude" } };
    expect(getStreamingContent(chunk, "content[0].text")).toBe("claude");
  });

  it("extracts Gemini-style nested parts", () => {
    const chunk = { candidates: [{ content: { parts: [{ text: "gem" }] } }] };
    expect(
      getStreamingContent(chunk, "candidates[0].content.parts[0].text")
    ).toBe("gem");
  });

  it("falls back to the provider's default path", () => {
    const chunk = { custom: { field: "weird" } };
    expect(getStreamingContent(chunk, "custom.field")).toBe("weird");
  });

  it("returns null when no path yields string content", () => {
    const chunk = { choices: [{ delta: {} }] };
    expect(getStreamingContent(chunk, "choices[0].message.content")).toBeNull();
  });

  it("ignores non-string matches (e.g. an object at the path)", () => {
    const chunk = { choices: [{ delta: { content: { nested: "x" } } }] };
    expect(getStreamingContent(chunk, "choices[0].message.content")).toBeNull();
  });
});
