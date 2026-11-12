package __PACKAGE__;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.content.res.AssetFileDescriptor;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayDeque;
import java.util.Locale;

/**
 * Foreground service that rings an alarm or timer: loops the sound on the ALARM audio stream (so it follows the
 * phone's alarm volume and is allowed through Do Not Disturb), vibrates, and posts a full-screen-intent
 * notification that opens the app over the lock screen. Snooze / Dismiss come from the notification buttons or the app.
 */
public class RingService extends Service {
    static final String ACTION_START = "owl.START";
    static final String ACTION_SNOOZE = "owl.SNOOZE";
    static final String ACTION_DISMISS = "owl.DISMISS";
    private static final String CHANNEL = "owl_ring";
    private static final int NOTIF_ID = 4242;

    /** The item that is ringing right now (null when quiet). Read by the plugin when the app opens. */
    static volatile JSONObject current;

    private final ArrayDeque<JSONObject> queue = new ArrayDeque<JSONObject>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private MediaPlayer player;
    private PowerManager.WakeLock wakeLock;
    private Runnable silenceTask;
    private Runnable rampTask;

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_START.equals(action)) {
            JSONObject it = null;
            try { it = new JSONObject(intent.getStringExtra("item")); } catch (Exception ignored) { }
            // Must go foreground right away after startForegroundService().
            goForeground(notificationFor(current != null ? current : it));
            if (it == null) { if (current == null) endService(); return START_NOT_STICKY; }
            AlarmScheduler.addEvent(this, "fired", it, it.optLong("at"), it.optInt("count"));
            if (current != null) {
                if (!it.optString("key").equals(current.optString("key"))) queue.add(it);
            } else {
                beginRing(it);
            }
        } else if (ACTION_SNOOZE.equals(action)) {
            snoozeCurrent();
        } else if (ACTION_DISMISS.equals(action)) {
            finish("dismiss");
        } else if (current == null) {
            endService();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        stopFeedback();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        current = null;
        super.onDestroy();
    }

    // ---------------------------------------------------------------- ringing

    private void beginRing(JSONObject it) {
        current = it;
        goForeground(notificationFor(it));
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (wakeLock == null) {
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "owl:ring");
            wakeLock.setReferenceCounted(false);
        }
        wakeLock.acquire(30 * 60 * 1000L);
        startSound(it);
        if (it.optBoolean("vibrate", true)) startVibration();
        int silence = it.optInt("silence", 0);
        if (silence > 0) {
            silenceTask = new Runnable() { @Override public void run() { finish("silenced"); } };
            handler.postDelayed(silenceTask, silence * 60000L);
        }
        OwlAlarmPlugin.emitRing(it, true);
    }

    private void finish(String type) {
        JSONObject it = current;
        if (it == null) { endService(); return; }
        if (!"snooze".equals(type)) AlarmScheduler.addEvent(this, type, it, 0, it.optInt("count"));
        if ("silenced".equals(type)) postMissed(it);
        stopFeedback();
        current = null;
        OwlAlarmPlugin.emitRing(null, false);
        JSONObject next = queue.poll();
        if (next != null) beginRing(next); else endService();
    }

    private void snoozeCurrent() {
        JSONObject it = current;
        if (it == null) { endService(); return; }
        if (!canSnooze(it)) { finish("dismiss"); return; }
        try {
            JSONObject s = new JSONObject(it.toString());
            long at = System.currentTimeMillis() + it.optInt("snoozeMin", 10) * 60000L;
            int count = it.optInt("count", 0) + 1;
            s.put("key", "s" + it.optLong("aid"));
            s.put("at", at);
            s.put("count", count);
            s.put("days", new JSONArray());
            AlarmScheduler.addItem(this, s);
            AlarmScheduler.addEvent(this, "snooze", s, at, count);
        } catch (Exception ignored) { }
        finish("snooze");
    }

    static boolean canSnooze(JSONObject it) {
        int limit = it.optInt("snoozeLimit", 0);
        return "alarm".equals(it.optString("kind")) && it.optBoolean("snooze", false)
                && (limit == 0 || it.optInt("count", 0) < limit);
    }

    private void endService() {
        stopFeedback();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        if (Build.VERSION.SDK_INT >= 24) stopForeground(Service.STOP_FOREGROUND_REMOVE);
        else stopForeground(true);
        stopSelf();
    }

    // ---------------------------------------------------------------- sound & vibration

    private static String slug(String s) {
        return s.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", "_").replaceAll("^_+|_+$", "");
    }

    private void startSound(JSONObject it) {
        try {
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            // An alarm that is muted at the system level is useless: lift the alarm volume to 60% if it is at 0.
            if (am.getStreamVolume(AudioManager.STREAM_ALARM) == 0) {
                int max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM);
                am.setStreamVolume(AudioManager.STREAM_ALARM, Math.max(1, max * 6 / 10), 0);
            }
            int res = getResources().getIdentifier("owl_" + slug(it.optString("sound", "classic beep")), "raw", getPackageName());
            if (res == 0) res = getResources().getIdentifier("owl_classic_beep", "raw", getPackageName());
            if (res == 0) return;
            player = new MediaPlayer();
            AssetFileDescriptor afd = getResources().openRawResourceFd(res);
            player.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
            afd.close();
            player.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
            player.setLooping(true);
            player.prepare();
            final float target = (float) Math.pow(Math.max(0, Math.min(100, it.optInt("volume", 80))) / 100.0, 1.5);
            final long rampMs = it.optInt("gradual", 0) * 1000L;
            if (rampMs > 0) {
                final long t0 = System.currentTimeMillis();
                player.setVolume(Math.min(0.02f, target), Math.min(0.02f, target));
                rampTask = new Runnable() {
                    @Override public void run() {
                        MediaPlayer p = player;
                        if (p == null) return;
                        float f = Math.min(1f, (System.currentTimeMillis() - t0) / (float) rampMs);
                        float v = Math.max(Math.min(0.02f, target), target * f);
                        try { p.setVolume(v, v); } catch (Exception ignored) { return; }
                        if (f < 1f) handler.postDelayed(this, 200);
                    }
                };
                handler.postDelayed(rampTask, 200);
            } else {
                player.setVolume(target, target);
            }
            player.start();
        } catch (Exception e) {
            releasePlayer();
        }
    }

    @SuppressWarnings("deprecation")
    private void startVibration() {
        try {
            Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
            if (v == null) return;
            long[] pattern = {0, 500, 250, 500, 750};
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0),
                        new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build());
            } else {
                v.vibrate(pattern, 0);
            }
        } catch (Exception ignored) { }
    }

    private void releasePlayer() {
        if (player != null) {
            try { player.stop(); } catch (Exception ignored) { }
            try { player.release(); } catch (Exception ignored) { }
            player = null;
        }
    }

    private void stopFeedback() {
        if (silenceTask != null) { handler.removeCallbacks(silenceTask); silenceTask = null; }
        if (rampTask != null) { handler.removeCallbacks(rampTask); rampTask = null; }
        releasePlayer();
        try {
            Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
            if (v != null) v.cancel();
        } catch (Exception ignored) { }
    }

    // ---------------------------------------------------------------- notifications

    private void goForeground(Notification n) {
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        else startForeground(NOTIF_ID, n);
    }

    private Notification.Builder builder() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            NotificationChannel ch = new NotificationChannel(CHANNEL, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH);
            ch.setSound(null, null);
            ch.enableVibration(false);
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(ch);
            return new Notification.Builder(this, CHANNEL);
        }
        return new Notification.Builder(this);
    }

    private int smallIcon() {
        int r = getResources().getIdentifier("ic_stat_owl", "drawable", getPackageName());
        return r != 0 ? r : getApplicationInfo().icon;
    }

    private PendingIntent openApp() {
        Intent open = new Intent(this, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(this, 1, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private PendingIntent action(String act, int code) {
        Intent i = new Intent(this, RingService.class);
        i.setAction(act);
        return PendingIntent.getService(this, code, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    @SuppressWarnings("deprecation")
    private Notification notificationFor(JSONObject it) {
        boolean timer = it != null && "timer".equals(it.optString("kind"));
        String title = it == null ? "Alarm" : timer ? "Timer finished" : (it.optString("label").length() > 0 ? it.optString("label") : "Alarm");
        String text = it == null ? "" : it.optString("timeText");
        PendingIntent full = openApp();
        Notification.Builder b = builder();
        b.setSmallIcon(smallIcon())
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(Notification.CATEGORY_ALARM)
                .setPriority(Notification.PRIORITY_MAX)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(full)
                .setFullScreenIntent(full, true);
        if (it != null && canSnooze(it)) b.addAction(0, "Snooze", action(ACTION_SNOOZE, 2));
        b.addAction(0, timer ? "Stop" : "Dismiss", action(ACTION_DISMISS, 3));
        return b.build();
    }

    private void postMissed(JSONObject it) {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            Notification.Builder b = builder();
            String label = it.optString("label");
            b.setSmallIcon(smallIcon())
                    .setContentTitle("Missed alarm")
                    .setContentText((label.length() > 0 ? label + " · " : "") + it.optString("timeText"))
                    .setAutoCancel(true)
                    .setContentIntent(openApp());
            nm.notify(NOTIF_ID + 1, b.build());
        } catch (Exception ignored) { }
    }
}
