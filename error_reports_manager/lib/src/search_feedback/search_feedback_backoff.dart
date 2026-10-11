import 'dart:convert';

import 'search_feedback_queue.dart';
import 'search_feedback_sender.dart';

Duration searchFeedbackRetryDelay({
  required SearchFeedbackStrike strike,
  required Duration? retryAfter,
  required int backoffStep,
  int previousFilteredSeconds = 0,
}) {
  var delay = retryAfter;
  if (strike == SearchFeedbackStrike.filtered) {
    delay ??= Duration(
      seconds: previousFilteredSeconds <= 0
          ? 21600
          : previousFilteredSeconds.clamp(0, 43200) * 2,
    );
    if (delay > const Duration(hours: 24)) {
      delay = const Duration(hours: 24);
    }
    if (retryAfter == null && delay < const Duration(hours: 6)) {
      delay = const Duration(hours: 6);
    }
  } else if (delay == null) {
    final factor = 1 << (backoffStep.clamp(1, 21) - 1);
    delay = Duration(seconds: 30 * factor);
    if (delay > const Duration(hours: 6)) {
      delay = const Duration(hours: 6);
    }
  }
  if (delay > const Duration(hours: 24)) {
    delay = const Duration(hours: 24);
  }
  return delay;
}

int searchFeedbackFilteredDelaySeconds(String contents) {
  try {
    final block = jsonDecode(contents);
    if (block is Map) {
      final seconds = block['delaySeconds'];
      if (seconds is int && seconds > 0) return seconds;
    }
  } on FormatException {
    return 0;
  }
  return 0;
}

bool searchFeedbackStrikesExhausted(
  SearchFeedbackStrikeRecord record,
  DateTime now,
) =>
    record.count >= 5 &&
    now.difference(record.firstAt) >= const Duration(hours: 24);
