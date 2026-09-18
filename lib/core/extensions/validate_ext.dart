import 'package:flutter/services.dart';

/// Units treated as decimal-capable (currency, weight, volume, etc).
/// Any unit NOT in this set is treated as integer-only (e.g. "count", "pcs").
const Set<String> _decimalUnits = {'usd', 'khr', 'kg', 'l', 'ml', 'ton'};

/// Centralized numeric-input rules based on a KPI/measurement unit string.
/// Reuse this anywhere a value + unit pair needs consistent validation:
/// daily entries, targets, product quantities, etc.
extension UnitValidation on String {
  /// True if this unit (e.g. "usd") should allow decimal values.
  bool get isDecimalUnit => _decimalUnits.contains(trim().toLowerCase());

  /// Keyboard type to use for a TextField editing a value with this unit.
  TextInputType get numericKeyboardType => isDecimalUnit
      ? const TextInputType.numberWithOptions(decimal: true)
      : TextInputType.number;

  /// Input formatters to attach to a TextField editing a value with this unit.
  /// Decimal units: digits + up to 2 decimal places (e.g. "10.00").
  /// Non-decimal units: digits only, no decimal point.
  List<TextInputFormatter> get numericInputFormatters => isDecimalUnit
      ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))]
      : [FilteringTextInputFormatter.digitsOnly];

  /// Validates a raw text value against this unit's rules.
  /// Returns null when valid, or a short user-facing error message.
  String? validateNumericValue(String value, {bool required = true}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return required ? 'Required' : null;
    }
    if (isDecimalUnit) {
      final parsed = double.tryParse(trimmed);
      if (parsed == null) return 'Invalid amount';
      if (parsed < 0) return 'Must be 0 or more';
    } else {
      final parsed = int.tryParse(trimmed);
      if (parsed == null) return 'Whole numbers only';
      if (parsed < 0) return 'Must be 0 or more';
    }
    return null;
  }
}
