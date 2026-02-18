import 'package:intl/intl.dart';

class Fmt {
  static final _dt = DateFormat('yyyy-MM-dd HH:mm');
  static String dt(DateTime d) => _dt.format(d);
}
