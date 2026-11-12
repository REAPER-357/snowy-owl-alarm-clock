package com.snowyowl.alarmclock;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.util.Calendar;

/**
 * Keeps the list of upcoming alarms, schedules them with AlarmManager.setAlarmClock (exact, works in Doze)
 * and keeps a small event log (fired / snooze / dismiss) that the web layer reads when the app opens.
 *
 * Item fields: key, kind ("alarm"|"timer"), aid, h, m, days[0-6 or empty], at (ms, one-shot only),
 * label, timeText, sound, snooze, vibrate, gradual, volume, silence, snoozeMin, snoozeLimit, count, skipUntil.
 * Keys: "a<nid>" = the alarm itself, "s<nid>" = its pending snooze, "t" = the timer.
 */
final class AlarmScheduler {
    static final String ACTION_FIRE = "owl.FIRE";
    private static final String PREFS = "owl_prefs";
    private static final String K_ITEMS = "items";
    private static final String K_EVENTS = "events";

    private AlarmScheduler() {}

    private static SharedPreferences prefs(Context c) {
        return c.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static synchronized JSONArray loadItems(Context c) {
        try { return new JSONArray(prefs(c).getString(K_ITEMS, "[]")); }
        catch (JSONException e) { return new JSONArray(); }
    }

    private static void storeItems(Context c, JSONArray a) {
        prefs(c).edit().putString(K_ITEMS, a.toString()).commit();
    }

    static boolean repeats(JSONObject it) {
        JSONArray d = it.optJSONArray("days");
        return d != null && d.length() > 0;
    }

    private static boolean has(JSONArray a, int v) {
        for (int i = 0; a != null && i < a.length(); i++) if (a.optInt(i, -1) == v) return true;
        return false;
    }

    /** Next local time (after "from") at h:m on one of the given weekdays (0 = Sunday). Returns 0 if none. */
    static long nextOccurrence(int h, int m, JSONArray days, long from) {
        Calendar c = Calendar.getInstance();
        for (int d = 0; d < 8; d++) {
            c.setTimeInMillis(from);
            c.add(Calendar.DAY_OF_YEAR, d);
            c.set(Calendar.HOUR_OF_DAY, h);
            c.set(Calendar.MINUTE, m);
            c.set(Calendar.SECOND, 0);
            c.set(Calendar.MILLISECOND, 0);
            if (c.getTimeInMillis() <= from) continue;
            int dow = c.get(Calendar.DAY_OF_WEEK) - 1;
            if (days == null || days.length() == 0 || has(days, dow)) return c.getTimeInMillis();
        }
        return 0;
    }

    static long triggerAt(JSONObject it, long now) {
        if (repeats(it)) {
            // skipUntil = a group the alarm belongs to is switched off until then (0 = no pause)
            long from = Math.max(now, it.optLong("skipUntil", 0) - 1);
            return nextOccurrence(it.optInt("h"), it.optInt("m"), it.optJSONArray("days"), from);
        }
        long at = it.optLong("at", 0);
        return at > now ? at : 0;
    }

    private static PendingIntent firePi(Context c, String key, int flags) {
        Intent i = new Intent(c, AlarmReceiver.class);
        i.setAction(ACTION_FIRE);
        i.setData(Uri.parse("owl://alarm/" + key));
        i.putExtra("key", key);
        return PendingIntent.getBroadcast(c, key.hashCode(), i, flags | PendingIntent.FLAG_IMMUTABLE);
    }

    static void scheduleOne(Context c, JSONObject it, long now) {
        long at = triggerAt(it, now);
        if (at <= 0) return;
        String key = it.optString("key");
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pi = firePi(c, key, PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent show = PendingIntent.getActivity(c, 7, new Intent(c, MainActivity.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        try {
            am.setAlarmClock(new AlarmManager.AlarmClockInfo(at, show), pi);
        } catch (SecurityException e) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
        }
    }

    private static void cancelOne(Context c, String key) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pi = firePi(c, key, PendingIntent.FLAG_NO_CREATE);
        if (pi != null) { am.cancel(pi); pi.cancel(); }
    }

    /** Replace the whole schedule with what the web layer says. */
    static synchronized void replaceAll(Context c, JSONArray next) {
        JSONArray old = loadItems(c);
        for (int i = 0; i < old.length(); i++) {
            JSONObject o = old.optJSONObject(i);
            if (o != null) cancelOne(c, o.optString("key"));
        }
        storeItems(c, next);
        long now = System.currentTimeMillis();
        for (int i = 0; i < next.length(); i++) {
            JSONObject o = next.optJSONObject(i);
            if (o != null) scheduleOne(c, o, now);
        }
    }

    /** Re-arm everything (after reboot, time change, app update). */
    static synchronized void rescheduleAll(Context c) {
        JSONArray items = loadItems(c);
        long now = System.currentTimeMillis();
        for (int i = 0; i < items.length(); i++) {
            JSONObject o = items.optJSONObject(i);
            if (o != null) scheduleOne(c, o, now);
        }
    }

    /** Add or replace one item (used for snooze) and schedule it. */
    static synchronized void addItem(Context c, JSONObject it) {
        JSONArray items = loadItems(c);
        JSONArray out = new JSONArray();
        String key = it.optString("key");
        for (int i = 0; i < items.length(); i++) {
            JSONObject o = items.optJSONObject(i);
            if (o != null && !key.equals(o.optString("key"))) out.put(o);
        }
        out.put(it);
        storeItems(c, out);
        scheduleOne(c, it, System.currentTimeMillis());
    }

    /** Called when an item fires: returns it, drops one-shots, and arms the next day for repeating alarms. */
    static synchronized JSONObject consume(Context c, String key) {
        JSONArray items = loadItems(c);
        JSONArray out = new JSONArray();
        JSONObject found = null;
        for (int i = 0; i < items.length(); i++) {
            JSONObject o = items.optJSONObject(i);
            if (o == null) continue;
            if (key.equals(o.optString("key"))) {
                found = o;
                if (repeats(o)) out.put(o);
            } else {
                out.put(o);
            }
        }
        storeItems(c, out);
        if (found != null && repeats(found)) scheduleOne(c, found, System.currentTimeMillis() + 1000);
        return found;
    }

    static void addEvent(Context c, String type, JSONObject it, long at, int count) {
        try {
            JSONObject e = new JSONObject();
            e.put("type", type);
            e.put("kind", it.optString("kind"));
            e.put("aid", it.optLong("aid"));
            e.put("key", it.optString("key"));
            e.put("at", at);
            e.put("count", count);
            synchronized (AlarmScheduler.class) {
                JSONArray a;
                try { a = new JSONArray(prefs(c).getString(K_EVENTS, "[]")); } catch (JSONException x) { a = new JSONArray(); }
                a.put(e);
                JSONArray t = new JSONArray();
                for (int i = Math.max(0, a.length() - 60); i < a.length(); i++) t.put(a.get(i));
                prefs(c).edit().putString(K_EVENTS, t.toString()).commit();
            }
        } catch (JSONException ignored) { }
    }

    static synchronized JSONArray takeEvents(Context c) {
        JSONArray a;
        try { a = new JSONArray(prefs(c).getString(K_EVENTS, "[]")); } catch (JSONException e) { a = new JSONArray(); }
        prefs(c).edit().remove(K_EVENTS).commit();
        return a;
    }
}
