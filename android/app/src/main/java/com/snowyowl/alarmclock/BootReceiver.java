package com.snowyowl.alarmclock;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Re-arms all alarms after a reboot, app update, clock change or time-zone change. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        AlarmScheduler.rescheduleAll(context);
    }
}
