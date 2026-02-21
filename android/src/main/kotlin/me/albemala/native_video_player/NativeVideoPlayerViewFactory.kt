package me.albemala.native_video_player

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeVideoPlayerViewFactory(
    private val messenger: BinaryMessenger
) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val id = "native_video_player_view"
    }

    override fun create(
        context: Context?,
        viewId: Int,
        args: Any?
    ): PlatformView {
        // Parse creation arguments to get showNativeControls flag
        @Suppress("UNCHECKED_CAST")
        val showNativeControls = (args as? Map<String, Any>)
            ?.get("showNativeControls") as? Boolean ?: false

        return NativeVideoPlayerViewController(
            messenger,
            viewId,
            context,
            showNativeControls
        )
    }
}
