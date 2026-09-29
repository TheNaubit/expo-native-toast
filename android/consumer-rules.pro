# Expo Modules v2 creates its provider and modules through reflection.
-keep class expo.modules.ExpoModulesV2ModuleList { *; }
-keep class expo.modules.nativetoast.** { *; }

# Kolibri and the v2 runtime resolve Java classes and members from JNI by name.
-keep class io.github.expo.kolibri.** { *; }
-keep class io.github.expo.modules.v2.** { *; }
