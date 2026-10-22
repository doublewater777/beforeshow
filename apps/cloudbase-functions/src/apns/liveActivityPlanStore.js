import { randomUUID } from 'node:crypto';
import { deliveredReminderKeys } from './liveActivityReminder.js';

const COLLECTION = 'liveActivityPlans';

export async function liveActivityDatabase() {
  const { default: cloudbase } = await import('@cloudbase/node-sdk');
  return cloudbase.init({}).database();
}

function document(db, id) { return db.collection(COLLECTION).doc(id); }
function check(result) {
  if (result?.code) throw Object.assign(new Error(result.message), { code: result.code });
  return result;
}
function data(result) {
  check(result);
  return Array.isArray(result.data) ? result.data[0] ?? null : result.data;
}

export async function readPlan(db, id) { return data(await document(db, id).get()); }

export async function registerPlan(db, incoming) {
  return db.runTransaction(async transaction => {
    const ref = document(transaction, incoming._id);
    const current = data(await ref.get());
    if (current?.planSecretHash && current.planSecretHash !== incoming.planSecretHash) {
      throw Object.assign(new Error('Device secret does not match existing plan.'), { code: 'PLAN_AUTH_FORBIDDEN' });
    }
    if (current && current.version >= incoming.version) {
      if (current.version > incoming.version) {
        throw Object.assign(new Error('Incoming plan version is older than existing registered plan.'), { code: 'STALE_PLAN_VERSION' });
      }
      return { acceptedVersion: current.version, planID: current.planID, idempotent: true };
    }
    const { _id, ...record } = incoming;
    check(await ref.set({ ...record, deliveredReminderKeys: deliveredReminderKeys(current),
      dispatchClaim: current?.dispatchClaim ?? null }));
    return { acceptedVersion: incoming.version, planID: incoming.planID };
  });
}

export async function claimDispatch(db, candidate, now) {
  return db.runTransaction(async transaction => {
    const ref = document(transaction, candidate._id);
    const current = data(await ref.get());
    if (!current || current.status !== 'active' || current.version !== candidate.version) return null;
    if (current.dispatchClaim && new Date(current.dispatchClaim.expiresAt) > now) return null;
    const claim = { id: randomUUID(), expiresAt: new Date(now.getTime() + 60_000) };
    check(await ref.update({ dispatchClaim: claim }));
    return { ...current, _id: candidate._id, dispatchClaim: claim };
  });
}

export async function finishDispatch(db, plan, update) {
  return db.runTransaction(async transaction => {
    const ref = document(transaction, plan._id);
    const current = data(await ref.get());
    if (!current || current.dispatchClaim?.id !== plan.dispatchClaim.id) return;
    const receipts = [...new Set([...deliveredReminderKeys(current), ...update.deliveredReminderKeys])];
    // A replacement plan keeps its own steps/status while receiving this in-flight delivery's receipt.
    const patch = current.version === plan.version && current.status === 'active' ? update : { updatedAt: update.updatedAt };
    check(await ref.update({ ...patch, deliveredReminderKeys: receipts, dispatchClaim: null }));
  });
}
