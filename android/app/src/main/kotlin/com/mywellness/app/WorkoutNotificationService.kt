package com.mywellness.app

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * The ongoing, quick-action notification for an active workout.
 *
 * A dumb remote, on purpose: `AppState` lives in exactly one place, the Flutter isolate that
 * [MainActivity] holds a channel to, and this class never reads or writes it. It only draws
 * whatever `WorkoutNotification.sync` (lib/platform/workout_notification.dart) last sent over
 * `show`, and forwards a button tap or a body tap back over the same channel as `minus` /
 * `plus` / `done` / `swap`. Every `PendingIntent` here targets this service, never an Activity —
 * that is what lets a tap register with the phone still locked.
 *
 * If the channel is gone when a tap arrives — the app was swiped away in Recents, so its
 * `FlutterEngine` died with the Activity — [forward] does not guess at what Dart would have
 * done. It cancels the notification and stops. The workout itself is untouched: `ActiveWorkout`
 * was already durable in `AppState` before this notification ever existed, and reopening the app
 * picks it up exactly where the last real write left it (`WorkoutNotification.sync` redraws the
 * notification from there too, if the session and the Settings toggle are still both live).
 */
class WorkoutNotificationService : Service() {
    companion object {
        private const val CHANNEL_ID = "workout_quick_log"
        private const val NOTIF_ID = 8200

        private const val ACTION_SHOW = "com.mywellness.app.workout.SHOW"
        private const val ACTION_CANCEL = "com.mywellness.app.workout.CANCEL"
        private const val ACTION_MINUS = "com.mywellness.app.workout.MINUS"
        private const val ACTION_PLUS = "com.mywellness.app.workout.PLUS"
        private const val ACTION_DONE = "com.mywellness.app.workout.DONE"
        private const val ACTION_SWAP = "com.mywellness.app.workout.SWAP"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val EXTRA_SUB = "sub"
        private const val EXTRA_MINUS_LABEL = "minusLabel"
        private const val EXTRA_PLUS_LABEL = "plusLabel"
        private const val EXTRA_DONE_LABEL = "doneLabel"
        private const val EXTRA_REST_ENDS_AT = "restEndsAt"

        /** Draws or redraws the notification from the model Dart just sent over `show`. */
        fun show(context: Context, data: Map<String, Any?>) {
            val intent = Intent(context, WorkoutNotificationService::class.java).apply {
                action = ACTION_SHOW
                putExtra(EXTRA_TITLE, data[EXTRA_TITLE] as? String ?: "")
                putExtra(EXTRA_BODY, data[EXTRA_BODY] as? String ?: "")
                putExtra(EXTRA_SUB, data[EXTRA_SUB] as? String ?: "")
                putExtra(EXTRA_MINUS_LABEL, data[EXTRA_MINUS_LABEL] as? String ?: "")
                putExtra(EXTRA_PLUS_LABEL, data[EXTRA_PLUS_LABEL] as? String ?: "")
                putExtra(EXTRA_DONE_LABEL, data[EXTRA_DONE_LABEL] as? String ?: "")
                putExtra(EXTRA_REST_ENDS_AT, (data[EXTRA_REST_ENDS_AT] as? Number)?.toLong() ?: -1L)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        /** Takes the notification down — the workout finished, was discarded, or the Settings
         * toggle was switched off. */
        fun cancel(context: Context) {
            context.startService(
                Intent(context, WorkoutNotificationService::class.java).setAction(ACTION_CANCEL))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> startForeground(NOTIF_ID, buildNotification(intent))
            ACTION_CANCEL -> stop()
            ACTION_MINUS -> forward("minus")
            ACTION_PLUS -> forward("plus")
            ACTION_DONE -> forward("done")
            ACTION_SWAP -> forward("swap")
        }
        return START_NOT_STICKY
    }

    /** Relays a tap to Dart, or fails closed — see the class doc. */
    private fun forward(method: String) {
        val channel = MainActivity.workoutChannel
        if (channel == null) {
            stop()
            return
        }
        // onStartCommand already runs on the main thread, same as it would for an Activity.
        channel.invokeMethod(method, null)
    }

    private fun stop() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun ensureChannel() {
        val manager = NotificationManagerCompat.from(this)
        if (manager.getNotificationChannelCompat(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName("Workout quick actions")
                .setDescription("The ongoing notification during a workout, with buttons to log a set.")
                .setShowBadge(false)
                .build())
    }

    /** One [PendingIntent] per action, all targeting this same service — see the class doc on
     * why none of them may target an Activity. */
    private fun actionIntent(action: String): PendingIntent {
        val intent = Intent(this, WorkoutNotificationService::class.java).setAction(action)
        return PendingIntent.getService(
            this, action.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun buildNotification(intent: Intent): Notification {
        ensureChannel()

        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        val sub = intent.getStringExtra(EXTRA_SUB) ?: ""
        val minusLabel = intent.getStringExtra(EXTRA_MINUS_LABEL) ?: ""
        val plusLabel = intent.getStringExtra(EXTRA_PLUS_LABEL) ?: ""
        val doneLabel = intent.getStringExtra(EXTRA_DONE_LABEL) ?: ""
        val restEndsAt = intent.getLongExtra(EXTRA_REST_ENDS_AT, -1L)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(if (sub.isEmpty()) body else "$body — $sub")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // The whole-notification tap swaps the quick-action column (reps <-> weight) rather
            // than opening the app — the one tap on this notification that is not a button still
            // has to work with the phone locked.
            .setContentIntent(actionIntent(ACTION_SWAP))

        if (minusLabel.isNotEmpty()) builder.addAction(0, minusLabel, actionIntent(ACTION_MINUS))
        if (plusLabel.isNotEmpty()) builder.addAction(0, plusLabel, actionIntent(ACTION_PLUS))
        if (doneLabel.isNotEmpty()) builder.addAction(0, doneLabel, actionIntent(ACTION_DONE))

        // The system draws the countdown itself from `restEndsAt` onward — nothing has to keep
        // pushing a redraw once a second while resting.
        if (restEndsAt > 0) {
            builder.setUsesChronometer(true)
                .setChronometerCountDown(true)
                .setWhen(restEndsAt)
        }

        return builder.build()
    }
}
