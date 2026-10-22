import { buildActivityKitPayload, sendActivityKitPush } from "../../apns/apnsClient.js";

import { contentDate, reminderEvents, reminderKey, reminderAlert, deliveredReminderKeys } from "../../apns/liveActivityReminder.js";

import { liveActivityDatabase, claimDispatch, finishDispatch } from "../../apns/liveActivityPlanStore.js";

const COLLECTION_NAME = "liveActivityPlans";
const REMINDER_WINDOW_MS = 15 * 60 * 1000;

export async function main(event = {}, context = {}, options = {}) {
  const now = options.now?.() ?? new Date();

  const apnsKeyId = options.apnsKeyId ?? process.env.APNS_KEY_ID;
  const apnsTeamId = options.apnsTeamId ?? process.env.APNS_TEAM_ID;
  const apnsPrivateKey = options.apnsPrivateKey ?? process.env.APNS_PRIVATE_KEY;

  if (!options.transport && (!apnsKeyId || !apnsTeamId || !apnsPrivateKey)) {
    console.error("dispatchLiveActivityPush: Missing APNs configuration, skipping push dispatch.");
    return {
      ok: false,
      error: { code: "CONFIG_MISSING", message: "Missing APNs configuration" },
      processedCount: 0,
      dispatchedCount: 0,
      expiredTokenCount: 0,
      skippedDueToConfig: true
    };
  }

  let activePlans;
  try {
    const findActivePlans = options.findActivePlans ?? queryActivePlansFromDb;
    activePlans = await findActivePlans(now, options);
  } catch (err) {
    console.error("dispatchLiveActivityPush: Database query failed:", err);
    return {
      ok: false,
      error: { code: "QUERY_FAILED", message: err.message },
      processedCount: 0,
      dispatchedCount: 0,
      expiredTokenCount: 0
    };
  }

  let processedCount = 0;
  let dispatchedCount = 0;
  let expiredTokenCount = 0;

  const database = options.database ?? (options.updatePlan ? null : await liveActivityDatabase());
  for (const candidate of activePlans) {
    let plan = candidate;
    try {
      if (database) {
        plan = await claimDispatch(database, candidate, now);
        if (!plan) continue;
      }
      processedCount += 1;
      const steps = plan.steps ?? [];
      const dueSteps = steps
        .filter(s => !s.isConsumed && new Date(s.scheduledAt) <= now)
        .sort((a, b) => new Date(a.scheduledAt).getTime() - new Date(b.scheduledAt).getTime());

      if (dueSteps.length === 0) {
        if (database) await finishDispatch(database, plan, {
          deliveredReminderKeys: deliveredReminderKeys(plan), updatedAt: now
        });
        continue;
      }

      // The target step is the latest step that has reached scheduledAt
      const targetStep = dueSteps[dueSteps.length - 1];

      // Mark skipped earlier steps if any
      for (let i = 0; i < dueSteps.length - 1; i++) {
        dueSteps[i].isConsumed = true;
        dueSteps[i].consumedAt = now;
        dueSteps[i].skipped = true;
      }

      const delivered = new Set(deliveredReminderKeys(plan));

      // Collect reminder events across all due steps so earlier due reminders are not lost
      const allDueEvents = [];
      const seenEventKeys = new Set();
      for (const s of dueSteps) {
        const stepEvents = reminderEvents(s.state, s.reminderEvents);
        for (const ev of stepEvents) {
          const key = reminderKey(ev);
          if (!seenEventKeys.has(key)) {
            seenEventKeys.add(key);
            allDueEvents.push(ev);
          }
        }
      }

      // Filter: only keep events within the reminder window (startsAt - 15m <= now < startsAt) and not yet delivered
      const freshEvents = allDueEvents.filter(event => {
        const startsAt = contentDate(event.startsAt);
        return !delivered.has(reminderKey(event)) && now < startsAt
          && now >= new Date(startsAt.getTime() - REMINDER_WINDOW_MS);
      });

      const mergedReminderCount = Math.max(
        freshEvents.length,
        targetStep.state?.reminderCount ?? 0,
        targetStep.state?.reminderPerformanceIDs?.length ?? 0
      );

      let alert = null;
      if (!targetStep.state?.isEnded && freshEvents.length) {
        const alertState = {
          ...targetStep.state,
          reminderArtistName: targetStep.state?.reminderArtistName ?? freshEvents[0].artistName,
          reminderStageName: targetStep.state?.reminderStageName ?? freshEvents[0].stageName,
          reminderStartsAt: targetStep.state?.reminderStartsAt ?? freshEvents[0].startsAt,
          reminderCount: mergedReminderCount
        };
        alert = reminderAlert(alertState, freshEvents, plan.language);
      } else if (!allDueEvents.length && targetStep.isReminder
          && now - new Date(targetStep.scheduledAt) <= REMINDER_WINDOW_MS) {
        // Preserve already-registered legacy steps without event identities.
        alert = { title: targetStep.alertTitle || "快开始了",
          body: targetStep.alertBody || targetStep.state?.showName || "", sound: "default" };
      }

      const isEnd = Boolean(targetStep.state?.isEnded);
      // Per-event handover metadata stays on the server; the widget only needs the count.
      const { reminderPerformanceIDs: ids, ...contentState } = targetStep.state;
      if (allDueEvents.length || freshEvents.length) {
        contentState.reminderCount = mergedReminderCount || 1;
      }
      const payload = buildActivityKitPayload({
        contentState,
        scheduledAt: targetStep.scheduledAt,
        staleAt: targetStep.staleAt,
        dismissalAt: targetStep.staleAt,
        isEnd,
        alert
      });

      const pushResult = await sendActivityKitPush({
        pushToken: plan.activityPushToken,
        payload,
        isProduction: Boolean(plan.isProduction),
        keyId: apnsKeyId,
        teamId: apnsTeamId,
        privateKeyPem: apnsPrivateKey,
        transport: options.transport
      });

      if (pushResult.ok) {
        targetStep.deliveredReminderKeys = alert ? freshEvents.map(reminderKey) : [];
        for (const key of targetStep.deliveredReminderKeys) delivered.add(key);
      }
      targetStep.isConsumed = pushResult.ok;
      targetStep.consumedAt = now;
      targetStep.pushStatus = pushResult.statusCode;

      let planStatus = plan.status;
      const allConsumed = steps.length > 0 && steps.every(s => s.isConsumed);
      const lastStepEnd = isEnd;

      if (pushResult.statusCode === 410 || pushResult.reason === "BadDeviceToken" || pushResult.reason === "Unregistered") {
        planStatus = "token_expired";
        expiredTokenCount += 1;
      } else if (pushResult.ok && (allConsumed || lastStepEnd)) {
        planStatus = "completed";
        if (pushResult.ok) dispatchedCount += 1;
      } else if (pushResult.ok) {
        dispatchedCount += 1;
      }

      const remainingSteps = steps.filter(s => !s.isConsumed);
      const nextDispatchAt = remainingSteps.length > 0
        ? new Date(Math.min(...remainingSteps.map(s => new Date(s.scheduledAt).getTime())))
        : null;

      const update = {
        steps,
        status: planStatus,
        nextDispatchAt,
        deliveredReminderKeys: [...delivered],
        updatedAt: now
      };
      if (database) await finishDispatch(database, plan, update);
      else await options.updatePlan(plan._id, update);
    } catch (planError) {
      console.error(`Failed to process live activity plan ${plan?._id}:`, planError);
    }
  }

  return {
    ok: true,
    processedCount,
    dispatchedCount,
    expiredTokenCount
  };
}

