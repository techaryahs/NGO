class UpiPayment {
  static const vpa = '9821125743m@pnb';
  static const payee = 'PARMARTH SEVA SAMITI';

  static String formatAmount(double amount) {
    if (!amount.isFinite || amount <= 0 || amount > 9000000000000) {
      throw ArgumentError('Enter a valid positive payment amount');
    }
    final paise = (amount * 100).round();
    if (paise == 0) throw ArgumentError('Minimum payment is ₹0.01');
    return '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
  }

  static String uri(double amount, {String note = 'NGO stay payment'}) {
    final parameters = <String, String>{
      'pa': vpa,
      'pn': payee,
      'mc': '8398',
      'tn': note,
      'am': formatAmount(amount),
      'cu': 'INR',
      'mode': '02',
    };
    return 'upi://pay?${parameters.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
  }

  static String? validateReference(String? value) {
    final reference = value?.trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9]{12,35}$').hasMatch(reference)) {
      return 'Enter the 12–35 character UTR / UPI reference (letters and numbers).';
    }
    return null;
  }
}
