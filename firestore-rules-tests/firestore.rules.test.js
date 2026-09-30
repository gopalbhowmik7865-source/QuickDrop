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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');

const PROJECT_ID = 'quickdrop-rules-test';
// Opt in to the isolated candidate; keep the existing local Rules test mode intact.
const profileAddressCandidate = process.env.QUICKDROP_PROFILE_ADDRESS_RULES === '1';
const rulesFile = profileAddressCandidate ? 'firestore.profile-address.rules' : 'firestore.rules';
const profileTest = (name, fn) => test(name, { skip: !profileAddressCandidate }, fn);
let testEnv;

function anonymousDb() {
  return testEnv.unauthenticatedContext().firestore();
}

profileTest('profile owner can create, read, update and delete own document', async () => {
  const ref = doc(customerDb('customerA'), 'users', 'customerA');
  await assertSucceeds(setDoc(ref, { name: 'Customer A' }));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(updateDoc(ref, { name: 'Updated' }));
  await assertSucceeds(deleteDoc(ref));
});

profileTest('customer cannot read, create, update or delete another profile', async () => {
  await seed([[['users', 'customerB'], { name: 'Customer B' }]]);
  const db = customerDb('customerA');
  const ref = doc(db, 'users', 'customerB');
  await assertFails(getDoc(ref));
  await assertFails(setDoc(doc(db, 'users', 'customerC'), { name: 'Forged' }));
  await assertFails(setDoc(ref, { name: 'Overwrite' }));
  await assertFails(updateDoc(ref, { name: 'Tampered' }));
  await assertFails(deleteDoc(ref));
  await assertFails(getDocs(collection(db, 'users')));
});

profileTest('customer can create, read, update and delete own address', async () => {
  const ref = doc(customerDb('customerA'), 'addresses', 'own-address');
  await assertSucceeds(setDoc(ref, { ownerId: 'customerA', line1: 'Test street' }));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(updateDoc(ref, { line1: 'Updated street' }));
  await assertSucceeds(deleteDoc(ref));
});

profileTest('address creation rejects another, missing or invalid ownerId', async () => {
  const ref = doc(customerDb('customerA'), 'addresses', 'forged');
  for (const data of [{ ownerId: 'customerB' }, {}, { ownerId: null }, { ownerId: 1 }]) {
    await assertFails(setDoc(ref, data));
  }
});

profileTest('customer cannot read, update, overwrite, steal or delete another address', async () => {
  await seed([[['addresses', 'other'], { ownerId: 'customerB', line1: 'Private' }]]);
  const ref = doc(customerDb('customerA'), 'addresses', 'other');
  await assertFails(getDoc(ref));
  await assertFails(updateDoc(ref, { line1: 'Tampered' }));
  await assertFails(updateDoc(ref, { ownerId: 'customerA' }));
  await assertFails(setDoc(ref, { ownerId: 'customerA', line1: 'Stolen' }));
  await assertFails(deleteDoc(ref));
});

profileTest('address owner cannot transfer or remove ownership', async () => {
  await seed([[['addresses', 'own'], { ownerId: 'customerA', line1: 'Test' }]]);
  const ref = doc(customerDb('customerA'), 'addresses', 'own');
  await assertFails(updateDoc(ref, { ownerId: 'customerB' }));
  await assertFails(updateDoc(ref, { ownerId: null }));
  await assertFails(setDoc(ref, { line1: 'Owner removed' }));
});

profileTest('owner-filtered address query succeeds; unscoped and foreign queries fail', async () => {
  await seed([
    [['addresses', 'a'], { ownerId: 'customerA' }],
    [['addresses', 'b'], { ownerId: 'customerB' }],
  ]);
  const addresses = collection(customerDb('customerA'), 'addresses');
  const result = await assertSucceeds(getDocs(query(addresses, where('ownerId', '==', 'customerA'))));
  if (result.size !== 1) throw new Error('Expected only the owner address');
  await assertFails(getDocs(addresses));
  await assertFails(getDocs(query(addresses, where('ownerId', '==', 'customerB'))));
});

