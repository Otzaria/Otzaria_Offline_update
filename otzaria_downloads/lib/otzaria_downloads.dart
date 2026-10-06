import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class FileDownloadResult {
  const FileDownloadResult(this.size, this.headers, this.sha256);
  final int size;
  final Map<String, String> headers;
  final String? sha256;
}

/// החלקי נשמר בנפרד מהיעד, ורק ETag חזק מאפשר לחבר אליו בייטים חדשים.
Future<FileDownloadResult> downloadFile({
  required http.Client client,
  required String url,
  required String destinationPath,
  required Object Function(int status) statusError,
  required Object Function(int actual, int expected) sizeError,
  int? expectedSize,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration stallTimeout = const Duration(seconds: 30),
  void Function(int received, int total)? onProgress,
  void Function()? checkCancelled,
  int maxAttempts = 2,
  bool calculateSha256 = false,
}) async {
  for (var attempt = 0;; attempt++) {
    try {
      return await _downloadFile(
        client: client,
        url: url,
        destinationPath: destinationPath,
        statusError: statusError,
        sizeError: sizeError,
        expectedSize: expectedSize,
        connectTimeout: connectTimeout,
        stallTimeout: stallTimeout,
        onProgress: onProgress,
        checkCancelled: checkCancelled,
        calculateSha256: calculateSha256,
      );
    } catch (error) {
      checkCancelled?.call();
      if (attempt + 1 >= maxAttempts ||
          (error is! TimeoutException &&
              error is! SocketException &&
              error is! http.ClientException) ||
          !await File('$destinationPath.resume').exists()) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

Future<FileDownloadResult> _downloadFile({
  required http.Client client,
  required String url,
  required String destinationPath,
  required Object Function(int status) statusError,
  required Object Function(int actual, int expected) sizeError,
  int? expectedSize,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration stallTimeout = const Duration(seconds: 30),
  void Function(int received, int total)? onProgress,
  void Function()? checkCancelled,
  required bool calculateSha256,
}) async {
  checkCancelled?.call();
  final file = File(destinationPath);
  final part = File('$destinationPath.part');
  final metadata = File('$destinationPath.resume');
  await file.parent.create(recursive: true);
  final knownSize =
      expectedSize != null && expectedSize > 0 ? expectedSize : null;
  Map<String, dynamic>? saved;
  try {
    saved = jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
  } on FileSystemException {
    saved = null;
  } on FormatException {
    saved = null;
  } on TypeError {
    saved = null;
  }
  var offset = await part.exists() ? await part.length() : 0;
  var validator = _strongEtag(saved?['etag']);
  var total = saved?['total'] is int ? saved!['total'] as int : null;
  if (saved?['url'] != url ||
      saved?['expectedSize'] != knownSize ||
      validator == null ||
      total == null ||
      total <= 0 ||
      offset >= total ||
      (knownSize != null && total != knownSize) ||
      saved?['headers'] is! Map ||
      (saved!['headers'] as Map)
          .entries
          .any((entry) => entry.key is! String || entry.value is! String)) {
    offset = 0;
    validator = null;
    total = null;
  }
  if (offset == 0) {
    await _delete(part);
    await _delete(metadata);
  }
  final initialOffset = offset;

  // ניסיון רגיל ועוד התחלה מאפס אחת בלבד אם השרת דחה את הטווח.
  for (var attempt = 0; attempt < 2; attempt++) {
    checkCancelled?.call();
    final abort = Completer<void>();
    final request = http.AbortableRequest('GET', Uri.parse(url),
        abortTrigger: abort.future);
    request.headers['Accept-Encoding'] = 'identity';
    if (offset > 0) {
      request.headers['Range'] = 'bytes=$offset-';
      request.headers['If-Range'] = validator!;
    }
    IOSink? sink;
    ByteConversionSink? hasher;
    Digest? digest;
    var retain = offset > 0;
    try {
      final pending = client.send(request);
      unawaited(pending.then((response) async {
        if (abort.isCompleted) {
          try {
            await response.stream.listen((_) {}).cancel();
          } catch (_) {}
        }
      }, onError: (Object _) {}));
      final response = await pending.timeout(connectTimeout);
      if (offset > 0 && response.statusCode == 416) {
        await response.stream.listen((_) {}).cancel();
        await _delete(part);
        await _delete(metadata);
        offset = 0;
        validator = null;
        total = null;
        continue;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.listen((_) {}).cancel();
        throw statusError(response.statusCode);
      }
      Map<String, String> headers;
      final encoded =
          (response.headers['content-encoding'] ?? 'identity') != 'identity';
      if (response.statusCode == 206) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers['content-range'] ?? '');
        final start = range == null ? null : int.parse(range[1]!);
        final end = range == null ? null : int.parse(range[2]!);
        final length = range == null ? null : int.parse(range[3]!);
        if (encoded ||
            offset == 0 ||
            start != offset ||
            end == null ||
            length == null ||
            end != length - 1 ||
            length != total ||
            (knownSize != null && length != knownSize) ||
            (response.contentLength != null &&
                response.contentLength != end - offset + 1) ||
            (response.headers['etag'] != null &&
                response.headers['etag'] != validator)) {
          await response.stream.listen((_) {}).cancel();
          retain = false;
          throw statusError(206);
        }
        headers = Map<String, String>.from(saved!['headers'] as Map);
      } else {
        // If-Range לא התאים או שהשרת התעלם מ-Range: הגוף המלא מחליף את החלקי.
        offset = 0;
        retain = false;
        validator = _strongEtag(response.headers['etag']);
        total = knownSize ?? (encoded ? null : response.contentLength);
        headers = response.headers;
        // מחיקה לפני החלפת הזהות: גם סגירת התהליך כאן לא תקשור חלקי ישן ל-ETag חדש.
        await part.writeAsBytes(const [], flush: true);
      }
      retain = !encoded && validator != null && total != null;
      if (retain) {
        await metadata.writeAsString(
            jsonEncode({
              'url': url,
              'expectedSize': knownSize,
              'etag': validator,
              'total': total,
              'headers': headers,
            }),
            flush: true);
      } else {
        await _delete(metadata);
      }
      if (calculateSha256) {
        hasher = sha256.startChunkedConversion(
          ChunkedConversionSink<Digest>.withCallback(
              (value) => digest = value.single),
        );
        if (offset > 0) {
          await for (final chunk in part.openRead(0, offset)) {
            checkCancelled?.call();
            hasher.add(chunk);
          }
        }
      }
      sink =
          part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
      var received = offset;
      var buffered = 0;
      onProgress?.call(received, total ?? 0);
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        checkCancelled?.call();
        received += chunk.length;
        if (total != null && received > total) {
          retain = false;
          throw sizeError(received, total);
        }
        sink.add(chunk);
        hasher?.add(chunk);
        buffered += chunk.length;
        onProgress?.call(received, total ?? 0);
        if (buffered >= 4 << 20) {
          await sink.flush();
          buffered = 0;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      checkCancelled?.call();
      hasher?.close();
      hasher = null;
      if (total != null && received != total) {
        retain = false;
        throw sizeError(received, total);
      }
      await part.rename(destinationPath);
      await _delete(metadata);
      return FileDownloadResult(received, headers, digest?.toString());
    } catch (_) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      // ביטול יזום נשאר ביטול; רק הפרעת רשת משאירה התקדמות ניתנת לחידוש.
      try {
        checkCancelled?.call();
      } catch (_) {
        retain = false;
        if (initialOffset > 0 && offset > 0 && await part.exists()) {
          final handle = await part.open(mode: FileMode.append);
          try {
            await handle.truncate(initialOffset);
          } finally {
            await handle.close();
          }
          await metadata.writeAsString(jsonEncode(saved), flush: true);
          retain = true;
        }
      }
      if (!retain) {
        await _delete(part);
        await _delete(metadata);
      }
      rethrow;
    } finally {
      hasher?.close();
      if (!abort.isCompleted) abort.complete();
    }
  }
  throw statusError(416);
}

String? _strongEtag(Object? value) =>
    value is String && RegExp(r'^"[\x21\x23-\x7e\x80-\xff]*"$').hasMatch(value)
        ? value
        : null;

Future<void> _delete(File file) async {
  if (await file.exists()) await file.delete();
}

/// הניקוי שומר רק חלקיים בעלי זהות וגודל תקינים שעדיין שייכים למקור מבוקש.
Future<Set<String>> pendingDownloadFiles(
    Directory dir, Set<String> urls) async {
  final files = <String>{};
  if (!await dir.exists()) return files;
  await for (final entry in dir.list(followLinks: false)) {
    if (entry is! File || !entry.path.endsWith('.resume')) continue;
    try {
      final saved = jsonDecode(await entry.readAsString());
      if (saved is! Map ||
          !urls.contains(saved['url']) ||
          _strongEtag(saved['etag']) == null ||
          saved['total'] is! int) {
        continue;
      }
      final part =
          File('${entry.path.substring(0, entry.path.length - 7)}.part');
      final length = await part.length();
      if (length > 0 && length < (saved['total'] as int)) {
        files.addAll([entry.path, part.path]);
      }
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    }
  }
  return files;
}
