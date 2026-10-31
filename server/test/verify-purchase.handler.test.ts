// verify-purchase uç noktası: Apple doğrulaması ve Supabase TAKLİT edilir
// (ağ yok, gerçek veri yok). Destek kaydının YALNIZCA imzası doğrulanmış ve
// appAccountToken'ı isteği yapan hesapla eşleşen işlemde açıldığını doğrular.
// Derlenmiş (CommonJS) hâliyle `node --test` ile çalışır.
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

const USER = '0b6f8a52-1c3e-4d7a-9f10-2a3b4c5d6e7f';
const OTHER = '11111111-1111-4111-8111-111111111111';

type Call = { name: string; args: Record<string, unknown> };
let rpcCalls: Call[] = [];
let profileUpdates = 0;
let claimResult: { result: string; previous_owner: string | null } = { result: 'linked', previous_owner: null };
let recordResponse: { data: unknown; error: unknown } = { data: 'K7M2Q9XZ', error: null };

// Taklit imzalı işlem: "valid:<json>" doğrulanır, diğer her şey imza hatası.
class FakeVerifier {
  async verifyAndDecodeTransaction(signed: string) {
    if (!signed.startsWith('valid:')) throw new Error('invalid signature');
    return JSON.parse(signed.slice(6));
  }
}

const fakeSupabase = {
  createClient: (_url: string, key: string) => ({
    auth: {
      getUser: async () => ({ data: { user: { id: USER } }, error: null }),
      admin: {
        getUserById: async () => ({ data: { user: { app_metadata: { provider: 'apple' } } } }),
      },
    },
    from: () => {
      profileUpdates++;
      throw new Error('verify-purchase profillere doğrudan yazmamalı');
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      assert.equal(key, 'service-key', 'RPC yalnızca service role ile');
      rpcCalls.push({ name, args });
      if (name === 'claim_subscription') {
        return { single: async () => ({ data: claimResult, error: null }) };
      }
      return Promise.resolve(recordResponse);
    },
  }),
};

// eslint-disable-next-line @typescript-eslint/no-var-requires
const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: unknown[]) {
  if (request === '@supabase/supabase-js') return fakeSupabase;
  if (request === '@apple/app-store-server-library') {
    return {
      SignedDataVerifier: FakeVerifier,
      Environment: { PRODUCTION: 'Production', SANDBOX: 'Sandbox' },
    };
  }
  return origLoad.call(this, request, ...rest);
};

process.env.SUPABASE_URL = 'http://localhost';
process.env.SUPABASE_ANON_KEY = 'anon-key';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-key';
process.env.APPLE_APP_APPLE_ID = '1234567890';
delete process.env.SUBSCRIPTION_TOKEN_TRANSFER;

// eslint-disable-next-line @typescript-eslint/no-var-requires
const handler = require('../api/verify-purchase').default;

function tx(overrides: Record<string, unknown> = {}) {
  return 'valid:' + JSON.stringify({
    bundleId: 'com.kaan.lifeadmin',
    productId: 'lifeadmin_premium_yearly',
    transactionId: 'TX-1',
    originalTransactionId: 'OT-1',
    appAccountToken: USER,
    expiresDate: Date.now() + 365 * 864e5,
    environment: 'Sandbox',
    ...overrides,
  });
}

async function call(receiptData: string) {
  const res: { code?: number; body?: Record<string, unknown> } = {};
  const r = {
    setHeader() {},
    status(c: number) { res.code = c; return r; },
    json(b: Record<string, unknown>) { res.body = b; return r; },
    end() { return r; },
  };
  await handler(
    { method: 'POST', headers: { authorization: 'Bearer user-jwt' },
      body: { productId: 'lifeadmin_premium_yearly', receiptData } },
    r,
  );
  return res;
}

const recorded = () => rpcCalls.filter((c) => c.name === 'record_subscription_claim');

