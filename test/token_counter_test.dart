import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/agent/token_counter.dart';

void main() {
  group('AgentTokenCounter.format', () {
    test('keeps counts under a thousand literal', () {
      expect(AgentTokenCounter.format(0), '0');
      expect(AgentTokenCounter.format(512), '512');
      expect(AgentTokenCounter.format(999), '999');
    });

    test('scales to k and drops a useless decimal', () {
      expect(AgentTokenCounter.format(1000), '1k');
      expect(AgentTokenCounter.format(12430), '12.4k');
      expect(AgentTokenCounter.format(57500), '57.5k');
      // Past a hundred the tenth is noise.
      expect(AgentTokenCounter.format(128000), '128k');
      expect(AgentTokenCounter.format(999499), '999k');
    });

    test('scales to M at a thousand k', () {
      expect(AgentTokenCounter.format(1000000), '1M');
      expect(AgentTokenCounter.format(1240000), '1.2M');
    });
  });

  group('AgentTokenCounter.formatPercent', () {
    test('stays precise while the share is small', () {
      expect(AgentTokenCounter.formatPercent(0.0001), '0.01%');
      expect(AgentTokenCounter.formatPercent(0.0425), '4.3%');
    });

    test('rounds once the share is large', () {
      expect(AgentTokenCounter.formatPercent(0.5), '50%');
      expect(AgentTokenCounter.formatPercent(1), '100%');
    });
  });

  group('AgentTokenCounter.estimate', () {
    test('counts nothing as nothing', () {
      expect(AgentTokenCounter.estimate(null), 0);
      expect(AgentTokenCounter.estimate(''), 0);
    });

    test('counts latin text at about four characters a token', () {
      expect(AgentTokenCounter.estimate('abcd'), 1);
      expect(AgentTokenCounter.estimate('abcde'), 2);
      expect(AgentTokenCounter.estimate('a' * 400), 100);
    });

    test('counts CJK at about one token a character', () {
      // A Han character is a token or two on its own, never a quarter of one.
      expect(AgentTokenCounter.estimate('你好世界'), 4);
      expect(AgentTokenCounter.estimate('こんにちは'), 5);
      expect(AgentTokenCounter.estimate('안녕하세요'), 5);
    });

    test('mixes scripts without discounting either', () {
      // Four latin characters and one Han character.
      expect(AgentTokenCounter.estimate('abcd你'), 2);
    });
  });

  group('AgentTokenCounter.estimateMessage', () {
    test('charges the message overhead even with no text', () {
      expect(
        AgentTokenCounter.estimateMessage({'role': 'user', 'content': ''}),
        AgentTokenCounter.messageOverhead,
      );
    });

    test('counts multimodal text parts and ignores image parts', () {
      final withText = AgentTokenCounter.estimateMessage({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'abcd'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AAAA'},
          },
        ],
      });
      expect(withText, AgentTokenCounter.messageOverhead + 1);
    });

    test('counts a tool call payload', () {
      final withCall = AgentTokenCounter.estimateMessage({
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'call_1',
            'function': {
              'name': 'run_command',
              'arguments': '{"command":"ls"}',
            },
          },
        ],
      });
      expect(withCall, greaterThan(AgentTokenCounter.messageOverhead));
    });
  });

  group('AgentTokenCounter.contextWindow', () {
    test('reads a bare model id', () {
      expect(AgentTokenCounter.contextWindow('gpt-4o-mini'), 128000);
      expect(AgentTokenCounter.contextWindow('gpt-4o'), 128000);
    });

    test('prefers the longest matching name', () {
      // `gpt-4` is a different, much smaller window than `gpt-4o-mini`.
      expect(AgentTokenCounter.contextWindow('gpt-4o-mini'), isNot(8192));
      expect(AgentTokenCounter.contextWindow('gpt-4-0613'), 8192);
    });

    test('reads provider-prefixed and tagged ids', () {
      expect(AgentTokenCounter.contextWindow('openai/gpt-4o'), 128000);
      expect(AgentTokenCounter.contextWindow('llama3.2:latest'), 131072);
    });

    test('leaves an unknown ceiling unknown rather than guessing', () {
      expect(AgentTokenCounter.contextWindow(null), isNull);
      expect(AgentTokenCounter.contextWindow(''), isNull);
      expect(AgentTokenCounter.contextWindow('deepseek-v4-pro'), isNull);
      expect(AgentTokenCounter.contextWindow('my-local-model'), isNull);
    });
  });

  group('AgentContextMeter', () {
    test('is quiet until a call has run or a prompt has substance', () {
      const empty = AgentContextMeter();
      expect(empty.isEmpty, isTrue);
      expect(
        empty.copyWith(tokens: AgentTokenCounter.messageOverhead).isEmpty,
        isTrue,
      );
      expect(
        empty.copyWith(tokens: AgentTokenCounter.messageOverhead + 1).isEmpty,
        isFalse,
      );
    });

    test('uses a provider count when the provider reported one', () {
      final meter = const AgentContextMeter().record(
        const AgentTurnUsage(
          inputTokens: 900,
          outputTokens: 100,
          totalTokens: 1000,
        ),
        42,
      );
      expect(meter.tokens, 900);
      expect(meter.peakTokens, 900);
      expect(meter.totalTokens, 1000);
      expect(meter.runs, 1);
      expect(meter.estimatedTotals, isFalse);
    });

    test('falls back to the estimate and says so', () {
      final meter = const AgentContextMeter().record(null, 700);
      expect(meter.tokens, 700);
      expect(meter.totalTokens, 700);
      expect(meter.estimatedTotals, isTrue);
    });

    test('keeps the fullest request across a mixed conversation', () {
      final meter = const AgentContextMeter()
          .record(null, 700)
          .record(
            const AgentTurnUsage(
              inputTokens: 500,
              outputTokens: 50,
              totalTokens: 550,
            ),
            500,
          )
          .record(null, 1200);
      expect(meter.peakTokens, 1200);
      expect(meter.totalTokens, 700 + 550 + 1200);
      expect(meter.runs, 3);
      // One counted call keeps the totals marked as estimates.
      expect(meter.estimatedTotals, isTrue);
    });
  });

  group('AgentTurnUsage.fromJson', () {
    test('reads OpenAI-style and chat-style keys', () {
      expect(
        AgentTurnUsage.fromJson({
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        })?.totalTokens,
        15,
      );
      expect(
        AgentTurnUsage.fromJson({
          'input_tokens': 10,
          'output_tokens': 5,
        })?.totalTokens,
        15,
      );
    });

    test('treats an empty or absent bag as nothing reported', () {
      expect(AgentTurnUsage.fromJson(null), isNull);
      expect(AgentTurnUsage.fromJson('nope'), isNull);
      expect(AgentTurnUsage.fromJson(const <String, dynamic>{}), isNull);
      expect(
        AgentTurnUsage.fromJson(const {
          'prompt_tokens': 0,
          'completion_tokens': 0,
          'total_tokens': 0,
        }),
        isNull,
      );
    });
  });
}
