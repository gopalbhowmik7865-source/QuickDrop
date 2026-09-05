const crypto = require('crypto');
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { normalizePhone } = require('./scripts/security_migration_utils');

const PROFILE_COLLECTION = 'delivery_partners';
const CREDENTIAL_COLLECTION = 'delivery_partner_credentials';

const hashPin = (pin) =>
  crypto.createHash('sha256').update(String(pin || '')).digest('hex');

function hashesMatch(storedHash, suppliedHash) {
  const stored = Buffer.from(String(storedHash || ''), 'utf8');
  const supplied = Buffer.from(String(suppliedHash || ''), 'utf8');

  return stored.length === supplied.length
    && stored.length > 0
    && crypto.timingSafeEqual(stored, supplied);
}

async function findCredentialByPhone(db, canonicalPhone) {
  const snapshot = await db
    .collection(CREDENTIAL_COLLECTION)
    .where('phoneCanonical', '==', canonicalPhone)
    .limit(2)
    .get();

  // A duplicate credential record is unsafe to authenticate. Do not choose one
  // based on query order.
  if (snapshot.size > 1) {
    return { ambiguous: true };
  }

  if (snapshot.empty) {
    return null;
  }

  return {
    id: snapshot.docs[0].id,
    data: snapshot.docs[0].data() || {},
  };
}

async function findLegacyProfileByPhone(db, canonicalPhone) {
  // Transitional compatibility only: profiles created before the credential
  // migration may hold the hash and may use a 10-digit phone value. Scanning is
  // intentional here because a direct equality query cannot safely cover both
  // formats. It must be removed after the credential migration is complete.
  const snapshot = await db.collection(PROFILE_COLLECTION).get();
  const matches = snapshot.docs.filter(
    (doc) => normalizePhone((doc.data() || {}).phone) === canonicalPhone,
  );

  if (matches.length !== 1) {
    return null;
  }

  return {
    id: matches[0].id,
    data: matches[0].data() || {},
  };
}

// Verifies delivery partner phone + PIN server-side so pinHash is never
// exposed to clients, and returns a custom auth token for the app session.
exports.deliveryPartnerLogin = onCall(async (request) => {
  const phone = normalizePhone(request.data && request.data.phone);
  const pin = String((request.data && request.data.pin) || '').trim();

  if (!phone || !pin) {
    throw new HttpsError(
      'invalid-argument',
      'Please enter your phone number and PIN',
    );
  }

  const db = admin.firestore();
  const suppliedHash = hashPin(pin);
  const credential = await findCredentialByPhone(db, phone);

  if (credential && credential.ambiguous) {
    throw new HttpsError('unauthenticated', 'Invalid phone number or PIN');
  }

  let partner;
  let storedHash;

  if (credential) {
    if (String(credential.data.uid || credential.id) !== credential.id) {
      throw new HttpsError('unauthenticated', 'Invalid phone number or PIN');
    }
    partner = await db.collection(PROFILE_COLLECTION).doc(credential.id).get();
    storedHash = credential.data.pinHash;
  } else {
    // Keep existing riders able to sign in until their server-side credential
    // record is copied. This fallback never exposes a hash to a client.
    const legacyPartner = await findLegacyProfileByPhone(db, phone);
    if (legacyPartner) {
      partner = {
        id: legacyPartner.id,
        exists: true,
        data: () => legacyPartner.data,
      };
      storedHash = legacyPartner.data.pinHash;
    }
  }

  if (!partner || !partner.exists) {
    throw new HttpsError('unauthenticated', 'Invalid phone number or PIN');
  }

  const data = partner.data() || {};

  if (!hashesMatch(storedHash, suppliedHash)) {
    throw new HttpsError('unauthenticated', 'Invalid phone number or PIN');
  }
  if (data.isActive !== true) {
    throw new HttpsError(
      'permission-denied',
      'Your account is not active yet. Contact QuickDrop support.',
    );
  }

  const token = await admin.auth().createCustomToken(partner.id, {
    deliveryPartner: true,
  });

  return {
    token,
    partner: {
      id: partner.id,
      phone: data.phone || phone,
      name: data.name || 'Delivery Partner',
    },
  };
});
