'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  _test: { evaluateApprovedRiderPhoneLogin },
} = require('../approved_rider_otp_auth');

const riderUid = 'rider-uid';
const riderPhone = '+919876543210';

function firestoreFor(profiles, profileUid = riderUid) {
  const documents = Object.entries(profiles).map(([id, data]) => ({
    id,
    data: () => data,
  }));

  return {
    collection(name) {
      assert.equal(name, 'delivery_partners');
      return {
        doc(id) {
          return {
            async get() {
              const data = profiles[id];
              return {
                exists: data !== undefined,
                data: () => data,
              };
            },
          };
        },
        async get() {
          return { docs: documents };
        },
      };
    },
    profileUid,
  };
}

function authFor({
  user,
  missingUser = false,
}) {
  const calls = { setClaims: [], revoked: [] };
  return {
    calls,
    async getUser(uid) {
      assert.equal(uid, riderUid);
      if (missingUser) {
        const error = new Error('missing');
        error.code = 'auth/user-not-found';
        throw error;
      }
      return user;
    },
    async setCustomUserClaims(uid, claims) {
      calls.setClaims.push({ uid, claims });
    },
    async revokeRefreshTokens(uid) {
      calls.revoked.push(uid);
    },
  };
}

function approvedProfile(overrides = {}) {
  return {
    phone: riderPhone,
    isActive: true,
    approvalState: 'approved',
    ...overrides,
  };
}

function phoneUser(overrides = {}) {
  return {
    uid: riderUid,
    phoneNumber: riderPhone,
    providerData: [{ providerId: 'phone', phoneNumber: riderPhone }],
    customClaims: {},
    ...overrides,
  };
}

async function expectCode(action, code) {
  await assert.rejects(action, (error) => error && error.code === code);
}

test('approved active rider receives only a refreshed rider authorization result', async () => {
  const auth = authFor({ user: phoneUser({ customClaims: { admin: true } }) });
  const result = await evaluateApprovedRiderPhoneLogin(
    { auth: { uid: riderUid }, data: { uid: 'attacker', phone: '+910000000000' } },
    { auth, db: firestoreFor({ [riderUid]: approvedProfile() }) },
  );

  assert.deepEqual(result, {
    eligible: true,
    approvalState: 'approved',
    requiresTokenRefresh: true,
  });
  assert.deepEqual(auth.calls.setClaims, [{
    uid: riderUid,
    claims: { admin: true, deliveryPartner: true },
  }]);
  assert.deepEqual(auth.calls.revoked, []);
});

test('unauthenticated callers are denied', async () => {
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: null },
      { auth: authFor({ user: phoneUser() }), db: firestoreFor({}) },
    ),
    'unauthenticated',
  );
});

test('unknown Firebase Auth UID is denied', async () => {
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid } },
      { auth: authFor({ missingUser: true }), db: firestoreFor({}) },
    ),
    'permission-denied',
  );
});

test('missing rider profile is denied and a stale rider claim is revoked', async () => {
  const auth = authFor({ user: phoneUser({ customClaims: { deliveryPartner: true, admin: true } }) });
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid } },
      { auth, db: firestoreFor({}) },
    ),
    'permission-denied',
  );
  assert.deepEqual(auth.calls.setClaims, [{
    uid: riderUid,
    claims: { deliveryPartner: false, admin: true },
  }]);
  assert.deepEqual(auth.calls.revoked, [riderUid]);
});

test('a missing phone provider or phone identity is denied', async () => {
  const withoutProvider = authFor({
    user: phoneUser({ providerData: [], customClaims: { deliveryPartner: true } }),
  });
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid } },
      { auth: withoutProvider, db: firestoreFor({ [riderUid]: approvedProfile() }) },
    ),
    'permission-denied',
  );
  assert.equal(withoutProvider.calls.setClaims[0].claims.deliveryPartner, false);

  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid } },
      {
        auth: authFor({ user: phoneUser({ phoneNumber: '' }) }),
        db: firestoreFor({ [riderUid]: approvedProfile() }),
      },
    ),
    'permission-denied',
  );
});

test('authenticated phone mismatch is denied', async () => {
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid }, data: { phone: riderPhone } },
      {
        auth: authFor({ user: phoneUser({ phoneNumber: '+919999999999' }) }),
        db: firestoreFor({ [riderUid]: approvedProfile() }),
      },
    ),
    'permission-denied',
  );
});

test('a declared rider profile UID mismatch is denied', async () => {
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid } },
      {
        auth: authFor({ user: phoneUser() }),
        db: firestoreFor({
          [riderUid]: approvedProfile({ uid: 'different-rider-uid' }),
        }),
      },
    ),
    'permission-denied',
  );
});

test('unapproved application states are denied', async () => {
  for (const approvalState of ['pending', 'under_review', 'correction_required', 'rejected']) {
    await expectCode(
      () => evaluateApprovedRiderPhoneLogin(
        { auth: { uid: riderUid } },
        {
          auth: authFor({ user: phoneUser() }),
          db: firestoreFor({ [riderUid]: approvedProfile({ approvalState }) }),
        },
      ),
      approvalState === 'rejected' ? 'permission-denied' : 'failed-precondition',
    );
  }
});

test('inactive, disabled, suspended, and retired riders are denied', async () => {
  for (const profile of [
    approvedProfile({ isActive: false }),
    approvedProfile({ isDisabled: true }),
    approvedProfile({ accountStatus: 'suspended' }),
    approvedProfile({ riderStatus: 'retired' }),
  ]) {
    await expectCode(
      () => evaluateApprovedRiderPhoneLogin(
        { auth: { uid: riderUid } },
        { auth: authFor({ user: phoneUser() }), db: firestoreFor({ [riderUid]: profile }) },
      ),
      'permission-denied',
    );
  }
});

test('duplicate active rider identities for one canonical phone are denied', async () => {
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      { auth: { uid: riderUid } },
      {
        auth: authFor({ user: phoneUser() }),
        db: firestoreFor({
          [riderUid]: approvedProfile(),
          duplicateRider: approvedProfile({ phone: '9876543210' }),
        }),
      },
    ),
    'permission-denied',
  );
});

test('a normal customer cannot obtain a rider claim and client values cannot bypass server identity', async () => {
  const auth = authFor({ user: phoneUser() });
  await expectCode(
    () => evaluateApprovedRiderPhoneLogin(
      {
        auth: { uid: riderUid },
        data: { uid: 'another-rider', phone: riderPhone, approvalState: 'approved' },
      },
      { auth, db: firestoreFor({ anotherRider: approvedProfile() }) },
    ),
    'permission-denied',
  );
  assert.deepEqual(auth.calls.setClaims, []);
});

test('legacy active profiles remain compatible until the application schema is deployed', async () => {
  const auth = authFor({ user: phoneUser() });
  const result = await evaluateApprovedRiderPhoneLogin(
    { auth: { uid: riderUid } },
    {
      auth,
      db: firestoreFor({ [riderUid]: approvedProfile({ approvalState: undefined }) }),
    },
  );
  assert.equal(result.approvalState, 'approved');
  assert.equal(auth.calls.setClaims[0].claims.deliveryPartner, true);
});
