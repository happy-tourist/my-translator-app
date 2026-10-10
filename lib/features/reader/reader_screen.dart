import 'package:flutter/material.dart';

import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

/// Cues-first Reader: timestamps + plain text (RC-01…RC-04). No tokenize/word card.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({
    super.key,
    required this.title,
    required this.cues,
  });

  final String title;
  final List<CueDto> cues;

  @override
  Widget build(BuildContext context) {
    final timeStyle = Theme.of(context).textTheme.labelMedium;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;

    return Scaffold(
      key: const Key('readerScreen'),
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          key: const Key('readerBack'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Column (not ListTile): show all text_lines without two-line clip (D5).
      body: ListView.builder(
        key: const Key('readerCueList'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cues.length,
        itemBuilder: (context, index) {
          final cue = cues[index];
          final time =
              '${formatCueTimestamp(cue.startMs)} → ${formatCueTimestamp(cue.endMs)}';
          final text = cue.textLines.join('\n');
          return Padding(
            key: Key('readerCue_${cue.index}'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  key: Key('readerCueTime_${cue.index}'),
                  style: timeStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  key: Key('readerCueText_${cue.index}'),
                  style: bodyStyle,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
