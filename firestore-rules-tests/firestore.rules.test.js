'use strict';

const { readFileSync } = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT_ID = 'quickdrop-rules-test';
let testEnv;

function customerDb(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

function riderDb(uid) {
  return customerDb(uid, { deliveryPartner: true });
}

function adminDb(uid = 'adminA') {
  return customerDb(uid, { admin: true });
}

function order(ownerUid, overrides = {}) {
  return {
    orderId: 'QD-test',
    ownerPhone: '+919876543210',
    ownerUid,
    ownerName: 'Customer',
    name: 'Customer',
    phone: '+919876543210',
    address: '1 Test Street',
    customerName: 'Customer',
    phoneNumber: '+919876543210',
    deliveryAddress: '1 Test Street',
    paymentMethod: 'Cash on Delivery',
    paymentStatus: 'Pending',
    latitude: null,
    longitude: null,
    items: [],
    subtotal: 100,
    deliveryCharge: 10,
    totalAmount: 110,
    status: 'Pending',
    statusUpdatedAt: new Date(),
    statusHistory: [{ status: 'Pending', updatedAt: new Date() }],
    createdAt: new Date(),
    ...overrides,
  };
}

function riderProfile(currentOrderId, overrides = {}) {
  return {
    name: 'Rider A',
    isActive: true,
    isOnDuty: true,
    availabilityStatus: 'assigned',
    currentOrderId,
    latitude: 12.9716,
    longitude: 77.5946,
    lastLocationUpdatedAt: new Date(),
    ...overrides,
  };
}

function message(senderId, senderType) {
  return {
    senderId,
    senderType,
    senderName: senderType === 'customer' ? 'Customer' : 'Rider A',
    message: 'Hello from local emulator',
    createdAt: serverTimestamp(),
    isDelivered: false,
    isSeen: false,
  };
}

async function seed(documents) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [pathParts, data] of documents) {
      await setDoc(doc(db, ...pathParts), data);
    }
  });
}

