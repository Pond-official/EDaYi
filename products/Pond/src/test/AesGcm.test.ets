import { describe, it, expect } from '@ohos/hypium';
import { aesGcmEncrypt, aesGcmDecrypt } from '../main/ets/utils/AesGcm';

/**
 * NIST SP 800-38D / McGrew-Viega GCM 官方测试向量（AES-256，Test Case 13/14/16/17）。
 * 期望值已用 OpenSSL（Node crypto aes-256-gcm）与公开向量文件双向核对。
 */
const KEY_ZERO: string = '00000000000000000000000000000000' +
  '00000000000000000000000000000000';
const KEY_FEFFE: string = 'feffe9928665731c6d6a8f9467308308' +
  'feffe9928665731c6d6a8f9467308308';
const IV_ZERO: string = '000000000000000000000000';
const IV_CAFE: string = 'cafebabefacedbaddecaf888';
const PT64: string = 'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72' +
  '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255';
const AAD_TC17: string = 'feedfacedeadbeeffeedfacedeadbeefabaddad2';
const TC13_TAG: string = '530f8afbc74536b9a963b4f1c4cb738b';
const TC14_CT: string = 'cea7403d4d606b6e074ec5d3baf39d18' +
  'd0d1c8a799996bf0265b98b5d48ab919';
const TC16_CT: string = '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa' +
  '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad' +
  'b094dac5d93471bdec1a502270e3cc6c';
const TC17_CT: string = '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa' +
  '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662' +
  '76fc6ece0f4e1768cddf8853bb2d551b';

function hexToBytes(hex: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(hex.length / 2);
  for (let i: number = 0; i < out.length; i++) {
    out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    const value: number = bytes[i];
    hex += value < 16 ? '0' + value.toString(16) : value.toString(16);
  }
  return hex;
}

/** 固定模式的测试字节序列（避免依赖随机源） */
function patternBytes(length: number, seed: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(length);
  for (let i: number = 0; i < length; i++) {
    out[i] = (i * 13 + seed) & 0xff;
  }
  return out;
}

