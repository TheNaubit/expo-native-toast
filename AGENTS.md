# expo-native-toast - agent guide

This is a standalone, publishable Expo module: `@nauverse/expo-native-toast`.
It shows native toasts. iOS uses SwiftUI (Liquid Glass on iOS 26+). Android uses a Material `Snackbar`.
The module uses **Expo Modules v2** (`@ExpoModule`, `@JS`, `@Record`, `@Event` macros and annotations). It needs Expo SDK 58 or later.

The reference for structure and release flow is [expo-cloud-settings](https://github.com/TheNaubit/expo-cloud-settings). Follow its conventions.

## Commands

Use **npm** only.

```bash
npm install
npm run lint        # expo-module lint (ESLint 9 flat config)
npm run typecheck   # tsc --noEmit
npm test            # expo-module test (jest-expo)
npm run build       # expo-module build -> build/
```

Run lint, typecheck, test, and build before you say a task is done. CI runs the same steps.

## Layout

```
src/
  index.ts                 public exports only
  ExpoNativeToast.ts       public API: show, dismiss, isAvailable, addActionListener, onToastAction
  ExpoNativeToast.types.ts public types
  normalize-options.ts     pure validation and cleaning of options (no native calls)
  native-module.ts         resolves the native module (lazy). native-module.web.ts is the web no-op
  constants.ts             every limit and default, with a comment
  __tests__/               Jest tests
ios/                       ExpoNativeToastModule.swift + podspec
android/                   Kotlin module, host, init provider, drawables, colors
example/                   demo app files (App.tsx and Metro config)
```

## Hard rules

1. **`show` and `dismiss` never throw.** Wrap every native call in `try/catch`. Warn in development only. Guard `__DEV__` with `typeof` because some runtimes do not define it.
2. **Validate in JavaScript first.** All input goes through `normalizeOptions`. Native code receives no `undefined` keys, a valid `type`, a clamped `duration`, and an `id`.
3. **Resolve the native module lazily.** Android v2 installs `globalThis.expoV2.modules.ExpoNativeToast` after JavaScript imports. Never read it once at import time.
4. **Attach native listeners lazily.** A listener added before the module installs must still work. Keep one native subscription for all JavaScript listeners.
5. **The web is a no-op.** Keep `native-module.web.ts` returning `null`.
6. **No magic numbers.** Put limits in `src/constants.ts`. Keep the same values in the Swift `NativeToastLimits` and the Kotlin `NativeToastHost` constants.
7. **Immutability.** Do not mutate options or listener collections you return. Build new objects.
8. **No emojis** in code, comments, or docs. No `console.log`. The only console use is the guarded `warn` helper.
9. **Files stay small** (under 400 lines typical, 800 max). One topic per file.

## Native rules

### Android (`NativeToastHost.kt`)

- Touch host state on the **main thread only**. Use `runOnMainThread`. Do not add `@Synchronized`.
- Handle `Snackbar.make` failure. It throws on a non-Material theme. Fall back to a system `Toast`.
- Check `isFinishing` and `isDestroyed` before you present.
- Keep one focus waiter. Clear it on pause, destroy, and `dismiss`.
- Expire a queued toast after 30 seconds.
- A resumed activity without window focus has a dialog on top. Show the system toast fallback after a short delay.
- Reset host state in the module `init`. A new instance means JavaScript reloaded.
- Anchor only to `BottomNavigationView`. A `NavigationRailView` is a side rail.
- Clear the focus waiter by the activity it belongs to, not by `currentActivity`.
- Keep the ProGuard rules in `consumer-rules.pro`. Release builds need them for the v2 runtime.

### iOS (`ExpoNativeToastModule.swift`)

- Present on the main actor only.
- Queue the toast if no scene is `foregroundActive`. Show it on `UIScene.didActivateNotification`. Expire it after 30 seconds.
- Touch handling: `NativeToastContainerView` passes touches through except inside the frame that the SwiftUI view reports. Do not rely on `hitTest` to find SwiftUI buttons. The hosting view owns SwiftUI gestures.
- Respect `UIAccessibility.isReduceMotionEnabled`.
- Keep an action toast on screen longer when VoiceOver runs.
- Send `show` and `dismiss` through `DispatchQueue.main.async` so they keep call order. Dismiss in `deinit` for reload.
- Removing a toast must not remove a newer toast. Set `presented = nil` before an animated removal.
- Accessibility: keep icons hidden from VoiceOver. Combine the text row into one element. Keep the action button a separate element.

## Testing

- TDD. Write the failing test first.
- Keep coverage at 80% or more. It is about 98% now.
- Test the pure logic in `normalize-options.ts` and the public API with a fake native module.
- Jest mock factories may only use variables whose names start with `mock`.
- Native code has no unit tests. Verify it by compiling in a real host app:
  - Android: sync `android/` into an app, then run `./gradlew :expo-native-toast:compileDebugKotlin`.
  - iOS: run `xcodebuild -project Pods/Pods.xcodeproj -target ExpoNativeToast -sdk iphonesimulator build`.
  - Then run the app and check the toast by eye. Compiling does not prove the layout is right.

## Verification lessons

- Compiling is not proof. A touch bug hid behind a green build: the SwiftUI frame reached the container as an empty rect, so every touch passed through. Always tap the button in a running app and check the result.
- Report the toast frame from a `GeometryReader` with `onAppear` and `onChange(of: proxy.size)`. A `PreferenceKey` with `onPreferenceChange` delivered only the default value here.
- The UIHostingController view is added to the window without a parent controller. It gets no safe area. The container lays it out below `safeAreaInsets.top`, and `safeAreaRegions = []` stops SwiftUI from adding the inset again.
- Toasts last a few seconds and tool calls are slow. Use a long `duration` in the example when you test a tap.
- Debug with temporary `NSLog` lines and `xcrun simctl spawn <sim> log stream`. Remove them before you commit.

## Example app and media

- `example/` is a real Expo app. It autolinks the library with `expo.autolinking.nativeModulesDir: ".."`.
- Pin the example to the same Expo package versions as a known working app. `expo` 58 preview releases can ship `expo-*` packages whose Android `publication` has no `version`. Gradle then fails with "Field 'version' is required". The `overrides` in `example/package.json` fix this.
- Record media from **release** builds so no dev menu shows. Use a clean status bar: `xcrun simctl status_bar <sim> override --time 9:41 ...` on iOS and the system UI demo mode on Android.
- Media lives in `docs/media/`. It is not in the npm tarball. The README uses absolute `raw.githubusercontent.com` URLs so npm shows the images.
- Media must not show personal data: no device names, notifications, accounts, or paths.

## Releases

- Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:`.
- Do not add "Co-Authored-By" or similar lines to commit messages.
- `semantic-release` runs on `main` and sets the version. Keep `version` in `package.json` at `0.0.0` in source.
- Before you publish, check the tarball with `npm pack --dry-run`. It must not include `android/build`, tests, or `example/`.
- The Android Gradle version and the podspec version do not drive releases. Do not bump them by hand.

## Gotchas

- `expo-module-scripts` 56 with TypeScript 6 needs `rootDir` in `tsconfig.json`.
- ESLint 9 needs `eslint.config.js`. Do not add `.eslintrc.js`.
- `expo` in `devDependencies` is a pinned SDK 58 preview. Update it on purpose, not by dist-tag.
- The Kotlin package is `expo.modules.nativetoast`. The native module name is `ExpoNativeToast`. Keep both in sync with `expo-module.config.json` and `NATIVE_MODULE_NAME`.
- The action event is named `action` in JavaScript. The native side declares `onAction`. Keep `ACTION_EVENT_NAME` in sync.
