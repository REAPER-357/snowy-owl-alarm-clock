# SNOWY OWL Alarm Clock – Capacitor (Android) project

`www/index.html` is the app. The alarm engine on the phone is native Java (in `android-src/`), so alarms ring
when the app is closed, the phone is locked, or the phone is asleep.

## What you need
- Node 20+ and npm
- Android Studio (with an Android SDK) and JDK 21 (Android Studio ships one)
- Capacitor 7 is pinned in `package.json` (`^7.0.0`). If you move to a newer major, bump every `@capacitor/*`
  package and `@capacitor-community/keep-awake` together.

## Build steps
```bash
npm install
npm run android:add      # creates android/, writes the Java files, patches the manifest, copies sounds
npm run icons            # optional: generates launcher icons from assets/icon.png
npm run android:sync     # builds CSS/fonts/bridge, cap sync, re-applies the Android patch
npm run android:open     # opens Android Studio
```
In Android Studio: plug in a phone (USB debugging on) and press Run, or use
**Build > Build Bundle(s) / APK(s) > Build APK(s)** for a debug APK.
For a release build use **Build > Generate Signed Bundle / APK** and make a keystore (keep it safe).

After any change to `www/index.html`, `src/native.js` or `android-src/`: `npm run android:sync`, then run again.

## How alarms work on the phone
1. The page sends the native side the list of upcoming alarms, snoozes and the running timer.
2. Each one is scheduled with `AlarmManager.setAlarmClock` (exact, works in Doze, shows the system alarm icon).
   Weekly alarms re-arm themselves for the next day without the app running. A reboot, app update, clock or
   time-zone change re-arms everything.
3. When one fires, `RingService` (a foreground service) starts:
   - plays the chosen sound **in a loop on the alarm audio stream** (follows the phone's alarm volume, allowed
     through Do Not Disturb); if the alarm volume is 0 it lifts it to 60% so you can't oversleep a muted phone
   - applies the app's volume setting, "Gradually increase volume" and "Silence after"
   - vibrates (if the alarm has Vibrate on) and holds the CPU awake
   - shows a full-screen notification that opens the app's ringing screen over the lock screen
4. Snooze and Dismiss work from the ringing screen **or** the notification buttons. An alarm with snooze turned off
   has no Snooze button anywhere. The snooze limit setting is respected.
5. Whatever happened while the app was closed (fired, snoozed, dismissed) is read back when the app opens, so
   one-time alarms switch themselves off and snoozes show in "Next alarm in...".
6. The timer works the same way and rings with a Stop button.

## Icons
Icons are drawn from a sprite inside `www/index.html`. Put your own Lucide files in `www/assets/icons/` (same file names)
and run `npm run build` (or `npm run android:sync`); the build copies them into the sprite. A missing file never makes an
icon disappear, because the icon already in the page is kept. `snooze.svg` (alarm clock with zzz) is custom, not from Lucide.

## Lock screen
Dismissing or snoozing an alarm that rang over the lock screen (or letting it silence itself) sends the app to the back,
so you land on the lock screen again instead of the Alarm page. If the phone is unlocked you stay where you are.

## Themes
Settings > Appearance > Theme switches between **Black** (pure black, good for OLED), **Dark** and **Light**. The choice is
saved and applied before the page draws, so there is no flash on start. The grey scale is driven by CSS variables
(`html[data-theme=...]` in `www/index.html`), so a theme switch needs no rebuild; the Tailwind config maps `neutral` and
`white` to those variables, so run `npm run build` once after updating `tailwind.config.js`.

## App emblem
The small icon next to the app name at the top of the main page is `www/small-icon.png` (the owl shows if the file is
missing). The large picture at the top of Settings is `www/icon.png` (your emblem with the name and picture). Replace that file with
your own PNG, then run `npm run android:sync`. If the file is missing the emblem is simply hidden. It is separate from
`assets/icon.png`, which `npm run icons` uses for the launcher icon.