profileTest('trusted Admin retains profile and address CRUD and list access', async () => {
  const db = adminDb();
  for (const [collectionName, id, data] of [
    ['users', 'customerA', { name: 'Customer' }],
    ['addresses', 'a', { ownerId: 'customerA' }],
  ]) {
    const ref = doc(db, collectionName, id);
    await assertSucceeds(setDoc(ref, data));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(getDocs(collection(db, collectionName)));
    await assertSucceeds(updateDoc(ref, collectionName === 'users'
      ? { name: 'Updated' } : { ownerId: 'customerB' }));
    await assertSucceeds(deleteDoc(ref));
  }
});

profileTest('anonymous and rider clients cannot access profiles or addresses', async () => {
  await seed([
    [['users', 'riderA'], { name: 'Private' }],
    [['addresses', 'rider-address'], { ownerId: 'riderA' }],
  ]);
  for (const db of [anonymousDb(), riderDb('riderA')]) {
    for (const [name, id, data] of [
      ['users', 'riderA', { name: 'Tampered' }],
      ['addresses', 'rider-address', { ownerId: 'riderA' }],
    ]) {
      const ref = doc(db, name, id);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, data));
      await assertFails(updateDoc(ref, data));
      await assertFails(deleteDoc(ref));
      await assertFails(setDoc(doc(db, name, 'new'), data));
    }
  }
});

profileTest('catch-all cannot reopen profile/address descendants or ownerless addresses', async () => {
  await seed([
    [['users', 'customerB', 'private', 'nested'], { secret: 'test' }],
    [['addresses', 'b', 'private', 'nested'], { secret: 'test' }],
    [['addresses', 'ownerless'], { line1: 'Legacy' }],
  ]);
  const db = customerDb('customerA');
  for (const parts of [
    ['users', 'customerB', 'private', 'nested'],
    ['addresses', 'b', 'private', 'nested'],
    ['addresses', 'ownerless'],
  ]) {
    await assertFails(getDoc(doc(db, ...parts)));
    await assertFails(setDoc(doc(db, ...parts), { ownerId: 'customerA' }));
  }
});

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
      rules: readFileSync(path.resolve(__dirname, '..', rulesFile), 'utf8'),
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

test(profileAddressCandidate
  ? 'deployed product permissions still deny customer stock writes'
  : 'checkout permits only a customer stock decrement on an existing product', async () => {
  await seed([
    [['settings', 'app'], { deliveryEnabled: true }],
    [['products', 'checkout-product'], {
      name: 'Checkout Product', price: 100, category: 'Grocery', stock: 5,
    }],
  ]);
  const customer = customerDb('customerA');
  const productRef = doc(customer, 'products', 'checkout-product');

  await assertSucceeds(getDoc(doc(customer, 'settings', 'app')));
  await (profileAddressCandidate ? assertFails : assertSucceeds)(updateDoc(productRef, { stock: 4 }));
  await assertFails(updateDoc(productRef, { stock: 5 }));
  await assertFails(updateDoc(productRef, { stock: -1 }));
  await assertFails(updateDoc(productRef, { name: 'Tampered' }));
  await assertFails(updateDoc(productRef, { stock: 3, price: 1 }));
  await assertFails(updateDoc(
    doc(anonymousDb(), 'products', 'checkout-product'),
    { stock: 3 },
  ));
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
    [['delivery_partners', 'riderA'], riderProfile('assigned')],
    [['orders', 'assigned'], order('customerA', { assignedPartnerId: 'riderA' })],
    [['orders', 'unassigned'], order('customerA')],
    [['orders', 'other-rider'], order('customerA', { assignedPartnerId: 'riderB' })],
  ]);
  const db = riderDb('riderA');
  await assertSucceeds(getDoc(doc(db, 'orders', 'assigned')));
  await assertFails(getDoc(doc(db, 'orders', 'unassigned')));
  await assertFails(getDoc(doc(db, 'orders', 'other-rider')));
});

test('inactive rider with a stale deliveryPartner claim cannot read an assigned order', async () => {
  await seed([
    [['delivery_partners', 'riderA'], riderProfile('inactive-read', { isActive: false })],
    [['orders', 'inactive-read'], order('customerA', { assignedPartnerId: 'riderA' })],
  ]);
  await assertFails(getDoc(doc(riderDb('riderA'), 'orders', 'inactive-read')));
});

