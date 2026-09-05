const admin = require('firebase-admin');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');

admin.initializeApp();

const db = admin.firestore();

const STATUS_MESSAGES = {
  accepted: {
    title: 'Order Accepted',
    body: 'Your order has been accepted.',
  },
  packed: {
    title: 'Order Packed',
    body: 'Your order has been packed and is being prepared.',
  },
  outForDelivery: {
    title: 'Out for Delivery',
    body: 'Your order is on the way.',
  },
  delivered: {
    title: 'Order Delivered',
    body: 'Your order has been delivered. Thank you for using QuickDrop!',
  },
  cancelled: {
    title: 'Order Cancelled',
    body: 'Your order has been cancelled.',
  },
};

function normalizeStatus(value) {
  const normalized = String(value || '').trim().toLowerCase();

  switch (normalized) {
    case 'pending':
      return 'pending';
    case 'accepted':
    case 'confirmed':
      return 'accepted';
    case 'packed':
      return 'packed';
    case 'out for delivery':
    case 'outfordelivery':
    case 'out_for_delivery':
      return 'outForDelivery';
    case 'delivered':
      return 'delivered';
    case 'rejected':
      return 'rejected';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    default:
      return 'pending';
  }
}

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, String(value ?? '')]),
  );
}

function orderIdFrom(data, fallbackId) {
  return String(data.orderId || fallbackId || '').trim();
}

