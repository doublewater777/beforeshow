import test from 'node:test';
import assert from 'node:assert/strict';
import { main as sync } from '../src/functions/syncLiveActivityPlan/entry.js';
import { main as dispatch } from '../src/functions/dispatchLiveActivityPush/entry.js';

const instant = minute => new Date(`2026-10-21T17:${String(minute).padStart(2, '0')}:00Z`);
const event = (id, minute = 55) => ({ performanceID: id, startsAt: instant(minute).toISOString() });
const state = events => ({
  showName: 'Festival', isReminderActive: true, reminderArtistName: 'The Chairs',
  reminderStageName: 'Wind Stage', reminderStartsAt: events[0].startsAt,
  reminderExpiresAt: events[0].startsAt, reminderPerformanceIDs: events.map(e => e.performanceID),
  reminderCount: events.length, timeZoneIdentifier: 'Asia/Taipei'
});
function harness() {
  let record;
  const payloads = [];
  return {
    payloads,
    record: () => record,
    async upload(steps, version = 1, language = 'en') {
      const result = await sync({ appInstanceId: 'device', appSignature: 'beforeshow-app-signature-v1',
        planSecret: 'secret-longer-than-16', plan: {
          showID: 'show', activityPushToken: 'token', version, language,
          deadline: '2026-10-21T20:00:00Z', steps
        } }, {}, { now: () => instant(30), findExisting: async () => record,
          savePlan: async saved => { record = saved; } });
      assert.equal(result.ok, true);
    },
    async deliver(minute, ok = true) {
      return dispatch({}, {}, { now: () => instant(minute), findActivePlans: async () => [record],
        updatePlan: async (_, data) => { record = { ...record, ...data }; },
        transport: async ({ payload }) => { payloads.push(payload); return { ok, statusCode: ok ? 200 : 503 }; }
      });
    }
  };
}
const step = (minute, events) => ({ scheduledAt: instant(minute).toISOString(), state: state(events), reminderEvents: events });

test('latest due step retains first alert, then new versions stay silent per performance and start', async () => {
  const h = harness();
  await h.upload([step(40, [event('a')]), step(42, [event('a')])]);
  await h.deliver(43);
  assert.ok(h.payloads[0].aps.alert, 'skipping initial step must not lose the first reminder');
  await h.upload([step(44, [event('a')])], 2);
  await h.deliver(44);
  assert.equal(h.payloads[1].aps.alert, undefined, 'a new version must preserve actual delivery receipts');
  await h.upload([step(45, [event('a', 59)])], 3);
  await h.deliver(45);
  assert.ok(h.payloads[2].aps.alert, 'rescheduling creates a distinct event');
});

test('overlapping reminder groups alert only for newly appearing events', async () => {
  const h = harness();
  const a = { ...event('a'), artistName: 'Already reminded', stageName: 'Old Stage' };
  const b = { ...event('b', 56), artistName: 'New artist', stageName: 'New Stage' };
  await h.upload([step(40, [a]), step(41, [a, b]), step(42, [b])]);
  await h.deliver(40);
  await h.deliver(41);
  await h.deliver(42);
  assert.deepEqual(h.payloads.map(p => Boolean(p.aps.alert)), [true, true, false]);
  assert.equal(h.payloads[1].aps.alert.title, 'New artist is starting soon');
  assert.equal(h.payloads[1].aps.alert.body, 'Starts at 01:56 · New Stage');
  assert.equal(h.payloads[1].aps["content-state"].reminderCount, 2);
});

test('mixed expired and upcoming events announce only the upcoming set', async () => {
  const h = harness();
  const expired = { ...event('expired', 41), artistName: 'Past artist', stageName: 'Past Stage' };
  const upcoming = { ...event('upcoming', 56), artistName: '下一场艺人', stageName: '新舞台' };
  await h.upload([step(41, [expired, upcoming])], 1, 'zh-Hans');
  await h.deliver(41);
  assert.equal(h.payloads[0].aps.alert.title, '下一场艺人 快开始了');
  assert.equal(h.payloads[0].aps.alert.body, '01:56 开演 · 新舞台');
  assert.deepEqual(h.record().deliveredReminderKeys, [`upcoming:${instant(56).getTime()}`]);
});

