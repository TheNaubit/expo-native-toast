package expo.modules.nativetoast

import io.github.expo.modules.v2.Event
import io.github.expo.modules.v2.ExpoModule
import io.github.expo.modules.v2.JS
import io.github.expo.modules.v2.Module
import io.github.expo.modules.v2.Record

@Record
data class NativeToastOptions(
  val id: String = "",
  val type: String = "info",
  val title: String,
  val message: String? = null,
  val duration: Int = NativeToastHost.DEFAULT_DURATION_MILLISECONDS,
  val actionLabel: String? = null,
)

@Record
data class NativeToastActionEvent(
  val id: String,
)

@ExpoModule(name = "ExpoNativeToast")
class ExpoNativeToastModule : Module() {
  init {
    // A new instance means JavaScript reloaded. Old toasts point to a closed runtime.
    NativeToastHost.reset()
  }

  @Event
  val onAction = event<NativeToastActionEvent>()

  @JS
  fun show(options: NativeToastOptions) {
    NativeToastHost.show(options) {
      onAction(NativeToastActionEvent(options.id))
    }
  }

  @JS
  fun dismiss() {
    NativeToastHost.dismiss()
  }
}
