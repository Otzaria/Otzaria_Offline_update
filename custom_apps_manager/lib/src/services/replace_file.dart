import 'dart:io';

Future<void> Function(String from, String to) replaceFile =
    (from, to) => File(from).rename(to);
