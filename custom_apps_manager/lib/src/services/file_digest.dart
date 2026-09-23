import 'dart:io';

import 'package:crypto/crypto.dart';

/// ה-sha256 של קובץ, ב-hex קטן — אותו פורמט שגיטהאב מפרסם ב-`digest`.
/// קורא בזרם, כי קובץ התקנה יכול להיות מאות MB.
Future<String> sha256OfFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
