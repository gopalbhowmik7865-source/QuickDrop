const admin = require('firebase-admin');

async function main() {
  const email = (process.argv[2] || '').trim().toLowerCase();

  if (!email || !email.includes('@')) {
    throw new Error(
      'Usage: node set_admin_claim.js <admin-email>\nExample: node set_admin_claim.js admin@example.com',
    );
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
    });
  }

  const auth = admin.auth();
  const user = await auth.getUserByEmail(email);
  const claims = user.customClaims || {};

  if (claims.admin === true) {
    console.log(`admin claim already set for ${email} (uid: ${user.uid})`);
    return;
  }

  const nextClaims = { ...claims, admin: true };
  await auth.setCustomUserClaims(user.uid, nextClaims);
  await auth.revokeRefreshTokens(user.uid);

  const updated = await auth.getUser(user.uid);
  console.log(
    `admin claim assigned for ${email} (uid: ${user.uid}) ->`,
    updated.customClaims || {},
  );
}

main().catch((error) => {
  console.error('Failed to set admin claim:', error.message || error);
  process.exitCode = 1;
});