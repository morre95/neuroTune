import 'dart:math';

import 'models.dart';

class ActionChoice {
  const ActionChoice(this.action, this.probability);
  final StimulusAction action;
  final double probability;
}

class EpsilonPolicy {
  EpsilonPolicy({
    required this.epsilon,
    required this.random,
    Map<StimulusAction, ActionStat>? stats,
  }) : stats = {
          for (final action in StimulusAction.values)
            action: stats == null ? const ActionStat(0, 0) : (stats[action] ?? const ActionStat(0, 0)),
        };

  final double epsilon;
  final Random random;
  final Map<StimulusAction, ActionStat> stats;

  ActionChoice select() {
    final actions = StimulusAction.values;
    var bestMean = double.negativeInfinity;
    for (final action in actions) {
      bestMean = max(bestMean, stats[action]!.mean);
    }
    final best = [
      for (final action in actions)
        if (stats[action]!.mean == bestMean) action,
    ];
    final explore = random.nextDouble() < epsilon;
    final action = explore ? actions[random.nextInt(actions.length)] : best[random.nextInt(best.length)];
    final probability = epsilon / actions.length +
        (best.contains(action) ? (1 - epsilon) / best.length : 0);
    return ActionChoice(action, probability);
  }

  void observe(StimulusAction action, double reward) {
    stats[action] = stats[action]!.observe(reward);
  }
}
