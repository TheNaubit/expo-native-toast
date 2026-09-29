package expo.modules.nativetoast

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.StyleSpan
import android.util.Log
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.snackbar.Snackbar
import java.lang.ref.WeakReference

internal object NativeToastHost : Application.ActivityLifecycleCallbacks {
  const val DEFAULT_DURATION_MILLISECONDS = 4_000
  private const val MIN_DURATION_MILLISECONDS = 1_000
  private const val MAX_DURATION_MILLISECONDS = 30_000
  private const val PENDING_LIFETIME_MILLISECONDS = 30_000L
  private const val DIALOG_FALLBACK_DELAY_MILLISECONDS = 800L
  private const val MESSAGE_MAX_LINES = 5
  private const val ICON_SIZE_DP = 20
  private const val ICON_SPACING_DP = 12
  private const val LOG_TAG = "ExpoNativeToast"

  // Every field below is read and written on the main thread only.
  private val mainHandler = Handler(Looper.getMainLooper())
  private var currentActivity = WeakReference<Activity>(null)
  private var currentSnackbar: WeakReference<Snackbar>? = null
  private var pendingToast: PendingToast? = null
  private var focusWaiter: FocusWaiter? = null

  fun install(context: Context) {
    (context.applicationContext as? Application)?.registerActivityLifecycleCallbacks(this)
  }

  fun show(options: NativeToastOptions, onAction: () -> Unit) {
    if (options.title.isBlank()) return
    runOnMainThread { showOnMainThread(options, onAction) }
  }

  fun dismiss() {
    runOnMainThread {
      pendingToast = null
      clearFocusWaiter()
      currentSnackbar?.get()?.dismiss()
      currentSnackbar = null
    }
  }

  /**
   * Drop all state. A new module instance calls this after a JavaScript reload,
   * because the old instance and its action callbacks are gone.
   */
  fun reset() = dismiss()

  private fun runOnMainThread(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
  }

  private fun showOnMainThread(options: NativeToastOptions, onAction: () -> Unit) {
    val activity = currentActivity.get()
    if (activity == null || !activity.isUsable() || !activity.hasWindowFocus()) {
      val pending = PendingToast(options, onAction, SystemClock.elapsedRealtime())
      pendingToast = pending
      activity?.takeIf { it.isUsable() }?.let { usable ->
        awaitWindowFocus(usable)
        scheduleDialogFallback(usable, pending)
      }
      return
    }

    pendingToast = null
    present(activity, options, onAction)
  }

  /**
   * A resumed activity without window focus usually has a dialog on top, for example a
   * React Native Modal. A Snackbar would sit behind it. Show a system toast instead.
   */
  private fun scheduleDialogFallback(activity: Activity, pending: PendingToast) {
    mainHandler.postDelayed({
      val stillWaiting = pendingToast === pending && currentActivity.get() === activity
      if (!stillWaiting || activity.hasWindowFocus() || !activity.isUsable()) return@postDelayed
      pendingToast = null
      clearFocusWaiter()
      presentFallback(activity, pending.options)
    }, DIALOG_FALLBACK_DELAY_MILLISECONDS)
  }

  private fun Activity.isUsable(): Boolean = !isFinishing && !isDestroyed

  private fun present(activity: Activity, options: NativeToastOptions, onAction: () -> Unit) {
    try {
      val anchor = activity.findViewById<View>(android.R.id.content) ?: return
      currentSnackbar?.get()?.dismiss()
      val kind = NativeToastKind.from(options.type)
      playHaptic(anchor, kind)

      val duration = options.duration.coerceIn(MIN_DURATION_MILLISECONDS, MAX_DURATION_MILLISECONDS)
      val snackbar = Snackbar.make(anchor, buildBody(options), duration)
      findBottomNavigationAnchor(activity.window.decorView)?.let(snackbar::setAnchorView)
      styleMessage(snackbar, kind)
      options.actionLabel?.takeIf(String::isNotBlank)?.let { label ->
        snackbar.setAction(label) { onAction() }
      }
      snackbar.show()
      currentSnackbar = WeakReference(snackbar)
    } catch (error: RuntimeException) {
      // Snackbar throws if the app theme is not a Material theme. Show a plain toast instead.
      Log.w(LOG_TAG, "Snackbar failed. Falling back to a system toast.", error)
      presentFallback(activity, options)
    }
  }

  private fun presentFallback(activity: Activity, options: NativeToastOptions) {
    try {
      val text = listOfNotNull(options.title, options.message?.takeIf(String::isNotBlank))
        .joinToString("\n")
      Toast.makeText(activity.applicationContext, text, Toast.LENGTH_LONG).show()
    } catch (error: RuntimeException) {
      Log.e(LOG_TAG, "The fallback toast failed.", error)
    }
  }

  private fun awaitWindowFocus(activity: Activity) {
    if (activity.hasWindowFocus()) {
      showPending(activity)
      return
    }
    if (focusWaiter != null) return

    val decorView = activity.window.decorView
    val listener = object : ViewTreeObserver.OnWindowFocusChangeListener {
      override fun onWindowFocusChanged(hasFocus: Boolean) {
        if (!hasFocus) return
        clearFocusWaiter()
        showPending(activity)
      }
    }
    focusWaiter = FocusWaiter(activity, WeakReference(decorView), listener)
    decorView.viewTreeObserver.addOnWindowFocusChangeListener(listener)
  }

