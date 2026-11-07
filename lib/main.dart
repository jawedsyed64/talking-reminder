import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'native.dart';
import 'ui/alert.dart';
import 'ui/calendar.dart';
import 'ui/home.dart';
import 'ui/reminders.dart';
import 'ui/settings.dart';
import 'ui/sheets.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Native.init();
  runApp(const TalkingReminderApp());
}

class TalkingReminderApp extends StatefulWidget {
  const TalkingReminderApp({super.key});
  @override
  State<TalkingReminderApp> createState() => _TalkingReminderAppState();
}

class _TalkingReminderAppState extends State<TalkingReminderApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Native.onShowAlert = showAlertJson;
    ctl.init().then((_) async {
      final a = await Native.takeLaunchAlert();
      if (a != null) {
        // wait for the first screen to be on
        WidgetsBinding.instance.addPostFrameCallback((_) => showAlertJson(a));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ctl.reload();
      ctl.refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final th = ctl.s.settings.theme;
        return MaterialApp(
          title: 'Talking Reminder',
          debugShowCheckedModeBanner: false,
          navigatorKey: navKey,
          scaffoldMessengerKey: messengerKey,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: th == 'dark' ? ThemeMode.dark : th == 'light' ? ThemeMode.light : ThemeMode.system,
          home: const Shell(),
        );
      },
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  Timer? minute;

  @override
  void initState() {
    super.initState();
    ctl.addListener(_checkMissed);
    // refresh lists every 30 s so "today/overdue" stay correct
    minute = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ctl.removeListener(_checkMissed);
    minute?.cancel();
    super.dispose();
  }

  void _checkMissed() {
    if (ctl.s.missed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMissedSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(goTo: (i) => setState(() => tab = i)),
      const CalendarPage(),
      const RemindersPage(),
      const SettingsPage(),
    ];
    final primary = Theme.of(context).colorScheme.primary;
    Widget navBtn(int i, IconData icon, String label) {
      final on = tab == i;
      final c = on ? primary : mutedColor(context);
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => tab = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: c, size: 26),
              Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 68,
        height: 68,
        child: FloatingActionButton(
          heroTag: 'add',
          tooltip: 'Add task',
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          onPressed: () => openEditor(context),
          child: const Icon(Icons.add, size: 36),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: cardColor(context),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          navBtn(0, Icons.home_rounded, 'Home'),
          navBtn(1, Icons.calendar_month, 'Calendar'),
          const SizedBox(width: 76),
          navBtn(2, Icons.notifications_rounded, 'Reminders'),
          navBtn(3, Icons.settings_rounded, 'Settings'),
        ]),
      ),
    );
  }
}
