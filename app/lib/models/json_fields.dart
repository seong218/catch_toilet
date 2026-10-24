typedef Json = Map<String, dynamic>;

Json jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

int integer(Json json, String key, {int? minimum}) {
  final value = json[key];
  if (value is! int || (minimum != null && value < minimum)) {
    throw FormatException('Invalid integer: $key');
  }
  return value;
}

double number(Json json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid number: $key');
  }
  return value.toDouble();
}

double? nullableNumber(Json json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing field: $key');
  return json[key] == null ? null : number(json, key);
}

bool boolean(Json json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid boolean: $key');
  return value;
}

String string(Json json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid string: $key');
  }
  return value;
}

void validateCounts(int total, int available, int bidet) {
  if (bidet < 0 || available < bidet || total < available) {
    throw const FormatException('Invalid stall counts');
  }
}
