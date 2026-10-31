// node --test ile çalışır (derlendikten sonra): sahiplik çakışması yanıtları.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  isClaimReference,
  normalizeEnvironment,
  ownershipConflictBody,
  tokenMatchesUser,
} from '../lib/ownership';

const USER = '0b6f8a52-1c3e-4d7a-9f10-2a3b4c5d6e7f';

test('token yalnızca aynı hesap kimliğiyle eşleşir', () => {
  assert.equal(tokenMatchesUser(USER, USER), true);
  assert.equal(tokenMatchesUser(USER.toUpperCase(), USER), true);
  assert.equal(tokenMatchesUser('11111111-1111-1111-1111-111111111111', USER), false);
  assert.equal(tokenMatchesUser(undefined, USER), false);
  assert.equal(tokenMatchesUser('not-a-uuid', USER), false);
});

test('ortam yalnızca production veya sandbox', () => {
  assert.equal(normalizeEnvironment('Production'), 'production');
  assert.equal(normalizeEnvironment('Sandbox'), 'sandbox');
  assert.equal(normalizeEnvironment(undefined), 'sandbox');
});

test('referans: 8 karakter Crockford Base32 (I, L, O, U yok)', () => {
  assert.equal(isClaimReference('7KQ2M9XZ'), true);
  assert.equal(isClaimReference('A1B2C3D4'), true);
  assert.equal(isClaimReference('A1B2C3DI'), false);
  assert.equal(isClaimReference('a1b2c3d4'), false);
  assert.equal(isClaimReference('A1B2C3D'), false);
  assert.equal(isClaimReference(undefined), false);
});

test('kayıt açıldıysa CLAIM_RECORDED, yeniden ödeme istenmez', () => {
  const body = ownershipConflictBody('apple', 'A1B2C3D4');
  assert.equal(body.success, false);
  assert.equal(body.code, 'SUBSCRIPTION_CLAIM_RECORDED');
  assert.equal(body.reference, 'A1B2C3D4');
  assert.match(String(body.reason), /yeniden ödeme yapma/);
  assert.match(String(body.reason), /A1B2C3D4/);
});

test('kayıt yoksa LINKED_ELSEWHERE + destek yolu', () => {
  const body = ownershipConflictBody(null, null);
  assert.equal(body.code, 'SUBSCRIPTION_LINKED_ELSEWHERE');
  assert.equal('reference' in body, false);
  assert.match(String(body.reason), /Destek/);
  assert.match(String(body.reason), /yeniden ödeme yapma/);
});
