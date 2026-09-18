import 'package:intl/intl.dart';

// capitalize String
extension StringCapialize on String {
  String get capitalizeWords => split(' ')
      .map(
        (word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
  //
  String get removeHtml {
    if (isEmpty) return '';
    final exp = RegExp(r'<[^>]+>', multiLine: true, caseSensitive: false);
    return replaceAll(exp, '').trim();
  }
}

extension DateFormatExt on String? {
  String dateFormatString({String format = 'dd-MM-yyyy hh:mm a'}) {
    if (this == null || this!.trim().isEmpty) return '';

    final trimmed = this!.trim();
    try {
      final dateTime = DateTime.tryParse(trimmed);
      if (dateTime != null) {
        return DateFormat(format).format(dateTime);
      }
    } catch (_) {}
    try {
      final parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parse(trimmed);
      return DateFormat(format).format(parsed);
    } catch (_) {}
    try {
      final parsed = DateFormat('yyyy-MM-dd HH:mm').parse(trimmed);
      return DateFormat(format).format(parsed);
    } catch (_) {}
    return trimmed;
  }
}
