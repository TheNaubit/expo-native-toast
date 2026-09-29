/** Shortest time a toast stays visible. Shorter values are not readable. */
export const MIN_DURATION_MS = 1_000;

/** Longest time a toast stays visible. Longer values block the screen. */
export const MAX_DURATION_MS = 30_000;

/** Default time for a toast without an action. */
export const DEFAULT_DURATION_MS = 4_000;

/** Default time for a toast with an action. The user needs time to reach it. */
export const DEFAULT_ACTION_DURATION_MS = 6_000;

/** Maximum title length. Native code shows at most two lines. */
export const MAX_TITLE_LENGTH = 120;

/** Maximum message length. Native code shows at most four lines. */
export const MAX_MESSAGE_LENGTH = 300;

/** Maximum action label length. A long label does not fit in the button. */
export const MAX_ACTION_LABEL_LENGTH = 30;

/** Name of the native module. It must match the native `Name` value. */
export const NATIVE_MODULE_NAME = "ExpoNativeToast";

/** Name of the native action event. */
export const ACTION_EVENT_NAME = "action";
