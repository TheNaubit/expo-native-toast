import ExpoModulesCore
import SwiftUI
import UIKit

@Record
struct NativeToastOptions {
  var id: String = ""
  var type: String = "info"
  var title: String
  var message: String?
  var duration: Int = NativeToastLimits.defaultDurationMilliseconds
  var actionLabel: String?
}

@Record
struct NativeToastActionEvent {
  var id: String
}

@ExpoModule("ExpoNativeToast")
public final class ExpoNativeToastModule: Module {
  @Event
  var onAction: (NativeToastActionEvent) -> Void

  @JS
  func show(options: NativeToastOptions) {
    let event = NativeToastActionEvent(id: options.id)
    let owner = WeakModuleBox(module: self)
    // One serial path keeps show and dismiss in call order.
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        NativeToastPresenter.shared.show(options) {
          owner.module?.onAction(event)
        }
      }
    }
  }

  @JS
  func dismiss() {
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        NativeToastPresenter.shared.dismiss()
      }
    }
  }

  deinit {
    // The module dies when JavaScript reloads. Its action callbacks die with it.
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        NativeToastPresenter.shared.dismiss()
      }
    }
  }
}

/// Holds the module weakly. The module emits events on the main thread only.
private struct WeakModuleBox: @unchecked Sendable {
  weak var module: ExpoNativeToastModule?
}

enum NativeToastLimits {
  static let defaultDurationMilliseconds = 4_000
  static let minimumDurationMilliseconds = 1_000
  static let maximumDurationMilliseconds = 30_000
  /// A toast that waits for the app to return expires after this time.
  static let pendingLifetime: TimeInterval = 30
  /// With VoiceOver, an action toast stays long enough to reach the button.
  static let voiceOverActionDurationMilliseconds = maximumDurationMilliseconds
}

private enum NativeToastKind: String {
  case error
  case warning
  case info
  case success

  init(value: String) {
    self = NativeToastKind(rawValue: value) ?? .info
  }

  var symbol: String {
    switch self {
    case .error: "xmark.octagon.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .info: "info.circle.fill"
    case .success: "checkmark.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .error: .red
    case .warning: .orange
    case .info: .accentColor
    case .success: .green
    }
  }
}

/// Layout values shared by the SwiftUI view and the touch container.
private enum NativeToastLayout {
  /// Space between the top safe area and the toast.
  static let topPadding: CGFloat = 8
  /// Size of the Dynamic Island. The toast grows out of this shape.
  static let islandSize = CGSize(width: 126, height: 37)
  /// Distance from the top of the screen to the Dynamic Island.
  static let islandTop: CGFloat = 11
  /// Extra touch area around the toast.
  static let touchSlop: CGFloat = 8
}

/// Drives the enter and exit animation. The presenter flips `isVisible`.
@MainActor
private final class NativeToastState: ObservableObject {
  @Published var isVisible = false
}

/// A container that passes touches through, except on the toast surface.
///
/// SwiftUI handles gestures in the hosting view. Hit testing cannot tell a button
/// from empty space. The SwiftUI view reports the size of the toast. The toast is
/// centered, so the container derives its position. A transform or an animation on
/// the toast does not change this rect.
private final class NativeToastContainerView: UIView {
  var interactiveSize: CGSize = .zero

  /// The SwiftUI view. It sits below the top safe area (status bar and Dynamic Island).
  var contentView: UIView? {
    didSet { setNeedsLayout() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let top = safeAreaInsets.top
    contentView?.frame = CGRect(
      x: 0,
      y: top,
      width: bounds.width,
      height: max(0, bounds.height - top)
    )
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let offset = contentView?.frame.origin ?? .zero
    let local = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
    let width = contentView?.bounds.width ?? bounds.width
    let toastFrame = CGRect(
      x: (width - interactiveSize.width) / 2,
      y: NativeToastLayout.topPadding,
      width: interactiveSize.width,
      height: interactiveSize.height
    ).insetBy(dx: -NativeToastLayout.touchSlop, dy: -NativeToastLayout.touchSlop)
    guard interactiveSize != .zero, toastFrame.contains(local) else { return nil }
    return super.hitTest(point, with: event)
  }
}

private struct PresentedToast {
  let container: NativeToastContainerView
  let controller: UIViewController
  let state: NativeToastState

  func remove() {
    controller.willMove(toParent: nil)
    container.removeFromSuperview()
    controller.removeFromParent()
  }
}

private struct PendingToast {
  let options: NativeToastOptions
  let onAction: () -> Void
  let createdAt: Date
}

@MainActor
private final class NativeToastPresenter {
  static let shared = NativeToastPresenter()

  /// The exit animation runs in SwiftUI. The view is removed after this time.
  private static let exitDuration: TimeInterval = 0.34

  private var dismissTask: Task<Void, Never>?
  private var presented: PresentedToast?
  private var pending: PendingToast?
  private var activationObserver: NSObjectProtocol?

