/// שאלה שהמשתמש הוסיף בעצמו.
class FaqUserEntry {
  const FaqUserEntry({required this.question, required this.answer});

  final String question;
  final String answer;

  Map<String, dynamic> toJson() => {'question': question, 'answer': answer};

  /// רשומה בלי שאלה או בלי תשובה מדולגת בקריאה — `null` ולא חריגה, כדי
  /// שקובץ שנערך ביד לא ימחק את שאר הרשימה.
  static FaqUserEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final question = raw['question'];
    final answer = raw['answer'];
    if (question is! String || answer is! String) return null;
    if (question.trim().isEmpty || answer.trim().isEmpty) return null;
    return FaqUserEntry(question: question, answer: answer);
  }
}

/// ההתאמות שהמשתמש עשה להדרכה: שאלות שהוסתרו, שאלות שהוסיף, והפרטים שלו
/// שנוספים בתחתית הרשימה.
///
/// קובץ נפרד מ-`launcher_settings.json` בכוונה: זה **תוכן** ולא העדפה, והוא
/// גדל. מי שמכין כוננים לקהילה שלו מגדיר אותו פעם אחת, והוא נוסע עם הכונן
/// יחד עם כל השאר.
class FaqCustomization {
  static const int schemaVersion = 1;

  const FaqCustomization({
    this.hiddenIds = const {},
    this.extras = const [],
    this.contactName = '',
    this.contactPhone = '',
  });

  /// מזהי השאלות המובנות שהוסתרו — [FaqEntry.id], כלומר שם השדה בחוזה המלל.
  /// מזהה ולא נוסח: הסתרה חייבת לשרוד גם החלפת שפה וגם ניסוח מחדש.
  final Set<String> hiddenIds;
  final List<FaqUserEntry> extras;
  final String contactName;
  final String contactPhone;

  bool get hasContact =>
      contactName.trim().isNotEmpty || contactPhone.trim().isNotEmpty;

  FaqCustomization copyWith({
    Set<String>? hiddenIds,
    List<FaqUserEntry>? extras,
    String? contactName,
    String? contactPhone,
  }) =>
      FaqCustomization(
        hiddenIds: hiddenIds ?? this.hiddenIds,
        extras: extras ?? this.extras,
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
      );

  FaqCustomization toggleHidden(String id) => copyWith(
        hiddenIds: {
          for (final existing in hiddenIds)
            if (existing != id) existing,
          if (!hiddenIds.contains(id)) id,
        },
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'hidden': hiddenIds.toList()..sort(),
        'extras': [for (final entry in extras) entry.toJson()],
        'contact': {'name': contactName, 'phone': contactPhone},
      };

  factory FaqCustomization.fromJson(Map<String, dynamic> json) {
    final hidden = json['hidden'];
    final extras = json['extras'];
    final contact = json['contact'];

    String text(String key) {
      final value = contact is Map ? contact[key] : null;
      return value is String ? value : '';
    }

    return FaqCustomization(
      hiddenIds: {
        if (hidden is List)
          for (final id in hidden)
            if (id is String) id,
      },
      extras: [
        if (extras is List)
          for (final raw in extras)
            if (FaqUserEntry.fromJson(raw) case final entry?) entry,
      ],
      contactName: text('name'),
      contactPhone: text('phone'),
    );
  }
}
