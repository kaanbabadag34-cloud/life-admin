// Abonelik başka bir Life Admin hesabına bağlıyken verilecek yanıt.
//
// Kural: abonelik ASLA otomatik taşınmaz (SUBSCRIPTION_TOKEN_TRANSFER kapalı).
//  * Satın alma Apple imzalı appAccountToken ile BU hesapta başlatıldıysa
//    (gerçekten bu hesapta ödeme yapıldı) bir destek kaydı açılır ve kullanıcıya
//    referans verilir; destek Apple'dan teyit edip aktarır.
//  * Aksi hâlde (Geri Yükle, token yok/başka hesap) kullanıcı doğru hesaba
//    yönlendirilir.
// Yanıt HTTP 200 + success:false döner (kesin sonuç): uygulama işlemi StoreKit'te
// kapatır, tekrar denemez ve yeniden satın almaya yönlendirmez.
// Kişisel veri paylaşılmaz: yalnızca bağlı hesabın GİRİŞ TÜRÜ söylenir.

export type LoginProvider = 'apple' | 'google' | 'email';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value);
}

/** appAccountToken, isteği yapan hesabın kimliğiyle eşleşiyor mu? */
export function tokenMatchesUser(appAccountToken: unknown, userId: string): boolean {
  return isUuid(appAccountToken) && appAccountToken.toLowerCase() === userId.toLowerCase();
}

export function normalizeEnvironment(env: unknown): 'production' | 'sandbox' {
  return String(env ?? '').toLowerCase() === 'production' ? 'production' : 'sandbox';
}

// Destek referansı: 8 karakter Crockford Base32 (veritabanı üretir ve
// benzersizliğini garanti eder; bkz. subscription_claim_reference).
const REFERENCE_RE = /^[0-9A-HJKMNP-TV-Z]{8}$/;

export function isClaimReference(value: unknown): value is string {
  return typeof value === 'string' && REFERENCE_RE.test(value);
}

function providerLabel(provider: LoginProvider | null): string {
  switch (provider) {
    case 'apple':
      return 'Apple ile giriş yapılmış ';
    case 'google':
      return 'Google ile giriş yapılmış ';
    case 'email':
      return 'e-posta ile oluşturulmuş ';
    default:
      return '';
  }
}

export function linkedElsewhereReason(provider: LoginProvider | null): string {
  return (
    `Bu abonelik ${providerLabel(provider)}başka bir Life Admin hesabına bağlı. ` +
    'Premium’u kullanmak için o hesapla giriş yap. O hesaba erişemiyorsan ' +
    'Destek’e yaz; yeniden ödeme yapma.'
  );
}

export function claimRecordedReason(provider: LoginProvider | null, reference: string): string {
  return (
    'Ödemen Apple tarafından doğrulandı, ancak bu abonelik ' +
    `${providerLabel(provider)}başka bir Life Admin hesabına bağlı olduğu için ` +
    'Premium bu hesapta henüz açılamadı. Lütfen yeniden ödeme yapma. ' +
    `Destek’e ${reference} referansıyla yaz; inceleme sonrası Premium bu hesaba aktarılır.`
  );
}

export function ownershipConflictBody(
  provider: LoginProvider | null,
  reference: string | null,
): Record<string, unknown> {
  return reference
    ? {
        success: false,
        code: 'SUBSCRIPTION_CLAIM_RECORDED',
        provider,
        reference,
        reason: claimRecordedReason(provider, reference),
      }
    : {
        success: false,
        code: 'SUBSCRIPTION_LINKED_ELSEWHERE',
        provider,
        reason: linkedElsewhereReason(provider),
      };
}
