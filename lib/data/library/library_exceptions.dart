/// Validation / domain error for library folder and document operations.
class LibraryValidationException implements Exception {
  LibraryValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
