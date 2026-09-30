import {
  DEFAULT_DURATION_MS,
  DEFAULT_ACTION_DURATION_MS,
  MAX_DURATION_MS,
  MAX_TITLE_LENGTH,
  MIN_DURATION_MS,
} from "../constants";
import { normalizeOptions } from "../normalize-options";

describe("normalizeOptions", () => {
  it("fills defaults for a minimal toast", () => {
    const result = normalizeOptions({ title: "Saved" });
    expect(result).toEqual({
      id: expect.stringMatching(/^toast-/),
      type: "info",
      title: "Saved",
      duration: DEFAULT_DURATION_MS,
    });
  });

  it("keeps a valid type, id, message, and action label", () => {
    const result = normalizeOptions({
      id: "undo-1",
      type: "error",
      title: "Failed",
      message: "Try again",
      actionLabel: "Retry",
      duration: 5000,
    });
    expect(result).toEqual({
      id: "undo-1",
      type: "error",
      title: "Failed",
      message: "Try again",
      actionLabel: "Retry",
      duration: 5000,
    });
  });

  it("returns null when the title is missing, blank, or not a string", () => {
    expect(normalizeOptions({ title: "" })).toBeNull();
    expect(normalizeOptions({ title: "   " })).toBeNull();
    expect(normalizeOptions({ title: 42 as never })).toBeNull();
    expect(normalizeOptions(undefined as never)).toBeNull();
    expect(normalizeOptions(null as never)).toBeNull();
  });

  it("falls back to info for an unknown type", () => {
    expect(
      normalizeOptions({ title: "x", type: "danger" as never })?.type,
    ).toBe("info");
  });

  it("trims text and drops blank optional fields", () => {
    const result = normalizeOptions({
      title: "  Hi  ",
      message: "   ",
      actionLabel: "",
    });
    expect(result?.title).toBe("Hi");
    expect(result).not.toHaveProperty("message");
    expect(result).not.toHaveProperty("actionLabel");
  });

  it("does not split an emoji when it truncates", () => {
    // The cut lands between the two UTF-16 halves of the emoji
    const title = `${"a".repeat(MAX_TITLE_LENGTH - 2)}\u{1F600}${"b".repeat(10)}`;
    const result = normalizeOptions({ title });
    const loneSurrogate =
      /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
    expect(result?.title).not.toMatch(loneSurrogate);
    expect(result?.title.endsWith("…")).toBe(true);
    expect(result?.title.length).toBeLessThanOrEqual(MAX_TITLE_LENGTH);
  });

  it("truncates very long text", () => {
    const result = normalizeOptions({
      title: "a".repeat(MAX_TITLE_LENGTH + 50),
    });
    expect(result?.title).toHaveLength(MAX_TITLE_LENGTH);
    expect(result?.title.endsWith("…")).toBe(true);
  });

  it("clamps duration to the allowed range and rounds it", () => {
    expect(normalizeOptions({ title: "x", duration: 10 })?.duration).toBe(
      MIN_DURATION_MS,
    );
    expect(normalizeOptions({ title: "x", duration: 10 ** 9 })?.duration).toBe(
      MAX_DURATION_MS,
    );
    expect(normalizeOptions({ title: "x", duration: 2500.6 })?.duration).toBe(
      2501,
    );
  });

  it("uses the default duration for NaN, Infinity, negative, or non-number input", () => {
    for (const duration of [NaN, Infinity, -Infinity, "3000" as never]) {
      expect(normalizeOptions({ title: "x", duration })?.duration).toBe(
        DEFAULT_DURATION_MS,
      );
    }
    expect(normalizeOptions({ title: "x", duration: -5 })?.duration).toBe(
      MIN_DURATION_MS,
    );
  });

  it("uses a longer default duration when the toast has an action", () => {
    expect(
      normalizeOptions({ title: "x", actionLabel: "Undo" })?.duration,
    ).toBe(DEFAULT_ACTION_DURATION_MS);
  });

  it("generates unique ids", () => {
    const a = normalizeOptions({ title: "x" })?.id;
    const b = normalizeOptions({ title: "x" })?.id;
    expect(a).not.toBe(b);
  });
});
