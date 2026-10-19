import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/expense_entry_model.dart';
import 'package:ngo/models/payment_details_model.dart';
import 'package:ngo/models/purchase_model.dart';
import 'package:ngo/models/salary_model.dart';
import 'package:ngo/models/sponsorship_model.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/inventory_expense_service.dart';
import 'package:ngo/services/sponsorship_service.dart';

final _formDate = DateTime.utc(2026, 10, 17, 9, 30);
final _editedDate = DateTime.utc(2026, 10, 19, 12, 15);
final _createdAt = DateTime.utc(2026, 10, 18, 10);
final _updatedAt = DateTime.utc(2026, 10, 18, 11);

PaymentDetailsModel _payment() => PaymentDetailsModel(
  paymentMethod: 'Cheque',
  paymentStatus: 'Partial',
  paymentDate: _formDate,
  paymentReferenceNumber: 'synthetic-payment-ref',
  bankName: 'Synthetic bank',
  transactionId: 'synthetic-utr',
  cashVoucherNumber: '',
  receivedBy: 'Synthetic cashier',
  chequeNumber: '000123',
  chequeDate: _editedDate,
  chequeClearanceStatus: 'Pending',
  proofUrl: 'https://example.invalid/synthetic-proof.pdf',
);

PaymentDetailsModel _clearedPayment() => PaymentDetailsModel(
  paymentMethod: 'UPI',
  paymentStatus: 'Pending',
  paymentReferenceNumber: '',
  transactionId: '',
);

// This mock checks the Flutter HTTP/model contract, not SQL persistence, stock
// transactions, migrations, authentication, or server-side authorization. It
// keeps only explicit relational fields and whitelisted metadata; PostgreSQL
// numerics are returned as strings and persisted dates as ISO/epoch values.
class _ErpContractBackend {
  final _rows = <String, Map<String, dynamic>>{};
  final requests = <String>[];
  int _nextId = 1;

  static const _columns = {
    'vendors': {
      'name': 'name',
      'contactPerson': 'contact_person',
      'mobileNumber': 'phone',
      'email': 'email',
      'address': 'address',
    },
    'purchases': {
      'vendorId': 'vendor_id',
      'vendorName': 'vendor_name',
      'itemId': 'item_id',
      'itemName': 'item_name',
      'quantity': 'quantity',
      'unitPrice': 'unit_price',
      'totalAmount': 'total_amount',
      'purchaseDate': 'purchase_date',
      'invoiceNumber': 'invoice_number',
    },
    'expenses': {
      'category': 'category',
      'totalAmount': 'amount',
      'paymentMethod': 'payment_method',
      'paidTo': 'paid_to',
      'expenseDate': 'expense_date',
      'description': 'description',
    },
    'salaries': {
      'employeeName': 'staff_name',
      'grossSalary': 'base_salary',
      'deductions': 'deductions',
      'netSalary': 'net_salary',
    },
    'sponsorships': {
      'sponsorName': 'sponsor_name',
      'sponsorshipDate': 'sponsorship_date',
      'amount': 'amount',
      'paymentMethod': 'payment_method',
      'notes': 'notes',
    },
  };

  static const _metadata = {
    'vendors': ['gstNumber', 'notes'],
    'purchases': ['paymentDetails'],
    'expenses': [
      'subcategory',
      'itemName',
      'vendorId',
      'vendorName',
      'quantity',
      'unit',
      'unitPrice',
      'paymentDetails',
    ],
    'salaries': ['role', 'salaryMonth', 'paymentDetails'],
    'sponsorships': [
      'sponsorPrefix',
      'sponsorMobile',
      'referencePrefix',
      'referenceName',
      'referenceMobile',
      'occasion',
      'honoreeName',
      'paymentStatus',
      'transactionRef',
      'bookingStatus',
    ],
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    expect(request.headers['authorization'], 'Bearer synthetic-token');
    final segments = request.url.pathSegments;
    expect(segments.take(2), ['api', 'erp']);
    final module = segments[2];
    expect(_columns, contains(module));
    final id = segments.length > 3 ? segments[3] : null;
    final key = '$module/$id';
    if (request.method == 'GET' && id == null) {
      return http.Response(
        jsonEncode([
          for (final entry in _rows.entries)
            if (entry.key.startsWith('$module/')) entry.value,
        ]),
        200,
      );
    }
    if (request.method == 'DELETE' && id != null) {
      expect(_rows.remove(key), isNotNull);
      return http.Response('', 204);
    }
    expect(request.method, isIn(['POST', 'PUT']));
    final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
    final creating = request.method == 'POST';
    if (creating &&
        body.containsKey('id') &&
        (body['id'].toString().isEmpty ||
            body['id'].toString().startsWith('temp_'))) {
      return http.Response('{"error":"Invalid record ID"}', 400);
    }
    final savedId = creating ? 'synthetic-$module-${_nextId++}' : id!;
    final savedKey = '$module/$savedId';
    if (!creating) expect(_rows, contains(savedKey));
    final saved = <String, dynamic>{...?_rows[savedKey], 'id': savedId};
    for (final field in _metadata[module]!) {
      if (body.containsKey(field)) saved[field] = body[field];
    }
    for (final column in _columns[module]!.entries) {
      if (!body.containsKey(column.key)) continue;
      final value = body[column.key];
      saved[column.value] = value is num
          ? column.key.endsWith('Date')
                ? DateTime.fromMillisecondsSinceEpoch(
                    value.toInt(),
                    isUtc: true,
                  ).toIso8601String()
                : value.toString()
          : value;
    }
    saved.addAll({
      'createdBy': module == 'salaries' ? 'synthetic-admin' : 'synthetic-staff',
      'updatedBy': creating
          ? module == 'salaries'
                ? 'synthetic-admin'
                : 'synthetic-staff'
          : 'synthetic-admin-editor',
      'createdAt': _createdAt.millisecondsSinceEpoch,
      'updatedAt': (creating ? _createdAt : _updatedAt).millisecondsSinceEpoch,
    });
    _rows[savedKey] = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(saved)) as Map,
    );
    return http.Response(jsonEncode(_rows[savedKey]), creating ? 201 : 200);
  }
}

