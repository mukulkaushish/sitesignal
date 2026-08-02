import 'package:characters/characters.dart';

extension DisplayString on String {
  int get graphemeLength => characters.length;

  String get normalizedWhitespace => replaceAll(RegExp(r'\s+'), ' ').trim();

  String ellipsized(int maxCharacters, {int minimumWordBreak = 0}) {
    if (maxCharacters < 2) {
      throw RangeError.range(maxCharacters, 2, null, 'maxCharacters');
    }
    final graphemes = characters;
    if (graphemes.length <= maxCharacters) {
      return this;
    }

    var prefix = graphemes.take(maxCharacters - 1).toString().trimRight();
    final lastSpace = prefix.lastIndexOf(' ');
    if (lastSpace >= minimumWordBreak) {
      prefix = prefix.substring(0, lastSpace).trimRight();
    }
    return '$prefix…';
  }
}
