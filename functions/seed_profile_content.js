const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function readJsonIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) {
      return null;
    }
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function projectIdFromEnv() {
  if (isNonEmptyString(process.env.GOOGLE_CLOUD_PROJECT)) {
    return process.env.GOOGLE_CLOUD_PROJECT.trim();
  }
  if (isNonEmptyString(process.env.GCLOUD_PROJECT)) {
    return process.env.GCLOUD_PROJECT.trim();
  }

  if (isNonEmptyString(process.env.FIREBASE_CONFIG)) {
    const raw = process.env.FIREBASE_CONFIG.trim();

    // FIREBASE_CONFIG can be JSON string or file path.
    if (raw.startsWith('{')) {
      try {
        const parsed = JSON.parse(raw);
        if (isNonEmptyString(parsed.projectId)) {
          return parsed.projectId.trim();
        }
      } catch (_) {
        // Ignore invalid JSON.
      }
    } else {
      const fileJson = readJsonIfExists(raw);
      if (fileJson && isNonEmptyString(fileJson.project_id)) {
        return fileJson.project_id.trim();
      }
      if (fileJson && isNonEmptyString(fileJson.projectId)) {
        return fileJson.projectId.trim();
      }
    }
  }

  return null;
}

function projectIdFromFirebaseJson(repoRoot) {
  const firebaseJsonPath = path.join(repoRoot, 'firebase.json');
  const firebaseJson = readJsonIfExists(firebaseJsonPath);
  if (!firebaseJson) {
    return null;
  }

  const fromAndroidDefault = firebaseJson.flutter?.platforms?.android?.default?.projectId;
  if (isNonEmptyString(fromAndroidDefault)) {
    return fromAndroidDefault.trim();
  }

  const fromDartConfig =
    firebaseJson.flutter?.platforms?.dart?.['lib/firebase_options.dart']?.projectId;
  if (isNonEmptyString(fromDartConfig)) {
    return fromDartConfig.trim();
  }

  return null;
}

function projectIdFromFirebaserc(repoRoot) {
  const firebasercPath = path.join(repoRoot, '.firebaserc');
  const firebaserc = readJsonIfExists(firebasercPath);
  if (!firebaserc || typeof firebaserc !== 'object') {
    return null;
  }

  const projects = firebaserc.projects;
  if (!projects || typeof projects !== 'object') {
    return null;
  }

  if (isNonEmptyString(projects.default)) {
    return projects.default.trim();
  }

  // Fallback for malformed alias files: pick first non-empty string value.
  for (const value of Object.values(projects)) {
    if (isNonEmptyString(value)) {
      return value.trim();
    }
  }

  return null;
}

function resolveProjectId() {
  const repoRoot = path.resolve(__dirname, '..');

  return (
    projectIdFromEnv() ||
    projectIdFromFirebaseJson(repoRoot) ||
    projectIdFromFirebaserc(repoRoot) ||
    'quickdrop-cbf49'
  );
}

const projectId = resolveProjectId();

if (!projectId) {
  throw new Error(
    'Unable to detect Firebase project ID. Set GOOGLE_CLOUD_PROJECT or configure firebase.json/.firebaserc.',
  );
}

function firebaseToolsConfigPath() {
  const candidates = [
    path.join(process.env.APPDATA || '', 'firebase-tools.json'),
    path.join(process.env.USERPROFILE || '', '.config', 'configstore', 'firebase-tools.json'),
    path.join(process.env.LOCALAPPDATA || '', 'configstore', 'firebase-tools.json'),
  ].filter(Boolean);

  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function readFirebaseCliAccessToken() {
  const configPath = firebaseToolsConfigPath();
  if (!configPath) {
    return null;
  }

  const parsed = readJsonIfExists(configPath);
  const token = parsed?.tokens?.access_token;
  if (!isNonEmptyString(token)) {
    return null;
  }

  return token.trim();
}

function readFirebaseCliRefreshToken() {
  const configPath = firebaseToolsConfigPath();
  if (!configPath) {
    return null;
  }

  const parsed = readJsonIfExists(configPath);
  const token = parsed?.tokens?.refresh_token;
  if (!isNonEmptyString(token)) {
    return null;
  }

  return token.trim();
}

async function refreshAccessTokenFromFirebaseCli() {
  const refreshToken = readFirebaseCliRefreshToken();
  if (!refreshToken) {
    return null;
  }

  // Firebase CLI OAuth client values from firebase-tools source.
  const clientId =
    process.env.FIREBASE_CLIENT_ID ||
    '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
  const clientSecret = process.env.FIREBASE_CLIENT_SECRET || 'j9iVZfS8kkCEFUPaAeJV0sAi';

  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
  }).toString();

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`OAuth refresh failed (${response.status}): ${text}`);
  }

  const json = await response.json();
  const accessToken = json?.access_token;
  if (!isNonEmptyString(accessToken)) {
    throw new Error('OAuth refresh response did not contain access_token.');
  }

  return accessToken.trim();
}

let adminReady = false;
let db = null;