BackendApiService _api(_ErpContractBackend backend) {
  final api = BackendApiService(
    baseUrl: 'https://erp.example/api',
    getAuthToken: () async => 'synthetic-token',
    client: MockClient(backend.handle),
  );
  addTearDown(api.dispose);
  return api;
}

InventoryExpenseService _inventory(_ErpContractBackend backend) =>
    InventoryExpenseService(backendApiService: _api(backend));

SponsorshipService _sponsorships(_ErpContractBackend backend) =>
    SponsorshipService(backendApiService: _api(backend));

void _expectRecord(
  Map<String, dynamic> actual,
  Map<String, dynamic> form,
  String id, {
  bool edited = false,
  bool salary = false,
}) {
  final creator = salary ? 'synthetic-admin' : 'synthetic-staff';
  expect(actual, {
    ...form,
    'id': id,
    'createdBy': creator,
    'updatedBy': edited ? 'synthetic-admin-editor' : creator,
    'createdAt': _createdAt.millisecondsSinceEpoch,
    'updatedAt': (edited ? _updatedAt : _createdAt).millisecondsSinceEpoch,
  });
}

void main() {
  test(
    'blank form IDs are omitted from PostgreSQL purchase creation',
    () async {
      Map<String, dynamic>? submitted;
      final api = BackendApiService(
        baseUrl: 'https://erp.example/api',
        client: MockClient((request) async {
          submitted = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          return http.Response(
            jsonEncode({'id': 'saved-purchase'}),
            submitted!.containsKey('id') ? 400 : 201,
          );
        }),
      );
      addTearDown(api.dispose);
      final inventory = InventoryExpenseService(backendApiService: api);
      final date = DateTime.utc(2026, 10, 18);
      final purchase = PurchaseModel(
        id: '',
        purchaseDate: date,
        vendorId: 'synthetic-vendor',
        vendorName: 'Synthetic vendor',
        itemId: 'synthetic-item',
        itemName: 'Synthetic item',
        quantity: 1,
        unitPrice: 0,
        totalAmount: 0,
        invoiceNumber: '',
        paymentDetails: PaymentDetailsModel(
          paymentMethod: 'Cash',
          paymentStatus: 'Pending',
        ),
        createdBy: 'client-submitted-actor',
        updatedBy: 'client-submitted-actor',
        createdAt: date,
        updatedAt: date,
      );

      expect(await inventory.addPurchase(purchase), 'saved-purchase');
      expect(submitted, isNot(contains('id')));
    },
  );

  test('vendor form fields survive create, edit, list and delete', () async {
    final backend = _ErpContractBackend();
    final service = _inventory(backend);
    final id = await service.addVendor(
      name: 'Synthetic supplier',
      contactPerson: 'Synthetic contact',
      mobileNumber: '00910000000001',
      email: 'synthetic@example.invalid',
      gstNumber: 'SYNTHETIC-GST-123',
      address: 'Synthetic warehouse',
      notes: 'Preserve delivery instructions',
      createdBy: 'untrusted-client-actor',
    );
    final created = (await _inventory(backend).getVendorsStream().first).single;
    expect(created.id, id);
    expect(created.name, 'Synthetic supplier');
    expect(created.contactPerson, 'Synthetic contact');
    expect(created.mobileNumber, '00910000000001');
    expect(created.email, 'synthetic@example.invalid');
    expect(created.gstNumber, 'SYNTHETIC-GST-123');
    expect(created.address, 'Synthetic warehouse');
    expect(created.notes, 'Preserve delivery instructions');
    expect(created.createdBy, 'synthetic-staff');
    expect(created.updatedBy, 'synthetic-staff');
    expect(
      created.createdAt.millisecondsSinceEpoch,
      _createdAt.millisecondsSinceEpoch,
    );
    final edited = created.copyWith(
      name: 'Edited supplier',
      contactPerson: '',
      mobileNumber: '',
      email: '',
      gstNumber: '',
      address: '',
      notes: '',
      createdBy: 'untrusted-replacement-creator',
      updatedBy: 'untrusted-editor',
    );
    await service.updateVendor(id, edited.toMap());
    _expectRecord(
      (await _inventory(backend).getVendorsStream().first).single.toMap(),
      edited.toMap(),
      id,
      edited: true,
    );
    await service.deleteVendor(id);
    expect(await _inventory(backend).getVendorsStream().first, isEmpty);
    expect(backend.requests, [
      'POST /api/erp/vendors',
      'GET /api/erp/vendors',
      'PUT /api/erp/vendors/$id',
      'GET /api/erp/vendors',
      'DELETE /api/erp/vendors/$id',
      'GET /api/erp/vendors',
    ]);
  });

  test(
    'purchase form preserves payment metadata and zero total on edit',
    () async {
      final backend = _ErpContractBackend();
      final service = _inventory(backend);
      final form = PurchaseModel(
        id: '',
        purchaseDate: _formDate,
        vendorId: 'synthetic-vendor',
        vendorName: 'Synthetic supplier',
        itemId: 'synthetic-item',
        itemName: 'Synthetic grain',
        quantity: 2.5,
        unitPrice: 123.45,
        totalAmount: 308.625,
        invoiceNumber: 'SYNTHETIC-INVOICE',
        paymentDetails: _payment(),
        createdBy: 'untrusted-client-actor',
        updatedBy: 'untrusted-client-actor',
        createdAt: _formDate,
        updatedAt: _formDate,
      );
      final id = await service.addPurchase(form);
      final created = (await _inventory(
        backend,
      ).getPurchasesStream().first).single;
      _expectRecord(created.toMap(), form.toMap(), id);
      final edited = form.copyWith(
        id: id,
        purchaseDate: _editedDate,
        vendorId: 'synthetic-vendor-2',
        vendorName: 'Edited supplier',
        itemId: 'synthetic-item-2',
        itemName: 'Edited grain',
        quantity: 1,
        unitPrice: 0,
        totalAmount: 0,
        invoiceNumber: '',
        paymentDetails: _clearedPayment(),
      );
      await service.updatePurchase(id, edited, oldQuantity: created.quantity);
      _expectRecord(
        (await _inventory(backend).getPurchasesStream().first).single.toMap(),
        edited.toMap(),
        id,
        edited: true,
      );
      await service.deletePurchase(id, edited.itemId, edited.quantity);
      expect(await _inventory(backend).getPurchasesStream().first, isEmpty);
      expect(backend.requests, [
        'POST /api/erp/purchases',
        'GET /api/erp/purchases',
        'PUT /api/erp/purchases/$id',
        'GET /api/erp/purchases',
        'DELETE /api/erp/purchases/$id',
        'GET /api/erp/purchases',
      ]);
    },
  );

  test(
    'expense form preserves nullable details and clears them on edit',
    () async {
      final backend = _ErpContractBackend();
      final service = _inventory(backend);
      final form = ExpenseEntryModel(
        id: '',
        expenseDate: _formDate,
        category: 'Kitchen',
        subcategory: 'Supplies',
        itemName: 'Synthetic grain',
        vendorId: 'synthetic-vendor',
        vendorName: 'Synthetic supplier',
        description: 'Synthetic general expense',
        quantity: 2.5,
        unit: 'kg',
        unitPrice: 11.2,
        totalAmount: 28,
        paymentDetails: _payment(),
        createdBy: 'untrusted-client-actor',
        updatedBy: 'untrusted-client-actor',
        createdAt: _formDate,
        updatedAt: _formDate,
      );
      final id = await service.addExpenseEntry(form);
      _expectRecord(
        (await _inventory(
          backend,
        ).getExpenseEntriesStream().first).single.toMap(),
        form.toMap(),
        id,
      );
      // Construct explicitly because copyWith(null) preserves existing values.
      final edited = ExpenseEntryModel(
        id: id,
        expenseDate: _editedDate,
        category: 'Other',
        subcategory: null,
        itemName: '',
        vendorId: null,
        vendorName: null,
        description: '',
        quantity: null,
        unit: '',
        unitPrice: null,
        totalAmount: 0,
        paymentDetails: _clearedPayment(),
        createdBy: 'untrusted-replacement-creator',
        updatedBy: 'untrusted-editor',
        createdAt: _formDate,
        updatedAt: _formDate,
      );
      await service.updateExpenseEntry(id, edited);
      _expectRecord(
        (await _inventory(
          backend,
        ).getExpenseEntriesStream().first).single.toMap(),
        edited.toMap(),
        id,
        edited: true,
      );
      await service.deleteExpenseEntry(id);
      expect(
        await _inventory(backend).getExpenseEntriesStream().first,
        isEmpty,
      );
    },
  );

  test(
    'salary form roundtrips employee, month, pay and payment details',
    () async {
      final backend = _ErpContractBackend();
      final service = _inventory(backend);
      final form = SalaryModel(
        id: '',
        employeeName: 'Synthetic employee',
        role: 'Kitchen coordinator',
        salaryMonth: '2026-10',
        grossSalary: 12000.5,
        deductions: 100.25,
        netSalary: 11900.25,
        paymentDetails: _payment(),
        createdBy: 'untrusted-client-actor',
        updatedBy: 'untrusted-client-actor',
        createdAt: _formDate,
        updatedAt: _formDate,
      );
      final id = await service.addSalary(form);
      _expectRecord(
        (await _inventory(backend).getSalariesStream().first).single.toMap(),
        form.toMap(),
        id,
        salary: true,
      );
      final edited = form.copyWith(
        id: id,
        employeeName: 'Edited employee',
        role: '',
        salaryMonth: '2026-11',
        grossSalary: 0,
        deductions: 0,
        netSalary: 0,
        paymentDetails: _clearedPayment(),
      );
      await service.updateSalary(id, edited);
      _expectRecord(
        (await _inventory(backend).getSalariesStream().first).single.toMap(),
        edited.toMap(),
        id,
        edited: true,
        salary: true,
      );
      await service.deleteSalary(id);
      expect(await _inventory(backend).getSalariesStream().first, isEmpty);
      expect(backend.requests, [
        'POST /api/erp/salaries',
        'GET /api/erp/salaries',
        'PUT /api/erp/salaries/$id',
        'GET /api/erp/salaries',
        'DELETE /api/erp/salaries/$id',
        'GET /api/erp/salaries',
      ]);
    },
  );

  test('sponsorship form preserves every booking and payment field', () async {
    final backend = _ErpContractBackend();
    final service = _sponsorships(backend);
    final form = SponsorshipModel(
      id: '',
      sponsorshipDate: _formDate,
      sponsorPrefix: 'Smt',
      sponsorName: 'Synthetic sponsor',
      sponsorMobile: '00910000000002',
      referencePrefix: 'Dr',
      referenceName: 'Synthetic reference',
      referenceMobile: '00910000000003',
      occasion: 'Anniversary',
      honoreeName: 'Synthetic honoree',
      amount: 1234.5,
      paymentMethod: 'Bank Transfer',
      paymentStatus: 'Partial',
      transactionRef: 'SYNTHETIC-UTR-123',
      notes: 'Preserve booking notes',
      bookingStatus: 'Booked',
      createdAt: _formDate,
      updatedAt: _formDate,
      createdBy: 'untrusted-client-actor',
      updatedBy: 'untrusted-client-actor',
    );
    await service.addSponsorship(form);
    final created = (await _sponsorships(
      backend,
    ).getSponsorshipsStream().first).single;
    final id = created.id;
    _expectRecord(created.toMap(), form.toMap(), id);
    final edited = SponsorshipModel(
      id: id,
      sponsorshipDate: _editedDate,
      sponsorPrefix: '',
      sponsorName: 'Edited sponsor',
      sponsorMobile: '',
      referencePrefix: '',
      referenceName: '',
      referenceMobile: '',
      occasion: 'Other',
      honoreeName: null,
      amount: 0,
      paymentMethod: 'Cash',
      paymentStatus: 'Pending',
      transactionRef: '',
      notes: '',
      bookingStatus: 'Cancelled',
      createdAt: _formDate,
      updatedAt: _formDate,
      createdBy: 'untrusted-replacement-creator',
      updatedBy: 'untrusted-editor',
    );
    await service.updateSponsorship(id, edited);
    _expectRecord(
      (await _sponsorships(
        backend,
      ).getSponsorshipsStream().first).single.toMap(),
      edited.toMap(),
      id,
      edited: true,
    );
    await service.deleteSponsorship(id);
    expect(await _sponsorships(backend).getSponsorshipsStream().first, isEmpty);
  });
}
