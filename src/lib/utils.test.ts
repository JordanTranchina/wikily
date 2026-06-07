import { describe, it, expect } from "vitest";
import { cn, floatArrayToWav } from "./utils";

// jsdom's Blob doesn't implement arrayBuffer(); read bytes via FileReader.
const blobToArrayBuffer = (blob: Blob): Promise<ArrayBuffer> =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as ArrayBuffer);
    reader.onerror = reject;
    reader.readAsArrayBuffer(blob);
  });

describe("cn", () => {
  it("merges class names", () => {
    expect(cn("a", "b")).toBe("a b");
  });

  it("dedupes conflicting tailwind classes (last wins)", () => {
    expect(cn("p-2", "p-4")).toBe("p-4");
  });

  it("drops falsy values", () => {
    expect(cn("a", false, null, undefined, "b")).toBe("a b");
  });
});

// floatArrayToWav encodes captured microphone audio before it is sent to STT
// providers. A malformed header or sample count would break transcription.
describe("floatArrayToWav", () => {
  it("produces a Blob with the wav mime type", () => {
    const blob = floatArrayToWav(new Float32Array([0, 0.5, -0.5]));
    expect(blob).toBeInstanceOf(Blob);
    expect(blob.type).toBe("audio/wav");
  });

  it("sizes the buffer as 44-byte header + 2 bytes per sample", async () => {
    const samples = new Float32Array([0, 0.25, -0.25, 1]);
    const blob = floatArrayToWav(samples);
    expect(blob.size).toBe(44 + samples.length * 2);
  });

  it("writes a RIFF/WAVE header", async () => {
    const blob = floatArrayToWav(new Float32Array([0]));
    const header = new Uint8Array(await blobToArrayBuffer(blob)).slice(0, 4);
    expect(String.fromCharCode(...header)).toBe("RIFF");
  });

  it("clamps out-of-range samples without overflowing", async () => {
    // Values beyond [-1, 1] must clamp to the 16-bit PCM extremes.
    const blob = floatArrayToWav(new Float32Array([5, -5]));
    const view = new DataView(await blobToArrayBuffer(blob));
    expect(view.getInt16(44, true)).toBe(0x7fff); // +full scale
    expect(view.getInt16(46, true)).toBe(-0x8000); // -full scale
  });

  it("honors a custom sample rate in the header", async () => {
    const blob = floatArrayToWav(new Float32Array([0]), 48000);
    const view = new DataView(await blobToArrayBuffer(blob));
    expect(view.getUint32(24, true)).toBe(48000); // sampleRate field
  });
});
