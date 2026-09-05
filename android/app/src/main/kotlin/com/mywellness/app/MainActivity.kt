package com.mywellness.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one Activity. Its only addition over the Flutter default is the channel
 * [WorkoutNotificationService] rides on — see the class doc there for the whole picture.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.mywellness.app/workout_notification"

        /**
         * The route back to the Dart isolate that owns `AppState`, for whichever
         * [WorkoutNotificationService] instance is currently running. Null whenever no engine is
         * attached — the app swiped away in Recents, say — which is exactly the moment a
         * notification tap must not guess at what Dart would have done: see
         * [WorkoutNotificationService.forward].
         */
        var workoutChannel: MethodChannel? = null
            private set
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart owns every decision about what the notification says; this only ever
                // repaints it with what it is handed, or takes it down.
                "show" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    WorkoutNotificationService.show(applicationContext, args)
                    result.success(null)
                }
                "cancel" -> {
                    WorkoutNotificationService.cancel(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        workoutChannel = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        workoutChannel?.setMethodCallHandler(null)
        workoutChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
