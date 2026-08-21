/// Whether [cp] is a CJK or Hangul codepoint (rendered as tinted text).
///
/// Wide characters that are NOT CJK are assumed to be emoji and rendered
/// as full-color image sprites. Flutter doesn't expose a font-level
/// `isColorGlyph()` check, so codepoint range classification is the
/// pragmatic way to distinguish CJK text from emoji in the hot loop.
bool isCjkCodepoint(int cp) {
  return (cp >= 0x2E80 && cp <= 0x9FFF) || // CJK radicals, unified ideographs
      (cp >= 0xAC00 && cp <= 0xD7AF) || // Hangul Syllables
      (cp >= 0xF900 && cp <= 0xFAFF) || // CJK Compatibility Ideographs
      (cp >= 0xFE30 && cp <= 0xFE4F) || // CJK Compatibility Forms
      (cp >= 0xFF01 && cp <= 0xFF60) || // Fullwidth Forms
      (cp >= 0xFFE0 && cp <= 0xFFE6) || // Fullwidth Signs
      (cp >= 0x1100 && cp <= 0x11FF) || // Hangul Jamo
      (cp >= 0x3130 && cp <= 0x318F) || // Hangul Compatibility Jamo
      (cp >= 0xA960 && cp <= 0xA97F) || // Hangul Jamo Extended-A
      (cp >= 0xD7B0 && cp <= 0xD7FF) || // Hangul Jamo Extended-B
      (cp >= 0x20000 && cp <= 0x2FA1F); // CJK Supplementary
}
