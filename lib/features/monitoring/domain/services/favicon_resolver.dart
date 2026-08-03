import 'package:site_signal/features/monitoring/domain/entities/favicon_image.dart';

abstract interface class FaviconResolver {
  Future<FaviconImage?> resolve(Uri baseUri);

  void close();
}
