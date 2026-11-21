import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppLog } from './AppLog';
import { CacheManager } from './CacheManager';
import { aesGcmEncrypt, aesGcmDecrypt } from '../utils/AesGcm';

const TAG: string = 'SecureStore';
const DOMAIN: number = 0x0000;
/** 与 CardDataStore 同一 preferences 文件（框架保证同进程同实例，跨进程实时可见） */
const PREF_NAME: string = 'jw_card_data';
/** HUKS KEK 别名（AES-256，密钥材料仅存在于系统密钥库） */
const KEK_ALIAS: string = 'edaiyi_secure_kek_v1';
/** 被包装 DEK（信封）在 preferences 中的键名 */
const KEY_WRAPPED_DEK: string = 'secureDekV1';
/** 数据/DEK 信封前缀；非此前缀的存量值视为旧明文透传（读取兼容，下次写入自动转密文） */
const ENVELOPE_PREFIX: string = 'e1.';
/** DEK 信封的 AAD（区别于数据信封的按键名 AAD） */
const DEK_AAD: string = 'edaiyi.dek.v1';
/** 旧明文迁移扫描键（仍由 SecureStore 管理的学生信息加密键） */
const LEGACY_MIGRATE_KEYS: string[] = ['appCache'];
/** 曾加密、现降级为明文存储的键（课表/期末/提醒名单为高频同步读路径，退出加密范围以提速启动与卡片链路）；
 *  hydrate 时把旧版本遗留的密文解密回明文，完成一次性降级迁移（幂等） */
const DEMOTED_KEYS: string[] = ['payload', 'finalExamDates', 'reminderDisabledSessions'];
/** DEK 重建时需整体清除的键：全部可能存在密文的 prefs 键（防不可解垃圾长期堆积） */
const ALL_CIPHER_KEYS: string[] = ['appCache', 'cacheOwnerSid', 'cacheProbeUid',
  'payload', 'finalExamDates', 'reminderDisabledSessions'];
/** 加密文件缓存名（与 EhallRepository/ZcpRepository 的缓存文件名一致） */
const CIPHER_CACHE_FILES: string[] = ['zcp_cache.json', 'ehall_stats.json'];

/**
 * 学生信息静态加密存储层：
 * - 数据密钥 DEK（32 字节 AES-256）仅存在于进程内存，绝不落盘；
 * - DEK 由 HUKS KEK（AES-256-GCM，别名见 KEK_ALIAS）包装为信封存于 preferences，
 *   进程启动时一次性异步解包（hydrate）——HUKS/cryptoFramework 全为异步接口，
 *   而数据层读写（preferences、卡片绑定构建）是同步调用链，因此数据加解密用
 *   纯同步 AES-256-GCM（utils/AesGcm.ets），仅 DEK 解包走 HUKS 异步；
 * - 信封格式：'e1.' + Base64(nonce(12B) ‖ 密文 ‖ tag(16B))，AAD = 键名/文件名
 *   （防跨键密文替换）；
 * - 加密范围：appCache（离线缓存）+ 缓存归属键（cacheOwnerSid/cacheProbeUid，B1）
 *   + zcp_cache.json/ehall_stats.json 文件缓存；
 *   课表 payload/finalExamDates/reminderDisabledSessions 已降级明文（高频同步读路径提速），
 *   旧版本遗留密文在 hydrate 时解密回明文完成迁移；
 * - DEK 重建（换机恢复备份/KEK 卸载）时主动清除全部旧密文，不残留不可解垃圾；
 * - 降级：HUKS 不可用/解包失败时不回退明文存储——读按"无缓存"（getString 返回 ''）、
 *   写暂存内存 pending（hydrate 成功后补写），hydrating 复位允许下次重试；
 * - 旧明文兼容：非 'e1.' 前缀的存量值读取时透传，hydrate 时主动扫描加密迁移。
 */
export class SecureStore {
  /** 解包后的数据密钥（32 字节）；null = 未就绪（未 hydrate / 降级） */
  private static dek: Uint8Array | null = null;
  /** 进行中的 hydrate 任务（去重并发触发）；失败后置回 null 允许重试 */
  private static hydrating: Promise<void> | null = null;
  /** 未就绪期间暂存的待写入（键名 → 最新值，后写覆盖先写） */
  private static pendingWrites: Map<string, string> = new Map<string, string>();

