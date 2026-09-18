import 'dart:convert';
import 'dart:developer';

extension JsonLogger on Object {
  void logJson(Map<String, dynamic> data, {String? title}) {
    const encoder = JsonEncoder.withIndent('  ');
    final name = title ?? runtimeType.toString();

    log(
      '========== $name ==========\n'
      '${encoder.convert(data)}\n'
      '===========================',
    );
  }
}


// ====== USED =======
// sale.logJson(sale.toJson(), title: 'Sale Request');