try {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  }
  db = admin.firestore();
  adminReady = true;
} catch (error) {
  adminReady = false;
  db = null;
}

console.log(`Using Firebase project: ${projectId}`);

function toFirestoreValue(value) {
  if (value === null || value === undefined) {
    return { nullValue: null };
  }
  if (typeof value === 'string') {
    return { stringValue: value };
  }
  if (typeof value === 'boolean') {
    return { booleanValue: value };
  }
  if (typeof value === 'number') {
    if (Number.isInteger(value)) {
      return { integerValue: String(value) };
    }
    return { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toFirestoreValue) } };
  }
  if (typeof value === 'object') {
    return { mapValue: { fields: toFirestoreFields(value) } };
  }

  return { stringValue: String(value) };
}

function toFirestoreFields(object) {
  const fields = {};
  for (const [key, value] of Object.entries(object)) {
    fields[key] = toFirestoreValue(value);
  }
  return fields;
}

function restDocUrl(collection, docId) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}/${docId}`;
}

async function restDocExists(collection, docId, accessToken) {
  const response = await fetch(restDocUrl(collection, docId), {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (response.status === 200) {
    return true;
  }
  if (response.status === 404) {
    return false;
  }

  const body = await response.text();
  throw new Error(`Firestore REST GET failed (${response.status}): ${body}`);
}

async function restCreateDoc(collection, docId, data, accessToken) {
  const nowIso = new Date().toISOString();
  const payload = {
    fields: toFirestoreFields({
      ...data,
      createdAt: nowIso,
      updatedAt: nowIso,
    }),
  };

  const response = await fetch(restDocUrl(collection, docId), {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Firestore REST PATCH failed (${response.status}): ${body}`);
  }
}

function isCredentialError(error) {
  const message = String(error?.message || error || '').toLowerCase();
  return (
    message.includes('default credentials') ||
    message.includes('could not load the default credentials') ||
    message.includes('unable to detect a project id') ||
    message.includes('project id')
  );
}

async function createIfMissing(collection, docId, data) {
  if (adminReady && db) {
    try {
      const ref = db.collection(collection).doc(docId);
      const snapshot = await ref.get();

      if (snapshot.exists) {
        console.log(`[skip] ${collection}/${docId} already exists`);
        return;
      }

      await ref.set({
        ...data,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`[create] ${collection}/${docId}`);
      return;
    } catch (error) {
      if (!isCredentialError(error)) {
        throw error;
      }
      console.log('[info] Admin SDK credentials unavailable, switching to Firebase CLI token fallback.');
    }
  }

  let accessToken = null;
  try {
    accessToken = await refreshAccessTokenFromFirebaseCli();
  } catch (error) {
    const cached = readFirebaseCliAccessToken();
    if (cached) {
      accessToken = cached;
    }
  }

  if (!accessToken) {
    throw new Error(
      'Firebase credentials not found. Run `firebase login` or set GOOGLE_APPLICATION_CREDENTIALS.',
    );
  }

  const exists = await restDocExists(collection, docId, accessToken);
  if (exists) {
    console.log(`[skip] ${collection}/${docId} already exists`);
    return;
  }

  await restCreateDoc(collection, docId, data, accessToken);
  console.log(`[create] ${collection}/${docId}`);
}

async function seedProfileContent() {
  await createIfMissing('app_support', 'customer_support', {
    phone: '+91 8837263356',
    whatsapp: '+91 8837263356',
    email: 'quickdropsupport@gmail.com',
    message:
      'Need help?\n\nOur support team is ready to assist you with orders, delivery updates, account issues and general inquiries.',
  });

  await createIfMissing('app_content', 'about_us', {
    title: 'About QuickDrop',
    content:
      'QuickDrop is a fast and reliable local delivery platform designed to make shopping simple and convenient.\n\nOur mission is to deliver groceries, food, gifts, cosmetics, electronics and daily essentials quickly and safely to customers.\n\nWe focus on fast delivery, trusted stores and excellent customer service.',
  });

  await createIfMissing('app_content', 'privacy_policy', {
    title: 'Privacy Policy',
    content:
      'QuickDrop respects your privacy.\n\nWe collect only the information necessary to provide our services such as mobile number, delivery address and order details.\n\nWe never sell customer information.',
  });

  await createIfMissing('app_content', 'terms_conditions', {
    title: 'Terms & Conditions',
    content:
      'Using QuickDrop means you agree to our terms.\n\nDelivery time may vary depending on traffic, weather and store availability.\n\nQuickDrop reserves the right to cancel invalid or fraudulent orders.',
  });

  await createIfMissing('app_content', 'share_quickdrop', {
    title: 'Share QuickDrop',
    message: 'Experience fast local delivery with QuickDrop.',
    url: '',
  });

  await createIfMissing('app_content', 'rate_app', {
    title: 'Rate QuickDrop',
    message:
      'Enjoying QuickDrop?\n\nPlease rate us on Google Play after the app is published.',
    url: '',
  });
}

seedProfileContent()
  .then(() => {
    console.log('Profile content seed completed.');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Profile content seed failed:', error);
    process.exit(1);
  });