async function queryActivePlansFromDb(now, options = {}) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const db = cloudbase.init({}).database();
  const _ = db?.command;

  const pageSize = options.pageSize ?? 100;
  const maxPages = options.maxPages ?? 10;
  const plans = [];

  let queryFilter = {
    status: "active"
  };
  if (typeof _?.gte === "function") {
    queryFilter.expireAt = _.gte(now);
  }
  if (typeof _?.and === "function" && typeof _?.or === "function" && typeof _?.lte === "function") {
    queryFilter = _.and([
      { status: "active" },
      { expireAt: _.gte(now) },
      _.or([
        { nextDispatchAt: _.lte(now) },
        { nextDispatchAt: typeof _?.exists === "function" ? _.exists(false) : null },
        { nextDispatchAt: null }
      ])
    ]);
  }

  for (let page = 0; page < maxPages; page++) {
    let query = db.collection(COLLECTION_NAME).where(queryFilter);
    if (typeof query.orderBy === "function") {
      query = query.orderBy("nextDispatchAt", "asc");
    }
    if (typeof query.skip === "function") {
      query = query.skip(page * pageSize);
    }
    if (typeof query.limit === "function") {
      query = query.limit(pageSize);
    }
    const res = await query.get();
    const batch = res.data ?? [];
    plans.push(...batch);
    if (batch.length < pageSize || typeof query.skip !== "function") {
      break;
    }
  }

  return plans;
}
