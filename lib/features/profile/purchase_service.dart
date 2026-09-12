import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class PurchaseService {
  PurchaseService._();

  static final PurchaseService instance =
      PurchaseService._();

  final InAppPurchase _inAppPurchase =
      InAppPurchase.instance;

  // App Store Connect'te daha sonra oluşturacağımız
  // aylık abonelik Product ID.
  static const String premiumMonthlyId =
      'life_admin_premium_monthly';

  StreamSubscription<List<PurchaseDetails>>?
      _purchaseSubscription;

  ProductDetails? premiumProduct;

  bool storeAvailable = false;
  bool loading = false;

  Future<void> initialize({
    required Future<void> Function(
      PurchaseDetails purchase,
    )
    onPurchaseVerified,
  }) async {
    storeAvailable =
        await _inAppPurchase.isAvailable();

    if (!storeAvailable) {
      return;
    }

    _purchaseSubscription ??=
        _inAppPurchase.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          switch (purchase.status) {
            case PurchaseStatus.pending:
              break;

            case PurchaseStatus.purchased:
            case PurchaseStatus.restored:
              // ÖNEMLİ:
              // Şimdilik satın alma geldiğinde buraya düşüyor.
              // Sonraki aşamada Apple makbuzunu
              // Supabase Edge Function ile doğrulayacağız.
              await onPurchaseVerified(
                purchase,
              );

              if (purchase.pendingCompletePurchase) {
                await _inAppPurchase
                    .completePurchase(
                  purchase,
                );
              }

              break;

            case PurchaseStatus.error:
              break;

            case PurchaseStatus.canceled:
              break;
          }
        }
      },
      onError: (_) {},
    );

    await loadProducts();
  }

  Future<void> loadProducts() async {
    if (!storeAvailable) {
      return;
    }

    loading = true;

    final response =
        await _inAppPurchase.queryProductDetails(
      {
        premiumMonthlyId,
      },
    );

    if (response.productDetails.isNotEmpty) {
      premiumProduct =
          response.productDetails.first;
    }

    loading = false;
  }

  Future<bool> buyPremium() async {
    final product = premiumProduct;

    if (!storeAvailable || product == null) {
      return false;
    }

    final purchaseParam = PurchaseParam(
      productDetails: product,
    );

    return _inAppPurchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
  }

  Future<void> restorePurchases() async {
    if (!storeAvailable) {
      return;
    }

    await _inAppPurchase.restorePurchases();
  }

  String get price {
    return premiumProduct?.price ?? '₺249';
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
  }
}