#!/usr/bin/env node
/**
 * 状态键契约校验脚本（任务 11）。
 *
 * 扫描全仓 .ets 文件中的状态装饰器键：
 *   @StorageLink('key') / @StorageProp('key')  -> AppStorage 键
 *   @LocalStorageProp('key')                    -> 卡片 LocalStorage 键
 * 与 products/Pond/src/main/ets/constants/StorageKeys.ets 的登记清单比对，
 * 出现未登记键（或类别登记错误）时以非 0 退出码报错。
 *
 * 用法（项目根目录）：node tools/check_storage_keys.mjs
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(scriptDir, '..');
const registryPath = join(
  repoRoot, 'products', 'Pond', 'src', 'main', 'ets', 'constants', 'StorageKeys.ets');

const SKIP_DIRS = new Set(['.git', '.hvigor', '.idea', 'node_modules', 'oh_modules', '.cxx', '.test', '.cache']);
const SCAN_ROOTS = [
  join(repoRoot, 'products'),
  join(repoRoot, 'common'),
];

/** 递归收集 .ets 文件（跳过构建产物目录）。 */
function collectEtsFiles(dir, out) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const name of entries) {
    if (SKIP_DIRS.has(name)) {
      continue;
    }
    const full = join(dir, name);
    let st;
    try {
      st = statSync(full);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      collectEtsFiles(full, out);
    } else if (name.endsWith('.ets')) {
      out.push(full);
    }
  }
}

/** 解析登记清单：行首标记 // [AppStorage] key ... / // [LocalStorage] key ... */
function parseRegistry(content) {
  const registry = new Map();
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^\/\/\s*\[(AppStorage|LocalStorage)\]\s*(\w+)/);
    if (m) {
      registry.set(m[2], m[1]);
    }
  }
  return registry;
}

function main() {
  if (!statSync(registryPath).isFile()) {
    console.error(`[check_storage_keys] 未找到登记清单：${registryPath}`);
    process.exit(1);
  }
  const registry = parseRegistry(readFileSync(registryPath, 'utf8'));

  const etsFiles = [];
  for (const root of SCAN_ROOTS) {
    collectEtsFiles(root, etsFiles);
  }

  const decoratorRe = /@(StorageLink|StorageProp|LocalStorageProp)\s*\(\s*'(\w+)'/g;
  const used = new Map();
  const errors = [];

  for (const file of etsFiles) {
    const content = readFileSync(file, 'utf8');
    let m;
    while ((m = decoratorRe.exec(content)) !== null) {
      const decorator = m[1];
      const key = m[2];
      const expectedCategory = decorator === 'LocalStorageProp' ? 'LocalStorage' : 'AppStorage';
      const relPath = relative(repoRoot, file).replace(/\\/g, '/');
      const loc = `${relPath} @${decorator}('${key}')`;
      used.set(`${expectedCategory}:${key}`, (used.get(`${expectedCategory}:${key}`) ?? 0) + 1);
      if (!registry.has(key)) {
        errors.push(`未登记的状态键：${loc}（请在 constants/StorageKeys.ets 登记）`);
      } else if (registry.get(key) !== expectedCategory) {
        errors.push(
          `状态键类别不符：${loc}（清单登记为 [${registry.get(key)}]，装饰器要求 [${expectedCategory}]）`);
      }
    }
  }

  // 清单中登记但全仓无任何装饰器使用的键（提示，不算失败）
  const warnings = [];
  for (const [key, category] of registry) {
    if (!used.has(`${category}:${key}`)) {
      warnings.push(`清单登记的键 [${category}] ${key} 未发现装饰器使用，请确认是否已废弃`);
    }
  }

  for (const w of warnings) {
    console.warn(`[check_storage_keys] 警告: ${w}`);
  }
  if (errors.length > 0) {
    for (const e of errors) {
      console.error(`[check_storage_keys] 错误: ${e}`);
    }
    console.error(`[check_storage_keys] 校验失败：${errors.length} 处状态键未通过契约检查。`);
    process.exit(1);
  }
  console.log(`[check_storage_keys] 通过：登记 ${registry.size} 键，扫描 ${etsFiles.length} 个 .ets 文件，装饰器用法全部合规。`);
}

main();
