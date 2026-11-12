package com.snowyowl.alarmclock;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(OwlAlarmPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
