import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

Uint8List encodeBatches(List<EegBatch> batches) => Uint8List.fromList(
  utf8.encode(jsonEncode([for (final batch in batches) batch.toJson()])),
);

List<EegBatch> decodeBatches(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
  return [
    for (final batch in decoded)
      EegBatch.fromJson(batch as Map<String, dynamic>),
  ];
}
