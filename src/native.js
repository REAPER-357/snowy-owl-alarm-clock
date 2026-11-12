// Native bridge for SNOWY OWL. Bundled by esbuild into www/js/native.bundle.js and exposed as window.SnowyNative.
// On the web (no Capacitor runtime) it is not needed: index.html falls back to its own in-page alarm engine.
//
// On Android the real work happens in Java (OwlAlarmPlugin / AlarmScheduler / RingService):
//   - sync()        gives the native side the list of upcoming alarms, snoozes and the timer
//   - takeEvents()  returns what happened while the web page was not running (fired / snooze / dismiss)
//   - ringState     a live event telling the page that something started or stopped ringing
import { Capacitor, registerPlugin } from '@capacitor/core';
import { LocalNotifications } from '@capacitor/local-notifications';
import { App } from '@capacitor/app';
import { KeepAwake } from '@capacitor-community/keep-awake';

const isNative = Capacitor.isNativePlatform();
const OwlAlarm = registerPlugin('OwlAlarm');
let H = {};
let chain = Promise.resolve();

const pad = n => String(n).padStart(2, '0');
function timeText(hm, f24) {
  const [h, m] = hm.split(':').map(Number);
  return f24 ? `${pad(h)}:${pad(m)}` : `${h % 12 || 12}:${pad(m)} ${h < 12 ? 'AM' : 'PM'}`;
}
function durText(ms) {
  const s = Math.round(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
  return (h ? h + ':' + pad(m) : pad(m)) + ':' + pad(s % 60);
}

async function init(h) {
  H = h || {};
  if (!isNative) return;
  // Android 13+ asks for the notification permission at runtime.
  try {
    const p = await LocalNotifications.checkPermissions();
    if (p.display === 'prompt' || p.display === 'prompt-with-rationale') await LocalNotifications.requestPermissions();
  } catch (e) {}
  OwlAlarm.addListener('ringState', ev => { if (H.onRing) H.onRing(ev); });
  App.addListener('appStateChange', ({ isActive }) => { if (isActive && H.onResume) H.onResume(); });
  App.addListener('backButton', () => { if (!(H.onBack && H.onBack())) App.minimizeApp(); });
  if (H.onResume) H.onResume();
}

// Turn the app state into the flat list the native scheduler wants.
function buildItems(st) {
  const { S, alarms, snoozed, timer } = st, now = Date.now(), f24 = S.timeFormat === '24', items = [];
  // Alarm groups: a switched-off group sends nothing to the phone; a group paused until a time sends "skipUntil".
  const groups = st.groups || [];
  const groupOf = a => (a.group ? groups.find(g => String(g.id) === String(a.group)) || null : null);
  const groupOff = (a, at) => { const g = groupOf(a); return !!g && (!g.enabled || g.pausedUntil > at); };
  const skipUntil = a => { const g = groupOf(a); return g && g.enabled && g.pausedUntil > now ? g.pausedUntil : 0; };
  const base = a => ({
    kind: 'alarm', aid: a.nid, label: a.label || 'Alarm', timeText: timeText(a.time, f24),
    sound: a.sound, snooze: !!a.snooze, vibrate: !!a.vibrate,
    gradual: S.gradual, volume: S.alarmVolume, silence: S.silenceAfter, snoozeMin: S.snoozeLength, snoozeLimit: S.snoozeLimit
  });
  alarms.forEach(a => {
    if (!a.enabled || !a.nid) return;
    const [h, m] = a.time.split(':').map(Number);
    if (!a.days.length && !(a.onceAt && a.onceAt > now)) return;
    if (a.days.length ? groupOf(a) && !groupOf(a).enabled : groupOff(a, a.onceAt)) return;
    items.push({ ...base(a), key: 'a' + a.nid, h, m, days: a.days, at: a.days.length ? 0 : a.onceAt, skipUntil: a.days.length ? skipUntil(a) : 0, count: 0 });
  });
  snoozed.forEach(s => {
    const a = alarms.find(x => String(x.id) === String(s.id));
    if (!a || !a.nid || s.at <= now || groupOff(a, s.at)) return;
    const [h, m] = a.time.split(':').map(Number);
    items.push({ ...base(a), key: 's' + a.nid, h, m, days: [], at: s.at, count: s.count });
  });
  if (timer && timer.endAt && timer.endAt > now) {
    items.push({
      key: 't', kind: 'timer', aid: 0, h: 0, m: 0, days: [], at: timer.endAt, count: 0,
      label: 'Timer', timeText: durText(timer.total) + ' timer', sound: S.timerSound, snooze: false, vibrate: !!S.timerVibrate,
      gradual: S.timerGradual, volume: S.alarmVolume, silence: S.silenceAfter, snoozeMin: 0, snoozeLimit: 0
    });
  }
  return items;
}

// Calls are queued so two syncs never overlap.
function sync(state) {
  if (!isNative) return Promise.resolve();
  const items = buildItems(JSON.parse(JSON.stringify(state)));
  chain = chain.then(() => OwlAlarm.sync({ items })).catch(e => console.error('sync failed', e));
  return chain;
}

async function takeEvents() {
  if (!isNative) return [];
  try { return (await OwlAlarm.takeEvents()).events || []; } catch (e) { return []; }
}
async function getRinging() {
  if (!isNative) return { ringing: false };
  try { return await OwlAlarm.getRinging(); } catch (e) { return { ringing: false }; }
}
function snooze() { return isNative ? OwlAlarm.snooze().catch(() => {}) : Promise.resolve(); }
function dismiss() { return isNative ? OwlAlarm.dismiss().catch(() => {}) : Promise.resolve(); }
function closeIfLocked() { return isNative ? OwlAlarm.closeIfLocked().catch(() => {}) : Promise.resolve(); }
// Android's "save as" screen; rejects with "cancelled" if the person backs out.
function saveFile(name, data, mime) { return OwlAlarm.saveFile({ name, data, mime: mime || 'application/json' }); }
function shareText(title, text) { return isNative ? OwlAlarm.shareText({ title, text }).catch(() => {}) : Promise.resolve(); }
function openSettings(kind) { return isNative ? OwlAlarm.openSettings({ kind }).catch(() => {}) : Promise.resolve(); }

async function status() {
  if (!isNative) return {};
  try { return await OwlAlarm.status(); } catch (e) { return {}; }
}

// Fix the first missing thing: notification permission, exact alarms, then full-screen ringing.
async function fixPermissions() {
  if (!isNative) return;
  let st = await status();
  if (!st.notif) {
    try { await LocalNotifications.requestPermissions(); } catch (e) {}
    st = await status();
    if (!st.notif) { await openSettings('notif'); return; }
  }
  if (st.exact === false) { await openSettings('exact'); return; }
  if (st.fullScreen === false) { await openSettings('fullScreen'); return; }
}

async function keepAwake(on) {
  if (!isNative) return;
  try { on ? await KeepAwake.keepAwake() : await KeepAwake.allowSleep(); } catch (e) {}
}

window.SnowyNative = { isNative, init, sync, takeEvents, getRinging, snooze, dismiss, closeIfLocked, saveFile, shareText, openSettings, status, fixPermissions, keepAwake };