test('inactive rider with a stale deliveryPartner claim cannot update an assigned order', async () => {
  await seedAssignedOrder('inactive-update', 'Pending', { isActive: false });
  await assertFails(updateDoc(doc(riderDb('riderA'), 'orders', 'inactive-update'), {
    status: 'Accepted',
    statusUpdatedAt: serverTimestamp(),
    statusHistory: [{ status: 'Accepted', updatedAt: new Date() }],
  }));
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
  await assertFails(updateDoc(profileRef, { isActive: false }));
  await assertFails(updateDoc(profileRef, { name: 'Changed by rider' }));
});

test('inactive rider cannot bypass the active check through duty or availability fields', async () => {
  await seed([[['delivery_partners', 'riderA'], riderProfile('', {
    isActive: false,
    isOnDuty: false,
    availabilityStatus: 'offline',
  })]]);
  const profileRef = doc(riderDb('riderA'), 'delivery_partners', 'riderA');
  await assertFails(updateDoc(profileRef, {
    isOnDuty: true,
    availabilityStatus: 'available',
  }));
  await assertFails(updateDoc(profileRef, {
    isActive: true,
    isOnDuty: true,
    availabilityStatus: 'available',
  }));
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

test('inactive rider with a stale claim cannot read or write assigned-order chat', async () => {
  await seed([
    [['orders', 'inactive-chat'], order('customerA', { assignedPartnerId: 'riderA' })],
    [['delivery_partners', 'riderA'], riderProfile('inactive-chat', { isActive: false })],
    [[
      'orders',
      'inactive-chat',
      'messages',
      'customer-message',
    ], message('customerA', 'customer')],
  ]);
  const rider = riderDb('riderA');
  await assertFails(getDoc(doc(
    rider,
    'orders',
    'inactive-chat',
    'messages',
    'customer-message',
  )));
  await assertFails(setDoc(doc(
    rider,
    'orders',
    'inactive-chat',
    'messages',
    'rider-message',
  ), message('riderA', 'deliveryPartner')));
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

test('anonymous visitors can read only allowlisted public product documents', async () => {
  await seed([
    [['products', 'tea'], {
      name: 'Tea', price: 120, oldPrice: 140, discount: 14,
      category: 'Grocery', subcategory: 'Tea, Coffee & Milk',
      childCategory: 'Tea', imageUrl: 'https://example.test/tea.jpg',
      imageUrls: ['https://example.test/tea.jpg'], stock: 12,
      brand: 'QuickDrop Test', weight: '250', unit: 'g',
      shortDescription: 'Test catalog product',
    }],
  ]);
  await assertSucceeds(getDoc(doc(anonymousDb(), 'products', 'tea')));
  await assertSucceeds(getDocs(collection(anonymousDb(), 'products')));
});

test('product documents containing non-catalog fields are not public', async () => {
  await seed([[['products', 'private-product'], {
    name: 'Unsafe product', price: 10, category: 'Grocery', stock: 1,
    supplierPhone: '+919999999999',
  }]]);
  await assertFails(getDoc(doc(anonymousDb(), 'products', 'private-product')));
});

test('anonymous visitors can read active banners but not inactive banners', async () => {
  await seed([
    [['banners', 'active'], {
      imageUrl: 'https://example.test/banner.jpg', isActive: true,
      order: 1, displayOrder: 1, createdAt: new Date(),
    }],
    [['banners', 'inactive'], {
      imageUrl: 'https://example.test/hidden.jpg', isActive: false,
      order: 2, displayOrder: 2, createdAt: new Date(),
    }],
  ]);
  await assertSucceeds(getDoc(doc(anonymousDb(), 'banners', 'active')));
  await assertFails(getDoc(doc(anonymousDb(), 'banners', 'inactive')));
});

test('anonymous visitors can read sanitized active public shops and inventory only', async () => {
  await seed([
    [['public_shops', 'shopA'], {
      storeId: 'shopA', name: 'Public Shop', area: 'Agartala',
      imageUrl: 'https://example.test/shop.jpg', isActive: true,
      updatedAt: new Date(),
    }],
    [['public_shops', 'shopA', 'inventory', 'tea'], {
      productId: 'tea', available: true, stock: 5, updatedAt: new Date(),
    }],
  ]);
  await assertSucceeds(getDoc(doc(anonymousDb(), 'public_shops', 'shopA')));
  await assertSucceeds(getDoc(doc(anonymousDb(), 'public_shops', 'shopA', 'inventory', 'tea')));
});

test('anonymous website catalog collection queries are authorized', async () => {
  await seed([
    [['products', 'tea'], {
      name: 'Tea', price: 50, category: 'Grocery', stock: 5,
      imageUrl: 'https://example.test/tea.jpg', isActive: true,
    }],
    [['banners', 'active'], {
      imageUrl: 'https://example.test/banner.jpg', isActive: true, order: 1,
    }],
    [['public_shops', 'shopA'], {
      storeId: 'shopA', name: 'Public Shop', area: 'Agartala',
      imageUrl: '', isActive: true,
    }],
    [['public_shops', 'shopA', 'inventory', 'tea'], {
      productId: 'tea', available: true, stock: 5,
    }],
  ]);

  const db = anonymousDb();
  await assertSucceeds(getDocs(collection(db, 'products')));
  await assertSucceeds(getDocs(query(collection(db, 'banners'), where('isActive', '==', true))));
  await assertSucceeds(getDocs(query(collection(db, 'public_shops'), where('isActive', '==', true))));
  await assertSucceeds(getDocs(query(
    collection(db, 'public_shops', 'shopA', 'inventory'),
    where('available', '==', true),
    where('stock', '>', 0),
  )));
});

test('public shop projections fail closed on sensitive or unavailable data', async () => {
  await seed([
    [['public_shops', 'unsafe'], {
      storeId: 'unsafe', name: 'Unsafe Shop', area: 'Agartala',
      imageUrl: '', isActive: true, phone: '+919999999999',
      latitude: 23.83, longitude: 91.28,
    }],
    [['public_shops', 'inactive'], {
      storeId: 'inactive', name: 'Inactive Shop', area: 'Agartala',
      imageUrl: '', isActive: false,
    }],
    [['public_shops', 'shopA', 'inventory', 'unavailable'], {
      productId: 'unavailable', available: false, stock: 5,
    }],
    [['public_shops', 'shopA', 'inventory', 'bad-stock'], {
      productId: 'bad-stock', available: true, stock: '5',
    }],
  ]);
  const db = anonymousDb();
  await assertFails(getDoc(doc(db, 'public_shops', 'unsafe')));
  await assertFails(getDoc(doc(db, 'public_shops', 'inactive')));
  await assertFails(getDoc(doc(db, 'public_shops', 'shopA', 'inventory', 'unavailable')));
  await assertFails(getDoc(doc(db, 'public_shops', 'shopA', 'inventory', 'bad-stock')));
});

test('anonymous visitors cannot read raw shops or private resources', async () => {
  await seed([
    [['shops', 'shopA'], {
      name: 'Private Shop', area: 'Agartala', phone: '+919999999999',
      latitude: 23.83, longitude: 91.28, isActive: true,
    }],
    [['users', 'customerA'], { phone: '+919876543210' }],
    [['delivery_partners', 'riderA'], riderProfile('')],
    [['delivery_partner_credentials', 'riderA'], { pinHash: 'secret' }],
    [['settings', 'app'], { latitude: 23.83, longitude: 91.28 }],
    [['orders', 'private-order'], order('customerA')],
    [['orders', 'private-order', 'messages', 'private-message'], message('customerA', 'customer')],
  ]);
  const db = anonymousDb();
  await assertFails(getDoc(doc(db, 'shops', 'shopA')));
  await assertFails(getDoc(doc(db, 'users', 'customerA')));
  await assertFails(getDoc(doc(db, 'delivery_partners', 'riderA')));
  await assertFails(getDoc(doc(db, 'delivery_partner_credentials', 'riderA')));
  await assertFails(getDoc(doc(db, 'settings', 'app')));
  await assertFails(getDoc(doc(db, 'orders', 'private-order')));
  await assertFails(getDoc(doc(db, 'orders', 'private-order', 'messages', 'private-message')));
});

test('anonymous visitors cannot write any public catalog resource', async () => {
  const db = anonymousDb();
  for (const pathParts of [
    ['products', 'new-product'],
    ['banners', 'new-banner'],
    ['shops', 'new-shop'],
    ['shops', 'shopA', 'inventory', 'new-product'],
    ['public_shops', 'new-shop'],
    ['public_shops', 'shopA', 'inventory', 'new-product'],
  ]) {
    await assertFails(setDoc(doc(db, ...pathParts), { name: 'blocked' }));
  }
});
