'use strict';

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { normalizePhone } = require('./scripts/security_migration_utils');

const PROFILE_COLLECTION = 'delivery_partners';

function normalizedState(value) {
  return String(value || '').trim().toLowerCase().replace(/[\s-]+/g, '_');
}

function hasPhoneProvider(user) {
  return (user.providerData || []).some(
    (provider) => provider.providerId === 'phone',
  );
}

function isExplicitlyDisabled(profile) {
  if (
    profile.isDisabled === true ||
    profile.isSuspended === true ||
    profile.isRetired === true
  ) {
    return true;
  }

  return ['disabled', 'suspended', 'retired'].includes(
    normalizedState(profile.accountStatus || profile.riderStatus),
  );
}

function approvalDecision(profile) {
  const state = normalizedState(
    profile.approvalState || profile.applicationStatus,
  );

  if (!state) {
    // The existing delivery-partner schema predates applications. Until the
    // application workflow exists, an active, non-disabled legacy profile is
    // the only compatible approval signal. New application records must set
    // approvalState explicitly and never rely on this branch.
    return { eligible: true, state: 'legacy_active' };
  }

  if (state === 'approved') {
    return { eligible: true, state };
  }

  return { eligible: false, state };
}

function eligibilityErrorForState(state) {
  switch (state) {
    case 'pending':
    case 'under_review':
      return new HttpsError(
        'failed-precondition',
        'Your QuickDrop Delivery Partner application is under review.',
      );
    case 'correction_required':
      return new HttpsError(
        'failed-precondition',
        'Your QuickDrop Delivery Partner application needs correction.',
      );
    case 'rejected':
      return new HttpsError(
        'permission-denied',
        'Your QuickDrop Delivery Partner application was not approved.',
      );
    default:
      return new HttpsError(
        'permission-denied',
        'This mobile number is not registered as an approved QuickDrop delivery partner.',
      );
  }
}

async function removeStaleRiderClaim(auth, user) {
  const claims = user.customClaims || {};
  if (claims.deliveryPartner !== true) {
    return false;
  }

  // Preserve unrelated claims, fail closed for the rider role, and invalidate
  // refresh tokens. Existing ID tokens still have Firebase's normal bounded
  // lifetime, so future Rules must also check the server-owned active profile.
  await auth.setCustomUserClaims(user.uid, {
    ...claims,
    deliveryPartner: false,
  });
  await auth.revokeRefreshTokens(user.uid);
  return true;
}

async function denyEligibility({ auth, user, error }) {
  if (user) {
    await removeStaleRiderClaim(auth, user);
  }
  throw error;
}

function activeDuplicateProfiles(documents, uid, canonicalPhone) {
  return documents.filter((document) => {
    const profile = document.data() || {};
    return document.id !== uid
      && profile.isActive === true
      && !isExplicitlyDisabled(profile)
      && normalizePhone(profile.phoneCanonical || profile.phone) === canonicalPhone;
  });
}

/**
 * Trusted eligibility check after Firebase Phone Auth. This intentionally
 * ignores request.data: the UID and phone identity come only from Firebase
 * Authentication and the server-owned rider profile.
 */
async function evaluateApprovedRiderPhoneLogin(request, { auth, db }) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in with your phone first.');
  }

  let user;
  try {
    user = await auth.getUser(uid);
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') {
      throw new HttpsError(
        'permission-denied',
        'This mobile number is not registered as an approved QuickDrop delivery partner.',
      );
    }
    throw error;
  }

  if (!hasPhoneProvider(user)) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'A verified phone identity is required for Delivery Partner access.',
      ),
    });
  }

  const canonicalPhone = normalizePhone(user.phoneNumber);
  if (!canonicalPhone) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'A verified phone identity is required for Delivery Partner access.',
      ),
    });
  }

  const profileRef = db.collection(PROFILE_COLLECTION).doc(uid);
  const [profileSnapshot, profilesSnapshot] = await Promise.all([
    profileRef.get(),
    db.collection(PROFILE_COLLECTION).get(),
  ]);

  if (!profileSnapshot.exists) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'This mobile number is not registered as an approved QuickDrop delivery partner.',
      ),
    });
  }

  const profile = profileSnapshot.data() || {};
  const declaredProfileUid = String(profile.uid || '').trim();
  if (declaredProfileUid && declaredProfileUid !== uid) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'This Delivery Partner account has an identity conflict. Please contact QuickDrop Support.',
      ),
    });
  }

  const registeredPhone = normalizePhone(profile.phoneCanonical || profile.phone);
  if (!registeredPhone || registeredPhone !== canonicalPhone) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'Your authenticated phone number does not match the registered Delivery Partner account.',
      ),
    });
  }

  if (profile.isActive !== true || isExplicitlyDisabled(profile)) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'Your Delivery Partner account is currently disabled. Please contact QuickDrop Support.',
      ),
    });
  }

  const approval = approvalDecision(profile);
  if (!approval.eligible) {
    await denyEligibility({
      auth,
      user,
      error: eligibilityErrorForState(approval.state),
    });
  }

  const duplicates = activeDuplicateProfiles(
    profilesSnapshot.docs,
    uid,
    canonicalPhone,
  );
  if (duplicates.length > 0) {
    await denyEligibility({
      auth,
      user,
      error: new HttpsError(
        'permission-denied',
        'This Delivery Partner account has an identity conflict. Please contact QuickDrop Support.',
      ),
    });
  }

  await auth.setCustomUserClaims(uid, {
    ...(user.customClaims || {}),
    deliveryPartner: true,
  });

  return {
    eligible: true,
    approvalState: approval.state === 'legacy_active'
      ? 'approved'
      : approval.state,
    requiresTokenRefresh: true,
  };
}

exports.completeApprovedRiderPhoneLogin = onCall(async (request) =>
  evaluateApprovedRiderPhoneLogin(request, {
    auth: admin.auth(),
    db: admin.firestore(),
  }),
);

exports._test = {
  activeDuplicateProfiles,
  approvalDecision,
  evaluateApprovedRiderPhoneLogin,
  hasPhoneProvider,
  isExplicitlyDisabled,
};
