abstract interface class FaviconResolver {
  Future<Uri?> resolve(Uri baseUri);

  void close();
}