  /** DEK 是否已解包就绪 */
  static isReady(): boolean {
    return SecureStore.dek !== null;
  }

  /**
   * 解包/生成 DEK（幂等，进程内单飞）：
   * 各进程入口（主 Ability、Form/Share 扩展）尽早调用；
   * 完成后重读不到的调用方用 runWhenReady 接续。
   */
  static hydrate(context: common.Context): Promise<void> {
    if (SecureStore.dek !== null) {
      return Promise.resolve();
    }
    if (SecureStore.hydrating !== null) {
      return SecureStore.hydrating;
    }
    const task: Promise<void> = SecureStore.doHydrate(context);
    SecureStore.hydrating = task;
    task.then(() => {
      if (SecureStore.hydrating === task) {
        SecureStore.hydrating = null;
      }
    });
    return task;
  }

  /** 等待 hydrate 完成，返回是否就绪（false = HUKS 降级，调用方按无缓存处理） */
  static async awaitReady(context: common.Context): Promise<boolean> {
    await SecureStore.hydrate(context);
    return SecureStore.dek !== null;
  }

  /** 就绪后执行 action；降级时丢弃并记日志（防未就绪读改写破坏数据基线） */
  static runWhenReady(context: common.Context, action: () => void): void {
    SecureStore.awaitReady(context).then((ready: boolean): void => {
      if (ready) {
        action();
      } else {
        AppLog.warn(DOMAIN, TAG, 'runWhenReady skipped: secure store degraded');
      }
    });
  }

  private static async doHydrate(context: common.Context): Promise<void> {
    try {
      const appContext: common.Context = context.getApplicationContext();
      const pref: preferences.Preferences =
        preferences.getPreferencesSync(appContext, { name: PREF_NAME });
      await SecureStore.ensureKek();
      let dek: Uint8Array | null = null;
      const stored: preferences.ValueType = pref.getSync(KEY_WRAPPED_DEK, '');
      if (typeof stored === 'string' && stored.startsWith(ENVELOPE_PREFIX)) {
        dek = await SecureStore.unwrapDek(stored);
        if (dek === null) {
          // C6：信封可能被其他进程刚重写（多进程并发首建 KEK 竞态的自愈产物），重读一次再试
          const retry: preferences.ValueType = pref.getSync(KEY_WRAPPED_DEK, '');
          if (typeof retry === 'string' && retry !== stored && retry.startsWith(ENVELOPE_PREFIX)) {
            dek = await SecureStore.unwrapDek(retry);
          }
        }
        if (dek === null) {
          // 解包失败：KEK 被卸载/换机恢复备份（HUKS 密钥不随备份走）——
          // 旧密文不可恢复，重新生成 DEK 让应用以空缓存继续可用，绝不回退明文
          AppLog.warn(DOMAIN, TAG, 'DEK unwrap failed; regenerate (old ciphertext unreadable)');
        }
      }
      if (dek === null) {
        dek = cryptoFramework.createRandom().generateRandomSync(32).data;
        const wrapped: string = await SecureStore.wrapDek(dek);
        // C3-C：旧 DEK 下的全部密文已成不可解垃圾，主动清除（prefs 键 + 文件缓存）防堆积
        SecureStore.clearCipherGarbage(appContext, pref);
        pref.putSync(KEY_WRAPPED_DEK, wrapped);
        pref.flushSync();
      }
      SecureStore.dek = dek;
      SecureStore.migrateDemotedKeys(dek, pref);
      SecureStore.migrateLegacyPlaintext(dek, pref);
      SecureStore.migrateLegacyFiles(appContext, dek);
      SecureStore.flushPendingWrites(dek, pref);
      AppLog.info(DOMAIN, TAG, 'hydrate ok');
    } catch (error) {
      // HUKS/偏好读写异常：保持未就绪降级（读空/写暂存），下次 hydrate 重试
      AppLog.error(DOMAIN, TAG, 'hydrate failed (degraded no-cache mode): %{public}s', `${error}`);
    }
  }