  private fun clearFocusWaiter() {
    val waiter = focusWaiter ?: return
    focusWaiter = null
    val observer = waiter.decorView.get()?.viewTreeObserver
    if (observer?.isAlive == true) observer.removeOnWindowFocusChangeListener(waiter.listener)
  }

  private fun showPending(activity: Activity) {
    val pending = pendingToast ?: return
    pendingToast = null
    val age = SystemClock.elapsedRealtime() - pending.createdAtMilliseconds
    if (age > PENDING_LIFETIME_MILLISECONDS || !activity.isUsable()) return
    present(activity, pending.options, pending.onAction)
  }

  private fun buildBody(options: NativeToastOptions): CharSequence =
    SpannableStringBuilder(options.title).apply {
      setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
      options.message?.takeIf(String::isNotBlank)?.let { message ->
        append('\n')
        append(message)
      }
    }

  private fun styleMessage(snackbar: Snackbar, kind: NativeToastKind) {
    val messageView = snackbar.view.findViewById<TextView>(
      com.google.android.material.R.id.snackbar_text,
    ) ?: return
    messageView.maxLines = MESSAGE_MAX_LINES
    messageView.ellipsize = TextUtils.TruncateAt.END
    val icon = ContextCompat.getDrawable(messageView.context, kind.iconResource)?.mutate() ?: return
    DrawableCompat.setTint(icon, ContextCompat.getColor(messageView.context, kind.tintResource))

    val density = messageView.resources.displayMetrics.density
    val iconSize = (ICON_SIZE_DP * density).toInt()
    icon.setBounds(0, 0, iconSize, iconSize)
    messageView.compoundDrawablePadding = (ICON_SPACING_DP * density).toInt()
    messageView.setCompoundDrawablesRelative(icon, null, null, null)
  }

  private fun findBottomNavigationAnchor(root: View): View? {
    val itemContent = root.findViewById<View>(
      com.google.android.material.R.id.navigation_bar_item_content_container,
    )
    val item = itemContent?.parent as? View
    val navigationBar = item?.parent as? View
    if (navigationBar is BottomNavigationView && navigationBar.isShown) return navigationBar

    return findVisibleNavigationBar(root)
  }

  private fun findVisibleNavigationBar(view: View): BottomNavigationView? {
    if (view is BottomNavigationView && view.isShown) return view
    if (view !is ViewGroup) return null

    for (index in 0 until view.childCount) {
      findVisibleNavigationBar(view.getChildAt(index))?.let { return it }
    }
    return null
  }

  private fun playHaptic(view: View, kind: NativeToastKind) {
    val feedback = when (kind) {
      NativeToastKind.SUCCESS -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        HapticFeedbackConstants.CONFIRM
      } else {
        HapticFeedbackConstants.VIRTUAL_KEY
      }
      NativeToastKind.ERROR -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        HapticFeedbackConstants.REJECT
      } else {
        HapticFeedbackConstants.LONG_PRESS
      }
      NativeToastKind.WARNING -> HapticFeedbackConstants.LONG_PRESS
      NativeToastKind.INFO -> HapticFeedbackConstants.CLOCK_TICK
    }
    view.performHapticFeedback(feedback)
  }

  override fun onActivityResumed(activity: Activity) {
    currentActivity = WeakReference(activity)
    if (pendingToast != null) awaitWindowFocus(activity)
  }

  override fun onActivityPaused(activity: Activity) {
    if (focusWaiter?.activity === activity) clearFocusWaiter()
    if (currentActivity.get() === activity) currentActivity.clear()
  }

  override fun onActivityDestroyed(activity: Activity) {
    if (focusWaiter?.activity === activity) clearFocusWaiter()
    if (currentActivity.get() === activity) currentActivity.clear()
  }

  override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
  override fun onActivityStarted(activity: Activity) = Unit
  override fun onActivityStopped(activity: Activity) = Unit
  override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
}

private data class PendingToast(
  val options: NativeToastOptions,
  val onAction: () -> Unit,
  val createdAtMilliseconds: Long,
)

private class FocusWaiter(
  val activity: Activity,
  val decorView: WeakReference<View>,
  val listener: ViewTreeObserver.OnWindowFocusChangeListener,
)

private enum class NativeToastKind(
  @param:DrawableRes val iconResource: Int,
  @param:ColorRes val tintResource: Int,
) {
  ERROR(R.drawable.ic_native_toast_error, R.color.native_toast_error_icon),
  INFO(R.drawable.ic_native_toast_info, R.color.native_toast_info_icon),
  SUCCESS(R.drawable.ic_native_toast_success, R.color.native_toast_success_icon),
  WARNING(R.drawable.ic_native_toast_warning, R.color.native_toast_warning_icon),
  ;

  companion object {
    fun from(value: String): NativeToastKind = entries.find {
      it.name.equals(value, ignoreCase = true)
    } ?: INFO
  }
}
