'use strict';

const admin = require('firebase-admin');

const PROJECT_ID = 'quickdrop-cbf49';
const APPLY_CONFIRMATION = 'APPLY_QUICKDROP_PUBLIC_SHOPS_PROJECTION';

const PRODUCT_PUBLIC_FIELDS = Object.freeze([
  'name', 'title', 'price', 'sellingPrice', 'category', 'subcategory',
  'childCategory', 'imageUrl', 'imageUrls', 'images', 'image', 'imageURL',
  'image_url', 'stock', 'brand', 'weight', 'unit', 'measureUnit', 'quantity',
  'size', 'oldPrice', 'old_price', 'mrp', 'originalPrice', 'strikePrice',
  'compareAtPrice', 'discount', 'discountPercent', 'description',
  'shortDescription', 'isActive', 'shopId', 'storeId', 'shopNameSnapshot',
  'shopName', 'popularity', 'ordersCount', 'sold', 'soldCount', 'sales',
  'orders', 'rating', 'reviewCount', 'offerTag', 'label', 'badge', 'tag',
  'offer', 'orderCount', 'views', 'emoji', 'createdAt', 'updatedAt',
]);

const BANNER_PUBLIC_FIELDS = Object.freeze([
  'imageUrl', 'image', 'title', 'name', 'subtitle', 'description',
  'isActive', 'order', 'displayOrder', 'createdAt', 'updatedAt',
]);

const SHOP_PUBLIC_FIELDS = Object.freeze([
  'storeId', 'name', 'area', 'imageUrl', 'isActive', 'createdAt', 'updatedAt',
]);

const INVENTORY_PUBLIC_FIELDS = Object.freeze([
  'productId', 'available', 'stock', 'updatedAt',
]);

const REQUIRED_SHOP_FIELDS = Object.freeze([
  'storeId', 'name', 'area', 'isActive',
]);

const REQUIRED_INVENTORY_FIELDS = Object.freeze([
  'productId', 'available', 'stock',
]);

const SUSPICIOUS_FIELD_PATTERN = /(?:phone|mobile|email|address|lat(?:itude)?|lng|lon(?:gitude)?|owner|customer|supplier|vendor|cost|purchase|margin|profit|payout|bank|account|ifsc|secret|token|password|credential|internal|private|note)/i;