  /** 确保 HUKS KEK 存在（不存在则生成 AES-256 密钥） */
  private static async ensureKek(): Promise<void> {
    const exists: boolean = await huks.hasKeyItem(KEK_ALIAS, { properties: [] });
    if (exists) {
      return;
    }
    // 多进程并发首建会互相覆盖（HUKS FAQ 已知竞态）：
    // 被覆盖方解包失败后按 unwrap 失败路径重生成 DEK，自愈且仅损失缓存
    const genProperties: huks.HuksParam[] = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }];
    await huks.generateKeyItem(KEK_ALIAS, { properties: genProperties });
  }

  /** 用 HUKS KEK（AES-256-GCM）包装 DEK，返回 'e1.' 信封 */
  private static async wrapDek(dek: Uint8Array): Promise<string> {
    const nonce: Uint8Array = cryptoFramework.createRandom().generateRandomSync(12).data;
    const encryptProperties: huks.HuksParam[] = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_NONE
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_GCM
    }, {
      tag: huks.HuksTag.HUKS_TAG_NONCE,
      value: nonce
    }, {
      tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
      value: SecureStore.utf8Encode(DEK_AAD)
    }];
    const session: huks.HuksSessionHandle =
      await huks.initSession(KEK_ALIAS, { properties: encryptProperties });
    const finishResult: huks.HuksReturnResult =
      await huks.finishSession(session.handle, { properties: encryptProperties, inData: dek });
    const outData: Uint8Array | undefined = finishResult.outData;
    if (outData === undefined || outData.length < 16) {
      throw new Error('wrapDek: HUKS finishSession returned no outData');
    }
    return SecureStore.buildEnvelope(nonce, outData);
  }

  /** 解包 DEK 信封；失败（密钥不符/密文损坏）返回 null */
  private static async unwrapDek(stored: string): Promise<Uint8Array | null> {
    try {
      const blob: Uint8Array = SecureStore.decodeEnvelope(stored);
      if (blob.length < 12 + 16 + 16) {
        return null;
      }
      const nonce: Uint8Array = blob.subarray(0, 12);
      const body: Uint8Array = blob.subarray(12);
      const cipherLen: number = body.length - 16;
      const tag: Uint8Array = body.subarray(cipherLen);
      const decryptProperties: huks.HuksParam[] = [{
        tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
        value: huks.HuksKeyAlg.HUKS_ALG_AES
      }, {
        tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
        value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
      }, {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      }, {
        tag: huks.HuksTag.HUKS_TAG_PADDING,
        value: huks.HuksKeyPadding.HUKS_PADDING_NONE
      }, {
        tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
        value: huks.HuksCipherMode.HUKS_MODE_GCM
      }, {
        tag: huks.HuksTag.HUKS_TAG_NONCE,
        value: nonce
      }, {
        tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
        value: SecureStore.utf8Encode(DEK_AAD)
      }, {
        tag: huks.HuksTag.HUKS_TAG_AE_TAG,
        value: tag
      }];
      const session: huks.HuksSessionHandle =
        await huks.initSession(KEK_ALIAS, { properties: decryptProperties });
      const finishResult: huks.HuksReturnResult = await huks.finishSession(session.handle,
        { properties: decryptProperties, inData: body.subarray(0, cipherLen) });
      const outData: Uint8Array | undefined = finishResult.outData;
      if (outData === undefined || outData.length !== 32) {
        return null;
      }
      return outData;
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'unwrapDek failed: %{public}s', `${error}`);
      return null;
    }
  }

  /** 曾加密、现降级明文的键：hydrate 时把旧版本遗留密文解密回明文（幂等；解密失败删键按无数据处理） */
  private static migrateDemotedKeys(dek: Uint8Array, pref: preferences.Preferences): void {
    let migrated: number = 0;
    for (const key of DEMOTED_KEYS) {
      try {
        const stored: preferences.ValueType = pref.getSync(key, '');
        if (typeof stored === 'string' && stored.startsWith(ENVELOPE_PREFIX)) {
          const plain: string = SecureStore.decryptValue(dek, key, stored);
          if (plain.length > 0) {
            pref.putSync(key, plain);
            migrated += 1;
          } else {
            pref.deleteSync(key);
          }
        }
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'demote key %{public}s failed: %{public}s', key, `${error}`);
      }
    }
    if (migrated > 0) {
      pref.flushSync();
      AppLog.info(DOMAIN, TAG, 'legacy ciphertext demoted to plaintext: %{public}d key(s)', migrated);
    }
  }

  /** C3-C：DEK 重建时清除所有旧密文（prefs 加密键 + 加密文件缓存），防止不可解垃圾长期堆积 */
  private static clearCipherGarbage(appContext: common.Context,
    pref: preferences.Preferences): void {
    for (const key of ALL_CIPHER_KEYS) {
      try {
        pref.deleteSync(key);
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'clear cipher key %{public}s failed: %{public}s', key, `${error}`);
      }
    }
    pref.flushSync();
    for (const name of CIPHER_CACHE_FILES) {
      const path: string = `${appContext.filesDir}/${name}`;
      try {
        if (fileIo.accessSync(path)) {
          fileIo.unlinkSync(path);
        }
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'clear cipher file %{public}s failed: %{public}s', name, `${error}`);
      }
    }
    AppLog.warn(DOMAIN, TAG, 'cipher garbage cleared after DEK regeneration');
  }

  /** C5：hydrate 成功后扫描旧明文文件缓存并就地加密（幂等：已加密/不存在/空文件跳过；原子写防半文件） */
  private static migrateLegacyFiles(appContext: common.Context, dek: Uint8Array): void {
    for (const name of CIPHER_CACHE_FILES) {
      const path: string = `${appContext.filesDir}/${name}`;
      try {
        if (!fileIo.accessSync(path)) {
          continue;
        }
        const stat: fileIo.Stat = fileIo.statSync(path);
        if (stat.size <= 0) {
          continue;
        }
        const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        fileIo.closeSync(file);
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        const stored: string = decoder.decodeToString(new Uint8Array(buf));
        if (stored.startsWith(ENVELOPE_PREFIX)) {
          continue;
        }
        CacheManager.atomicWriteText(path, SecureStore.encryptValue(dek, name, stored));
        AppLog.info(DOMAIN, TAG, 'legacy plaintext file encrypted: %{public}s', name);
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'migrate file %{public}s failed: %{public}s', name, `${error}`);
      }
    }
  }

  /** hydrate 时扫描旧明文敏感键并就地加密迁移（幂等：已是信封则跳过） */
  private static migrateLegacyPlaintext(dek: Uint8Array, pref: preferences.Preferences): void {
    let migrated: number = 0;
    for (const key of LEGACY_MIGRATE_KEYS) {
      try {
        const stored: preferences.ValueType = pref.getSync(key, '');
        if (typeof stored === 'string' && stored.length > 0 && !stored.startsWith(ENVELOPE_PREFIX)) {
          pref.putSync(key, SecureStore.encryptValue(dek, key, stored));
          migrated += 1;
        }
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'migrate key %{public}s failed: %{public}s', key, `${error}`);
      }
    }
    if (migrated > 0) {
      pref.flushSync();
      AppLog.info(DOMAIN, TAG, 'legacy plaintext migrated: %{public}d key(s)', migrated);
    }
  }

  /** hydrate 成功后补写未就绪期间暂存的值（后写覆盖先写已由 Map 语义保证） */
  private static flushPendingWrites(dek: Uint8Array, pref: preferences.Preferences): void {
    if (SecureStore.pendingWrites.size === 0) {
      return;
    }
    SecureStore.pendingWrites.forEach((value: string, key: string): void => {
      try {
        pref.putSync(key, SecureStore.encryptValue(dek, key, value));
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'flush pending %{public}s failed: %{public}s', key, `${error}`);
      }
    });
    SecureStore.pendingWrites.clear();
    pref.flushSync();
    AppLog.info(DOMAIN, TAG, 'pending writes flushed');
  }

  /**
   * 读取并解密加密键；未就绪/无值/解密失败返回 ''（按无缓存降级），
   * 旧明文（非 'e1.' 前缀）透传返回以保证升级过渡期数据可用。
   */
  static getString(context: common.Context, key: string): string {
    const dek: Uint8Array | null = SecureStore.dek;
    if (dek === null) {
      return '';
    }
    try {
      const pref: preferences.Preferences = SecureStore.store(context);
      const stored: preferences.ValueType = pref.getSync(key, '');
      if (typeof stored !== 'string' || stored.length === 0) {
        return '';
      }
      if (!stored.startsWith(ENVELOPE_PREFIX)) {
        return stored;
      }
      return SecureStore.decryptValue(dek, key, stored);
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'getString %{public}s failed: %{public}s', key, `${error}`);
      return '';
    }
  }

  /**
   * 加密并写入加密键；未就绪时暂存内存 pending（hydrate 成功后补写），绝不落明文。
   */
  static putString(context: common.Context, key: string, value: string): void {
    const dek: Uint8Array | null = SecureStore.dek;
    if (dek === null) {
      SecureStore.pendingWrites.set(key, value);
      SecureStore.hydrate(context);
      return;
    }
    try {
      const pref: preferences.Preferences = SecureStore.store(context);
      pref.putSync(key, SecureStore.encryptValue(dek, key, value));
      pref.flushSync();
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'putString %{public}s failed: %{public}s', key, `${error}`);
    }
  }

  /** 删除加密键（不依赖就绪状态；同时丢弃对应 pending 防止清除后被补写复活） */
  static remove(context: common.Context, key: string): void {
    try {
      const pref: preferences.Preferences = SecureStore.store(context);
      pref.deleteSync(key);
      pref.flushSync();
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'remove %{public}s failed: %{public}s', key, `${error}`);
    }
    SecureStore.pendingWrites.delete(key);
  }

  /**
   * 加密文件缓存内容（AAD = 文件名）；未就绪返回 ''（调用方跳过本次写入，下次再存）。
   */
  static encryptFileText(context: common.Context, fileName: string, plain: string): string {
    const dek: Uint8Array | null = SecureStore.dek;
    if (dek === null) {
      SecureStore.hydrate(context);
      return '';
    }
    return SecureStore.encryptValue(dek, fileName, plain);
  }

  /**
   * 解密文件缓存内容；旧明文透传（迁移兼容），未就绪/密文损坏返回 ''。
   */
  static decryptFileText(context: common.Context, fileName: string, stored: string): string {
    if (stored.length === 0) {
      return '';
    }
    if (!stored.startsWith(ENVELOPE_PREFIX)) {
      return stored;
    }
    if (SecureStore.dek === null) {
      SecureStore.hydrate(context);
      return '';
    }
    const dek: Uint8Array = SecureStore.dek;
    return SecureStore.decryptValue(dek, fileName, stored);
  }

  /** 是否为 SecureStore 加密信封值（降级明文键读侧识别旧版遗留密文用） */
  static isEnvelopeValue(text: string): boolean {
    return text.startsWith(ENVELOPE_PREFIX);
  }

  private static store(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context.getApplicationContext(), { name: PREF_NAME });
  }

  /** 数据信封加密：'e1.' + Base64(nonce ‖ 密文‖tag)，AAD = 键名/文件名 */
  private static encryptValue(dek: Uint8Array, name: string, plain: string): string {
    const nonce: Uint8Array = cryptoFramework.createRandom().generateRandomSync(12).data;
    const out: Uint8Array =
      aesGcmEncrypt(dek, nonce, SecureStore.utf8Encode(name), SecureStore.utf8Encode(plain));
    return SecureStore.buildEnvelope(nonce, out);
  }

  /** 数据信封解密：认证失败/损坏返回 '' */
  private static decryptValue(dek: Uint8Array, name: string, stored: string): string {
    try {
      const blob: Uint8Array = SecureStore.decodeEnvelope(stored);
      if (blob.length < 12 + 16) {
        return '';
      }
      const nonce: Uint8Array = blob.subarray(0, 12);
      const body: Uint8Array = blob.subarray(12);
      const plain: Uint8Array | null = aesGcmDecrypt(dek, nonce, SecureStore.utf8Encode(name), body);
      if (plain === null) {
        return '';
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(plain);
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'decryptValue failed: %{public}s', `${error}`);
      return '';
    }
  }

  /** nonce ‖ data → 'e1.' + Base64 */
  private static buildEnvelope(nonce: Uint8Array, data: Uint8Array): string {
    const blob: Uint8Array = new Uint8Array(nonce.length + data.length);
    blob.set(nonce);
    blob.set(data, nonce.length);
    const helper: util.Base64Helper = new util.Base64Helper();
    return ENVELOPE_PREFIX + helper.encodeToStringSync(blob);
  }

  /** 'e1.' 信封 → 原始字节（nonce ‖ data）；格式非法抛异常由调用方兜底 */
  private static decodeEnvelope(stored: string): Uint8Array {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.decodeSync(stored.substring(ENVELOPE_PREFIX.length));
  }

  private static utf8Encode(text: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(text);
  }
}
