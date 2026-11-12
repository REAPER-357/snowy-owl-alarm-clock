// Run after "cap add android" / "cap sync". Safe to run repeatedly.
// - adds the alarm permissions to AndroidManifest.xml and lets the app show over the lock screen
// - registers the native alarm engine (receivers + ring service) in the manifest
// - writes the Java sources from android-src/ into the app's package folder
// - copies the alarm sounds into res/raw and the notification icon into res/drawable
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, copyFileSync } from 'node:fs';

const root = 'android/app/src/main';
const manifestPath = `${root}/AndroidManifest.xml`;
if (!existsSync(manifestPath)) { console.error('No android/ project yet. Run "npm run android:add" first.'); process.exit(1); }

const appId = JSON.parse(readFileSync('capacitor.config.json', 'utf8')).appId;
const log = [];

// ---- manifest ----
let xml = readFileSync(manifestPath, 'utf8');
const perms = [
  ['android.permission.POST_NOTIFICATIONS', ''],
  ['android.permission.SCHEDULE_EXACT_ALARM', ' android:maxSdkVersion="32"'],
  ['android.permission.USE_EXACT_ALARM', ''],
  ['android.permission.USE_FULL_SCREEN_INTENT', ''],
  ['android.permission.FOREGROUND_SERVICE', ''],
  ['android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK', ''],
  ['android.permission.VIBRATE', ''],
  ['android.permission.WAKE_LOCK', ''],
  ['android.permission.RECEIVE_BOOT_COMPLETED', '']
];
for (const [name, extra] of perms) {
  if (!xml.includes(`"${name}"`)) { xml = xml.replace('</manifest>', `    <uses-permission android:name="${name}"${extra} />\n</manifest>`); log.push(name.split('.').pop()); }
}
const act = xml.match(/<activity\b[^>]*>/);
if (act && !act[0].includes('showWhenLocked')) {
  xml = xml.replace(act[0], act[0].replace('<activity', '<activity android:showWhenLocked="true" android:turnScreenOn="true"'));
  log.push('showWhenLocked');
}
if (!xml.includes('.RingService')) {
  const block = `
        <receiver android:name=".AlarmReceiver" android:exported="false" />
        <receiver android:name=".BootReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
            </intent-filter>
        </receiver>
        <service android:name=".RingService" android:exported="false" android:foregroundServiceType="mediaPlayback" />
    `;
  xml = xml.replace('</application>', block + '</application>');
  log.push('RingService + receivers');
}
writeFileSync(manifestPath, xml);

// ---- Java sources ----
const javaDir = `${root}/java/${appId.replace(/\./g, '/')}`;
mkdirSync(javaDir, { recursive: true });
let nj = 0;
for (const f of readdirSync('android-src')) {
  if (!f.endsWith('.java.tpl')) continue;
  const src = readFileSync(`android-src/${f}`, 'utf8').replace(/__PACKAGE__/g, appId);
  writeFileSync(`${javaDir}/${f.replace(/\.tpl$/, '')}`, src);
  nj++;
}

// ---- sounds & icon ----
const raw = `${root}/res/raw`; mkdirSync(raw, { recursive: true });
let ns = 0;
for (const f of readdirSync('assets/sounds')) if (f.endsWith('.wav')) { copyFileSync(`assets/sounds/${f}`, `${raw}/${f}`); ns++; }
if (existsSync('assets/android/ic_stat_owl.png')) {
  mkdirSync(`${root}/res/drawable`, { recursive: true });
  copyFileSync('assets/android/ic_stat_owl.png', `${root}/res/drawable/ic_stat_owl.png`);
}
console.log(`Manifest: ${log.length ? 'added ' + log.join(', ') : 'already up to date'}. Wrote ${nj} Java files to ${javaDir}. Copied ${ns} sounds.`);
