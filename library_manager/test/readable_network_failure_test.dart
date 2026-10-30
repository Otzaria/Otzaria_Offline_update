import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/readable_releases_client.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  test('a filtered manifest is not retried by the schema adapter', () async {
    var requests = 0;
    final httpClient = MockClient((_) async {
      requests++;
      return http.Response('blocked', 418);
    });
    addTearDown(httpClient.close);
    final source = GithubLibraryReleaseClient(httpClient: httpClient);
    final client = ReadableReleasesClient(
      source,
      readableSchema: 6,
      allowPrerelease: false,
    );
    await expectLater(
      client.fetchManifest('https://github.com/m.json'),
      throwsA(isA<LibraryHttpException>()),
    );
    expect(requests, 1);
  });
}