test('expired reminders and failed deliveries do not become successful reminder receipts', async () => {
  const h = harness();
  await h.upload([step(40, [event('a', 45)])]);
  await h.deliver(45);
  assert.equal(h.payloads[0].aps.alert, undefined, 'do not announce starting soon after the set started');
  await h.upload([step(46, [event('b', 59)])], 2);
  await h.deliver(46, false);
  await h.upload([step(47, [event('b', 59)])], 3);
  await h.deliver(47);
  assert.ok(h.payloads[2].aps.alert);
});

for (const [language, title, body] of [
  ['en', 'The Chairs is starting soon', 'Starts at 01:55 · Wind Stage'],
  ['zh-Hans', 'The Chairs 快开始了', '01:55 开演 · Wind Stage'],
  ['zh-Hant', 'The Chairs 快開始了', '01:55 開演 · Wind Stage']
]) {
  test(`cloud alert uses ${language} and absolute event-local opening time`, async () => {
    const h = harness();
    await h.upload([step(40, [event('a')])], 1, language);
    await h.deliver(40);
    assert.equal(h.payloads[0].aps.alert.title, title);
    assert.equal(h.payloads[0].aps.alert.body, body);
    assert.ok(Buffer.byteLength(JSON.stringify(h.payloads[0])) < 4096);
  });
}

// SDK transaction boundary: document reads/writes are serialized and get returns an object.
function memoryDatabase() {
  const docs = new Map();
  let queue = Promise.resolve();
  const collection = () => ({ doc: id => ({
    get: async () => ({ data: structuredClone(docs.get(id) ?? null) }),
    set: async data => { docs.set(id, structuredClone({ ...data, _id: id })); },
    update: async data => { docs.set(id, structuredClone({ ...docs.get(id), ...data })); }
  }) });
  return { collection, async runTransaction(callback) {
    const previous = queue;
    let release;
    queue = new Promise(resolve => { release = resolve; });
    await previous;
    try { return await callback({ collection }); } finally { release(); }
  }, record: () => structuredClone(docs.get('device:show')) };
}

for (const ordering of ['upload during APNs send', 'delivery after sync read']) {
  test(`plan replacement and receipts survive ${ordering}`, async () => {
    const db = memoryDatabase();
    const store = db.collection('liveActivityPlans').doc('device:show');
    let pauseRead = false;
    let readReached;
    let continueRead;
    const reached = new Promise(resolve => { readReached = resolve; });
    const resumed = new Promise(resolve => { continueRead = resolve; });
    const upload = (version, minute) => sync({ appInstanceId: 'device',
      appSignature: 'beforeshow-app-signature-v1', planSecret: 'secret-longer-than-16',
      plan: { showID: 'show', version, activityPushToken: 'token', language: 'en',
        deadline: '2026-10-21T20:00:00Z', steps: [step(minute, [event('a')])] }
    }, {}, { database: db, now: () => instant(30), findExisting: async () => {
      const previous = db.record();
      if (pauseRead) { readReached(); await resumed; }
      return previous;
    }, savePlan: record => store.set(record) });
    const send = transport => dispatch({}, {}, { database: db, now: () => instant(43),
      findActivePlans: async () => [db.record()], updatePlan: (_, data) => store.update(data), transport });
    await upload(1, 40);
    if (ordering === 'upload during APNs send') {
      await send(async () => { await upload(2, 42); return { ok: true, statusCode: 200 }; });
    } else {
      pauseRead = true;
      const uploading = upload(2, 42);
      await reached;
      await send(async () => ({ ok: true, statusCode: 200 }));
      continueRead();
      await uploading;
    }
    assert.equal(db.record().version, 2);
    assert.equal(new Date(db.record().steps[0].scheduledAt).getTime(), instant(42).getTime());
    let payload;
    await send(async args => { payload = args.payload; return { ok: true, statusCode: 200 }; });
    assert.equal(payload.aps.alert, undefined, 'receipt survives concurrent replacement');
  });
}

test('upgrade reconstructs successful legacy receipts from consumed steps', async () => {
  const h = harness();
  await h.upload([step(40, [event('a')])]);
  const oldStep = h.record().steps[0];
  oldStep.isConsumed = true;
  oldStep.pushStatus = 200;
  delete oldStep.deliveredReminderKeys;
  await h.upload([step(42, [event('a')])], 2);
  await h.deliver(43);
  assert.equal(h.payloads[0].aps.alert, undefined);
});

