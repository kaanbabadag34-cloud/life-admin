# Apple kök sertifikaları — buraya gerekiyor

`index.ts`, StoreKit 2 signed transaction'ların imza zincirini Apple PKI'daki
kök sertifikalara kadar doğrulamak için bu klasördeki **üç** dosyayı okuyor.
Hiçbiri **secret değil** — Apple'ın herkese açık kök sertifikaları, repoya
commit edilmesinde sakınca yok.

## İndirmen gereken 3 dosya (isimleri AYNEN böyle kalmalı)

| Dosya adı (bu klasöre, bu adla) | Kaynak |
|---|---|
| `AppleIncRoot.cer` | https://www.apple.com/certificateauthority/AppleIncRootCertificate.cer |
| `AppleRootCA-G2.cer` | https://www.apple.com/certificateauthority/AppleRootCA-G2.cer |
| `AppleRootCA-G3.cer` | https://www.apple.com/certificateauthority/AppleRootCA-G3.cer |

(Tüm liste: https://www.apple.com/certificateauthority/ — sayfadaki "Apple
Root Certificates" bölümü.)

## Yapman gereken (tek seferlik)

1. Yukarıdaki 3 dosyayı indir, **değiştirmeden**, tam olarak tablodaki
   adlarla bu klasöre (`supabase/functions/verify-purchase/certs/`) koy.
2. `supabase functions deploy verify-purchase` ile tekrar deploy et.

Üçünden biri bile eksikse fonksiyon, satın almayı yanlış/eksik yorumlamak
yerine net bir "Apple kök sertifikaları eksik: ..." hatasıyla durur —
sessizce yanlış/güvensiz bir doğrulama yapmaz.
