import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune/ui/muse_battery_indicator.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  const batteryChannel = 'dev.neurotune/muse_battery';

  Future<void> send(String channel, Object? value) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel,
      codec.encodeSuccessEnvelope(value),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    for (final name in [
      'dev.neurotune/muse',
      'dev.neurotune/muse_eeg',
      'dev.neurotune/muse_optics',
      batteryChannel,
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });

  test(
    'battery updates, clears on disconnect and resets on reconnect',
    () async {
      final muse = MuseChannel();
      await muse.start();
      expect(muse.batteryPercent.value, isNull);
      await send(batteryChannel, 76.4);
      expect(muse.batteryPercent.value, 76);
      await send(batteryChannel, 0);
      expect(muse.batteryPercent.value, 0);
      await send(batteryChannel, 101);
      expect(muse.batteryPercent.value, isNull);
      await send(batteryChannel, 50);
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.neurotune/muse_eeg',
        codec.encodeErrorEnvelope(code: 'MUSE_DISCONNECTED'),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(muse.batteryPercent.value, isNull);
      await muse.start();
      expect(muse.batteryPercent.value, isNull);
      await send(batteryChannel, 25);
      expect(muse.batteryPercent.value, 25);
      await muse.stop();
      expect(muse.batteryPercent.value, isNull);
    },
  );

  testWidgets('indicator updates and disappears without a current reading', (
    tester,
  ) async {
    final level = ValueNotifier<int?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [MuseBatteryIndicator(batteryPercent: level)],
          ),
        ),
      ),
    );
    expect(find.byType(Icon), findsNothing);
    level.value = 80;
    await tester.pump();
    expect(find.text('80 %'), findsOneWidget);
    expect(find.byTooltip('Muse-batteri: 80 %'), findsOneWidget);
    level.value = 0;
    await tester.pump();
    expect(find.text('0 %'), findsOneWidget);
    expect(find.byIcon(Icons.battery_alert), findsOneWidget);
    level.value = null;
    await tester.pump();
    expect(find.byType(Icon), findsNothing);
    expect(find.text('0 %'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    level.dispose();
  });
}
