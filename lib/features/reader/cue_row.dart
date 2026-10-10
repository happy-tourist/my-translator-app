import 'package:flutter/material.dart';

import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

/// Shared cue row (timestamp + text_lines) for original and translation panes.
class CueRow extends StatelessWidget {
  const CueRow({
    super.key,
    required this.cue,
    this.keyPrefix = 'readerCue',
  });

  final CueDto cue;

  /// Prefix for Keys: `readerCue` (original) / `readerTranslationCue`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final timeStyle = Theme.of(context).textTheme.labelMedium;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final time =
        '${formatCueTimestamp(cue.startMs)} → ${formatCueTimestamp(cue.endMs)}';
    final text = cue.textLines.join('\n');

    return Padding(
      key: Key('${keyPrefix}_${cue.index}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            key: Key('${keyPrefix}Time_${cue.index}'),
            style: timeStyle,
          ),
          const SizedBox(height: 4),
          Text(
            text,
            key: Key('${keyPrefix}Text_${cue.index}'),
            style: bodyStyle,
          ),
        ],
      ),
    );
  }
}
