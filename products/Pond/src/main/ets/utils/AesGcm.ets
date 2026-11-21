/**
 * 纯 ArkTS 同步 AES-256-GCM 实现（FIPS-197 + NIST SP 800-38D）。
 *
 * 背景：HarmonyOS SDK 的 HUKS / cryptoFramework 加解密均为异步 Promise 接口，而本应用
 * 数据层（preferences 读写、卡片绑定数据构建）是同步调用链，且部分处于同步生命周期回调
 * （FormExtensionAbility.onAddForm 必须同步返回 FormBindingData），无法改造为异步。
 *
 * 因此：数据加解密用本模块同步完成；仅数据密钥（DEK）的 HUKS 解包在进程启动时一次性
 * 异步完成（见 data/SecureStore.ets），解包后 DEK 仅存在于进程内存，绝不落盘。
 *
 * 正确性由 NIST GCM 官方测试向量（Test Case 14/16/17）在单元测试中保证。
 */

/** AES S 盒（FIPS-197） */
const SBOX: number[] = [
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
];

/** GF(2^8) 上的 xtime（乘 2，多项式 x^8+x^4+x^3+x+1） */
function xtime(a: number): number {
  const shifted: number = (a << 1) & 0xff;
  return (a & 0x80) !== 0 ? (shifted ^ 0x1b) : shifted;
}

/** AES-256 密钥扩展：返回 240 字节轮密钥（Nr=14，4*(Nr+1) 个 4 字节字） */
export function expandKey256(key: Uint8Array): Uint8Array {
  const roundKeys: Uint8Array = new Uint8Array(240);
  for (let i: number = 0; i < 32; i++) {
    roundKeys[i] = key[i];
  }
  let rcon: number = 0x01;
  for (let word: number = 8; word < 60; word++) {
    const base: number = (word - 1) * 4;
    let t0: number = roundKeys[base];
    let t1: number = roundKeys[base + 1];
    let t2: number = roundKeys[base + 2];
    let t3: number = roundKeys[base + 3];
    if (word % 8 === 0) {
      // RotWord + SubWord + Rcon
      const r0: number = SBOX[t1] ^ rcon;
      const r1: number = SBOX[t2];
      const r2: number = SBOX[t3];
      const r3: number = SBOX[t0];
      t0 = r0;
      t1 = r1;
      t2 = r2;
      t3 = r3;
      rcon = xtime(rcon);
    } else if (word % 8 === 4) {
      // 仅 SubWord（AES-256 特有）
      t0 = SBOX[t0];
      t1 = SBOX[t1];
      t2 = SBOX[t2];
      t3 = SBOX[t3];
    }
    const prev: number = (word - 8) * 4;
    roundKeys[word * 4] = roundKeys[prev] ^ t0;
    roundKeys[word * 4 + 1] = roundKeys[prev + 1] ^ t1;
    roundKeys[word * 4 + 2] = roundKeys[prev + 2] ^ t2;
    roundKeys[word * 4 + 3] = roundKeys[prev + 3] ^ t3;
  }
  return roundKeys;
}

