'use strict';

const fs = require('fs');
const path = require('path');

const APPLY_CONFIRMATION = 'APPLY_QUICKDROP_SECURITY_MIGRATION';

/**
 * Converts the phone formats historically used by QuickDrop to a stable E.164
 * value. A bare ten-digit number is only interpreted as an Indian number;
 * unfamiliar local formats are rejected rather than guessed.
 */
function normalizePhone(value) {
  const raw = String(value || '').trim();
  if (!raw) {
    return null;
  }

  const digits = raw.replace(/\D/g, '');
  if (!digits) {
    return null;
  }

  if (raw.startsWith('+') && digits.length >= 8 && digits.length <= 15) {
    return `+${digits}`;
  }

  if (digits.length === 10) {
    return `+91${digits}`;
  }

  if (digits.length === 12 && digits.startsWith('91')) {
    return `+${digits}`;
  }

  return null;
}

function maskPhone(phone) {
  const normalized = normalizePhone(phone);
  if (!normalized) {
    return null;
  }

  return `${normalized.slice(0, Math.min(3, normalized.length))}***${normalized.slice(-2)}`;
}

function parseMigrationArgs(argv) {
  const args = {
    apply: false,
    confirm: '',
    limit: null,
    report: '',
  };

  for (const value of argv) {
    if (value === '--apply') {
      args.apply = true;
    } else if (value.startsWith('--confirm=')) {
      args.confirm = value.slice('--confirm='.length);
    } else if (value.startsWith('--limit=')) {
      const limit = Number.parseInt(value.slice('--limit='.length), 10);
      if (!Number.isSafeInteger(limit) || limit <= 0) {
        throw new Error('--limit must be a positive integer.');
      }
      args.limit = limit;
    } else if (value.startsWith('--report=')) {
      args.report = value.slice('--report='.length).trim();
      if (!args.report) {
        throw new Error('--report requires a file path.');
      }
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }

  if (args.apply && args.confirm !== APPLY_CONFIRMATION) {
    throw new Error(
      `Refusing to write. Use --apply --confirm=${APPLY_CONFIRMATION} after reviewing a dry run.`,
    );
  }

  return args;
}

function createReport(name, apply) {
  return {
    migration: name,
    mode: apply ? 'apply' : 'dry-run',
    generatedAt: new Date().toISOString(),
    summary: {},
    records: [],
  };
}

function record(report, outcome, recordData) {
  report.summary[outcome] = (report.summary[outcome] || 0) + 1;
  report.records.push({ outcome, ...recordData });
}

function finishReport(report, reportPath) {
  report.completedAt = new Date().toISOString();
  const serialized = `${JSON.stringify(report, null, 2)}\n`;

  if (reportPath) {
    const absolutePath = path.resolve(process.cwd(), reportPath);
    fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
    fs.writeFileSync(absolutePath, serialized, 'utf8');
    console.log(`Migration report written to ${absolutePath}`);
  } else {
    console.log(serialized);
  }
}

module.exports = {
  APPLY_CONFIRMATION,
  createReport,
  finishReport,
  maskPhone,
  normalizePhone,
  parseMigrationArgs,
  record,
};
