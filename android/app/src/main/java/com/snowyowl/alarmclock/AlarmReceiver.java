package com.snowyowl.alarmclock;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import org.json.JSONObject;

/** Fires when AlarmManager says an alarm or timer is due. Hands the item to the ring service. */
public class AlarmReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String key = intent.getStringExtra("key");
        if (key == null) return;
        JSONObject item = AlarmScheduler.consume(context, key);
        if (item == null) return;
        Intent svc = new Intent(context, RingService.class);
        svc.setAction(RingService.ACTION_START);
        svc.putExtra("item", item.toString());
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(svc);
        else context.startService(svc);
    }
}
