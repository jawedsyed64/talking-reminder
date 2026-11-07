import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';

final navKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

const kPrimary = Color(0xFF5B4BDB);
const kPrimary2 = Color(0xFF8A6CF5);
const kAccent = Color(0xFFFF7A50);
const kOk = Color(0xFF1C9A5F);
const kWarn = Color(0xFFD9850A);
const kBad = Color(0xFFD93A40);

class Cat {
  final String emoji;
  final Color color;
  const Cat(this.emoji, this.color);
}

const cats = <String, Cat>{
  'Personal': Cat('🙂', Color(0xFF7C6BF0)),
  'Work': Cat('💼', Color(0xFF2F80ED)),
  'Health': Cat('💚', Color(0xFF1C9A5F)),
  'Family': Cat('👨‍👩‍👧', Color(0xFFE5539A)),
  'Shopping': Cat('🛒', Color(0xFFD9850A)),
  'Finance': Cat('💰', Color(0xFF0FA3A3)),
  'Study': Cat('📚', Color(0xFF9B51E0)),
  'Other': Cat('📌', Color(0xFF7A7A95)),
};
Cat catOf(String c) => cats[c] ?? cats['Other']!;

Color priColor(String p) => p == 'high' ? kBad : p == 'low' ? kOk : kWarn;
String priLabel(String p) => p == 'high' ? 'High' : p == 'low' ? 'Low' : 'Medium';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final cs = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: b,
    primary: dark ? const Color(0xFF9D90FF) : kPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    brightness: b,
    scaffoldBackgroundColor: dark ? const Color(0xFF0E0E1A) : const Color(0xFFF3F2FA),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF202138) : const Color(0xFFF6F5FC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color cardColor(BuildContext c) => isDark(c) ? const Color(0xFF181929) : Colors.white;
Color mutedColor(BuildContext c) => isDark(c) ? const Color(0xFFA5A4C6) : const Color(0xFF67668A);
Color softPrimary(BuildContext c) => isDark(c) ? const Color(0xFF29265A) : const Color(0xFFECE9FF);

void toast(String msg) {
  final m = messengerKey.currentState;
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 15)), duration: const Duration(seconds: 3)));
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero, this.margin = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark(context) ? 0.3 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3))
          ],
        ),
        child: child,
      );
}

class Badge2 extends StatelessWidget {
  final String text;
  final Color color;
  const Badge2(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 16, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

class PageTitle extends StatelessWidget {
  final String title, subtitle;
  const PageTitle(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          Text(subtitle, style: TextStyle(color: mutedColor(context), fontSize: 14.5)),
        ]),
      );
}

class EmptyNote extends StatelessWidget {
  final String emoji, text;
  const EmptyNote(this.emoji, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
        child: Center(
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: mutedColor(context), fontSize: 15)),
          ]),
        ),
      );
}

/// One task row with a tick button, time, repeat, category and a "more" menu.
class TaskCard extends StatelessWidget {
  final Item item;
  final bool done;
  final VoidCallback onCheck;
  final VoidCallback? onTap;
  final VoidCallback? onMore;
  const TaskCard({super.key, required this.item, required this.done, required this.onCheck, this.onTap, this.onMore});

  @override
  Widget build(BuildContext context) {
    final t = item.t, o = item.o;
    final muted = mutedColor(context);
    final od = !done && o.isBefore(DateTime.now().subtract(const Duration(minutes: 1)));
    final cat = catOf(t.category);
    final snoozed = !done && ctl.s.snoozes.any((z) => z.taskId == t.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark(context) ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: priColor(t.priority)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 2, 12),
              child: Align(
                alignment: Alignment.topCenter,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onCheck,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? kOk : Colors.transparent,
                      border: Border.all(color: done ? kOk : muted.withValues(alpha: 0.5), width: 2.5),
                    ),
                    child: done ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? muted : null,
                        )),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.schedule, size: 15, color: od ? kBad : muted),
                        const SizedBox(width: 3),
                        Text('${fmtDay(o)} · ${ctl.fmtT(o)}${od ? ' · overdue' : ''}',
                            style: TextStyle(fontSize: 13.5, color: od ? kBad : muted, fontWeight: od ? FontWeight.w700 : null)),
                      ]),
                      if (isRec(t) && !done)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.repeat, size: 15, color: muted),
                          const SizedBox(width: 3),
                          Text(repeatLabel(t), style: TextStyle(fontSize: 13.5, color: muted)),
                        ]),
                      if (!done)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.notifications_none, size: 15, color: muted),
                          Text('${1 + t.advance.length}', style: TextStyle(fontSize: 13.5, color: muted)),
                        ]),
                      if (snoozed) const Badge2('Snoozed', kWarn),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      Badge2('${cat.emoji} ${t.category}', cat.color),
                      if (t.priority == 'high' && !done) const Badge2('High priority', kBad),
                      if (done && item.h != null)
                        Badge2('Done ${fmtDay(DateTime.fromMillisecondsSinceEpoch(item.h!.at)).toLowerCase()}', kOk),
                    ]),
                    if (t.description.isNotEmpty && !done)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(t.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13.5)),
                      ),
                  ]),
                ),
              ),
            ),
            if (onMore != null)
              IconButton(onPressed: onMore, icon: Icon(Icons.more_vert, color: muted), tooltip: 'More actions'),
          ]),
        ),
      ),
    );
  }
}

/// Big, friendly button used across the app.
class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color bg, fg;
  final VoidCallback? onPressed;
  const BigButton(this.label, {super.key, this.icon, required this.bg, required this.fg, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          onPressed: onPressed,
          icon: Icon(icon ?? Icons.check, size: 22),
          label: Text(label),
        ),
      );
}

Future<bool> confirm(BuildContext context, String title, {String ok = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kBad) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}