beforeEach(() => {
  rpcCalls = [];
  profileUpdates = 0;
  claimResult = { result: 'owned_by_other', previous_owner: OTHER };
  recordResponse = { data: 'K7M2Q9XZ', error: null };
});

test('imzası geçersiz işlem: hiçbir RPC çağrılmaz, kayıt açılmaz', async () => {
  const res = await call('forged:' + tx().slice(6));
  assert.equal(res.code, 200);
  assert.equal(res.body?.success, false);
  assert.equal(rpcCalls.length, 0);
});

test('başka uygulamanın (bundle) işlemi: kayıt açılmaz', async () => {
  const res = await call(tx({ bundleId: 'com.evil.app' }));
  assert.equal(res.body?.success, false);
  assert.equal(rpcCalls.length, 0);
});

test('bilinmeyen ürün: kayıt açılmaz', async () => {
  await call(tx({ productId: 'other_product' }));
  assert.equal(rpcCalls.length, 0);
});

test('token bu hesapla eşleşiyor + başka hesapta: kayıt açılır, referans döner', async () => {
  const res = await call(tx());
  assert.equal(res.body?.code, 'SUBSCRIPTION_CLAIM_RECORDED');
  assert.equal(res.body?.reference, 'K7M2Q9XZ');
  assert.equal(res.body?.provider, 'apple');
  const [rec] = recorded();
  assert.deepEqual(rec.args, {
    p_user_id: USER,
    p_original_transaction_id: 'OT-1',
    p_transaction_id: 'TX-1',
    p_product_id: 'lifeadmin_premium_yearly',
    p_environment: 'sandbox',
    p_expires_at: (rec.args.p_expires_at as string),
    p_token_matches: true,
  });
  assert.equal(rpcCalls.find((c) => c.name === 'claim_subscription')?.args.p_allow_token_transfer, false);
  assert.equal(profileUpdates, 0);
});

test('token BAŞKA hesabın: kayıt açılmaz, LINKED_ELSEWHERE', async () => {
  const res = await call(tx({ appAccountToken: OTHER }));
  assert.equal(res.body?.code, 'SUBSCRIPTION_LINKED_ELSEWHERE');
  assert.equal(recorded().length, 0);
  assert.equal('reference' in (res.body ?? {}), false);
});

test('token yok (eski satın alma / Geri Yükle): kayıt açılmaz', async () => {
  const res = await call(tx({ appAccountToken: undefined }));
  assert.equal(res.body?.code, 'SUBSCRIPTION_LINKED_ELSEWHERE');
  assert.equal(recorded().length, 0);
});

test('kayıt hatası (ör. işlem başka hesabın talebi): referans sızmaz', async () => {
  recordResponse = { data: null, error: { code: '23505' } };
  const res = await call(tx());
  assert.equal(res.code, 200);
  assert.equal(res.body?.code, 'SUBSCRIPTION_LINKED_ELSEWHERE');
  assert.equal('reference' in (res.body ?? {}), false);
});

test('biçimsiz referans gelirse gösterilmez', async () => {
  recordResponse = { data: 'user@example.com', error: null };
  const res = await call(tx());
  assert.equal(res.body?.code, 'SUBSCRIPTION_LINKED_ELSEWHERE');
});

test('abonelik bu hesaba bağlanırsa kayıt açılmaz (normal satın alma)', async () => {
  claimResult = { result: 'linked', previous_owner: null };
  const res = await call(tx());
  assert.equal(res.body?.success, true);
  assert.equal(res.body?.plan, 'premium');
  assert.equal(recorded().length, 0);
});

test('iade edilmiş (revoked) işlem: kayıt açılmaz', async () => {
  const res = await call(tx({ revocationDate: Date.now() - 1000 }));
  assert.equal(res.body?.code, 'SUBSCRIPTION_LINKED_ELSEWHERE');
  assert.equal(recorded().length, 0);
  assert.equal(rpcCalls.find((c) => c.name === 'claim_subscription')?.args.p_status, 'revoked');
});
