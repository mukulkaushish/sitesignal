import 'dart:typed_data';

/// A small, decoder-normalized PNG kept only in memory.
final class FaviconImage {
  FaviconImage.fromPngBytes(List<int> pngBytes)
    : _pngBytes = Uint8List.fromList(pngBytes);

  final Uint8List _pngBytes;

  Uint8List get pngBytes => Uint8List.fromList(_pngBytes);
}