  func show(_ options: NativeToastOptions, onAction: @escaping () -> Void) {
    guard !options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    guard let scene = activeScene() else {
      queue(PendingToast(options: options, onAction: onAction, createdAt: Date()))
      return
    }

    clearPending()
    guard present(options, onAction: onAction, in: scene) else {
      queue(PendingToast(options: options, onAction: onAction, createdAt: Date()))
      return
    }
  }

  func dismiss() {
    clearPending()
    removePresented(animated: true)
  }

  // MARK: - Pending toast

  private func queue(_ toast: PendingToast) {
    pending = toast
    guard activationObserver == nil else { return }
    activationObserver = NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.showPending() }
    }
  }

  private func showPending() {
    guard let toast = pending, let scene = activeScene() else { return }
    clearPending()
    guard Date().timeIntervalSince(toast.createdAt) < NativeToastLimits.pendingLifetime else {
      return
    }
    _ = present(toast.options, onAction: toast.onAction, in: scene)
  }

  private func clearPending() {
    pending = nil
    if let observer = activationObserver {
      NotificationCenter.default.removeObserver(observer)
      activationObserver = nil
    }
  }

  // MARK: - Presentation

  private func activeScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }

  private func present(
    _ options: NativeToastOptions,
    onAction: @escaping () -> Void,
    in scene: UIWindowScene
  ) -> Bool {
    guard let hostWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    else {
      return false
    }

    removePresented(animated: false)

    let kind = NativeToastKind(value: options.type)
    playHaptic(kind)
    UIAccessibility.post(notification: .announcement, argument: announcement(for: options))

    let container = NativeToastContainerView(frame: hostWindow.bounds)
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.backgroundColor = .clear

    let state = NativeToastState()
    // Distance from the final position back up to the Dynamic Island. Devices without an
    // island slide in from just above the screen edge instead.
    let toTheIsland =
      hostWindow.safeAreaInsets.top + NativeToastLayout.topPadding - NativeToastLayout.islandTop
    let controller = UIHostingController(
      rootView: NativeToastView(
        options: options,
        kind: kind,
        state: state,
        originOffset: -max(toTheIsland, 40),
        onSizeChange: { [weak container] size in
          container?.interactiveSize = size
        },
        onAction: { [weak self] in
          onAction()
          self?.removePresented(animated: true)
        }
      )
    )
    controller.view.backgroundColor = .clear
    controller.view.isOpaque = false
    // The container applies the top safe area. SwiftUI must not add it a second time.
    controller.safeAreaRegions = []
    container.addSubview(controller.view)
    container.contentView = controller.view
    hostWindow.addSubview(container)

    presented = PresentedToast(container: container, controller: controller, state: state)
    let needsMoreTimeForVoiceOver =
      UIAccessibility.isVoiceOverRunning && !(options.actionLabel ?? "").isEmpty
    scheduleDismiss(
      after: needsMoreTimeForVoiceOver
        ? NativeToastLimits.voiceOverActionDurationMilliseconds
        : options.duration
    )
    return true
  }

  private func scheduleDismiss(after milliseconds: Int) {
    let clamped = min(
      max(milliseconds, NativeToastLimits.minimumDurationMilliseconds),
      NativeToastLimits.maximumDurationMilliseconds
    )
    dismissTask?.cancel()
    dismissTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
      guard !Task.isCancelled else { return }
      self?.removePresented(animated: true)
    }
  }

  private func removePresented(animated: Bool) {
    dismissTask?.cancel()
    dismissTask = nil
    guard let current = presented else { return }
    presented = nil

    guard animated else {
      current.remove()
      return
    }

    // The view stays on screen during the exit animation. A second tap on the action
    // button must not send the action event again.
    current.container.isUserInteractionEnabled = false
    current.state.isVisible = false
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.exitDuration) {
      current.remove()
    }
  }

  private func announcement(for options: NativeToastOptions) -> String {
    [options.title, options.message, options.actionLabel]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: ". ")
  }

  private func playHaptic(_ kind: NativeToastKind) {
    switch kind {
    case .success:
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .warning:
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .error:
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .info:
      UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
  }
}

private struct NativeToastView: View {
  let options: NativeToastOptions
  let kind: NativeToastKind
  @ObservedObject var state: NativeToastState
  let originOffset: CGFloat
  let onSizeChange: (CGSize) -> Void
  let onAction: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var measuredSize: CGSize = .zero
  @State private var revealsTitle = false
  @State private var showsContent = false
  @State private var showsAction = false

  private static let cardCornerRadius: CGFloat = 24
  private static let cardMinWidth: CGFloat = 220
  private static let cardMaxWidth: CGFloat = 340
  private static let actionCornerRadius: CGFloat = 10
  private static let capsuleCollapsedScale: CGFloat = 0.55