/** AES 单块加密（16 字节输入 → 16 字节输出） */
function encryptBlock(roundKeys: Uint8Array, input: Uint8Array, output: Uint8Array): void {
  const s: number[] = new Array<number>(16);
  for (let i: number = 0; i < 16; i++) {
    s[i] = input[i];
  }
  for (let i: number = 0; i < 16; i++) {
    s[i] ^= roundKeys[i];
  }
  for (let round: number = 1; round <= 13; round++) {
    const off: number = round * 16;
    // SubBytes
    for (let i: number = 0; i < 16; i++) {
      s[i] = SBOX[s[i]];
    }
    // ShiftRows：行 r（下标 r、r+4、r+8、r+12）左循环移 r 位
    let t: number = s[1];
    s[1] = s[5];
    s[5] = s[9];
    s[9] = s[13];
    s[13] = t;
    t = s[2];
    s[2] = s[10];
    s[10] = t;
    t = s[6];
    s[6] = s[14];
    s[14] = t;
    t = s[15];
    s[15] = s[11];
    s[11] = s[7];
    s[7] = s[3];
    s[3] = t;
    // MixColumns
    for (let c: number = 0; c < 4; c++) {
      const o: number = c * 4;
      const a0: number = s[o];
      const a1: number = s[o + 1];
      const a2: number = s[o + 2];
      const a3: number = s[o + 3];
      s[o] = xtime(a0) ^ xtime(a1) ^ a1 ^ a2 ^ a3;
      s[o + 1] = a0 ^ xtime(a1) ^ xtime(a2) ^ a2 ^ a3;
      s[o + 2] = a0 ^ a1 ^ xtime(a2) ^ xtime(a3) ^ a3;
      s[o + 3] = xtime(a0) ^ a0 ^ a1 ^ a2 ^ xtime(a3);
    }
    // AddRoundKey
    for (let i: number = 0; i < 16; i++) {
      s[i] ^= roundKeys[off + i];
    }
  }
  // 最后一轮：无 MixColumns
  for (let i: number = 0; i < 16; i++) {
    s[i] = SBOX[s[i]];
  }
  let t: number = s[1];
  s[1] = s[5];
  s[5] = s[9];
  s[9] = s[13];
  s[13] = t;
  t = s[2];
  s[2] = s[10];
  s[10] = t;
  t = s[6];
  s[6] = s[14];
  s[14] = t;
  t = s[15];
  s[15] = s[11];
  s[11] = s[7];
  s[7] = s[3];
  s[3] = t;
  for (let i: number = 0; i < 16; i++) {
    output[i] = s[i] ^ roundKeys[224 + i];
  }
}

/** GCM 的 GF(2^128) 乘法（NIST SP 800-38D Algorithm 1，R = E1 || 0^120） */
function gfMul(x: Uint8Array, y: Uint8Array): Uint8Array {
  const z: Uint8Array = new Uint8Array(16);
  const v: Uint8Array = new Uint8Array(16);
  v.set(y);
  for (let i: number = 0; i < 128; i++) {
    if ((x[i >> 3] & (1 << (7 - (i & 7)))) !== 0) {
      for (let j: number = 0; j < 16; j++) {
        z[j] ^= v[j];
      }
    }
    // V 右移一位（128 位跨字节），最低位为 1 时异或 R
    const lsb: number = v[15] & 1;
    for (let j: number = 15; j > 0; j--) {
      v[j] = (v[j] >>> 1) | ((v[j - 1] & 1) << 7);
    }
    v[0] = v[0] >>> 1;
    if (lsb === 1) {
      v[0] ^= 0xe1;
    }
  }
  return z;
}

/** GHASH：对 AAD 与密文按 16 字节分块（末块零填充）+ 长度块累乘 H */
function ghash(h: Uint8Array, aad: Uint8Array, cipher: Uint8Array): Uint8Array {
  const y: Uint8Array = new Uint8Array(16);
  const block: Uint8Array = new Uint8Array(16);
  let index: number = 0;
  for (let part: number = 0; part < 2; part++) {
    const data: Uint8Array = part === 0 ? aad : cipher;
    index = 0;
    while (index < data.length) {
      for (let i: number = 0; i < 16; i++) {
        block[i] = index + i < data.length ? data[index + i] : 0;
      }
      for (let i: number = 0; i < 16; i++) {
        block[i] ^= y[i];
      }
      y.set(gfMul(block, h));
      index += 16;
    }
  }
  // 长度块：AAD 位数 || 密文位数（64 位大端各一）
  const aadBits: number = aad.length * 8;
  const cipherBits: number = cipher.length * 8;
  for (let i: number = 0; i < 16; i++) {
    block[i] = 0;
  }
  block[4] = (aadBits >>> 24) & 0xff;
  block[5] = (aadBits >>> 16) & 0xff;
  block[6] = (aadBits >>> 8) & 0xff;
  block[7] = aadBits & 0xff;
  block[12] = (cipherBits >>> 24) & 0xff;
  block[13] = (cipherBits >>> 16) & 0xff;
  block[14] = (cipherBits >>> 8) & 0xff;
  block[15] = cipherBits & 0xff;
  for (let i: number = 0; i < 16; i++) {
    block[i] ^= y[i];
  }
  return gfMul(block, h);
}

