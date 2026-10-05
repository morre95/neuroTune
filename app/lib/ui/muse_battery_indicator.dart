import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A null level means there is no current battery reading from a connected Muse.
class MuseBatteryIndicator extends StatelessWidget {
  const MuseBatteryIndicator({super.key, required this.batteryPercent});

  final ValueListenable<int?> batteryPercent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: batteryPercent,
      builder: (context, level, _) {
        if (level == null) return const SizedBox.shrink();
        final label = 'Muse-batteri: $level %';
        final icon = switch (level) {
          <= 10 => Icons.battery_alert,
          <= 20 => Icons.battery_1_bar,
          <= 35 => Icons.battery_2_bar,
          <= 50 => Icons.battery_3_bar,
          <= 65 => Icons.battery_4_bar,
          <= 80 => Icons.battery_5_bar,
          < 95 => Icons.battery_6_bar,
          _ => Icons.battery_full,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Semantics(
              label: label,
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: level <= 20
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$level %',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
