/// מצב התוסף מול ההתקנה בפועל של אוצריא במחשב הזה.
///
/// [unknown] אינו "שגיאה": הוא המצב התקין של תוסף שקובץ ה-`.otzplugin` שלו
/// עוד לא ירד, ולכן ה-`manifestId` שלו טרם חולץ ואי אפשר להשוות אותו לכלום.
enum PluginInstallStatus { notInstalled, upToDate, updateAvailable, unknown }
