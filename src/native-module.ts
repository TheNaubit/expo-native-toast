import { requireOptionalNativeModule, type NativeModule } from "expo";
import { Platform } from "react-native";

import type {
  NativeToastActionEvent,
  NativeToastSubscription,
  NormalizedNativeToastOptions,
} from "./ExpoNativeToast.types";
import { NATIVE_MODULE_NAME } from "./constants";

export type ExpoNativeToastModule = Pick<
  NativeModule<{ action: (event: NativeToastActionEvent) => void }>,
  never
> & {
  addListener(
    eventName: "action",
    listener: (event: NativeToastActionEvent) => void,
  ): NativeToastSubscription;
  dismiss(): void;
  show(options: NormalizedNativeToastOptions): void;
};

declare global {
  var expoV2:
    | {
        modules?: {
          ExpoNativeToast?: ExpoNativeToastModule;
        };
      }
    | undefined;
}

let cachedModule: ExpoNativeToastModule | null = null;

/**
 * Return the native module, or `null` if the app binary does not contain it.
 * Resolve on every call until found. Android Expo Modules v2 installs the module
 * on `globalThis.expoV2` after JavaScript imports.
 */
export function getNativeModule(): ExpoNativeToastModule | null {
  if (cachedModule) return cachedModule;

  const resolved =
    Platform.OS === "android"
      ? (globalThis.expoV2?.modules?.ExpoNativeToast ?? null)
      : requireOptionalNativeModule<never>(NATIVE_MODULE_NAME);

  cachedModule = (resolved as ExpoNativeToastModule | null) ?? null;
  return cachedModule;
}