async function seedAssignedOrder(orderId, status, profileOverrides = {}) {
  await seed([
    [
      ['delivery_partners', 'riderA'],
      riderProfile(orderId, profileOverrides),
    ],
    [
      ['orders', orderId],
      order('customerA', {
        assignedPartnerId: 'riderA',
        status,
      }),
    ],
  ]);
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: '127.0.0.1',
      port: 8081,
      rules: readFileSync(path.resolve(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

test('customer A can read only their UID-owned order', async () => {
  await seed([[['orders', 'owner-order'], order('customerA')]]);
  await assertSucceeds(getDoc(doc(customerDb('customerA'), 'orders', 'owner-order')));
  await assertFails(getDoc(doc(customerDb('customerB'), 'orders', 'owner-order')));
});

test('ownerPhone never grants legacy order access', async () => {
  await seed([[['orders', 'legacy-order'], order('', { ownerPhone: '+919876543210' })]]);
  await assertFails(getDoc(doc(
    customerDb('customerA', { phone_number: '+919876543210' }),
    'orders',
    'legacy-order',
  )));
  await assertSucceeds(getDoc(doc(adminDb(), 'orders', 'legacy-order')));
});

test('customer can create only a UID-owned unassigned Pending order', async () => {
  const db = customerDb('customerA');
  await assertSucceeds(setDoc(doc(db, 'orders', 'valid-create'), order('customerA')));
  await assertFails(setDoc(doc(db, 'orders', 'wrong-owner'), order('customerB')));
  await assertFails(setDoc(doc(db, 'orders', 'assigned-create'), order('customerA', {
    assignedPartnerId: 'riderA',
  })));
  await assertFails(setDoc(doc(db, 'orders', 'protected-create'), order('customerA', {
    currentOrderId: 'order-not-allowed-here',
  })));
});

test('customer cannot change rider/backend-owned fields and can only cancel Pending safely', async () => {
  await seed([[['orders', 'customer-order'], order('customerA')]]);
  const orderRef = doc(customerDb('customerA'), 'orders', 'customer-order');
  await assertFails(updateDoc(orderRef, { assignedPartnerId: 'riderA' }));
  await assertFails(updateDoc(orderRef, {
    status: 'Out for Delivery',
    statusUpdatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(orderRef, {
    status: 'Cancelled',
    statusUpdatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(orderRef, { deliveryAddress: 'Changed by customer' }));
});

test('admin claim permits operations while an ordinary user cannot impersonate admin', async () => {
  await seed([[['orders', 'admin-order'], order('customerA')]]);
  await assertSucceeds(updateDoc(doc(adminDb(), 'orders', 'admin-order'), {
    assignedPartnerId: 'riderA',
    assignedAt: serverTimestamp(),
    assignmentType: 'manual',
  }));
  await assertFails(updateDoc(doc(customerDb('customerB'), 'orders', 'admin-order'), {
    assignedPartnerId: 'riderB',
  }));
});

test('assigned rider can read only their assigned order', async () => {
  await seed([
    [['orders', 'assigned'], order('customerA', { assignedPartnerId: 'riderA' })],
    [['orders', 'unassigned'], order('customerA')],
    [['orders', 'other-rider'], order('customerA', { assignedPartnerId: 'riderB' })],
  ]);
  const db = riderDb('riderA');
  await assertSucceeds(getDoc(doc(db, 'orders', 'assigned')));
  await assertFails(getDoc(doc(db, 'orders', 'unassigned')));
  await assertFails(getDoc(doc(db, 'orders', 'other-rider')));
});

test('rider cannot self-assign or change an order assignment', async () => {
  await seedAssignedOrder('rider-order', 'Pending');
  const db = riderDb('riderA');
  const orderRef = doc(db, 'orders', 'rider-order');
  await assertFails(updateDoc(orderRef, { assignedPartnerId: 'riderB' }));
  await assertFails(updateDoc(doc(db, 'orders', 'unassigned'), {
    assignedPartnerId: 'riderA',
  }));
});

for (const [oldStatus, newStatus] of [
  ['Pending', 'Accepted'],
  ['Pending', 'Rejected'],
  ['Accepted', 'Going to Store'],
  ['Going to Store', 'Reached Store'],
  ['Reached Store', 'Order Collected'],
  ['Order Collected', 'Out for Delivery'],
  ['Out for Delivery', 'Delivered'],
]) {
  test(`rider valid transition: ${oldStatus} to ${newStatus}`, async () => {
    const orderId = `transition-${newStatus.replaceAll(' ', '-').toLowerCase()}`;
    await seedAssignedOrder(orderId, oldStatus, {
      availabilityStatus: oldStatus === 'Pending' ? 'assigned' : 'on_delivery',
    });
    await assertSucceeds(updateDoc(doc(riderDb('riderA'), 'orders', orderId), {
      status: newStatus,
      statusUpdatedAt: serverTimestamp(),
      statusHistory: [{ status: newStatus, updatedAt: new Date() }],
    }));
  });
}

test('rider status jumps and obsolete Packed shortcut are denied', async () => {
  await seedAssignedOrder('jump-order', 'Accepted', { availabilityStatus: 'assigned' });
  const ref = doc(riderDb('riderA'), 'orders', 'jump-order');
  await assertFails(updateDoc(ref, {
    status: 'Out for Delivery',
    statusUpdatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ref, {
    status: 'Packed',
    statusUpdatedAt: serverTimestamp(),
  }));
});

for (const [name, profileOverrides] of [
  ['inactive', { isActive: false }],
  ['off duty', { isOnDuty: false }],
  ['wrong current order', { currentOrderId: 'different-order' }],
  ['not assigned availability', { availabilityStatus: 'available' }],
]) {
  test(`rider acceptance/rejection is denied when ${name}`, async () => {
    await seedAssignedOrder('reservation-order', 'Pending', profileOverrides);
    const ref = doc(riderDb('riderA'), 'orders', 'reservation-order');
    await assertFails(updateDoc(ref, {
      status: 'Accepted',
      statusUpdatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(ref, {
      status: 'Rejected',
      statusUpdatedAt: serverTimestamp(),
    }));
  });
}

test('rider can update legitimate operational profile fields only', async () => {
  await seed([[['delivery_partners', 'riderA'], riderProfile('active-order')]]);
  const profileRef = doc(riderDb('riderA'), 'delivery_partners', 'riderA');
  await assertSucceeds(updateDoc(profileRef, {
    isOnDuty: false,
    availabilityStatus: 'assigned',
  }));
  await assertSucceeds(updateDoc(profileRef, {
    latitude: 13.0,
    longitude: 77.6,
    lastLocationUpdatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(profileRef, { currentOrderId: 'different-order' }));
  await assertFails(updateDoc(profileRef, { name: 'Changed by rider' }));
});

test('rider availability values and types are validated', async () => {
  const validStatuses = ['offline', 'available', 'assigned', 'on_delivery'];
  for (const status of validStatuses) {
    await seed([[['delivery_partners', 'riderA'], riderProfile('active-order')]]);
    await assertSucceeds(updateDoc(doc(riderDb('riderA'), 'delivery_partners', 'riderA'), {
      availabilityStatus: status,
    }));
  }
  await seed([[['delivery_partners', 'riderA'], riderProfile('active-order')]]);
  const profileRef = doc(riderDb('riderA'), 'delivery_partners', 'riderA');
  await assertFails(updateDoc(profileRef, { availabilityStatus: 'busy' }));
  await assertFails(updateDoc(profileRef, { isOnDuty: 'true' }));
});

test('private credentials deny every direct client including claimed admin', async () => {
  await seed([[['delivery_partner_credentials', 'riderA'], {
    uid: 'riderA',
    phoneCanonical: '+919876543210',
    pinHash: 'not-a-real-secret',
  }]]);
  const credentialPath = ['delivery_partner_credentials', 'riderA'];
  for (const db of [customerDb('customerA'), riderDb('riderA'), adminDb()]) {
    await assertFails(getDoc(doc(db, ...credentialPath)));
    await assertFails(setDoc(doc(db, ...credentialPath), { uid: 'riderA' }));
    await assertFails(updateDoc(doc(db, ...credentialPath), { uid: 'changed' }));
    await assertFails(deleteDoc(doc(db, ...credentialPath)));
  }
});

test('order owner and assigned rider can use chat; unrelated users cannot', async () => {
  await seed([
    [['orders', 'chat-order'], order('customerA', { assignedPartnerId: 'riderA' })],
    [['delivery_partners', 'riderA'], riderProfile('chat-order')],
  ]);
  const messageRef = doc(customerDb('customerA'), 'orders', 'chat-order', 'messages', 'message-1');
  await assertSucceeds(setDoc(messageRef, message('customerA', 'customer')));
  await assertSucceeds(getDoc(doc(riderDb('riderA'), 'orders', 'chat-order', 'messages', 'message-1')));
  const riderMessageRef = doc(riderDb('riderA'), 'orders', 'chat-order', 'messages', 'message-2');
  await assertSucceeds(setDoc(riderMessageRef, message('riderA', 'deliveryPartner')));
  await assertSucceeds(getDoc(doc(customerDb('customerA'), 'orders', 'chat-order', 'messages', 'message-2')));
  await assertFails(getDoc(doc(customerDb('customerB'), 'orders', 'chat-order', 'messages', 'message-1')));
  await assertFails(getDoc(doc(riderDb('riderB'), 'orders', 'chat-order', 'messages', 'message-1')));
});

test('chat receipts progress monotonically and cannot have timestamps rewritten', async () => {
  await seed([
    [['orders', 'receipt-order'], order('customerA', { assignedPartnerId: 'riderA' })],
    [['delivery_partners', 'riderA'], riderProfile('receipt-order')],
    [[
      'orders',
      'receipt-order',
      'messages',
      'receipt-message',
    ], {
      senderId: 'customerA',
      senderType: 'customer',
      senderName: 'Customer',
      message: 'Track this receipt',
      createdAt: new Date(),
      isDelivered: false,
      isSeen: false,
    }],
  ]);
  const riderMessage = doc(riderDb('riderA'), 'orders', 'receipt-order', 'messages', 'receipt-message');
  await assertSucceeds(updateDoc(riderMessage, {
    isDelivered: true,
    deliveredAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(riderMessage, {
    isSeen: true,
    seenAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(riderMessage, { isDelivered: false }));
  await assertFails(updateDoc(riderMessage, { seenAt: serverTimestamp() }));
});

test('generic fallback cannot bypass order, chat, or credential restrictions', async () => {
  await seed([
    [['orders', 'fallback-order'], order('customerA', { assignedPartnerId: 'riderA' })],
    [['delivery_partner_credentials', 'riderA'], { uid: 'riderA' }],
    [[
      'orders',
      'fallback-order',
      'messages',
      'message-1',
    ], {
      senderId: 'customerA',
      senderType: 'customer',
      senderName: 'Customer',
      message: 'Private order chat',
      createdAt: new Date(),
      isDelivered: false,
      isSeen: false,
    }],
  ]);
  const unrelated = customerDb('customerB');
  await assertFails(getDoc(doc(unrelated, 'orders', 'fallback-order')));
  await assertFails(getDoc(doc(unrelated, 'orders', 'fallback-order', 'messages', 'message-1')));
  await assertFails(getDoc(doc(unrelated, 'delivery_partner_credentials', 'riderA')));
});
