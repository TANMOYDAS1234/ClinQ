import 'package:akd_care/features/chat/presentation/widgets/hold_to_talk_overlay.dart';
import 'package:akd_care/features/chat/presentation/widgets/voice_input_sheet.dart';
import 'package:akd_care/features/chat/presentation/widgets/voice_recognizer.dart';
import 'package:akd_care/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Stack(children: [child])),
  );

  // A read-only recogniser: never started, so no platform channels are hit.
  VoiceRecognizer recogniser() => VoiceRecognizer('en');

  const micRect = Rect.fromLTWH(300, 470, 56, 56); // on-screen for the 800x600 test surface

  group('HoldToTalkView', () {
    testWidgets('while holding: shows the recording bar and the open lock, no Send', (tester) async {
      final hold = VoiceHoldController();
      await tester.pumpWidget(
        harness(HoldToTalkView(
          recognizer: recogniser(),
          hold: hold,
          micRect: micRect,
          onLockedSend: () {},
          onLockedCancel: () {},
        )),
      );
      await tester.pump();

      expect(find.text('0:00'), findsOneWidget); // timer
      expect(find.text('Slide to cancel'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget); // not yet engaged
      expect(find.byIcon(Icons.send_rounded), findsNothing); // send only after lock
    });

    testWidgets('lock progress engages the lock icon before it snaps', (tester) async {
      final hold = VoiceHoldController();
      await tester.pumpWidget(
        harness(HoldToTalkView(
          recognizer: recogniser(),
          hold: hold,
          micRect: micRect,
          onLockedSend: () {},
          onLockedCancel: () {},
        )),
      );
      hold.update(lockProgress: 0.7, cancelArmed: false); // past the engage point, not locked
      await tester.pump();

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });

    testWidgets('locked: Send appears and calls back', (tester) async {
      final hold = VoiceHoldController();
      var sent = 0;
      await tester.pumpWidget(
        harness(HoldToTalkView(
          recognizer: recogniser(),
          hold: hold,
          micRect: micRect,
          onLockedSend: () => sent++,
          onLockedCancel: () {},
        )),
      );
      hold.update(lockProgress: 1.0, cancelArmed: false); // locks
      await tester.pump();

      expect(hold.locked, isTrue);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget); // discard

      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(sent, 1);
    });

    testWidgets('cancel-armed turns the hint red', (tester) async {
      final hold = VoiceHoldController();
      await tester.pumpWidget(
        harness(HoldToTalkView(
          recognizer: recogniser(),
          hold: hold,
          micRect: micRect,
          onLockedSend: () {},
          onLockedCancel: () {},
        )),
      );
      hold.update(lockProgress: 0.0, cancelArmed: true);
      await tester.pump();

      expect(find.text('Release to cancel'), findsOneWidget);
    });
  });
}
