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

function main() {
  const { shardIndex, shardTotal, jsonOutput } = parseArgs();
  const allFiles = walk(path.join(E2E_DIR, 'tests')).sort();

  const heavy = [];
  const normal = [];

  for (const file of allFiles) {
    const fullPath = path.join(E2E_DIR, file);
    const content = fs.readFileSync(fullPath, 'utf8');
    if (content.includes('usePerTestIsolation')) {
      heavy.push(file);
    } else {
      normal.push(file);
    }
  }

  const buckets = Array.from({ length: shardTotal }, () => []);

  // Distribute heavy files first round-robin
  heavy.forEach((file, idx) => {
    buckets[idx % shardTotal].push(file);
  });

  // Distribute normal files in reverse round-robin to balance total weight
  normal.forEach((file, idx) => {
    buckets[(shardTotal - 1 - (idx % shardTotal))].push(file);
  });

  const selectedFiles = buckets[shardIndex - 1] || [];

  if (jsonOutput) {
    console.log(JSON.stringify(selectedFiles));
  } else {
    // Print space-delimited list of files relative to e2e directory
    console.log(selectedFiles.join(' '));
  }
}

main();
