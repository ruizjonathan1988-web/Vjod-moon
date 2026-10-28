/// A browser keeps no provider catalogue.
Future<String?> readCatalogCache(String key) async => null;

Future<void> writeCatalogCache(String key, String data) async {}

Future<void> deleteCatalogCache(String key) async {}

/// A browser fetches no catalogue from the seedbox.
Future<String?> fetchServerCatalog(String url) async => null;
