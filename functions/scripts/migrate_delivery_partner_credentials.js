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

const PROFILE_COLLECTION = 'delivery_partners';
const CREDENTIAL_COLLECTION = 'delivery_partner_credentials';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

function hasPinHash(data) {
  return String(data.pinHash || '').trim().length > 0;
}

function credentialMatches(credential, uid, phone, pinHash) {
  return credential.exists
    && String(credential.data().uid || credential.id) === uid
    && credential.data().phoneCanonical === phone
    && credential.data().pinHash === pinHash;
}

async function copyCredentialIfStillEligible(profileRef, expectedPhone, expectedHash) {
  const credentialRef = db.collection(CREDENTIAL_COLLECTION).doc(profileRef.id);
  const credentialPhoneQuery = db
    .collection(CREDENTIAL_COLLECTION)
    .where('phoneCanonical', '==', expectedPhone);

  return db.runTransaction(async (transaction) => {
    const profile = await transaction.get(profileRef);
    const credential = await transaction.get(credentialRef);
    const credentialsWithPhone = await transaction.get(credentialPhoneQuery);

    if (!profile.exists) {
      return 'skipped-profile-deleted';
    }

    const profileData = profile.data() || {};
    if (!hasPinHash(profileData)) {
      return 'skipped-profile-pinhash-removed';
    }
    if (normalizePhone(profileData.phone) !== expectedPhone) {
      return 'skipped-profile-phone-changed';
    }
    if (profileData.pinHash !== expectedHash) {
      return 'skipped-profile-pinhash-changed';
    }

    const conflictingCredential = credentialsWithPhone.docs.find(
      (doc) => doc.id !== profileRef.id,
    );
    if (conflictingCredential) {
      return 'skipped-credential-phone-conflict';
    }

    if (credential.exists) {
      return credentialMatches(credential, profileRef.id, expectedPhone, expectedHash)
        ? 'already-migrated'
        : 'skipped-credential-conflict';
    }

    // Retain the source hash in the operational profile. It is removed only by
    // a later, separately approved cleanup after production verification.
    transaction.create(credentialRef, {
      uid: profileRef.id,
      phoneCanonical: expectedPhone,
      pinHash: expectedHash,
      schemaVersion: 1,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return 'migrated';
  });
}

async function main() {
  const args = parseMigrationArgs(process.argv.slice(2));
  const report = createReport('delivery-partner-credentials', args.apply);
  const snapshot = await db.collection(PROFILE_COLLECTION).get();
  const candidates = [];
  const phoneCounts = new Map();

  // Always inspect every profile first. Even a limited apply must see duplicate
  // phone values outside its processing window so it cannot create an unsafe
  // credential lookup key.
  for (const profile of snapshot.docs) {
    const data = profile.data() || {};
    const audit = { riderUid: profile.id };

    if (!hasPinHash(data)) {
      record(report, 'skipped-missing-pinhash', audit);
      continue;
    }

    const phone = normalizePhone(data.phone);
    if (!phone) {
      record(report, 'skipped-invalid-or-missing-phone', audit);
      continue;
    }

    const candidate = { profile, data, phone, audit };
    candidates.push(candidate);
    phoneCounts.set(phone, (phoneCounts.get(phone) || 0) + 1);
  }

  const candidatesToProcess = args.limit
    ? candidates.slice(0, args.limit)
    : candidates;

  for (const candidate of candidatesToProcess) {
    const { profile, data, phone, audit } = candidate;
    const planned = { ...audit, phone: maskPhone(phone) };

    // A phone must correspond to exactly one public rider profile before it can
    // become a credential lookup key.
    if (phoneCounts.get(phone) !== 1) {
      record(report, 'skipped-duplicate-profile-phone', planned);
      continue;
    }

    const credentialRef = db.collection(CREDENTIAL_COLLECTION).doc(profile.id);
    const credential = await credentialRef.get();
    const existingForPhone = await db
      .collection(CREDENTIAL_COLLECTION)
      .where('phoneCanonical', '==', phone)
      .limit(2)
      .get();
    const conflictingCredential = existingForPhone.docs.find(
      (doc) => doc.id !== profile.id,
    );

    if (conflictingCredential) {
      record(report, 'skipped-credential-phone-conflict', planned);
      continue;
    }
    if (credential.exists) {
      record(
        report,
        credentialMatches(credential, profile.id, phone, data.pinHash)
          ? 'already-migrated'
          : 'skipped-credential-conflict',
        planned,
      );
      continue;
    }

    if (!args.apply) {
      record(report, 'would-copy-credential', planned);
      continue;
    }

    const outcome = await copyCredentialIfStillEligible(profile.ref, phone, data.pinHash);
    record(report, outcome, planned);
  }

  if (args.limit && candidates.length > args.limit) {
    record(report, 'not-processed-due-to-limit', {
      count: candidates.length - args.limit,
    });
  }

  finishReport(report, args.report);
}

main().catch((error) => {
  // Never print source document data, PINs, or hashes.
  console.error('Delivery credential migration failed:', error.message);
  process.exitCode = 1;
});
