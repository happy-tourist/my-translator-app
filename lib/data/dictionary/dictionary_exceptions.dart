/// Validation / domain error for dictionary entry operations.
class DictionaryValidationException implements Exception {
  DictionaryValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
