import 'package:error_reports_manager/src/search_feedback/search_feedback_backoff.dart';
import 'package:error_reports_manager/src/search_feedback/search_feedback_queue.dart';
import 'package:error_reports_manager/src/search_feedback/search_feedback_sender.dart';
import 'package:test/test.dart';

void main() {
  group('retry delay', () {
    Duration delay(
      SearchFeedbackStrike strike, {
      Duration? retryAfter,
      int step = 1,
      int previous = 0,
    }) =>
        searchFeedbackRetryDelay(
          strike: strike,
          retryAfter: retryAfter,
          backoffStep: step,
          previousFilteredSeconds: previous,
        );

    test('exponential backoff doubles from 30 seconds and caps at 6 hours', () {
      expect(delay(SearchFeedbackStrike.none, step: 1),
          const Duration(seconds: 30));
      expect(delay(SearchFeedbackStrike.serverError, step: 2),
          const Duration(seconds: 60));
      expect(delay(SearchFeedbackStrike.none, step: 5),
          const Duration(seconds: 480));
      expect(delay(SearchFeedbackStrike.none, step: 10),
          const Duration(seconds: 15360));
      expect(
          delay(SearchFeedbackStrike.none, step: 11), const Duration(hours: 6));
      expect(delay(SearchFeedbackStrike.none, step: 1000),
          const Duration(hours: 6));
      expect(delay(SearchFeedbackStrike.none, step: 0),
          const Duration(seconds: 30));
    });

    test('server Retry-After wins over backoff and is capped at 24 hours', () {
      expect(
          delay(SearchFeedbackStrike.serverError,
              retryAfter: const Duration(seconds: 5), step: 12),
          const Duration(seconds: 5));
      expect(
          delay(SearchFeedbackStrike.none,
              retryAfter: const Duration(hours: 10)),
          const Duration(hours: 10));
      expect(
          delay(SearchFeedbackStrike.none, retryAfter: const Duration(days: 3)),
          const Duration(hours: 24));
    });

    test('filtered starts at 6 hours, doubles and caps at 24 hours', () {
      expect(delay(SearchFeedbackStrike.filtered), const Duration(hours: 6));
      expect(delay(SearchFeedbackStrike.filtered, previous: 21600),
          const Duration(hours: 12));
      expect(delay(SearchFeedbackStrike.filtered, previous: 43200),
          const Duration(hours: 24));
      expect(delay(SearchFeedbackStrike.filtered, previous: 86400),
          const Duration(hours: 24));
      expect(delay(SearchFeedbackStrike.filtered, previous: 1 << 62),
          const Duration(hours: 24));
      expect(delay(SearchFeedbackStrike.filtered, previous: 60),
          const Duration(hours: 6));
      expect(delay(SearchFeedbackStrike.filtered, previous: -5),
          const Duration(hours: 6));
    });

    test('filtered honours a short Retry-After without the 6 hour floor', () {
      expect(
          delay(SearchFeedbackStrike.filtered,
              retryAfter: const Duration(minutes: 2), previous: 43200),
          const Duration(minutes: 2));
      expect(
          delay(SearchFeedbackStrike.filtered,
              retryAfter: const Duration(days: 2)),
          const Duration(hours: 24));
    });
  });

  group('filtered delay file', () {
    test('reads a valid stored delay', () {
      expect(
          searchFeedbackFilteredDelaySeconds('{"delaySeconds":43200}'), 43200);
    });

    for (final contents in [
      '',
      '{"delaySec',
      '[]',
      '5',
      'null',
      '{"delaySeconds":"21600"}',
      '{"delaySeconds":1.5}',
      '{"delaySeconds":-10}',
      '{}',
    ]) {
      test('treats ${contents.isEmpty ? 'empty' : contents} as no delay', () {
        expect(searchFeedbackFilteredDelaySeconds(contents), 0);
      });
    }
  });

  group('server error strikes', () {
    final first = DateTime.utc(2026, 10, 1, 12);
    SearchFeedbackStrikeRecord record(int count) => SearchFeedbackStrikeRecord(
          kind: SearchFeedbackStrike.serverError.name,
          count: count,
          firstAt: first,
        );

    test('drop needs both five strikes and 24 hours since the first', () {
      final dayLater = first.add(const Duration(hours: 24));
      expect(searchFeedbackStrikesExhausted(record(5), dayLater), true);
      expect(searchFeedbackStrikesExhausted(record(9), dayLater), true);
      expect(searchFeedbackStrikesExhausted(record(4), dayLater), false);
      expect(
          searchFeedbackStrikesExhausted(
              record(5), dayLater.subtract(const Duration(seconds: 1))),
          false);
      expect(
          searchFeedbackStrikesExhausted(
              record(50), first.add(const Duration(hours: 1))),
          false);
    });
  });
}
