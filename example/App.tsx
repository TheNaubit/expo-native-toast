import {
  addActionListener,
  dismiss,
  isAvailable,
  show,
  type NativeToastActionEvent,
  type NativeToastType,
} from "@nauverse/expo-native-toast";
import { useEffect, useState } from "react";
import {
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from "react-native";

type Demo = { label: string; run: () => void };

function typeDemo(type: NativeToastType, title: string): Demo {
  return { label: type, run: () => show({ type, title }) };
}

const DEMOS: { heading: string; items: Demo[] }[] = [
  {
    heading: "Title only",
    items: [
      typeDemo("success", "Saved to favorites"),
      typeDemo("info", "Syncing in the background"),
      typeDemo("warning", "Storage almost full"),
      typeDemo("error", "Could not refresh"),
    ],
  },
  {
    heading: "With message",
    items: [
      {
        label: "message",
        run: () =>
          show({
            type: "warning",
            title: "Storage almost full",
            message: "Delete old downloads to free space.",
          }),
      },
    ],
  },
  {
    heading: "With action",
    items: [
      {
        label: "action",
        run: () =>
          show({
            id: "bookmark",
            type: "success",
            title: "Post added to your Bookmarks",
            actionLabel: "Add to Folder",
            duration: 20000,
          }),
      },
    ],
  },
];

const FEED = [
  "Sunrise hike above the clouds",
  "Ten quiet cafes worth the detour",
  "A weekend by the coast",
  "Night market food guide",
];

export default function App() {
  const dark = useColorScheme() === "dark";
  const [lastAction, setLastAction] = useState<NativeToastActionEvent | null>(null);
  const colors = dark ? DARK : LIGHT;

  useEffect(() => {
    const subscription = addActionListener(setLastAction);
    return () => subscription.remove();
  }, []);

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={[styles.header, { color: colors.text }]}>Native Toast</Text>
        <Text style={[styles.meta, { color: colors.muted }]}>
          Module available: {String(isAvailable())} | Last action: {lastAction?.id ?? "none"}
        </Text>

        {FEED.map((title) => (
          <View key={title} style={[styles.card, { backgroundColor: colors.card }]}>
            <View style={[styles.thumb, { backgroundColor: colors.thumb }]} />
            <View style={styles.cardText}>
              <Text style={[styles.cardTitle, { color: colors.text }]}>{title}</Text>
              <View style={[styles.line, { backgroundColor: colors.thumb }]} />
              <View style={[styles.line, styles.lineShort, { backgroundColor: colors.thumb }]} />
            </View>
          </View>
        ))}

        {DEMOS.map((group) => (
          <View key={group.heading} style={styles.group}>
            <Text style={[styles.subheader, { color: colors.text }]}>{group.heading}</Text>
            <View style={styles.row}>
              {group.items.map((demo) => (
                <Pressable
                  key={demo.label}
                  accessibilityRole="button"
                  accessibilityLabel={demo.label}
                  onPress={demo.run}
                  style={({ pressed }) => [
                    styles.button,
                    { backgroundColor: colors.button },
                    pressed && styles.pressed,
                  ]}
                >
                  <Text style={styles.buttonText}>{demo.label}</Text>
                </Pressable>
              ))}
            </View>
          </View>
        ))}
        <Pressable
          accessibilityRole="button"
          onPress={dismiss}
          style={[styles.button, { backgroundColor: colors.button }]}
        >
          <Text style={styles.buttonText}>dismiss</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

const LIGHT = {
  background: "#F2F2F7",
  card: "#FFFFFF",
  thumb: "#E1E1E8",
  text: "#111114",
  muted: "#6B6B76",
  button: "#2F6FED",
};
const DARK = {
  background: "#0B0B0F",
  card: "#1A1A20",
  thumb: "#2C2C35",
  text: "#F5F5F7",
  muted: "#9A9AA6",
  button: "#3B7BFF",
};

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: 20, paddingTop: 56, gap: 12 },
  header: { fontSize: 32, fontWeight: "800", textAlign: "left" },
  meta: { marginBottom: 4, textAlign: "left" },
  card: { flexDirection: "row", gap: 12, padding: 12, borderRadius: 16 },
  thumb: { width: 56, height: 56, borderRadius: 12 },
  cardText: { flex: 1, justifyContent: "center", gap: 6 },
  cardTitle: { fontSize: 16, fontWeight: "600", textAlign: "left" },
  line: { height: 8, borderRadius: 4 },
  lineShort: { width: "60%" },
  group: { gap: 8, marginTop: 8 },
  subheader: { fontSize: 18, fontWeight: "700", textAlign: "left" },
  row: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  button: { borderRadius: 12, paddingHorizontal: 16, paddingVertical: 12 },
  pressed: { opacity: 0.6 },
  buttonText: { color: "#fff", fontWeight: "600", textAlign: "left" },
});
