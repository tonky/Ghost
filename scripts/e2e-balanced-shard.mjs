#!/usr/bin/env node
/**
 * scripts/e2e-balanced-shard.mjs
 *
 * Evenly distributes Ghost's 82 Playwright E2E test files across N shards.
 * Interleaves heavy `usePerTestIsolation()` files (which cold-boot a fresh Docker
 * container per test) with standard test files, eliminating straggler skew.
 *
 * Usage:
 *   node scripts/e2e-balanced-shard.mjs --shard=1/10
 *   node scripts/e2e-balanced-shard.mjs --shard=1/10 --json
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..');
const E2E_DIR = path.join(REPO_ROOT, 'e2e');

function walk(dir) {
  let files = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files = files.concat(walk(fullPath));
    } else if (entry.isFile() && (fullPath.endsWith('.test.ts') || fullPath.endsWith('.test.js'))) {
      if (
        !fullPath.includes('analytics') &&
        !fullPath.includes('stripe-fixtures') &&
        !fullPath.endsWith('.setup.ts') &&
        !fullPath.endsWith('.teardown.ts')
      ) {
        files.push(path.relative(E2E_DIR, fullPath));
      }
    }
  }
  return files;
}

function parseArgs() {
  const args = process.argv.slice(2);
  let shardIndex = 1;
  let shardTotal = 10;
  let jsonOutput = false;

  for (const arg of args) {
    if (arg.startsWith('--shard=')) {
      const parts = arg.replace('--shard=', '').split('/');
      shardIndex = parseInt(parts[0], 10);
      shardTotal = parseInt(parts[1], 10);
    } else if (arg === '--json') {
      jsonOutput = true;
    }
  }

  return { shardIndex, shardTotal, jsonOutput };
}

function getFileWeight(file, timings) {
  if (timings && typeof timings[file] === 'number') {
    return timings[file];
  }
  const fullPath = path.join(E2E_DIR, file);
  const content = fs.readFileSync(fullPath, 'utf8');
  const count = (content.match(/\btest(\.only|\.skip)?\s*\(/g) || []).length || 1;
  const isPerTest = content.includes('usePerTestIsolation');
  return count * (isPerTest ? 20.0 : 10.0);
}

function main() {
  const { shardIndex, shardTotal, jsonOutput } = parseArgs();
  const allFiles = walk(path.join(E2E_DIR, 'tests')).sort();

  let timings = null;
  const timingsPath = path.join(__dirname, 'e2e-file-timings.json');
  if (fs.existsSync(timingsPath)) {
    try {
      timings = JSON.parse(fs.readFileSync(timingsPath, 'utf8'));
    } catch {
      timings = null;
    }
  }

  const fileStats = allFiles.map((file) => ({
    file,
    weight: getFileWeight(file, timings),
  }));

  // LPT (Longest Processing Time first) deterministic bin-packing
  fileStats.sort((a, b) => b.weight - a.weight || a.file.localeCompare(b.file));

  const buckets = Array.from({ length: shardTotal }, () => ({
    files: [],
    weight: 0,
  }));

  for (const item of fileStats) {
    let minBucket = buckets[0];
    for (let i = 1; i < buckets.length; i++) {
      if (buckets[i].weight < minBucket.weight) {
        minBucket = buckets[i];
      }
    }
    minBucket.files.push(item.file);
    minBucket.weight += item.weight;
  }

  const selectedFiles = (buckets[shardIndex - 1] && buckets[shardIndex - 1].files) || [];

  if (jsonOutput) {
    console.log(JSON.stringify(selectedFiles));
  } else {
    // Print space-delimited list of files relative to e2e directory
    console.log(selectedFiles.join(' '));
  }
}

main();
