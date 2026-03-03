import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> saveReport(List<int> bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  // Optionally could open the file or show path to user
}
