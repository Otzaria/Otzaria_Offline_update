/// מפרט טבלה אחת במנגנון ה-patch: שמה, עמודות המפתח הראשי, והאם היא ניתנת
/// לעדכון (יש לה עמודות שאינן PK) או שהיא טבלת junction טהורה.
///
/// משוכפל מ-`PatchTables.kt` (PATCH_TABLES_IN_FK_ORDER) ב-SeforimLibrary.
class PatchTableSpec {
  final String name;
  final List<String> primaryKey;

  /// `true` כאשר לטבלה יש עמודות שאינן PK (upsert עם `DO UPDATE`).
  /// `false` לטבלת junction טהורה שכל עמודותיה הן PK (upsert עם `DO NOTHING`).
  final bool updatable;

  const PatchTableSpec(this.name, this.primaryKey, {required this.updatable});
}

/// סדר הטבלאות להחלת patch — לפי תלויות מפתח זר (FK).
/// upserts מורצים בסדר זה; deletes בסדר ההפוך.
///
/// משוכפל אות-באות מ-`PATCH_TABLES_IN_FK_ORDER` ב-SeforimLibrary.
/// שים לב: הסדר כאן שונה מסדר ה-hash ב-[kHashTableOrder].
const List<PatchTableSpec> kPatchTablesInFkOrder = [
  PatchTableSpec('source', ['id'], updatable: true),
  PatchTableSpec('author', ['id'], updatable: true),
  PatchTableSpec('topic', ['id'], updatable: true),
  PatchTableSpec('pub_place', ['id'], updatable: true),
  PatchTableSpec('pub_date', ['id'], updatable: true),
  PatchTableSpec('connection_type', ['id'], updatable: true),
  PatchTableSpec('tocText', ['id'], updatable: true),
  PatchTableSpec('generation', ['id'], updatable: true),
  PatchTableSpec('category', ['id'], updatable: true),
  PatchTableSpec('category_closure', ['ancestorId', 'descendantId'],
      updatable: false),
  PatchTableSpec('book', ['id'], updatable: true),
  PatchTableSpec('book_author', ['bookId', 'authorId'], updatable: false),
  PatchTableSpec('book_base_text', ['bookId', 'baseBookId'], updatable: false),
  PatchTableSpec('book_topic', ['bookId', 'topicId'], updatable: false),
  PatchTableSpec('book_pub_place', ['bookId', 'pubPlaceId'], updatable: false),
  PatchTableSpec('book_pub_date', ['bookId', 'pubDateId'], updatable: false),
  PatchTableSpec('book_acronym', ['bookId', 'term'], updatable: false),
  PatchTableSpec('book_generation', ['bookId', 'generationId'],
      updatable: false),
  PatchTableSpec('tocEntry', ['id'], updatable: true),
  PatchTableSpec('line', ['id'], updatable: true),
  PatchTableSpec('line_toc', ['lineId'], updatable: true),
  // סכמה 4. אינדקס ההפניות הקנוני — טבלת מפתח טהורה, אין מה לעדכן בהתנגשות.
  PatchTableSpec('line_ref', ['bookId', 'refKeyHash', 'lineIndex'],
      updatable: false),
  // סכמה 4; בסכמה 5 נוספה לה `dhDisplay` (הצורה המודפסת), ולכן היא ניתנת
  // לעדכון גם כשה-PK הקיים לא השתנה.
  PatchTableSpec('line_dh', ['bookId', 'dhText', 'lineIndex'], updatable: true),
  PatchTableSpec('link', ['id'], updatable: true),
  PatchTableSpec('link_anchor', ['linkId', 'side', 'charStart'],
      updatable: true),
  PatchTableSpec('link_range', ['linkId', 'side'], updatable: true),
  PatchTableSpec('link_coverage', ['lineId', 'linkId', 'side'],
      updatable: false),
  // סכמה 3.
  PatchTableSpec('link_suppressed_side', ['linkId', 'side'], updatable: true),
  PatchTableSpec('book_has_links', ['bookId'], updatable: true),
  PatchTableSpec('book_version', ['id'], updatable: true),
  PatchTableSpec('version_line', ['versionId', 'lineId'], updatable: true),
  PatchTableSpec('alt_toc_structure', ['id'], updatable: true),
  PatchTableSpec('alt_toc_entry', ['id'], updatable: true),
  PatchTableSpec('line_alt_toc', ['lineId', 'structureId'], updatable: true),
  PatchTableSpec('default_commentator', ['bookId', 'commentatorBookId'],
      updatable: true),
  PatchTableSpec('default_targum', ['bookId', 'targumBookId'], updatable: true),
  PatchTableSpec('schema_meta', ['key'], updatable: true),
];

/// סדר ה-hash של סכמה 4 (37 טבלאות). `line_ref` ואחריה `line_dh` יושבות מיד
/// אחרי `line_toc`, ו-`link_suppressed_side` מיד אחרי `link_coverage` — אותם
/// מיקומים בדיוק כמו בצד הקוטליני.
///
/// משוכפל אות-באות מ-`DEFAULT_TABLES` ב-`LogicalContentHasher.kt`.
/// הסדר כאן שונה מ-[kPatchTablesInFkOrder] — אסור להחליף ביניהם.
const List<String> kHashTableOrderSchema4 = [
  'source',
  'author',
  'topic',
  'pub_place',
  'pub_date',
  'connection_type',
  'generation',
  'category',
  'category_closure',
  'tocText',
  'book',
  'book_topic',
  'book_author',
  'book_base_text',
  'book_pub_place',
  'book_pub_date',
  'book_generation',
  'tocEntry',
  'line',
  'line_toc',
  'line_ref',
  'line_dh',
  'link',
  'link_anchor',
  'link_range',
  'link_coverage',
  'link_suppressed_side',
  'book_has_links',
  'book_version',
  'version_line',
  'book_acronym',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'default_commentator',
  'default_targum',
  'schema_meta',
];

