/// מצב התוסף מול ההתקנה בפועל של אוצריא במחשב הזה.
///
/// [unknown] אינו "שגיאה": הוא המצב התקין של תוסף שקובץ ה-`.otzplugin` שלו
/// עוד לא ירד, ולכן ה-`manifestId` שלו טרם חולץ ואי אפשר להשוות אותו לכלום.
///
/// [incompatible] גם הוא מצב תקין: לתוסף אין אף בילד שירוץ על גרסת אוצריא
/// שבמחשב — בדרך כלל כי הוא דורש גרסה חדשה יותר.
enum PluginInstallStatus {
  notInstalled,
  upToDate,
  updateAvailable,
  unknown,
  incompatible,
}