/** 32 位大端自增（GCM 计数器块最后 4 字节） */
function inc32(block: Uint8Array): void {
  for (let i: number = 15; i >= 12; i--) {
    block[i] = (block[i] + 1) & 0xff;
    if (block[i] !== 0) {
      return;
    }
  }
}

/**
 * AES-256-GCM 加密（96 位 nonce）。
 * 返回 密文||tag（16 字节认证标签）。
 */
export function aesGcmEncrypt(key: Uint8Array, nonce: Uint8Array, aad: Uint8Array,
  plain: Uint8Array): Uint8Array {
  const roundKeys: Uint8Array = expandKey256(key);
  const h: Uint8Array = new Uint8Array(16);
  encryptBlock(roundKeys, h, h);
  // J0 = nonce || 0x00000001
  const j0: Uint8Array = new Uint8Array(16);
  j0.set(nonce);
  j0[15] = 1;
  const out: Uint8Array = new Uint8Array(plain.length + 16);
  const counter: Uint8Array = new Uint8Array(16);
  const stream: Uint8Array = new Uint8Array(16);
  counter.set(j0);
  let index: number = 0;
  while (index < plain.length) {
    inc32(counter);
    encryptBlock(roundKeys, counter, stream);
    const n: number = plain.length - index < 16 ? plain.length - index : 16;
    for (let i: number = 0; i < n; i++) {
      out[index + i] = plain[index + i] ^ stream[i];
    }
    index += 16;
  }
  const cipher: Uint8Array = out.subarray(0, plain.length);
  const s: Uint8Array = ghash(h, aad, cipher);
  encryptBlock(roundKeys, j0, stream);
  for (let i: number = 0; i < 16; i++) {
    out[plain.length + i] = s[i] ^ stream[i];
  }
  return out;
}

/**
 * AES-256-GCM 解密：输入为 密文||tag（与 aesGcmEncrypt 输出同构）。
 * 认证失败返回 null（密文被篡改 / 密钥不符 / nonce 不符）。
 */
export function aesGcmDecrypt(key: Uint8Array, nonce: Uint8Array, aad: Uint8Array,
  cipherWithTag: Uint8Array): Uint8Array | null {
  if (cipherWithTag.length < 16) {
    return null;
  }
  const cipherLen: number = cipherWithTag.length - 16;
  const roundKeys: Uint8Array = expandKey256(key);
  const h: Uint8Array = new Uint8Array(16);
  encryptBlock(roundKeys, h, h);
  const j0: Uint8Array = new Uint8Array(16);
  j0.set(nonce);
  j0[15] = 1;
  // 先校验 tag
  const cipher: Uint8Array = cipherWithTag.subarray(0, cipherLen);
  const givenTag: Uint8Array = cipherWithTag.subarray(cipherLen);
  const s: Uint8Array = ghash(h, aad, cipher);
  const stream: Uint8Array = new Uint8Array(16);
  encryptBlock(roundKeys, j0, stream);
  for (let i: number = 0; i < 16; i++) {
    stream[i] ^= s[i];
  }
  let diff: number = 0;
  for (let i: number = 0; i < 16; i++) {
    diff |= stream[i] ^ givenTag[i];
  }
  if (diff !== 0) {
    return null;
  }
  // 校验通过后 CTR 解密
  const out: Uint8Array = new Uint8Array(cipherLen);
  const counter: Uint8Array = new Uint8Array(16);
  counter.set(j0);
  let index: number = 0;
  while (index < cipherLen) {
    inc32(counter);
    encryptBlock(roundKeys, counter, stream);
    const n: number = cipherLen - index < 16 ? cipherLen - index : 16;
    for (let i: number = 0; i < n; i++) {
      out[index + i] = cipher[index + i] ^ stream[i];
    }
    index += 16;
  }
  return out;
}