function parseArgs(argv) {
  const args = { apply: false, confirm: '', report: '' };

  for (const value of argv) {
    if (value === '--apply') {
      args.apply = true;
    } else if (value.startsWith('--confirm=')) {
      args.confirm = value.slice('--confirm='.length);
    } else if (value.startsWith('--report=')) {
      args.report = value.slice('--report='.length).trim();
      if (!args.report) throw new Error('--report requires a file path.');
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }

  if (args.apply && args.confirm !== APPLY_CONFIRMATION) {
    throw new Error(
      `Refusing production writes. Use --apply --confirm=${APPLY_CONFIRMATION} only after reviewing a dry run.`,
    );
  }

  return args;
}

function sortedUnique(values) {
  return [...new Set(values)].sort((a, b) => a.localeCompare(b));
}

function incrementFieldCounts(target, fields) {
  for (const field of fields) target[field] = (target[field] || 0) + 1;
}

function unexpectedFields(data, allowlist) {
  const allowed = new Set(allowlist);
  return Object.keys(data).filter((field) => !allowed.has(field)).sort();
}

function suspiciousFields(data) {
  return Object.keys(data).filter((field) => SUSPICIOUS_FIELD_PATTERN.test(field)).sort();
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function missingProductFields(data) {
  const missing = [];
  if (!isNonEmptyString(data.name) && !isNonEmptyString(data.title)) missing.push('name|title');
  if (typeof (data.price ?? data.sellingPrice) !== 'number') missing.push('price|sellingPrice');
  if (typeof data.category !== 'string') missing.push('category');
  if (typeof data.stock !== 'number') missing.push('stock');
  return missing;
}

function missingShopFields(data) {
  return REQUIRED_SHOP_FIELDS.filter((field) => {
    if (field === 'isActive') return typeof data[field] !== 'boolean';
    return !isNonEmptyString(data[field]);
  });
}

function missingInventoryFields(data, documentId) {
  return REQUIRED_INVENTORY_FIELDS.filter((field) => {
    if (field === 'productId') {
      return !isNonEmptyString(data.productId) && !isNonEmptyString(documentId);
    }
    if (field === 'available') return typeof data.available !== 'boolean';
    return typeof data.stock !== 'number' || !Number.isFinite(data.stock);
  });
}

function copyDefinedFields(data, fields) {
  const result = {};
  for (const field of fields) {
    if (data[field] !== undefined) result[field] = data[field];
  }
  return result;
}

function buildPublicShop(data) {
  return copyDefinedFields(data, SHOP_PUBLIC_FIELDS);
}

function buildPublicInventory(data, documentId) {
  return {
    productId: isNonEmptyString(data.productId) ? data.productId.trim() : documentId,
    available: data.available,
    stock: data.stock,
    ...(data.updatedAt !== undefined ? { updatedAt: data.updatedAt } : {}),
  };
}

function jsonSafe(value) {
  if (value === undefined) return null;
  if (value === null || typeof value !== 'object') return value;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(jsonSafe);
  return Object.fromEntries(
    Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => [key, jsonSafe(item)]),
  );
}

function projectionsEqual(left, right) {
  return JSON.stringify(jsonSafe(left || {})) === JSON.stringify(jsonSafe(right || {}));
}

function planWrite(result, path, desired, existing) {
  if (existing && projectionsEqual(desired, existing)) {
    result.unchangedProjectionDocuments += 1;
    return;
  }
  result.writes.push({ path, data: desired });
}

async function auditProducts(db) {
  const snapshot = await db.collection('products').get();
  const unexpectedFieldCounts = {};
  const suspiciousFieldCounts = {};
  const incompatibleDocuments = [];
  const missingRequiredDocuments = [];

  for (const document of snapshot.docs.sort((a, b) => a.id.localeCompare(b.id))) {
    const data = document.data() || {};
    const unexpected = unexpectedFields(data, PRODUCT_PUBLIC_FIELDS);
    const missing = missingProductFields(data);
    const suspicious = suspiciousFields(data);
    incrementFieldCounts(unexpectedFieldCounts, unexpected);
    incrementFieldCounts(suspiciousFieldCounts, suspicious);
    if (unexpected.length) incompatibleDocuments.push({ path: document.ref.path, unexpectedFields: unexpected });
    if (missing.length) missingRequiredDocuments.push({ path: document.ref.path, missingFields: missing });
  }

  const incompatiblePaths = new Set([
    ...incompatibleDocuments.map((item) => item.path),
    ...missingRequiredDocuments.map((item) => item.path),
  ]);

  return {
    total: snapshot.size,
    compatible: snapshot.size - incompatiblePaths.size,
    unexpectedFieldCounts,
    unexpectedFields: Object.keys(unexpectedFieldCounts).sort(),
    documentsWithUnexpectedFields: incompatibleDocuments,
    missingRequiredDocuments,
    suspiciousFieldCounts,
    suspiciousFields: Object.keys(suspiciousFieldCounts).sort(),
    safeForPublicRules: incompatiblePaths.size === 0 && Object.keys(suspiciousFieldCounts).length === 0,
  };
}

async function auditBanners(db) {
  const snapshot = await db.collection('banners').get();
  const unexpectedFieldCounts = {};
  const suspiciousFieldCounts = {};
  const documentsWithUnexpectedFields = [];

  for (const document of snapshot.docs.sort((a, b) => a.id.localeCompare(b.id))) {
    const data = document.data() || {};
    const unexpected = unexpectedFields(data, BANNER_PUBLIC_FIELDS);
    const suspicious = suspiciousFields(data);
    incrementFieldCounts(unexpectedFieldCounts, unexpected);
    incrementFieldCounts(suspiciousFieldCounts, suspicious);
    if (unexpected.length) {
      documentsWithUnexpectedFields.push({ path: document.ref.path, unexpectedFields: unexpected });
    }
  }

  return {
    total: snapshot.size,
    active: snapshot.docs.filter((document) => document.data().isActive === true).length,
    unexpectedFieldCounts,
    unexpectedFields: Object.keys(unexpectedFieldCounts).sort(),
    documentsWithUnexpectedFields,
    suspiciousFieldCounts,
    suspiciousFields: Object.keys(suspiciousFieldCounts).sort(),
  };
}

async function auditShops(db) {
  const snapshot = await db.collection('shops').get();
  const publicSnapshot = await db.collection('public_shops').get();
  const existingPublicShops = new Map(publicSnapshot.docs.map((document) => [document.id, document]));
  const rawShopIds = new Set(snapshot.docs.map((document) => document.id));
  const result = {
    totalShops: snapshot.size,
    eligibleShops: 0,
    inactiveShops: 0,
    invalidShops: [],
    excludedShopFieldCounts: {},
    sensitiveShopFieldsExcluded: {},
    inventoriesScanned: 0,
    inventoryDocuments: 0,
    eligibleInventoryDocuments: 0,
    writeEligibleInventoryDocuments: 0,
    invalidInventoryDocuments: [],
    ineligibleInventoryDocuments: [],
    excludedInventoryFieldCounts: {},
    sensitiveInventoryFieldsExcluded: {},
    orphanedPublicShopsDisabled: 0,
    orphanedPublicInventoryDisabled: 0,
    unchangedProjectionDocuments: 0,
    writes: [],
  };

  for (const shop of snapshot.docs.sort((a, b) => a.id.localeCompare(b.id))) {
    const data = shop.data() || {};
    const missing = missingShopFields(data);
    const excluded = unexpectedFields(data, SHOP_PUBLIC_FIELDS);
    const sensitiveExcluded = excluded.filter((field) => SUSPICIOUS_FIELD_PATTERN.test(field));
    incrementFieldCounts(result.excludedShopFieldCounts, excluded);
    incrementFieldCounts(result.sensitiveShopFieldsExcluded, sensitiveExcluded);

    const parentEligible = missing.length === 0 && data.isActive === true;
    if (data.isActive !== true) result.inactiveShops += 1;
    if (missing.length) {
      result.invalidShops.push({ path: shop.ref.path, missingFields: missing });
    }
    const existingPublicShop = existingPublicShops.get(shop.id);
    if (parentEligible) {
      result.eligibleShops += 1;
    }
    const publicShop = missing.length ? { isActive: false } : buildPublicShop(data);
    planWrite(result, `public_shops/${shop.id}`, publicShop, existingPublicShop?.data());

    const inventorySnapshot = await shop.ref.collection('inventory').get();
    const existingInventorySnapshot = await db
      .collection('public_shops').doc(shop.id).collection('inventory').get();
    const existingInventory = new Map(
      existingInventorySnapshot.docs.map((document) => [document.id, document]),
    );
    const rawInventoryIds = new Set(inventorySnapshot.docs.map((document) => document.id));
    result.inventoriesScanned += 1;
    result.inventoryDocuments += inventorySnapshot.size;

    for (const inventory of inventorySnapshot.docs.sort((a, b) => a.id.localeCompare(b.id))) {
      const inventoryData = inventory.data() || {};
      const inventoryMissing = missingInventoryFields(inventoryData, inventory.id);
      const inventoryExcluded = unexpectedFields(inventoryData, INVENTORY_PUBLIC_FIELDS);
      const inventorySensitive = inventoryExcluded.filter((field) => SUSPICIOUS_FIELD_PATTERN.test(field));
      incrementFieldCounts(result.excludedInventoryFieldCounts, inventoryExcluded);
      incrementFieldCounts(result.sensitiveInventoryFieldsExcluded, inventorySensitive);

      if (inventoryMissing.length) {
        result.invalidInventoryDocuments.push({
          path: inventory.ref.path,
          missingFields: inventoryMissing,
        });
      } else if (inventoryData.available !== true || inventoryData.stock <= 0) {
        result.ineligibleInventoryDocuments.push({
          path: inventory.ref.path,
          reasons: [
            ...(inventoryData.available !== true ? ['not-available'] : []),
            ...(inventoryData.stock <= 0 ? ['stock-not-positive'] : []),
          ],
        });
      } else {
        result.eligibleInventoryDocuments += 1;
      }

      const publiclyAvailable = parentEligible
        && inventoryMissing.length === 0
        && inventoryData.available === true
        && inventoryData.stock > 0;
      if (publiclyAvailable) {
        result.writeEligibleInventoryDocuments += 1;
      }
      const publicInventory = {
        productId: isNonEmptyString(inventoryData.productId)
          ? inventoryData.productId.trim()
          : inventory.id,
        available: publiclyAvailable,
        stock: typeof inventoryData.stock === 'number' && Number.isFinite(inventoryData.stock)
          ? inventoryData.stock
          : 0,
        ...(inventoryData.updatedAt !== undefined ? { updatedAt: inventoryData.updatedAt } : {}),
      };
      planWrite(
        result,
        `public_shops/${shop.id}/inventory/${inventory.id}`,
        publicInventory,
        existingInventory.get(inventory.id)?.data(),
      );
    }

    for (const existing of existingInventorySnapshot.docs) {
      if (rawInventoryIds.has(existing.id)) continue;
      result.orphanedPublicInventoryDisabled += 1;
      planWrite(
        result,
        existing.ref.path,
        { productId: existing.id, available: false, stock: 0 },
        existing.data(),
      );
    }
  }

  for (const existingShop of publicSnapshot.docs) {
    if (rawShopIds.has(existingShop.id)) continue;
    result.orphanedPublicShopsDisabled += 1;
    planWrite(result, existingShop.ref.path, { isActive: false }, existingShop.data());
    const existingInventorySnapshot = await existingShop.ref.collection('inventory').get();
    for (const existing of existingInventorySnapshot.docs) {
      result.orphanedPublicInventoryDisabled += 1;
      planWrite(
        result,
        existing.ref.path,
        { productId: existing.id, available: false, stock: 0 },
        existing.data(),
      );
    }
  }

  result.writes.sort((a, b) => a.path.localeCompare(b.path));
  return result;
}

async function applyProjection(db, writes) {
  const writer = db.bulkWriter();
  for (const write of writes) {
    writer.set(db.doc(write.path), write.data);
  }
  await writer.close();
  return writes.length;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
  }

  const actualProjectId = admin.app().options.projectId;
  if (actualProjectId !== PROJECT_ID) {
    throw new Error(`Refusing to run for project ${actualProjectId || '(unknown)'}. Expected ${PROJECT_ID}.`);
  }

  const db = admin.firestore();
  const report = {
    tool: 'quickdrop-public-catalog-preflight',
    projectId: PROJECT_ID,
    mode: args.apply ? 'apply' : 'dry-run',
    generatedAt: new Date().toISOString(),
    allowlists: {
      products: PRODUCT_PUBLIC_FIELDS,
      banners: BANNER_PUBLIC_FIELDS,
      publicShops: SHOP_PUBLIC_FIELDS,
      publicInventory: INVENTORY_PUBLIC_FIELDS,
    },
    products: await auditProducts(db),
    banners: await auditBanners(db),
    shops: await auditShops(db),
  };

  if (args.apply) {
    if (!report.products.safeForPublicRules) {
      throw new Error('Refusing projection writes because the product public-field audit is not safe.');
    }
    report.appliedWrites = await applyProjection(db, report.shops.writes);
  } else {
    report.appliedWrites = 0;
  }
  report.completedAt = new Date().toISOString();

  const output = `${JSON.stringify(jsonSafe(report), null, 2)}\n`;
  if (args.report) {
    const fs = require('fs');
    const path = require('path');
    const outputPath = path.resolve(process.cwd(), args.report);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, output, 'utf8');
    console.log(`Catalog preflight report written to ${outputPath}`);
  } else {
    console.log(output);
  }

  if (!report.products.safeForPublicRules) process.exitCode = 2;
}

main().catch((error) => {
  console.error('Public catalog preflight failed:', error.message);
  process.exitCode = 1;
});

module.exports = {
  APPLY_CONFIRMATION,
  BANNER_PUBLIC_FIELDS,
  INVENTORY_PUBLIC_FIELDS,
  PRODUCT_PUBLIC_FIELDS,
  SHOP_PUBLIC_FIELDS,
  buildPublicInventory,
  buildPublicShop,
  missingInventoryFields,
  missingProductFields,
  missingShopFields,
  parseArgs,
  suspiciousFields,
  unexpectedFields,
};
