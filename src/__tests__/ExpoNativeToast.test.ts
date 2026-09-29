type Listener = (event: { id: string }) => void;

type FakeNativeModule = {
  addListener: jest.Mock;
  dismiss: jest.Mock;
  show: jest.Mock;
  emit: (event: { id: string }) => void;
  removeSpy: jest.Mock;
};

function createFakeNativeModule(): FakeNativeModule {
  const listeners = new Set<Listener>();
  const removeSpy = jest.fn();
  return {
    show: jest.fn(),
    dismiss: jest.fn(),
    removeSpy,
    addListener: jest.fn((_name: string, listener: Listener) => {
      listeners.add(listener);
      return {
        remove: () => {
          removeSpy();
          listeners.delete(listener);
        },
      };
    }),
    emit: (event) => listeners.forEach((listener) => listener(event)),
  };
}

let mockPlatform: "android" | "ios" = "android";
let mockOptionalModule: unknown = null;

jest.mock("expo", () => ({
  NativeModule: class {},
  requireOptionalNativeModule: jest.fn(() => mockOptionalModule),
}));

jest.mock("react-native", () => ({
  Platform: {
    get OS() {
      return mockPlatform;
    },
  },
}));

function loadApi(): typeof import("../index") {
  let api: typeof import("../index") | undefined;
  jest.isolateModules(() => {
    api = require("../index");
  });
  return api as typeof import("../index");
}

function installAndroidModule(): FakeNativeModule {
  const nativeModule = createFakeNativeModule();
  globalThis.expoV2 = { modules: { ExpoNativeToast: nativeModule as never } };
  return nativeModule;
}

describe("ExpoNativeToast", () => {
  let warnSpy: jest.SpyInstance;

  beforeEach(() => {
    warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
    mockPlatform = "android";
    mockOptionalModule = null;
    globalThis.expoV2 = undefined;
  });

  afterEach(() => {
    warnSpy.mockRestore();
    delete (globalThis as { __DEV__?: boolean }).__DEV__;
  });

  describe("availability", () => {
    it("resolves an Android v2 module that installs after JavaScript imports", () => {
      const api = loadApi();
      expect(api.isAvailable()).toBe(false);
      installAndroidModule();
      expect(api.isAvailable()).toBe(true);
    });

    it("resolves the iOS module lazily", () => {
      mockPlatform = "ios";
      const api = loadApi();
      expect(api.isAvailable()).toBe(false);
      mockOptionalModule = createFakeNativeModule();
      expect(api.isAvailable()).toBe(true);
    });
  });

  describe("show", () => {
    it("sends normalized options and returns the toast id", () => {
      const nativeModule = installAndroidModule();
      const api = loadApi();
      const id = api.show({ id: "a", title: "  Saved ", type: "success" });
      expect(id).toBe("a");
      expect(nativeModule.show).toHaveBeenCalledWith({
        id: "a",
        title: "Saved",
        type: "success",
        duration: expect.any(Number),
      });
    });

    it("returns null and does nothing when the module is unavailable", () => {
      const api = loadApi();
      expect(api.show({ title: "Saved", type: "success" })).toBeNull();
    });

    it("returns null and skips native for an invalid title", () => {
      const nativeModule = installAndroidModule();
      const api = loadApi();
      expect(api.show({ title: "  ", type: "info" })).toBeNull();
      expect(nativeModule.show).not.toHaveBeenCalled();
    });

    it("warns in development when native fails and stays silent otherwise", () => {
      const nativeModule = installAndroidModule();
      nativeModule.show.mockImplementation(() => {
        throw new Error("native crash");
      });
      const api = loadApi();
      api.show({ title: "Saved" });
      expect(warnSpy).not.toHaveBeenCalled();
      (globalThis as { __DEV__?: boolean }).__DEV__ = true;
      api.show({ title: "Saved" });
      api.show({ title: "" });
      expect(warnSpy).toHaveBeenCalledTimes(2);
    });

    it("never throws when the native call throws", () => {
      const nativeModule = installAndroidModule();
      nativeModule.show.mockImplementation(() => {
        throw new Error("native crash");
      });
      const api = loadApi();
      expect(() => api.show({ title: "Saved" })).not.toThrow();
      expect(api.show({ title: "Saved" })).toBeNull();
    });
  });

  describe("dismiss", () => {
    it("calls native dismiss", () => {
      const nativeModule = installAndroidModule();
      loadApi().dismiss();
      expect(nativeModule.dismiss).toHaveBeenCalledTimes(1);
    });

    it("never throws when unavailable or when native throws", () => {
      const api = loadApi();
      expect(() => api.dismiss()).not.toThrow();
      const nativeModule = installAndroidModule();
      nativeModule.dismiss.mockImplementation(() => {
        throw new Error("boom");
      });
      expect(() => api.dismiss()).not.toThrow();
    });
  });

  describe("addActionListener", () => {
    it("delivers native action events to every listener", () => {
      const nativeModule = installAndroidModule();
      const api = loadApi();
      const first = jest.fn();
      const second = jest.fn();
      api.addActionListener(first);
      api.addActionListener(second);
      nativeModule.emit({ id: "x" });
      expect(first).toHaveBeenCalledWith({ id: "x" });
      expect(second).toHaveBeenCalledWith({ id: "x" });
      expect(nativeModule.addListener).toHaveBeenCalledTimes(1);
    });

    it("attaches a listener registered before the native module installs", () => {
      const api = loadApi();
      const listener = jest.fn();
      api.addActionListener(listener);
      const nativeModule = installAndroidModule();
      api.show({ id: "late", title: "Hi", actionLabel: "Undo" });
      nativeModule.emit({ id: "late" });
      expect(listener).toHaveBeenCalledWith({ id: "late" });
    });

    it("stops delivering after remove and detaches native when empty", () => {
      const nativeModule = installAndroidModule();
      const api = loadApi();
      const listener = jest.fn();
      const subscription = api.addActionListener(listener);
      subscription.remove();
      subscription.remove();
      nativeModule.emit({ id: "x" });
      expect(listener).not.toHaveBeenCalled();
      expect(nativeModule.removeSpy).toHaveBeenCalledTimes(1);
    });

    it("isolates a throwing listener from the others", () => {
      const nativeModule = installAndroidModule();
      const api = loadApi();
      const good = jest.fn();
      api.addActionListener(() => {
        throw new Error("listener bug");
      });
      api.addActionListener(good);
      expect(() => nativeModule.emit({ id: "x" })).not.toThrow();
      expect(good).toHaveBeenCalled();
    });

    it("returns an inert subscription when the module never installs", () => {
      const api = loadApi();
      const subscription = api.addActionListener(jest.fn());
      expect(() => subscription.remove()).not.toThrow();
    });
  });

  describe("onToastAction", () => {
    it("only fires for the matching toast id", () => {
      const nativeModule = installAndroidModule();
      const api = loadApi();
      const handler = jest.fn();
      api.onToastAction("mine", handler);
      nativeModule.emit({ id: "other" });
      nativeModule.emit({ id: "mine" });
      expect(handler).toHaveBeenCalledTimes(1);
    });
  });
});