  private static let enterSpring = Animation.spring(response: 0.5, dampingFraction: 0.74)
  private static let exitSpring = Animation.spring(response: 0.3, dampingFraction: 1)
  private static let enterFade = Animation.easeOut(duration: 0.18)
  private static let exitFade = Animation.easeIn(duration: 0.2)

  var body: some View {
    VStack {
      toastSurface
        .background(
          GeometryReader { proxy in
            Color.clear
              .onAppear { measuredSize = proxy.size; onSizeChange(proxy.size) }
              .onChange(of: proxy.size) { size in measuredSize = size; onSizeChange(size) }
          }
        )
        .opacity(state.isVisible ? 1 : 0)
        .blur(radius: state.isVisible || reduceMotion ? 0 : 8)
        .animation(state.isVisible ? Self.enterFade : Self.exitFade, value: state.isVisible)
        .scaleEffect(
          x: state.isVisible || reduceMotion ? 1 : collapsedScale.width,
          y: state.isVisible || reduceMotion ? 1 : collapsedScale.height,
          anchor: .top
        )
        .offset(y: state.isVisible || reduceMotion ? 0 : originOffset)
        .animation(state.isVisible ? Self.enterSpring : Self.exitSpring, value: state.isVisible)
        .padding(.top, NativeToastLayout.topPadding)
        .padding(.horizontal, 12)
      Spacer()
    }
    .background(Color.clear)
    .onChange(of: state.isVisible) { visible in stageContent(visible) }
    .onAppear {
      // SwiftUI has now rendered the collapsed state. Start the entrance on the next turn,
      // so `isVisible` changes after the first render and the animation runs.
      DispatchQueue.main.async { state.isVisible = true }
    }
  }

  /// The card starts as the shape of the Dynamic Island and grows to its full size.
  private var collapsedScale: CGSize {
    guard options.hasCardContent, measuredSize.width > 0, measuredSize.height > 0 else {
      return CGSize(width: Self.capsuleCollapsedScale, height: Self.capsuleCollapsedScale)
    }
    return CGSize(
      width: min(1, NativeToastLayout.islandSize.width / measuredSize.width),
      height: min(1, NativeToastLayout.islandSize.height / measuredSize.height)
    )
  }

  /// Show the content after the surface starts to grow. The action appears last.
  private func stageContent(_ visible: Bool) {
    if reduceMotion {
      revealsTitle = visible
      showsContent = visible
      showsAction = visible
      return
    }
    if visible {
      withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.2)) {
        revealsTitle = true
      }
      withAnimation(.easeOut(duration: 0.24).delay(0.12)) { showsContent = true }
      withAnimation(.easeOut(duration: 0.24).delay(0.22)) { showsAction = true }
    } else {
      withAnimation(.easeIn(duration: 0.12)) {
        showsContent = false
        showsAction = false
      }
    }
  }

  @ViewBuilder
  private var toastSurface: some View {
    if options.hasCardContent {
      surface(
        cardContent,
        shape: RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
      )
      .frame(minWidth: Self.cardMinWidth, maxWidth: Self.cardMaxWidth)
      .fixedSize(horizontal: true, vertical: false)
    } else {
      surface(capsuleContent, shape: Capsule())
    }
  }

  private func icon(size: CGFloat) -> some View {
    Image(systemName: kind.symbol)
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(kind.tint)
      .accessibilityHidden(true)
  }

  private var capsuleContent: some View {
    HStack(alignment: .center, spacing: revealsTitle ? 8 : 0) {
      icon(size: 16)
      if revealsTitle {
        ViewThatFits(in: .horizontal) {
          Text(options.title)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
          Text(options.title)
            .lineLimit(2)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .transition(.move(edge: .leading).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        icon(size: 20)
        VStack(alignment: .leading, spacing: 2) {
          Text(options.title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
          if let message = options.message, !message.isEmpty {
            Text(message)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(4)
          }
        }
        .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
      }
      .opacity(showsContent ? 1 : 0)
      .blur(radius: showsContent || reduceMotion ? 0 : 4)
      .accessibilityElement(children: .combine)

      if let label = options.actionLabel, !label.isEmpty {
        Button(action: onAction) {
          Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
              Color.primary.opacity(0.12),
              in: RoundedRectangle(cornerRadius: Self.actionCornerRadius, style: .continuous)
            )
            .contentShape(
              RoundedRectangle(cornerRadius: Self.actionCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .opacity(showsAction ? 1 : 0)
        .offset(y: showsAction || reduceMotion ? 0 : 6)
      }
    }
    .padding(12)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func surface<S: InsettableShape>(_ content: some View, shape: S) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular, in: shape)
    } else {
      content
        .background(.regularMaterial, in: shape)
        .overlay {
          shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
  }
}

private extension NativeToastOptions {
  /// A toast with a message or an action uses the card layout.
  var hasCardContent: Bool {
    let hasMessage = !(message ?? "").isEmpty
    let hasAction = !(actionLabel ?? "").isEmpty
    return hasMessage || hasAction
  }
}