## Backup, sharing and Google Sheets
- **Export** opens Android's "save as" screen, so you choose where the `.json` backup goes (Downloads, Drive...). **Import** reads it back.
- **Share alarms** sends your alarms through the share sheet as tab-separated rows. Paste them into a Google Sheet and each value
  lands in its own cell. Columns: `Time, Label, Days, Sound, Snooze, Vibrate, Group`.
- **From a sheet** adds alarms from a Google Sheet shared as "Anyone with the link" (paste the link), or from rows you paste.
  Days accept Weekdays, Weekends, Every day, Once, `Mon Wed Fri`, `M Tu Th`, `Mon-Fri`. Times accept `7:00`, `6:30 PM`, `18:30`.
  Alarms already in the app are skipped, and you can drop the imported alarms into a group. It adds; it never replaces.
  The phone fetches the sheet through Capacitor's native HTTP (`CapacitorHttp` in `capacitor.config.json`), run `npm run android:sync` to pick that up.

## Alarm groups
Put alarms in groups (for example "Work") from the Alarm tab: **Group** makes one, and each alarm's editor has a
Group row. The switch on a group turns the whole group off in one go; it asks for how long:
rest of today, today and tomorrow, next 3 or 7 days, through a chosen date, or until you switch it back on.
Alarms keep their own on/off state, so when the group comes back everything is exactly as you left it, and a timed
pause ends by itself. The phone's alarm engine honours this: a switched-off group schedules nothing, and a timed
pause is sent as `skipUntil`, so weekly alarms skip the paused days and resume on their own even if the app is closed.
Deleting a group moves its alarms to Main.

In a normal browser (no Android), the page falls back to its own in-page alarm engine.

## Test on a real phone before relying on it
1. Set an alarm 2 minutes ahead and lock the phone: the screen should wake, the owl ringing screen appear, and the sound loop.
2. Same, after swiping the app out of recents.
3. Restart the phone, then check an alarm still rings.
4. Turn snooze off on an alarm: only Dismiss should show, on the screen and in the notification.
5. Snooze, close the app, wait: it should ring again after the snooze time.
6. Set a 1-minute timer, lock the phone, check it rings.
7. Put the phone on Do Not Disturb: the alarm should still sound.

## One-time phone setup (the app shows a red banner for the first three)
- **Notifications:** allow when asked (Android 13+).
- **Alarms & reminders:** allow (only needed on Android 12; Android 13+ grants it automatically).
- **Full-screen alarms:** on Android 14+ allow "Full-screen notifications" for the app if the banner asks.
- **Battery:** Settings > Battery optimisation in the app opens the system screen. Set SNOWY OWL to Unrestricted.
  Xiaomi, Oppo, Vivo, Huawei and Samsung ("sleeping apps") also have an auto-start / background setting; see dontkillmyapp.com.

## Things to know
- This native code has not been compiled or run by me; I could only syntax-check it. Expect to fix a small
  compile or behaviour issue on first build, and use the checklist above.
- **Play Store:** `USE_EXACT_ALARM` and `USE_FULL_SCREEN_INTENT` need a Play Console declaration that the app's core
  purpose is alarms. `FOREGROUND_SERVICE_MEDIA_PLAYBACK` is used for the ringing service.
- Sounds are 20-second loops generated by `npm run sounds` (already in `assets/sounds`). To change a tone, replace the
  WAV with the same name and run `npm run android:sync`.
- Hardware Back closes sheets and menus first, then returns to the Alarm tab, then minimises. It does nothing while ringing.
- A one-time alarm that rang while the app was closed switches itself off the next time you open the app.

## Files
- `www/index.html` – the app
- `src/native.js` – web-to-native bridge (bundled to `www/js/native.bundle.js`)
- `android-src/*.java.tpl` – native alarm engine: `AlarmScheduler`, `AlarmReceiver`, `BootReceiver`, `RingService`,
  `OwlAlarmPlugin`, `MainActivity` (copied into the Android project by `scripts/patch-android.mjs`)
- `src/app.css`, `tailwind.config.js` – Tailwind build (no CDN)
- `scripts/` – asset copy, sound generator, Android patcher
- `assets/` – alarm WAVs, app icon, notification icon
- Generated by `npm run build` (git-ignored): `www/css`, `www/fonts`, `www/webfonts`, `www/js`
