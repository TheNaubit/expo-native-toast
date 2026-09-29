export type NativeToastType = "error" | "warning" | "info" | "success";

export type NativeToastOptions = {
  /** Label of the action button. Omit it for a toast without an action. */
  actionLabel?: string;
  /** Time in milliseconds. The library clamps it to 1000-30000. */
  duration?: number;
  /** Identifier that comes back in the action event. The library creates one if you omit it. */
  id?: string;
  /** Second line. iOS VoiceOver and Android show it. */
  message?: string;
  /** Required. The library ignores a toast with a blank title. */
  title: string;
  /** Semantic type. It sets the icon, tint, and haptic. Default: `info`. */
  type?: NativeToastType;
};

/** Options after validation. This is the exact shape that native code receives. */
export type NormalizedNativeToastOptions = {
  actionLabel?: string;
  duration: number;
  id: string;
  message?: string;
  title: string;
  type: NativeToastType;
};

export type NativeToastActionEvent = {
  id: string;
};

export type NativeToastSubscription = {
  remove: () => void;
};
