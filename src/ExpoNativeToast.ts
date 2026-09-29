import type {
  NativeToastActionEvent,
  NativeToastOptions,
  NativeToastSubscription,
} from "./ExpoNativeToast.types";
import { ACTION_EVENT_NAME } from "./constants";
import { getNativeModule } from "./native-module";
import { normalizeOptions } from "./normalize-options";

type ActionListener = (event: NativeToastActionEvent) => void;

const listeners = new Set<ActionListener>();
let nativeSubscription: NativeToastSubscription | null = null;

/** Warn in development only. Some runtimes do not define `__DEV__`, so guard the read. */
function warn(message: string, error?: unknown): void {
  const isDevelopment = typeof __DEV__ !== "undefined" && __DEV__;
  if (isDevelopment)
    console.warn(`[expo-native-toast] ${message}`, error ?? "");
}

function dispatchAction(event: NativeToastActionEvent): void {
  for (const listener of [...listeners]) {
    try {
      listener(event);
    } catch (error) {
      warn("An action listener threw an error.", error);
    }
  }
}

/**
 * Attach one native subscription while at least one JavaScript listener exists.
 * Call it again later because the native module can install after import.
 */
function syncNativeSubscription(): void {
  if (listeners.size === 0 || nativeSubscription) return;
  const nativeModule = getNativeModule();
  if (!nativeModule) return;
  try {
    nativeSubscription = nativeModule.addListener(
      ACTION_EVENT_NAME,
      dispatchAction,
    );
  } catch (error) {
    warn("Could not subscribe to native action events.", error);
  }
}

function releaseNativeSubscription(): void {
  if (listeners.size > 0 || !nativeSubscription) return;
  const subscription = nativeSubscription;
  nativeSubscription = null;
  try {
    subscription.remove();
  } catch (error) {
    warn("Could not remove the native subscription.", error);
  }
}

/** Return `true` if the app binary contains the native module. */
export function isAvailable(): boolean {
  return getNativeModule() != null;
}

/**
 * Show a toast. A new toast replaces the visible one.
 * Return the toast id, or `null` if the toast was not shown.
 * This function never throws.
 */
export function show(options: NativeToastOptions): string | null {
  const normalized = normalizeOptions(options);
  if (!normalized) {
    warn("Ignored a toast without a title.");
    return null;
  }

  const nativeModule = getNativeModule();
  if (!nativeModule) return null;

  syncNativeSubscription();
  try {
    nativeModule.show(normalized);
    return normalized.id;
  } catch (error) {
    warn("The native module failed to show the toast.", error);
    return null;
  }
}

/** Hide the visible toast and clear a toast that waits for the app to return. */
export function dismiss(): void {
  try {
    getNativeModule()?.dismiss();
  } catch (error) {
    warn("The native module failed to dismiss the toast.", error);
  }
}

/**
 * Listen for taps on toast action buttons.
 * A listener that you add before the native module installs still works.
 */
export function addActionListener(
  listener: ActionListener,
): NativeToastSubscription {
  listeners.add(listener);
  syncNativeSubscription();

  return {
    remove() {
      if (!listeners.delete(listener)) return;
      releaseNativeSubscription();
    },
  };
}

/** Listen for the action of one toast id. */
export function onToastAction(
  id: string,
  handler: () => void,
): NativeToastSubscription {
  return addActionListener((event) => {
    if (event.id === id) handler();
  });
}
