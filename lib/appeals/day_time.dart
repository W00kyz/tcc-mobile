/// `DD/MM HH:MM` in the device's local time — the campus clock the worker
/// reads (an appeal's declared time, its deadline). Hand-rolled like the
/// other screens' formatters: the app ships pt-BR only and `intl` for one
/// format is not worth the dependency.
///
///     Text(formatDayTime(stop.deadline)) // "23/10 11:00"
String formatDayTime(DateTime when) {
  final local = when.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} '
      '${two(local.hour)}:${two(local.minute)}';
}