export default function aesGcmTest() {
  describe('AesGcm', () => {
    it('nist_tc13_empty_plaintext_tag_only', 0, () => {
      const out: Uint8Array = aesGcmEncrypt(hexToBytes(KEY_ZERO), hexToBytes(IV_ZERO),
        hexToBytes(''), hexToBytes(''));
      expect(out.length).assertEqual(16);
      expect(bytesToHex(out)).assertEqual(TC13_TAG);
    });
    it('nist_tc14_zero_key_single_block', 0, () => {
      const out: Uint8Array = aesGcmEncrypt(hexToBytes(KEY_ZERO), hexToBytes(IV_ZERO),
        hexToBytes(''), hexToBytes('00000000000000000000000000000000'));
      expect(out.length).assertEqual(32);
      expect(bytesToHex(out)).assertEqual(TC14_CT);
    });
    it('nist_tc16_multiblock_64_bytes', 0, () => {
      const out: Uint8Array = aesGcmEncrypt(hexToBytes(KEY_FEFFE), hexToBytes(IV_CAFE),
        hexToBytes(''), hexToBytes(PT64));
      expect(bytesToHex(out)).assertEqual(TC16_CT);
    });
    it('nist_tc17_with_aad_60_bytes', 0, () => {
      const pt60: string = PT64.substring(0, 120);
      const out: Uint8Array = aesGcmEncrypt(hexToBytes(KEY_FEFFE), hexToBytes(IV_CAFE),
        hexToBytes(AAD_TC17), hexToBytes(pt60));
      expect(bytesToHex(out)).assertEqual(TC17_CT);
    });
    it('decrypt_nist_tc16_recovers_plaintext', 0, () => {
      const dec: Uint8Array | null = aesGcmDecrypt(hexToBytes(KEY_FEFFE), hexToBytes(IV_CAFE),
        hexToBytes(''), hexToBytes(TC16_CT));
      expect(dec !== null).assertTrue();
      if (dec === null) {
        return;
      }
      expect(bytesToHex(dec)).assertEqual(PT64);
    });
    it('decrypt_nist_tc17_recovers_plaintext', 0, () => {
      const pt60: string = PT64.substring(0, 120);
      const dec: Uint8Array | null = aesGcmDecrypt(hexToBytes(KEY_FEFFE), hexToBytes(IV_CAFE),
        hexToBytes(AAD_TC17), hexToBytes(TC17_CT));
      expect(dec !== null).assertTrue();
      if (dec === null) {
        return;
      }
      expect(bytesToHex(dec)).assertEqual(pt60);
    });
    it('roundtrip_odd_length_with_aad', 0, () => {
      const key: Uint8Array = patternBytes(32, 3);
      const nonce: Uint8Array = patternBytes(12, 1);
      const plain: Uint8Array = patternBytes(37, 7);
      const aad: Uint8Array = hexToBytes(AAD_TC17);
      const enc: Uint8Array = aesGcmEncrypt(key, nonce, aad, plain);
      expect(enc.length).assertEqual(37 + 16);
      const dec: Uint8Array | null = aesGcmDecrypt(key, nonce, aad, enc);
      expect(dec !== null).assertTrue();
      if (dec === null) {
        return;
      }
      expect(bytesToHex(dec)).assertEqual(bytesToHex(plain));
    });
    it('decrypt_rejects_tampered_ciphertext', 0, () => {
      const key: Uint8Array = patternBytes(32, 3);
      const nonce: Uint8Array = patternBytes(12, 1);
      const plain: Uint8Array = patternBytes(37, 7);
      const aad: Uint8Array = hexToBytes(AAD_TC17);
      const enc: Uint8Array = aesGcmEncrypt(key, nonce, aad, plain);
      enc[0] = enc[0] ^ 0x01;
      expect(aesGcmDecrypt(key, nonce, aad, enc)).assertNull();
    });
    it('decrypt_rejects_tampered_tag', 0, () => {
      const key: Uint8Array = patternBytes(32, 3);
      const nonce: Uint8Array = patternBytes(12, 1);
      const plain: Uint8Array = patternBytes(37, 7);
      const aad: Uint8Array = hexToBytes(AAD_TC17);
      const enc: Uint8Array = aesGcmEncrypt(key, nonce, aad, plain);
      enc[enc.length - 1] = enc[enc.length - 1] ^ 0x80;
      expect(aesGcmDecrypt(key, nonce, aad, enc)).assertNull();
    });
    it('decrypt_rejects_wrong_aad', 0, () => {
      const key: Uint8Array = patternBytes(32, 3);
      const nonce: Uint8Array = patternBytes(12, 1);
      const plain: Uint8Array = patternBytes(37, 7);
      const enc: Uint8Array = aesGcmEncrypt(key, nonce, hexToBytes(AAD_TC17), plain);
      const dec: Uint8Array | null = aesGcmDecrypt(key, nonce, hexToBytes('deadbeef'), enc);
      expect(dec).assertNull();
    });
    it('decrypt_rejects_wrong_key', 0, () => {
      const key: Uint8Array = patternBytes(32, 3);
      const wrongKey: Uint8Array = patternBytes(32, 11);
      const nonce: Uint8Array = patternBytes(12, 1);
      const plain: Uint8Array = patternBytes(37, 7);
      const enc: Uint8Array = aesGcmEncrypt(key, nonce, hexToBytes(''), plain);
      expect(aesGcmDecrypt(wrongKey, nonce, hexToBytes(''), enc)).assertNull();
    });
    it('decrypt_rejects_short_input', 0, () => {
      const key: Uint8Array = patternBytes(32, 3);
      const nonce: Uint8Array = patternBytes(12, 1);
      expect(aesGcmDecrypt(key, nonce, hexToBytes(''), patternBytes(15, 5))).assertNull();
    });
  });
}
