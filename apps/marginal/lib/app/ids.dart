int _last = 0;
String newId(String prefix) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final value = now <= _last ? _last + 1 : now;
  _last = value;
  return '$prefix-$value';
}