/// סדר ה-hash הנוכחי. סכמה 5 שינתה עמודה ב-`line_dh` ולא את סדר הטבלאות,
/// ולכן היא חולקת את רשימת סכמה 4.
const List<String> kHashTableOrder = kHashTableOrderSchema4;

/// סדר ה-hash הקפוא של סכמה-3 (35 טבלאות, בלי טבלאות סכמה-4 `line_ref`
/// ו-`line_dh`) — משחזר בדיוק את ה-hash של ארטיפקטי סכמה-3. אין לערוך.
const List<String> kHashTableOrderSchema3 = [
  'source',
  'author',
  'topic',
  'pub_place',
  'pub_date',
  'connection_type',
  'generation',
  'category',
  'category_closure',
  'tocText',
  'book',
  'book_topic',
  'book_author',
  'book_base_text',
  'book_pub_place',
  'book_pub_date',
  'book_generation',
  'tocEntry',
  'line',
  'line_toc',
  'link',
  'link_anchor',
  'link_range',
  'link_coverage',
  'link_suppressed_side',
  'book_has_links',
  'book_version',
  'version_line',
  'book_acronym',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'default_commentator',
  'default_targum',
  'schema_meta',
];

/// סדר ה-hash הקפוא של סכמה-2 (34 טבלאות, בלי `link_suppressed_side` של
/// סכמה-3) — משחזר בדיוק את ה-hash של ארטיפקטי סכמה-2. אין לערוך.
const List<String> kHashTableOrderSchema2 = [
  'source',
  'author',
  'topic',
  'pub_place',
  'pub_date',
  'connection_type',
  'generation',
  'category',
  'category_closure',
  'tocText',
  'book',
  'book_topic',
  'book_author',
  'book_base_text',
  'book_pub_place',
  'book_pub_date',
  'book_generation',
  'tocEntry',
  'line',
  'line_toc',
  'link',
  'link_anchor',
  'link_range',
  'link_coverage',
  'book_has_links',
  'book_version',
  'version_line',
  'book_acronym',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'default_commentator',
  'default_targum',
  'schema_meta',
];

/// סדר ה-hash הקפוא של סכמה-1 (33 טבלאות, ללא `book_base_text`) — משחזר בדיוק
/// את ה-hash של ארטיפקטי סכמה-1 ההיסטוריים. לעולם אין לערוך.
const List<String> kHashTableOrderSchema1 = [
  'source',
  'author',
  'topic',
  'pub_place',
  'pub_date',
  'connection_type',
  'generation',
  'category',
  'category_closure',
  'tocText',
  'book',
  'book_topic',
  'book_author',
  'book_pub_place',
  'book_pub_date',
  'book_generation',
  'tocEntry',
  'line',
  'line_toc',
  'link',
  'link_anchor',
  'link_range',
  'link_coverage',
  'book_has_links',
  'book_version',
  'version_line',
  'book_acronym',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'default_commentator',
  'default_targum',
  'schema_meta',
];

/// סדרי ה-hash לפי גרסת סכמת ה-DB — **נקודת האמת היחידה** לשאלה "איזו סכמה
/// אנחנו יודעים להחיל patch עליה". התכנון וייצוא המראה נגזרים ממנה דרך
/// [isSupportedSchemaVersion], כדי שהוספת סכמה תיגע במקום אחד בלבד.
const Map<int, List<String>> kHashTableOrderBySchemaVersion = {
  1: kHashTableOrderSchema1,
  2: kHashTableOrderSchema2,
  3: kHashTableOrderSchema3,
  4: kHashTableOrderSchema4,
  // סכמה 5 שינתה עמודה בתוך `line_dh`, לא את סדר הטבלאות.
  5: kHashTableOrderSchema4,
};

/// סכמת ה-DB הגבוהה ב-[kHashTableOrderBySchemaVersion]. const (ולכן כתוב
/// ידנית) כי הוא ברירת מחדל בבנאי `const`; `patch_table_spec_test` מוודא
/// שהוא נשאר תואם למפה.
const int kSupportedDbSchemaVersion = 5;

/// גרסת פורמט `patch.db` (`patch_meta.schema_version`) הגבוהה ביותר
/// שה-applier יודע להחיל. **ציר נפרד מסכמת ה-DB**: סכמה 5 פורסמה בפורמט 4,
/// ומפיק חדש יכול לכתוב פורמט 4 גם למעבר DB לוגי 2→3. קבוע אחד לשני הצירים
/// שולח לקוח להחיל פורמט שאינו מכיר.
const int kSupportedPatchFormatVersion = 4;

/// האם קיים סדר hash לסכמה הזו — כלומר האם אפשר להחיל patch שנוגע בה.
/// סכמה חדשה יותר אינה תקלה: המסלול אליה הוא הורדת מסד מלא, כמו באוצריא
/// עצמה. ראו `LibraryUpdateDiscovery.discover`.
bool isSupportedSchemaVersion(int schemaVersion) =>
    kHashTableOrderBySchemaVersion.containsKey(schemaVersion);

/// האם ה-applier יודע להחיל את פורמט ה-`patch.db` הזה — אותו היגיון כמו
/// [isSupportedSchemaVersion], על הציר השני.
bool isSupportedPatchFormatVersion(int patchFormatVersion) =>
    patchFormatVersion >= 1 &&
    patchFormatVersion <= kSupportedPatchFormatVersion;
