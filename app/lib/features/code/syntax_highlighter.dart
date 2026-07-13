import 'package:flutter/material.dart';

/// Lightweight regex-based syntax highlighter — no external packages, so
/// the app compiles everywhere. Covers keywords, strings, comments and
/// numbers for the most common languages.
class NexusSyntaxHighlighter {
  NexusSyntaxHighlighter(this.language);

  final String language;

  static const _keywords = {
    'dart': ['class', 'void', 'final', 'const', 'var', 'if', 'else', 'for', 'while', 'return', 'async', 'await', 'import', 'extends', 'implements', 'new', 'true', 'false', 'null', 'static', 'this', 'super'],
    'javascript': ['function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'return', 'async', 'await', 'import', 'export', 'class', 'extends', 'new', 'true', 'false', 'null', 'undefined', 'this', 'typeof'],
    'typescript': ['function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'return', 'async', 'await', 'import', 'export', 'class', 'extends', 'new', 'true', 'false', 'null', 'undefined', 'this', 'interface', 'type', 'enum'],
    'python': ['def', 'class', 'if', 'elif', 'else', 'for', 'while', 'return', 'import', 'from', 'as', 'with', 'try', 'except', 'True', 'False', 'None', 'self', 'lambda', 'async', 'await', 'pass', 'raise'],
    'html': ['html', 'head', 'body', 'div', 'span', 'script', 'style', 'link', 'meta', 'title', 'h1', 'h2', 'p', 'a', 'img', 'ul', 'li', 'button', 'input', 'form'],
    'css': ['color', 'background', 'display', 'flex', 'grid', 'margin', 'padding', 'border', 'width', 'height', 'position', 'font-size', 'font-family'],
    'sql': ['SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'JOIN', 'ON', 'GROUP', 'BY', 'ORDER', 'LIMIT', 'CREATE', 'TABLE', 'PRIMARY', 'KEY', 'NOT', 'NULL', 'AND', 'OR'],
  };

  /// Tokenizes [code] into styled spans for a [Text.rich]/[TextField].
  TextSpan highlight(String code, ColorScheme scheme) {
    final keywordSet = (_keywords[language] ?? _keywords['javascript']!).toSet();
    final spans = <TextSpan>[];

    final pattern = RegExp(
      r'(//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/|<!--[\s\S]*?-->)'   // comments
      r'''|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')'''          // strings
      r'|\b(\d+\.?\d*)\b'                                    // numbers
      r'|\b([A-Za-z_][A-Za-z0-9_-]*)\b',                     // identifiers
    );

    var last = 0;
    for (final m in pattern.allMatches(code)) {
      if (m.start > last) spans.add(TextSpan(text: code.substring(last, m.start)));
      final text = m[0]!;
      Color? color;
      if (m[1] != null) {
        color = scheme.outline;                              // comment
      } else if (m[2] != null) {
        color = Colors.green.shade600;                       // string
      } else if (m[3] != null) {
        color = Colors.orange.shade700;                      // number
      } else if (keywordSet.contains(text) || keywordSet.contains(text.toUpperCase())) {
        color = scheme.primary;                              // keyword
      }
      spans.add(TextSpan(
        text: text,
        style: color != null
            ? TextStyle(color: color, fontWeight: m[1] == null && m[2] == null && m[3] == null ? FontWeight.w600 : null)
            : null,
      ));
      last = m.end;
    }
    if (last < code.length) spans.add(TextSpan(text: code.substring(last)));
    return TextSpan(children: spans);
  }
}

/// TextEditingController that renders its content with syntax colors.
class CodeEditingController extends TextEditingController {
  CodeEditingController({required this.language, super.text});

  String language;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final highlighted = NexusSyntaxHighlighter(language).highlight(text, Theme.of(context).colorScheme);
    return TextSpan(style: style, children: highlighted.children ?? [highlighted]);
  }
}
