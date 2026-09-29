import type {
  NativeToastOptions,
  NativeToastType,
  NormalizedNativeToastOptions,
} from "./ExpoNativeToast.types";
import {
  DEFAULT_ACTION_DURATION_MS,
  DEFAULT_DURATION_MS,
  MAX_ACTION_LABEL_LENGTH,
  MAX_DURATION_MS,
  MAX_MESSAGE_LENGTH,
  MAX_TITLE_LENGTH,
  MIN_DURATION_MS,
} from "./constants";

const TOAST_TYPES: readonly NativeToastType[] = [
  "error",
  "warning",
  "info",
  "success",
];
const ELLIPSIS = "…";

let idCounter = 0;

function createId(): string {
  idCounter += 1;
  return `toast-${Date.now().toString(36)}-${idCounter}`;
}

function cleanText(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (trimmed.length === 0) return undefined;
  if (trimmed.length <= maxLength) return trimmed;
  return `${trimmed.slice(0, maxLength - ELLIPSIS.length).trimEnd()}${ELLIPSIS}`;
}

function cleanType(value: unknown): NativeToastType {
  return TOAST_TYPES.includes(value as NativeToastType)
    ? (value as NativeToastType)
    : "info";
}

function cleanDuration(value: unknown, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.min(
    MAX_DURATION_MS,
    Math.max(MIN_DURATION_MS, Math.round(value)),
  );
}

/**
 * Validate and clean toast options from JavaScript.
 * Return `null` if the toast cannot be shown (no usable title).
 * Never throw. The result has no `undefined` keys, so native decoders accept it.
 */
export function normalizeOptions(
  options: NativeToastOptions,
): NormalizedNativeToastOptions | null {
  if (options == null || typeof options !== "object") return null;

  const title = cleanText(options.title, MAX_TITLE_LENGTH);
  if (title === undefined) return null;

  const message = cleanText(options.message, MAX_MESSAGE_LENGTH);
  const actionLabel = cleanText(options.actionLabel, MAX_ACTION_LABEL_LENGTH);
  const id =
    typeof options.id === "string" && options.id.length > 0
      ? options.id
      : createId();
  const fallbackDuration = actionLabel
    ? DEFAULT_ACTION_DURATION_MS
    : DEFAULT_DURATION_MS;

  return {
    id,
    type: cleanType(options.type),
    title,
    ...(message !== undefined && { message }),
    ...(actionLabel !== undefined && { actionLabel }),
    duration: cleanDuration(options.duration, fallbackDuration),
  };
}