test('many overlapping reminders keep the actual APNs payload below 4KB', async () => {
  const h = harness();
  const events = Array.from({ length: 40 }, (_, index) => ({ ...event(`performance-${index}`),
    artistName: `椅子乐团与特别嘉宾 ${index}`, stageName: '草莓音乐节主舞台' }));
  await h.upload([step(40, events)], 1, 'zh-Hans');
  await h.deliver(40);
  const payload = h.payloads[0];
  assert.ok(Buffer.byteLength(JSON.stringify(payload), 'utf8') < 4096);
  assert.equal(payload.aps['content-state'].reminderCount, 40);
  assert.equal(payload.aps['content-state'].reminderEvents, undefined);
  assert.match(payload.aps.alert.body, /另有 39 场/);
});

test('concurrent dispatch invocations share one in-flight claim', async () => {
  const db = memoryDatabase();
  await sync({ appInstanceId: 'device', appSignature: 'beforeshow-app-signature-v1',
    planSecret: 'secret-longer-than-16', plan: { showID: 'show', version: 1,
      activityPushToken: 'token', deadline: '2026-10-21T20:00:00Z', steps: [step(40, [event('a')])] }
  }, {}, { database: db, now: () => instant(30), findExisting: async () => null,
    savePlan: record => db.collection('liveActivityPlans').doc('device:show').set(record) });
  let sends = 0;
  let release;
  let sending;
  const reached = new Promise(resolve => { sending = resolve; });
  const wait = new Promise(resolve => { release = resolve; });
  const run = () => dispatch({}, {}, { database: db, now: () => instant(42),
    findActivePlans: async () => [db.record()],
    updatePlan: (_, data) => db.collection('liveActivityPlans').doc('device:show').update(data),
    transport: async () => {
      sends++; sending(); if (sends === 1) await wait; return { ok: true, statusCode: 200 };
    } });
  const first = run();
  await reached;
  await run();
  release();
  await first;
  assert.equal(sends, 1);
});

test('SDK code-style transaction write errors do not acknowledge registration', async () => {
  const db = { runTransaction: callback => callback({ collection: () => ({ doc: () => ({
    get: async () => ({ data: null }), set: async () => ({ code: 'WRITE_FAILED', message: 'Write failed' })
  }) }) }) };
  const result = await sync({ appInstanceId: 'device', appSignature: 'beforeshow-app-signature-v1',
    planSecret: 'secret-longer-than-16', plan: { showID: 'show', version: 1,
      activityPushToken: 'token', deadline: '2026-10-21T20:00:00Z', steps: [step(40, [event('a')])] }
  }, {}, { database: db, findExisting: async () => null, now: () => instant(30),
    savePlan: async () => ({ code: 'WRITE_FAILED', message: 'Write failed' }) });
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'WRITE_FAILED');
});

test("multiple due steps merge unconsumed reminder events without dropping earlier due fresh reminders", async () => {
  const h = harness();
  await h.upload([
    step(40, [event("a", 55)]),
    step(42, [event("b", 56)])
  ]);
  await h.deliver(43);
  assert.equal(h.payloads.length, 1);
  const alert = h.payloads[0].aps.alert;
  assert.ok(alert, "alert must be generated");
  assert.match(alert.body, /1 more saved set starts soon/);
  const rec = h.record();
  assert.equal(rec.deliveredReminderKeys.length, 2);
  assert.ok(rec.deliveredReminderKeys.some(k => k.startsWith("a:")));
  assert.ok(rec.deliveredReminderKeys.some(k => k.startsWith("b:")));
});

test("nextDispatchAt is computed on upload and advances after steps are consumed", async () => {
  const h = harness();
  await h.upload([
    step(40, [event("a", 55)]),
    step(45, [event("b", 59)])
  ]);
  assert.equal(new Date(h.record().nextDispatchAt).getTime(), instant(40).getTime());

  await h.deliver(40);
  assert.equal(new Date(h.record().nextDispatchAt).getTime(), instant(45).getTime());

  await h.deliver(45);
  assert.equal(h.record().nextDispatchAt, null);
  assert.equal(h.record().status, "completed");
});

test("dispatchLiveActivityPush returns QUERY_FAILED when findActivePlans throws", async () => {
  const res = await dispatch({}, {}, {
    now: () => instant(40),
    transport: async () => ({ ok: true, statusCode: 200 }),
    findActivePlans: async () => { throw new Error("DB connection reset"); }
  });
  assert.equal(res.ok, false);
  assert.equal(res.error.code, "QUERY_FAILED");
  assert.equal(res.error.message, "DB connection reset");
});
