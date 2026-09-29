# expo-native-toast

[![npm version](https://img.shields.io/npm/v/@nauverse/expo-native-toast)](https://www.npmjs.com/package/@nauverse/expo-native-toast)
[![CI](https://github.com/TheNaubit/expo-native-toast/actions/workflows/ci.yml/badge.svg)](https://github.com/TheNaubit/expo-native-toast/actions/workflows/ci.yml)
[![Release](https://github.com/TheNaubit/expo-native-toast/actions/workflows/release.yml/badge.svg)](https://github.com/TheNaubit/expo-native-toast/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/npm/l/@nauverse/expo-native-toast)](https://github.com/TheNaubit/expo-native-toast/blob/main/LICENSE)

Native toasts for Expo. iOS uses SwiftUI with Liquid Glass. Android uses a Material `Snackbar`. Each toast plays a semantic haptic and announces itself to the screen reader.

## Preview

Recorded from release builds of the [example app](./example). From top to bottom: title only (success), title and message (warning), error, and a toast with an action button.

<table>
  <tr>
    <th align="center">iOS (SwiftUI, Liquid Glass)</th>
    <th align="center">Android (Material Snackbar)</th>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/TheNaubit/expo-native-toast/main/docs/media/ios-demo.gif" alt="iOS demo: success, message, error, and action toasts" width="300"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/TheNaubit/expo-native-toast/main/docs/media/android-demo.gif" alt="Android demo: success, message, error, and action snackbars" width="300"></td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/TheNaubit/expo-native-toast/main/docs/media/ios-variants.png" alt="iOS toast variants" width="300"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/TheNaubit/expo-native-toast/main/docs/media/android-variants.png" alt="Android snackbar variants" width="300"></td>
  </tr>
</table>

## Features

- One small API: `show`, `dismiss`, `isAvailable`, `addActionListener`, `onToastAction`
- Four semantic types: `success`, `info`, `warning`, `error`
- Optional message and one optional action button on iOS and Android
- iOS 26 and later use Liquid Glass. Earlier iOS versions use a regular material.
- Native haptics that match the type
- VoiceOver announcement on iOS. TalkBack support through `Snackbar` on Android.
- Respects Reduce Motion and Dynamic Type
- Safe by design: `show` never throws, bad input is cleaned, and the web is a no-op

## Requirements

- Expo SDK 58 or later. The Android side uses Expo Modules v2.
- A development build or a release build. This module does not run in Expo Go.
- iOS 16.4 or later. Android with a Material theme (Expo apps use one by default).

## Installation

```bash
npx expo install @nauverse/expo-native-toast
```

Then rebuild the native app (`npx expo prebuild` and `npx expo run:ios` or `run:android`).

## Usage

```ts
import { show } from "@nauverse/expo-native-toast";

show({ type: "success", title: "Saved" });

show({
  type: "warning",
  title: "Storage almost full",
  message: "Delete old downloads to free space.",
});
```

### Toast with an action

```ts
import { onToastAction, show } from "@nauverse/expo-native-toast";

const id = show({
  type: "success",
  title: "Post added to your Bookmarks",
  actionLabel: "Add to Folder",
});

if (id) {
  const subscription = onToastAction(id, () => openFolderPicker());
  // Call subscription.remove() when your screen unmounts.
}
```

Use `addActionListener` to receive every action event. Each event has the toast `id`.

```ts
useEffect(() => {
  const subscription = addActionListener(({ id }) => console.log("action", id));
  return () => subscription.remove();
}, []);
```

## API

### `show(options): string | null`

Show a toast. A new toast replaces the visible one. Return the toast id, or `null` if the toast was not shown. This function never throws.

| Option        | Type                                        | Default                     | Notes                                                        |
| ------------- | ------------------------------------------- | --------------------------- | ------------------------------------------------------------ |
| `title`       | `string`                                    | required                    | Trimmed. A blank title shows nothing. Max 120 characters.    |
| `type`        | `"success" \| "info" \| "warning" \| "error"` | `"info"`                    | Sets the icon, tint, and haptic. An unknown value becomes `info`. |
| `message`     | `string`                                    | none                        | Second line. Max 300 characters.                             |
| `actionLabel` | `string`                                    | none                        | Adds an action button. Max 30 characters.                    |
| `duration`    | `number` (ms)                               | 4000, or 6000 with an action | Clamped to 1000 - 30000. Give actionable toasts more time.   |
| `id`          | `string`                                    | generated                   | Comes back in the action event.                              |

### `dismiss(): void`

Hide the visible toast. Also clear a toast that waits for the app to return.

### `isAvailable(): boolean`

Return `true` if the app binary contains the native module. Return `false` on web and in Expo Go.

### `addActionListener(listener): { remove() }`

Listen for taps on action buttons. You can add a listener before the native module installs.

### `onToastAction(id, handler): { remove() }`

Listen for the action of one toast.

## Platform behavior

### iOS

- A toast with only a title is a compact capsule. It drops out of the Dynamic Island, then widens to show the title.
- A toast with a message or an action is a card. The card grows out of the shape of the Dynamic Island with a light spring. The title and message fade in first. The action button follows. The card fits its content, up to 340 points wide.
- On exit the toast shrinks back toward the island. With Reduce Motion on, it only fades.
- Devices without a Dynamic Island slide the toast in from just above the screen edge.
- The toast sits in the active window, above modals. Touches pass through everywhere except the toast itself.
- If the app is not active, the toast waits and shows when the app returns. It expires after 30 seconds.
- Success, warning, and error use `UINotificationFeedbackGenerator`. Info uses a soft impact.
- The module posts a VoiceOver announcement with the title, message, and action label.
- If VoiceOver is on and the toast has an action, the toast stays for 30 seconds so the user can reach the button.

### Android

- The module uses a Material `Snackbar` above the bottom navigation bar if one is visible.
- A tinted leading icon and bold title identify the type. Color is never the only signal.
- If the window has no focus, the toast waits for focus. If a dialog is open (for example a React Native `Modal`), a `Snackbar` would be hidden behind it. After 0.8 seconds the module shows a system toast instead, without an action. A toast that waits for the app to return expires after 30 seconds.
- If the app theme is not a Material theme, the module falls back to a system toast without an action.
- Haptics use system feedback constants. The system controls user settings.

### Why a Snackbar and not a Toast on Android

On Android this module uses a Material [`Snackbar`](https://developer.android.com/develop/ui/views/notifications/snackbar), not the system `Toast`. Material Design 3 defines the [snackbar component](https://m3.material.io/components/snackbar/overview) for short in-app messages. The Android documentation says:

> "The `Snackbar` class supersedes `Toast`. While `Toast` is supported, `Snackbar` is the preferred way to display brief, transient messages to the user."

A Snackbar also gives you things a `Toast` cannot:

- One optional action button
- A tinted icon, a bold title, and a message on the next line
- Placement above the bottom navigation bar
- Correct behavior with TalkBack and the system accessibility timeout

The module uses a system `Toast` only as a fallback, in two cases: a dialog (for example a React Native `Modal`) hides the Snackbar, or the app theme is not a Material theme. The fallback has no action button.

### Web

Every function is a safe no-op. `isAvailable()` returns `false`.

## Robustness

- Input is validated. A missing title, an unknown type, a bad duration, or very long text never reaches native code unchecked.
- Native errors are caught in JavaScript. A failed native call never crashes your app.
- A throwing action listener does not stop other listeners.
- Android UI state is touched on the main thread only.
- A JavaScript reload clears the visible and queued toasts, so no action reaches a closed runtime.

## Example

```bash
cd example
npx expo install
npx expo run:ios
```

## Contributing

```bash
npm install
npm run lint
npm run typecheck
npm test
npm run build
```

Commits use [Conventional Commits](https://www.conventionalcommits.org). Releases run through `semantic-release` on `main`.

## License

MIT
