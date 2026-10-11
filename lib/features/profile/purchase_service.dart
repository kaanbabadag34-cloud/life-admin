import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// verify-purchase artık bir Supabase Edge Function değil, ayrı bir Vercel
// Node serverless function (server/api/verify-purchase.ts) — @apple/app-
// store-server-library Node.js runtime hedeflediği için Deno/Supabase Edge
// ortamında bir sertifika doğrulama uyumsuzluğu ("BER error") yaşanıyordu.
// TODO: Vercel'e deploy ettikten sonra gerçek URL'ini buraya yaz
// (örn. 'https://life-admin-verify-purchase.vercel.app/api/verify-purchase').
const String _verifyPurchaseEndpoint =
    'https://life-admin-server.vercel.app/api/verify-purchase';

// App Store Connect'te oluşturulacak abonelik Product ID'leri.
enum PremiumPlan { monthly, yearly }

// Paywall'ın UI'ı bu durumları göstermek için kullanıyor. `verifying`,
// StoreKit'in "purchased/restored" dediği ANDAN, bizim sunucuya (Supabase
// Edge Function) sorup Apple'ın makbuzunu gerçekten doğrulattığımız ana
// kadar geçen aralığı temsil ediyor — Premium bu aralıkta ASLA açılmaz.
enum PurchaseFlowStatus { idle, pending, verifying, success, canceled, error }

// Tek, uygulama ömrü boyunca yaşayan singleton — `main.dart`'ta bir kez
// initialize() ediliyor (Apple'ın kendi önerdiği gibi: satın alma listener'ı
// mümkün olduğunca erken bağlanmalı, çünkü uygulama kapalıyken tamamlanan
// bir işlem bir sonraki açılışta purchaseStream üzerinden gelebilir).
// initialize() `_initialized` bayrağıyla korunuyor; PremiumPage tekrar
// açılıp kapansa bile İKİNCİ bir stream listener asla oluşmuyor.
class PurchaseService extends ChangeNotifier {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  static const String monthlyProductId = 'lifeadmin_premium_monthly';
  static const String yearlyProductId = 'lifeadmin_premium_yearly';

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;
  int _restoreRequestId = 0;

  bool storeAvailable = false;
  bool loadingProducts = false;
  String? productsError;

  final Map<String, ProductDetails> _products = {};

  PurchaseFlowStatus status = PurchaseFlowStatus.idle;
  String? statusMessage;

  ProductDetails? productFor(PremiumPlan plan) {
    return _products[_productId(plan)];
  }

