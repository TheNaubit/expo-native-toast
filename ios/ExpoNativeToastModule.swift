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

/// A container that passes touches through, except on the toast surface.
///
/// SwiftUI handles gestures in the hosting view. Hit testing cannot tell a button
/// from empty space. The SwiftUI view reports the frame of the toast instead.
private final class NativeToastContainerView: UIView {
  var interactiveFrame: CGRect = .zero

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
    // `interactiveFrame` is in the coordinate space of the SwiftUI view. Convert the point.
    let offset = contentView?.frame.origin ?? .zero
    let local = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
    guard interactiveFrame.contains(local) else { return nil }
    return super.hitTest(point, with: event)
  }
}

private struct PresentedToast {
  let container: NativeToastContainerView
  let controller: UIViewController

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

  private static let enterDuration: TimeInterval = 0.34
  private static let exitDuration: TimeInterval = 0.2
  private static let enterOffset: CGFloat = -16

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

    let controller = UIHostingController(
      rootView: NativeToastView(
        options: options,
        kind: kind,
        onFrameChange: { [weak container] frame in
          container?.interactiveFrame = frame.insetBy(dx: -8, dy: -8)
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

    let animatesMotion = !UIAccessibility.isReduceMotionEnabled
    container.alpha = 0
    if animatesMotion {
      container.transform = CGAffineTransform(translationX: 0, y: Self.enterOffset)
    }
    UIView.animate(
      withDuration: Self.enterDuration,
      delay: 0,
      usingSpringWithDamping: 1,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction]
    ) {
      container.alpha = 1
      container.transform = .identity
    }

    presented = PresentedToast(container: container, controller: controller)
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

    UIView.animate(
      withDuration: Self.exitDuration,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseIn]
    ) {
      current.container.alpha = 0
    } completion: { _ in
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
  let onFrameChange: (CGRect) -> Void
  let onAction: () -> Void

  @State private var revealsTitle: Bool

  private static let coordinateSpaceName = "NativeToastRoot"
  private static let cardCornerRadius: CGFloat = 26
  private static let cardMaxWidth: CGFloat = 480

  init(
    options: NativeToastOptions,
    kind: NativeToastKind,
    onFrameChange: @escaping (CGRect) -> Void,
    onAction: @escaping () -> Void
  ) {
    self.options = options
    self.kind = kind
    self.onFrameChange = onFrameChange
    self.onAction = onAction
    // A card shows all content at once. Only the compact capsule reveals its title.
    _revealsTitle = State(initialValue: options.hasCardContent)
  }

  var body: some View {
    VStack {
      toastSurface
        .background(
          GeometryReader { proxy in
            Color.clear
              .onAppear { reportFrame(proxy) }
              .onChange(of: proxy.size) { _ in reportFrame(proxy) }
          }
        )
        .padding(.top, 8)
        .padding(.horizontal, 12)
      Spacer()
    }
    .background(Color.clear)
    .coordinateSpace(name: Self.coordinateSpaceName)
    .onAppear {
      guard !revealsTitle else { return }
      withAnimation(.spring(response: 0.34, dampingFraction: 0.9).delay(0.12)) {
        revealsTitle = true
      }
    }
  }

  private func reportFrame(_ proxy: GeometryProxy) {
    let frame = proxy.frame(in: .named(Self.coordinateSpaceName))
    onFrameChange(frame)
  }

  @ViewBuilder
  private var toastSurface: some View {
    if options.hasCardContent {
      surface(cardContent, shape: RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        .frame(maxWidth: Self.cardMaxWidth)
    } else {
      surface(capsuleContent, shape: Capsule())
    }
  }

  private var icon: some View {
    Image(systemName: kind.symbol)
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(kind.tint)
      .accessibilityHidden(true)
  }

  private var capsuleContent: some View {
    HStack(alignment: .center, spacing: revealsTitle ? 8 : 0) {
      icon
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
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        icon
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 2) {
          Text(options.title)
            .font(.subheadline.weight(.semibold))
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
      .accessibilityElement(children: .combine)

      if let label = options.actionLabel, !label.isEmpty {
        Button(action: onAction) {
          Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 12)
            .background(
              Color.primary.opacity(0.12),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
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
