/// Labels that group draws for the shrinker.
library;

import 'bindings.g.dart' as raw;

/// What a span groups.
///
/// The engine reserves the values below; a library may mint its own with any
/// other stable number, which is why this is an extension type over an int
/// rather than an enum closed over the reserved set. Reusing a reserved value
/// for something else only makes shrinking slower, not wrong.
///
/// Every value here is taken from the generated bindings rather than written
/// out, so it cannot drift from the header.
extension type const SpanLabel(int value) {
  /// The span the engine reserves as `HEGEL_LABEL_LIST`.
  static const SpanLabel list = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_LIST);

  /// The span the engine reserves as `HEGEL_LABEL_LIST_ELEMENT`.
  static const SpanLabel listElement = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_LIST_ELEMENT,
  );

  /// The span the engine reserves as `HEGEL_LABEL_SET`.
  static const SpanLabel set = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_SET);

  /// The span the engine reserves as `HEGEL_LABEL_SET_ELEMENT`.
  static const SpanLabel setElement = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_SET_ELEMENT,
  );

  /// The span the engine reserves as `HEGEL_LABEL_MAP`.
  static const SpanLabel map = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_MAP);

  /// The span the engine reserves as `HEGEL_LABEL_MAP_ENTRY`.
  static const SpanLabel mapEntry = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_MAP_ENTRY,
  );

  /// The span the engine reserves as `HEGEL_LABEL_TUPLE`.
  static const SpanLabel tuple = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_TUPLE);

  /// The span the engine reserves as `HEGEL_LABEL_ONE_OF`.
  static const SpanLabel oneOf = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_ONE_OF,
  );

  /// The span the engine reserves as `HEGEL_LABEL_OPTIONAL`.
  static const SpanLabel optional = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_OPTIONAL,
  );

  /// The span the engine reserves as `HEGEL_LABEL_FIXED_DICT`.
  static const SpanLabel fixedDict = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_FIXED_DICT,
  );

  /// The span the engine reserves as `HEGEL_LABEL_FLAT_MAP`.
  static const SpanLabel flatMap = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_FLAT_MAP,
  );

  /// The span the engine reserves as `HEGEL_LABEL_FILTER`.
  static const SpanLabel filter = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_FILTER,
  );

  /// The span the engine reserves as `HEGEL_LABEL_MAPPED`.
  static const SpanLabel mapped = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_MAPPED,
  );

  /// The span the engine reserves as `HEGEL_LABEL_SAMPLED_FROM`.
  static const SpanLabel sampledFrom = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_SAMPLED_FROM,
  );

  /// The span the engine reserves as `HEGEL_LABEL_ENUM_VARIANT`.
  static const SpanLabel enumVariant = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_ENUM_VARIANT,
  );

  /// The span the engine reserves as `HEGEL_LABEL_FEATURE_FLAG`.
  static const SpanLabel featureFlag = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_FEATURE_FLAG,
  );

  /// The span the engine reserves as `HEGEL_LABEL_REGEX`.
  static const SpanLabel regex = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_REGEX);

  /// The span the engine reserves as `HEGEL_LABEL_EMAIL`.
  static const SpanLabel email = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_EMAIL);

  /// The span the engine reserves as `HEGEL_LABEL_URL`.
  static const SpanLabel url = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_URL);

  /// The span the engine reserves as `HEGEL_LABEL_DOMAIN`.
  static const SpanLabel domain = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_DOMAIN,
  );

  /// The span the engine reserves as `HEGEL_LABEL_DATE`.
  static const SpanLabel date = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_DATE);

  /// The span the engine reserves as `HEGEL_LABEL_TIME`.
  static const SpanLabel time = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_TIME);

  /// The span the engine reserves as `HEGEL_LABEL_DATETIME`.
  static const SpanLabel datetime = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_DATETIME,
  );

  /// The span the engine reserves as `HEGEL_LABEL_UUID`.
  static const SpanLabel uuid = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_UUID);

  /// The span the engine reserves as `HEGEL_LABEL_IP_ADDRESS`.
  static const SpanLabel ipAddress = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_IP_ADDRESS,
  );

  /// The span the engine reserves as `HEGEL_LABEL_INTEGER`.
  static const SpanLabel integer = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_INTEGER,
  );

  /// The span the engine reserves as `HEGEL_LABEL_FLOAT`.
  static const SpanLabel float = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_FLOAT);

  /// The span the engine reserves as `HEGEL_LABEL_BOOLEAN`.
  static const SpanLabel boolean = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_BOOLEAN,
  );

  /// The span the engine reserves as `HEGEL_LABEL_BYTES`.
  static const SpanLabel bytes = SpanLabel(raw.hegel_label_t.HEGEL_LABEL_BYTES);

  /// The span the engine reserves as `HEGEL_LABEL_STRING`.
  static const SpanLabel string = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_STRING,
  );

  /// The span the engine reserves as `HEGEL_LABEL_STATEFUL_RULE`.
  static const SpanLabel statefulRule = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_STATEFUL_RULE,
  );

  /// The span the engine reserves as `HEGEL_LABEL_FRESH_ID`.
  static const SpanLabel freshId = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_FRESH_ID,
  );

  /// The span the engine reserves as `HEGEL_LABEL_SET_CHOICE`.
  static const SpanLabel setChoice = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_SET_CHOICE,
  );

  /// The span the engine reserves as `HEGEL_LABEL_CONCURRENCY`.
  static const SpanLabel concurrency = SpanLabel(
    raw.hegel_label_t.HEGEL_LABEL_CONCURRENCY,
  );

  /// The first value above everything the engine reserves.
  ///
  /// A library defining its own spans should start here or later.
  static const int firstAvailable =
      raw.hegel_label_t.HEGEL_LABEL_CONCURRENCY + 1;
}
