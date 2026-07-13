import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_ai/features/code/syntax_highlighter.dart';

String _plainText(TextSpan span) {
  final buffer = StringBuffer();
  span.visitChildren((child) {
    if (child is TextSpan && child.text != null) buffer.write(child.text);
    return true;
  });
  return buffer.toString();
}

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);

  group('NexusSyntaxHighlighter', () {
    test('round-trips the exact source text', () {
      const code = 'const x = "hallo"; // Kommentar\nlet n = 42;';
      final span = NexusSyntaxHighlighter('javascript').highlight(code, scheme);
      expect(_plainText(span), code);
    });

    test('colors keywords with the primary color', () {
      final span = NexusSyntaxHighlighter('javascript').highlight('const x = 1;', scheme);
      final colored = <String, Color?>{};
      span.visitChildren((child) {
        if (child is TextSpan && child.text != null) colored[child.text!] = child.style?.color;
        return true;
      });
      expect(colored['const'], scheme.primary);
      expect(colored['x'], isNull);
    });

    test('unknown language falls back without crashing', () {
      final span = NexusSyntaxHighlighter('cobol').highlight('MOVE A TO B', scheme);
      expect(_plainText(span), 'MOVE A TO B');
    });
  });
}
