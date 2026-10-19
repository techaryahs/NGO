import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/payment_details_model.dart';
import 'package:ngo/models/purchase_model.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/inventory_expense_service.dart';

PurchaseModel _purchase({String id = 'temp_purchase', double quantity = 3}) {
  final date = DateTime(2026, 10, 18);
  return PurchaseModel(
    id: id,
    purchaseDate: date,
    vendorId: 'vendor',
    vendorName: 'Synthetic vendor',
    itemId: 'item',
    itemName: 'Synthetic item',
    quantity: quantity,
    unitPrice: 1,
    totalAmount: quantity,
    invoiceNumber: 'synthetic',
    paymentDetails: PaymentDetailsModel(
      paymentMethod: 'Cash',
      paymentStatus: 'Paid',
    ),
    createdBy: 'synthetic',
    updatedBy: 'synthetic',
    createdAt: date,
    updatedAt: date,
  );
}

void main() {
  test(
    'PostgreSQL purchase create, edit and delete issue one server write each',
    () async {
      final requests = <String>[];
      final api = BackendApiService(
        baseUrl: 'https://backend.example/api',
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({'id': 'saved_purchase', ...jsonDecode(request.body)}),
              201,
            );
          }
          return http.Response(
            jsonEncode({'id': 'saved_purchase', 'success': true}),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final service = InventoryExpenseService(backendApiService: api);

      expect(await service.addPurchase(_purchase()), 'saved_purchase');
      await service.updatePurchase(
        'saved_purchase',
        _purchase(id: 'saved_purchase', quantity: 5),
        oldQuantity: 3,
      );
      await service.deletePurchase('saved_purchase', 'item', 5);

      expect(requests, [
        'POST /api/erp/purchases',
        'PUT /api/erp/purchases/saved_purchase',
        'DELETE /api/erp/purchases/saved_purchase',
      ]);
    },
  );

  test(
    'PostgreSQL purchase completion waits for the server acknowledgement',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final api = BackendApiService(
        baseUrl: 'https://backend.example/api',
        client: MockClient((request) {
          started.complete();
          return response.future;
        }),
      );
      addTearDown(api.dispose);
      final service = InventoryExpenseService(backendApiService: api);
      var completed = false;
      final saved = service.addPurchase(_purchase()).then((id) {
        completed = true;
        return id;
      });
      await started.future;
      expect(completed, isFalse);
      response.complete(
        http.Response(jsonEncode({'id': 'acknowledged_purchase'}), 201),
      );
      expect(await saved, 'acknowledged_purchase');
    },
  );

  test(
    'PostgreSQL purchase write failure propagates without a stock adjustment',
    () async {
      final requests = <String>[];
      final api = BackendApiService(
        baseUrl: 'https://backend.example/api',
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response('{}', 500);
        }),
      );
      addTearDown(api.dispose);
      final service = InventoryExpenseService(backendApiService: api);
      await expectLater(
        service.addPurchase(_purchase()),
        throwsA(isA<BackendApiException>()),
      );
      await expectLater(
        service.updatePurchase(
          'saved_purchase',
          _purchase(id: 'saved_purchase'),
        ),
        throwsA(isA<BackendApiException>()),
      );
      await expectLater(
        service.deletePurchase('saved_purchase', 'item', 3),
        throwsA(isA<BackendApiException>()),
      );
      expect(requests, [
        'POST /api/erp/purchases',
        'PUT /api/erp/purchases/saved_purchase',
        'DELETE /api/erp/purchases/saved_purchase',
      ]);
    },
  );
}
