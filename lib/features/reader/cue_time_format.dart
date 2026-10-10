/// Formats cue milliseconds as `HH:MM:SS,mmm` (zero-padded, design D5).
String formatCueTimestamp(BigInt ms) {
  var total = ms.toInt();
  if (total < 0) total = 0;
  final hours = total ~/ 3600000;
  final minutes = (total % 3600000) ~/ 60000;
  final seconds = (total % 60000) ~/ 1000;
  final millis = total % 1000;
  return '${_pad2(hours)}:${_pad2(minutes)}:${_pad2(seconds)},${_pad3(millis)}';
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _pad3(int n) => n.toString().padLeft(3, '0');
