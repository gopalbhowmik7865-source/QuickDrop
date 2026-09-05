'use strict';

const admin = require('firebase-admin');
const {
  createReport,
  finishReport,
  maskPhone,
  normalizePhone,
  parseMigrationArgs,
  record,
} = require('./security_migration_utils');

const ORDER_COLLECTION = 'orders';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

function hasOwnerUid(data) {
  return String(data.ownerUid || '').trim().length > 0;
}

async function findVerifiedOwner(phone) {
  try {
    const user = await admin.auth().getUserByPhoneNumber(phone);
    const verifiedPhone = normalizePhone(user.phoneNumber);
    if (verifiedPhone !== phone) {
      return { outcome: 'skipped-auth-phone-mismatch' };
    }

    return { outcome: 'matched', uid: user.uid };
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') {
      return { outcome: 'skipped-auth-user-not-found' };
    }

    return {
      outcome: 'skipped-auth-lookup-error',
      errorCode: String(error && error.code ? error.code : 'unknown'),
    };
  }
}

async function setOwnerUidIfStillEligible(orderRef, expectedPhone, uid) {
  return db.runTransaction(async (transaction) => {
    const latest = await transaction.get(orderRef);
    if (!latest.exists) {
      return 'skipped-order-deleted';
    }

    const data = latest.data() || {};
    if (hasOwnerUid(data)) {
      return 'skipped-owner-already-set';
    }
    if (normalizePhone(data.ownerPhone) !== expectedPhone) {
      return 'skipped-owner-phone-changed';
    }

    // Only this field is written. The source ownerPhone is retained as the
    // historical identifier and no client gets an opportunity to claim it.
    transaction.update(orderRef, { ownerUid: uid });
    return 'migrated';
  });
}

async function main() {
  const args = parseMigrationArgs(process.argv.slice(2));
  const report = createReport('legacy-order-owner-uid', args.apply);
  const snapshot = await db.collection(ORDER_COLLECTION).get();
  const orders = args.limit ? snapshot.docs.slice(0, args.limit) : snapshot.docs;

  for (const order of orders) {
    const data = order.data() || {};
    const audit = {
      orderDocId: order.id,
      orderId: String(data.orderId || order.id),
    };

    if (hasOwnerUid(data)) {
      record(report, 'skipped-owner-already-set', audit);
      continue;
    }

    // Do not trust contact, shipping, or arbitrary phone fields for ownership.
    // Only the legacy ownerPhone field is eligible for a verified Auth mapping.
    const ownerPhone = normalizePhone(data.ownerPhone);
    if (!ownerPhone) {
      record(report, 'skipped-invalid-or-missing-owner-phone', audit);
      continue;
    }

    const matched = await findVerifiedOwner(ownerPhone);
    if (matched.outcome !== 'matched') {
      record(report, matched.outcome, {
        ...audit,
        ownerPhone: maskPhone(ownerPhone),
        ...(matched.errorCode ? { errorCode: matched.errorCode } : {}),
      });
      continue;
    }

    const planned = {
      ...audit,
      ownerPhone: maskPhone(ownerPhone),
      candidateOwnerUid: matched.uid,
    };

    if (!args.apply) {
      record(report, 'would-set-owner-uid', planned);
      continue;
    }

    const outcome = await setOwnerUidIfStillEligible(order.ref, ownerPhone, matched.uid);
    record(report, outcome, planned);
  }

  if (args.limit && snapshot.size > args.limit) {
    record(report, 'not-scanned-due-to-limit', { count: snapshot.size - args.limit });
  }

  finishReport(report, args.report);
}

main().catch((error) => {
  // Deliberately omit document contents and identity values from error output.
  console.error('Legacy owner UID migration failed:', error.message);
  process.exitCode = 1;
});
