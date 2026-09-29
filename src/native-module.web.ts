import type { ExpoNativeToastModule } from "./native-module";

export type { ExpoNativeToastModule };

/** Web has no native toast. Every public function is a safe no-op. */
export function getNativeModule(): ExpoNativeToastModule | null {
  return null;
}
