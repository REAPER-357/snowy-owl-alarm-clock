package __PACKAGE__;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.KeyguardManager;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import androidx.activity.result.ActivityResult;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.OutputStream;
import org.json.JSONException;
import org.json.JSONObject;

/** Bridge between the web app and the native alarm engine (AlarmScheduler + RingService). */
@CapacitorPlugin(name = "OwlAlarm")
public class OwlAlarmPlugin extends Plugin {
    private static OwlAlarmPlugin instance;

    @Override
    public void load() { instance = this; }

    @Override
    protected void handleOnDestroy() { if (instance == this) instance = null; }

    // ---- state pushed to the web layer ----

    static JSObject ringPayload(JSONObject it, boolean ringing) {
        JSObject o = new JSObject();
        o.put("ringing", ringing);
        if (it != null) {
            JSObject item;
            try { item = new JSObject(it.toString()); } catch (JSONException e) { item = new JSObject(); }
            item.put("canSnooze", RingService.canSnooze(it));
            o.put("item", item);
        }
        return o;
    }

    /** Called by RingService when ringing starts or stops. Silently ignored if the web view is not running. */
    static void emitRing(JSONObject it, boolean ringing) {
        final OwlAlarmPlugin p = instance;
        if (p == null) return;
        final JSObject payload = ringPayload(it, ringing);
        new Handler(Looper.getMainLooper()).post(new Runnable() {
            @Override public void run() {
                try { p.notifyListeners("ringState", payload, true); } catch (Exception ignored) { }
            }
        });
    }

    // ---- methods called from JavaScript ----

    @PluginMethod
    public void sync(PluginCall call) {
        JSArray items = call.getArray("items", new JSArray());
        AlarmScheduler.replaceAll(getContext(), items);
        call.resolve();
    }

    @PluginMethod
    public void takeEvents(PluginCall call) {
        JSObject r = new JSObject();
        r.put("events", AlarmScheduler.takeEvents(getContext()));
        call.resolve(r);
    }

    @PluginMethod
    public void getRinging(PluginCall call) {
        JSONObject cur = RingService.current;
        call.resolve(ringPayload(cur, cur != null));
    }

    @PluginMethod
    public void snooze(PluginCall call) {
        sendToService(RingService.ACTION_SNOOZE);
        call.resolve();
    }

    @PluginMethod
    public void dismiss(PluginCall call) {
        sendToService(RingService.ACTION_DISMISS);
        call.resolve();
    }

    private void sendToService(String action) {
        Intent i = new Intent(getContext(), RingService.class);
        i.setAction(action);
        getContext().startService(i);
    }

    /** After dismissing/snoozing over the lock screen: send the app to the back so the lock screen shows again. */
    @PluginMethod
    public void closeIfLocked(PluginCall call) {
        KeyguardManager km = (KeyguardManager) getContext().getSystemService(Context.KEYGUARD_SERVICE);
        final boolean locked = km != null && km.isKeyguardLocked();
        if (locked && getActivity() != null) {
            getActivity().runOnUiThread(new Runnable() {
                @Override public void run() { getActivity().moveTaskToBack(true); }
            });
        }
        JSObject r = new JSObject();
        r.put("closed", locked);
        call.resolve(r);
    }

    /** Backup export: opens Android's "save as" screen and writes the text to the file the person picks. */
    @PluginMethod
    public void saveFile(PluginCall call) {
        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType(call.getString("mime", "application/json"));
        i.putExtra(Intent.EXTRA_TITLE, call.getString("name", "snowy_owl_backup.json"));
        startActivityForResult(call, i, "saveFileResult");
    }

    @ActivityCallback
    private void saveFileResult(PluginCall call, ActivityResult result) {
        if (call == null) return;
        if (result.getResultCode() != Activity.RESULT_OK || result.getData() == null || result.getData().getData() == null) {
            call.reject("cancelled");
            return;
        }
        try {
            OutputStream os = getContext().getContentResolver().openOutputStream(result.getData().getData(), "wt");
            if (os == null) { call.reject("write failed"); return; }
            try { os.write(call.getString("data", "").getBytes("UTF-8")); } finally { os.close(); }
            call.resolve();
        } catch (Exception e) {
            call.reject("write failed");
        }
    }

    /** Share plain text (the alarm rows) through Android's share sheet. */
    @PluginMethod
    public void shareText(PluginCall call) {
        try {
            Intent s = new Intent(Intent.ACTION_SEND);
            s.setType("text/plain");
            s.putExtra(Intent.EXTRA_SUBJECT, call.getString("title", ""));
            s.putExtra(Intent.EXTRA_TEXT, call.getString("text", ""));
            Intent chooser = Intent.createChooser(s, call.getString("title", "Share"));
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(chooser);
            call.resolve();
        } catch (Exception e) {
            call.reject("share failed");
        }
    }

    @PluginMethod
    public void status(PluginCall call) {
        Context c = getContext();
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        PowerManager pm = (PowerManager) c.getSystemService(Context.POWER_SERVICE);
        JSObject r = new JSObject();
        r.put("notif", nm.areNotificationsEnabled());
        r.put("exact", Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms());
        r.put("fullScreen", Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent());
        r.put("battery", pm.isIgnoringBatteryOptimizations(c.getPackageName()));
        call.resolve(r);
    }

    @PluginMethod
    public void openSettings(PluginCall call) {
        String kind = call.getString("kind", "");
        Context c = getContext();
        String pkg = c.getPackageName();
        try {
            Intent i;
            if ("exact".equals(kind) && Build.VERSION.SDK_INT >= 31) {
                i = new Intent("android.settings.REQUEST_SCHEDULE_EXACT_ALARM", Uri.parse("package:" + pkg));
            } else if ("fullScreen".equals(kind) && Build.VERSION.SDK_INT >= 34) {
                i = new Intent("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT", Uri.parse("package:" + pkg));
            } else if ("battery".equals(kind)) {
                i = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
            } else {
                i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
                i.putExtra(Settings.EXTRA_APP_PACKAGE, pkg);
            }
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
        } catch (Exception e) {
            try {
                Intent d = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + pkg));
                d.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                c.startActivity(d);
            } catch (Exception ignored) { }
        }
        call.resolve();
    }
}
