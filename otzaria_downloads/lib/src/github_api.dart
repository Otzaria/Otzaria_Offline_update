import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';

const String githubUserAgent = 'otzaria-launcher';

const Map<String, String> githubApiHeaders = {
  'Accept': 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': githubUserAgent,
};

const Map<String, String> githubUserAgentHeaders = {
  'User-Agent': githubUserAgent,
};

const String githubApiHost = 'api.github.com';

const Duration githubRateLimitMaxWait = Duration(hours: 1);

String? githubAssetSha256(Object? digest) =>
    digest is String && digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length).toLowerCase()
        : null;

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.state,
    this.sha256,
  });

  final String name;
  final String downloadUrl;
  final int size;
  final String? state;
  final String? sha256;

  bool get isReady => (state == null || state == 'uploaded') && size > 0;

  static GithubReleaseAsset? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = json['browser_download_url'];
    final size = json['size'];
    if (name is! String || url is! String || size is! int) return null;
    final state = json['state'];
    return GithubReleaseAsset(
      name: name,
      downloadUrl: url,
      size: size,
      state: state is String ? state : null,
      sha256: githubAssetSha256(json['digest']),
    );
  }
}

class GithubRateLimitException implements Exception {
  const GithubRateLimitException({
    required this.uri,
    this.statusCode,
    this.retryAfter,
    this.resetAt,
  });

  final Uri uri;
  final int? statusCode;
  final Duration? retryAfter;
  final DateTime? resetAt;

  int? get retryAfterMinutes {
    final wait = retryAfter;
    if (wait == null) return null;
    final minutes = (wait.inSeconds + 59) ~/ 60;
    return minutes < 1 ? 1 : minutes;
  }

  String get message =>
      AppL10n.strings.appDomain.githubRateLimited(retryAfterMinutes);

  @override
  String toString() => message;
}

({Duration? wait})? githubRateLimitOf(
  http.BaseResponse response, {
  DateTime Function() clock = DateTime.now,
}) {
  final status = response.statusCode;
  if (status != 403 && status != 429) return null;
  final headers = response.headers;
  final retryAfter = int.tryParse(headers['retry-after']?.trim() ?? '');
  if (retryAfter != null && retryAfter >= 0) {
    return (wait: _capped(Duration(seconds: retryAfter)));
  }
  if (headers['x-ratelimit-remaining']?.trim() != '0') return null;
  final reset = int.tryParse(headers['x-ratelimit-reset']?.trim() ?? '');
  if (reset == null) return (wait: null);
  final now = _serverTime(headers['date']) ?? clock();
  final resetAt =
      DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true);
  return (wait: _capped(resetAt.difference(now)));
}

Duration _capped(Duration wait) => wait.isNegative
    ? Duration.zero
    : wait > githubRateLimitMaxWait
        ? githubRateLimitMaxWait
        : wait;

DateTime? _serverTime(String? date) {
  if (date == null || date.trim().isEmpty) return null;
  try {
    return HttpDate.parse(date.trim());
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}

class GithubRateLimitGate {
  GithubRateLimitGate({
    Duration Function()? elapsed,
    DateTime Function()? clock,
  })  : _elapsed = elapsed ?? _monotonic,
        _clock = clock ?? DateTime.now;

  static final GithubRateLimitGate shared = GithubRateLimitGate();

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _monotonic() => _stopwatch.elapsed;

  final Duration Function() _elapsed;
  final DateTime Function() _clock;
  Duration? _openAt;

  Duration? get remaining {
    final openAt = _openAt;
    if (openAt == null) return null;
    final left = openAt - _elapsed();
    if (left <= Duration.zero) {
      _openAt = null;
      return null;
    }
    return left;
  }

  void close(Duration wait) {
    if (wait <= Duration.zero) return;
    final openAt = _elapsed() + _capped(wait);
    final current = _openAt;
    if (current == null || openAt > current) _openAt = openAt;
  }

  void reset() => _openAt = null;

  GithubRateLimitException? blocked(Uri uri) {
    final left = remaining;
    if (left == null) return null;
    return GithubRateLimitException(
      uri: uri,
      retryAfter: left,
      resetAt: _clock().add(left),
    );
  }

  GithubRateLimitException limited(
    Uri uri,
    int statusCode,
    Duration? wait,
  ) {
    if (wait != null) close(wait);
    return GithubRateLimitException(
      uri: uri,
      statusCode: statusCode,
      retryAfter: wait,
      resetAt: wait == null ? null : _clock().add(wait),
    );
  }
}

Future<http.Response> githubGet(
  http.Client client,
  Uri uri, {
  required Duration timeout,
  Map<String, String> headers = githubApiHeaders,
  GithubRateLimitGate? gate,
}) async {
  final limiter = gate ?? GithubRateLimitGate.shared;
  final api = uri.host == githubApiHost;
  if (api) {
    final blocked = limiter.blocked(uri);
    if (blocked != null) throw blocked;
  }
  final response = await client.get(uri, headers: headers).timeout(timeout);
  if (api) {
    final limit = githubRateLimitOf(response);
    if (limit != null) {
      throw limiter.limited(uri, response.statusCode, limit.wait);
    }
  }
  return response;
}

Future<Object?> githubGetJson(
  http.Client client,
  Uri uri, {
  required Duration timeout,
  required Object Function(int statusCode) statusError,
  GithubRateLimitGate? gate,
}) async {
  final response = await githubGet(client, uri, timeout: timeout, gate: gate);
  if (response.statusCode != 200) throw statusError(response.statusCode);
  return decodeGithubJson(response);
}

Object? decodeGithubJson(http.Response response) =>
    jsonDecode(utf8.decode(response.bodyBytes));