  String _productId(PremiumPlan plan) {
    return plan == PremiumPlan.monthly ? monthlyProductId : yearlyProductId;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _subscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object _) {
        status = PurchaseFlowStatus.error;
        statusMessage = 'Satın alma sırasında beklenmeyen bir hata oluştu.';
        notifyListeners();
      },
    );

    await loadProducts();
  }

  Future<void> loadProducts() async {
    loadingProducts = true;
    productsError = null;
    notifyListeners();

    try {
      storeAvailable = await _inAppPurchase.isAvailable();

      if (!storeAvailable) {
        productsError = 'Mağazaya şu anda ulaşılamıyor.';
        return;
      }

      final response = await _inAppPurchase.queryProductDetails(
        {monthlyProductId, yearlyProductId},
      );

      for (final product in response.productDetails) {
        _products[product.id] = product;
      }

      if (_products.isEmpty) {
        productsError = 'Abonelik ürünleri bulunamadı.';
      }
    } catch (_) {
      productsError = 'Ürünler yüklenemedi. Tekrar deneyin.';
    } finally {
      loadingProducts = false;
      notifyListeners();
    }
  }

  Future<void> buy(PremiumPlan plan) async {
    final product = productFor(plan);
    if (product == null) return;

    status = PurchaseFlowStatus.pending;
    statusMessage = null;
    notifyListeners();

    await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> restore() async {
    if (!storeAvailable) {
      status = PurchaseFlowStatus.error;
      statusMessage = 'Mağazaya şu anda ulaşılamıyor.';
      notifyListeners();
      return;
    }

    status = PurchaseFlowStatus.pending;
    statusMessage = null;
    notifyListeners();

    final requestId = ++_restoreRequestId;

    await _inAppPurchase.restorePurchases();

    // StoreKit, geri yüklenecek HİÇBİR satın alma yoksa purchaseStream'e
    // hiçbir event basmayabilir — bu durumda `status` sonsuza kadar
    // `pending` kalırdı. Kısa bir süre sonra hâlâ AYNI istekteysek (ve
    // hâlâ pending'sek) bunu "geri yüklenecek satın alma yok" olarak kabul
    // edip kullanıcıyı sonsuz beklemede bırakmıyoruz. `requestId` kontrolü,
    // bu arada gerçek bir purchase event'i gelip durumu değiştirmişse
    // (veya kullanıcı restore'a tekrar basmışsa) bu ESKİ zamanlayıcının
    // yanlışlıkla üzerine yazmasını engelliyor.
    Future.delayed(const Duration(seconds: 6), () {
      if (requestId != _restoreRequestId) return;
      if (status != PurchaseFlowStatus.pending) return;

      status = PurchaseFlowStatus.error;
      statusMessage = 'Geri yüklenecek bir satın alma bulunamadı.';
      notifyListeners();
    });
  }

  void resetStatus() {
    status = PurchaseFlowStatus.idle;
    statusMessage = null;
    notifyListeners();
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          status = PurchaseFlowStatus.pending;
          notifyListeners();

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(purchase);

        case PurchaseStatus.canceled:
          status = PurchaseFlowStatus.canceled;
          notifyListeners();
          await _completeIfNeeded(purchase);

        case PurchaseStatus.error:
          status = PurchaseFlowStatus.error;
          statusMessage =
              purchase.error?.message ?? 'Satın alma başarısız oldu.';
          notifyListeners();
          await _completeIfNeeded(purchase);
      }
    }
  }

  // ÇOK ÖNEMLİ: Premium burada AÇILMIYOR. StoreKit "purchased/restored"
  // dediği anda client'a güvenip profiles.plan yazmak yerine, makbuzu
  // verify-purchase endpoint'ine (Vercel Node serverless function —
  // _verifyPurchaseEndpoint) gönderiyoruz — Apple'a karşı GERÇEKTEN
  // doğrulanana ve service role ile profiles satırı güncellenene kadar
  // `status` hep `verifying` kalır. ProfilePage/PremiumPage, gerçek
  // premium durumunu HER ZAMAN Supabase'den (refreshProfile) okur, bu
  // servisin durumundan değil.
  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    status = PurchaseFlowStatus.verifying;
    notifyListeners();

    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;

      if (accessToken == null) {
        throw Exception('Oturum bulunamadı.');
      }

      final response = await http.post(
        Uri.parse(_verifyPurchaseEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'productId': purchase.productID,
          'receiptData': purchase.verificationData.serverVerificationData,
          'source': purchase.verificationData.source,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      final success = data['success'] == true;

      status = success ? PurchaseFlowStatus.success : PurchaseFlowStatus.error;
      statusMessage = success
          ? null
          : data['reason']?.toString() ??
                'Satın alma doğrulanamadı. Lütfen tekrar dene veya '
                    '"Satın Alımları Geri Yükle" seçeneğini kullan.';
    } catch (_) {
      status = PurchaseFlowStatus.error;
      statusMessage =
          'Satın alma sunucuda doğrulanamadı. İnternet bağlantını kontrol '
          'edip tekrar dene.';
    }

    notifyListeners();
    await _completeIfNeeded(purchase);
  }

  // Apple'a işlemin işlendiğini bildiriyoruz — doğrulama başarısız olsa
  // BİLE bu çağrılmalı, aksi halde StoreKit aynı transaction'ı sonsuza
  // kadar tekrar tekrar (her app açılışında) teslim etmeye çalışır ve
  // duplicate purchase event'lerine yol açar. Doğrulama başarısızsa
  // kullanıcı "Satın Alımları Geri Yükle" ile güvenle tekrar deneyebilir.
  Future<void> _completeIfNeeded(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchase);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