async function recordNotification({
  recipientType,
  recipientId,
  title,
  body,
  data,
  fcmToken,
}) {
  await db.collection('notification_history').add({
    recipientType,
    recipientId,
    title,
    body,
    data,
    fcmToken: fcmToken || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function sendPushAndRecord({
  recipientType,
  recipientId,
  token,
  title,
  body,
  data,
}) {
  const normalizedData = stringifyData(data);

  await recordNotification({
    recipientType,
    recipientId,
    title,
    body,
    data: normalizedData,
    fcmToken: token,
  });

  if (!token) {
    logger.info('Skipping FCM send because token is missing.', {
      recipientType,
      recipientId,
    });
    return;
  }

  await admin.messaging().send({
    token,
    notification: { title, body },
    data: normalizedData,
    android: {
      priority: 'high',
      notification: {
        channelId: 'quickdrop_high_importance',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  });
}

async function getAdminTokens() {
  const snapshot = await db
    .collection('notification_tokens')
    .where('userType', '==', 'admin')
    .get();

  return snapshot.docs
    .map((doc) => ({
      recipientId: doc.data().userId,
      token: doc.data().fcmToken,
    }))
    .filter((entry) => Boolean(entry.token));
}

exports.notifyOrderCreated = onDocumentCreated('orders/{orderDocId}', async (event) => {
  const data = event.data?.data() || {};
  const orderId = orderIdFrom(data, event.params.orderDocId);
  const ownerPhone = String(data.ownerPhone || data.phoneNumber || data.phone || '').trim();
  const tokens = await getAdminTokens();

  const jobs = [
    tokens.map(({ recipientId, token }) =>
      sendPushAndRecord({
        recipientType: 'admin',
        recipientId: String(recipientId || 'unknown'),
        token,
        title: 'New Order Received',
        body: orderId
          ? `Order ${orderId} has been placed.`
          : 'A new order has been placed.',
        data: {
          kind: 'new_order',
          orderId,
        },
      }),
    ),
  ];

  if (ownerPhone) {
    const customerTokenDoc = await db
      .collection('notification_tokens')
      .doc(`customer_${ownerPhone}`)
      .get();
    const customerToken = customerTokenDoc.data()?.fcmToken;

    jobs.push(
      sendPushAndRecord({
        recipientType: 'customer',
        recipientId: ownerPhone,
        token: customerToken,
        title: 'Order Placed',
        body: orderId
          ? `Your order ${orderId} has been placed successfully.`
          : 'Your order has been placed successfully.',
        data: {
          kind: 'order_created',
          orderId,
          status: 'pending',
        },
      }),
    );
  } else {
    logger.warn('Order created without owner phone; skipping customer notification.', {
      orderDocId: event.params.orderDocId,
    });
  }

  await Promise.all(jobs.flat());
});

exports.notifyOrderStatusUpdated = onDocumentUpdated('orders/{orderDocId}', async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};
  const previousStatus = normalizeStatus(before.status);
  const nextStatus = normalizeStatus(after.status);

  if (previousStatus === nextStatus) {
    return;
  }

  const notification = STATUS_MESSAGES[nextStatus];
  if (!notification) {
    return;
  }

  const ownerPhone = String(after.ownerPhone || before.ownerPhone || '').trim();
  if (!ownerPhone) {
    logger.warn('Order update missing ownerPhone; skipping customer push.', {
      orderDocId: event.params.orderDocId,
      nextStatus,
    });
    return;
  }

  const tokenDoc = await db.collection('notification_tokens').doc(`customer_${ownerPhone}`).get();
  const token = tokenDoc.data()?.fcmToken;
  const orderId = orderIdFrom(after, event.params.orderDocId);

  await sendPushAndRecord({
    recipientType: 'customer',
    recipientId: ownerPhone,
    token,
    title: notification.title,
    body: notification.body,
    data: {
      kind: 'order_status',
      orderId,
      status: nextStatus,
    },
  });
});

exports.notifyNewUserRegistered = onDocumentCreated('user_profiles/{profileId}', async (event) => {
  const data = event.data?.data() || {};
  const name = String(data.name || data.fullName || '').trim();
  const phone = String(data.phoneNumber || data.phone || '').trim();
  const tokens = await getAdminTokens();

  if (tokens.length === 0) {
    return;
  }

  const body = name || phone
    ? `${name || 'A user'}${phone ? ` (${phone})` : ''} has registered.`
    : 'A new user has registered.';

  await Promise.all(
    tokens.map(({ recipientId, token }) =>
      sendPushAndRecord({
        recipientType: 'admin',
        recipientId: String(recipientId || 'unknown'),
        token,
        title: 'New User Registered',
        body,
        data: {
          kind: 'new_user_registered',
          profileId: event.params.profileId,
          name,
          phone,
        },
      }),
    ),
  );
});

// Customers cannot read `delivery_partners` (credentials stay admin-only), so
// the assigned rider's public contact details are mirrored onto the order.
exports.mirrorAssignedPartnerDetails = onDocumentUpdated('orders/{orderDocId}', async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};
  const partnerId = String(after.assignedPartnerId || '').trim();

  if (partnerId === String(before.assignedPartnerId || '').trim()) {
    return;
  }

  if (!partnerId) {
    await event.data.after.ref.update({
      assignedPartnerName: admin.firestore.FieldValue.delete(),
      assignedPartnerPhone: admin.firestore.FieldValue.delete(),
    });
    return;
  }

  const partner = await db.collection('delivery_partners').doc(partnerId).get();
  if (!partner.exists) {
    logger.warn('Assigned partner not found; skipping mirror.', { partnerId });
    return;
  }

  const partnerData = partner.data() || {};
  await event.data.after.ref.update({
    assignedPartnerName: String(partnerData.name || '').trim(),
    assignedPartnerPhone: String(partnerData.phone || '').trim(),
  });
});

exports.deliveryPartnerLogin =
  require('./delivery_partner_auth').deliveryPartnerLogin;

// Riders cannot write `currentOrderId` (admin-only collection), so the trusted
// backend releases the rider once the assigned order reaches a terminal state.
exports.releaseRiderOnOrderDelivered = onDocumentUpdated('orders/{orderDocId}', async (event) => {
  const before = event.data?.before?.data() || {};
  const after = event.data?.after?.data() || {};
  const previousStatus = normalizeStatus(before.status);
  const nextStatus = normalizeStatus(after.status);

  if (!['delivered', 'cancelled', 'rejected'].includes(nextStatus)
    || previousStatus === nextStatus) {
    return;
  }

  const partnerId = String(after.assignedPartnerId || '').trim();
  if (!partnerId) {
    return;
  }

  const orderDocId = event.params.orderDocId;
  const riderRef = db.collection('delivery_partners').doc(partnerId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(riderRef);
    if (!snapshot.exists) {
      logger.warn('Assigned partner not found; skipping release.', { partnerId });
      return;
    }

    const rider = snapshot.data() || {};
    if (String(rider.currentOrderId || '').trim() !== orderDocId) {
      return;
    }

    transaction.update(riderRef, {
      currentOrderId: '',
      currentOrderAssignedAt: admin.firestore.FieldValue.delete(),
      availabilityStatus: rider.isOnDuty === true ? 'available' : 'offline',
      currentOrderReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
});
