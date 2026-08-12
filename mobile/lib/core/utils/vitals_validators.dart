/// Shared client-side vitals validators — used by the consult flow, the desk
/// intake form and patient self-registration so all three enforce the same
/// rules. Bounds mirror the server's zod schema, so a value that would be
/// rejected with an opaque 400 is caught inline before the round trip.
///
/// Every field is optional: an empty value always passes. A non-empty value
/// must be a number within range, and diastolic must sit below systolic.
class VitalsValidators {
  VitalsValidators._();

  static String? _range(String? v, num min, num max, String unit) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = num.tryParse(s);
    if (n == null) return 'Enter a number';
    if (n < min || n > max) return '$min–$max $unit';
    return null;
  }

  static String? height(String? v) => _range(v, 50, 250, 'cm');
  static String? weight(String? v) => _range(v, 10, 400, 'kg');
  static String? waist(String? v) => _range(v, 30, 250, 'cm');
  static String? systolic(String? v) => _range(v, 50, 300, 'mmHg');
  static String? pulse(String? v) => _range(v, 25, 250, 'bpm');
  static String? spo2(String? v) => _range(v, 50, 100, '%');
  static String? sugar(String? v) => _range(v, 10, 900, 'mg/dL');

  /// Diastolic: in range, and strictly below the systolic value entered
  /// alongside it (a diastolic ≥ systolic is physiologically impossible).
  static String? diastolic(String? v, {String? systolicText}) {
    final base = _range(v, 30, 200, 'mmHg');
    if (base != null) return base;
    final d = num.tryParse((v ?? '').trim());
    final s = num.tryParse((systolicText ?? '').trim());
    if (d != null && s != null && d >= s) return 'Below systolic';
    return null;
  }
}
