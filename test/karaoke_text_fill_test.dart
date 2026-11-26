import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_lyrics/widgets/karaoke_text_fill.dart';

void main() {
  testWidgets(
    'longHold letter-by-letter fill keeps exact layout width and next-word position',
    (WidgetTester tester) async {
      final firstKey = GlobalKey();
      final nextKey = GlobalKey();

      Future<({Size firstSize, Offset nextPos})> measureAt(
          double progress) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 260,
                child: Wrap(
                  spacing: 0,
                  runSpacing: 4,
                  children: [
                    KaraokeTextFill(
                      key: firstKey,
                      text: 'Together ',
                      progress: progress,
                      longHold: true,
                      elapsedSeconds: progress * 1.6,
                      wordDuration: 1.6,
                      style: const TextStyle(
                        fontSize: 33,
                        fontWeight: FontWeight(1000),
                        letterSpacing: -0.6,
                      ),
                    ),
                    KaraokeTextFill(
                      key: nextKey,
                      text: 'now',
                      progress: 0.0,
                      longHold: false,
                      style: const TextStyle(
                        fontSize: 33,
                        fontWeight: FontWeight(1000),
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final firstBox =
            firstKey.currentContext!.findRenderObject()! as RenderBox;
        final nextBox =
            nextKey.currentContext!.findRenderObject()! as RenderBox;
        return (
          firstSize: firstBox.size,
          nextPos: nextBox.localToGlobal(Offset.zero),
        );
      }

      final idle = await measureAt(0.0);
      final early = await measureAt(0.05);
      final mid = await measureAt(0.5);
      final done = await measureAt(1.0);

      for (final sample in [early, mid, done]) {
        expect(sample.firstSize.width, equals(idle.firstSize.width));
        expect(sample.firstSize.height, equals(idle.firstSize.height));
        expect(sample.nextPos.dx, equals(idle.nextPos.dx));
        expect(sample.nextPos.dy, equals(idle.nextPos.dy));
      }
    },
  );
}
