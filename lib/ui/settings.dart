import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../core.dart';
import '../native.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double? rate, pitch, volume;
  final sample = TextEditingController();

  @override
  void initState() {
    super.initState();
    sample.text = ctl.s.settings.sample;
    if (!ctl.voicesLoaded) ctl.loadVoices();
    ctl.refreshStatus();
  }

  @override
  void dispose() {
    sample.dispose();
    super.dispose();
  }

  static const _brands = {
    'xiaomi': 'Xiaomi / Redmi / POCO',
    'redmi': 'Xiaomi / Redmi / POCO',
    'poco': 'Xiaomi / Redmi / POCO',
    'oppo': 'OPPO',
    'realme': 'realme',
    'vivo': 'vivo',
    'infinix': 'Infinix',
    'tecno': 'TECNO',
    'itel': 'itel',
    'huawei': 'Huawei',
    'honor': 'HONOR',
    'samsung': 'Samsung',
    'oneplus': 'OnePlus',
  };

  String _voiceLabel(Map<String, dynamic> v) {
    final name = '${v['name']}';
    final m = RegExp(r'-x-([a-z0-9]+)', caseSensitive: false).firstMatch(name);
    final code = m != null ? m.group(1)!.toUpperCase() : name.replaceAll(RegExp(r'[-_]'), ' ');
    return 'Voice $code';
  }

  Widget _group(BuildContext context, String title, List<Widget> children) => Panel(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _check(BuildContext context, bool ok, String title, String why, String fixLabel, VoidCallback onFix) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle : Icons.error, color: ok ? kOk : kWarn, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              Text(why, style: TextStyle(color: mutedColor(context), fontSize: 13)),
            ]),
          ),
          if (!ok) FilledButton(onPressed: onFix, child: Text(fixLabel)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final st = ctl.s.settings;
        final status = ctl.status;
        final primary = Theme.of(context).colorScheme.primary;
        final muted = mutedColor(context);
        final manu = '${status['manufacturer'] ?? ''}'.toLowerCase();
        final brand = _brands.entries.where((e) => manu.contains(e.key)).map((e) => e.value).firstOrNull;
        final next = (status['nextAlarm'] as num?)?.toInt() ?? 0;

        // voices
        final langs = <String, String>{};
        for (final v in ctl.voices) {
          langs['${v['lang']}'] = '${v['langName']}';
        }
        final sortedLangs = langs.keys.toList()..sort((a, b) => langs[a]!.compareTo(langs[b]!));
        final filterLang = st.lang.isNotEmpty ? st.lang : (ctl.defaultVoiceLang.isNotEmpty ? ctl.defaultVoiceLang : '');
        final shown = ctl.voices.where((v) {
          final l = '${v['lang']}'.toLowerCase();
          return filterLang.isEmpty || l == filterLang.toLowerCase() || l.startsWith('${filterLang.toLowerCase()}-');
        }).take(60).toList();

        return ListView(padding: EdgeInsets.zero, children: [
          const PageTitle('Settings', 'Voice, reminders and personalisation.'),

          _group(context, '✅ Reminder setup', [
            Text('All four must be green for reminders to speak on time, even when the app is closed.',
                style: TextStyle(color: muted, fontSize: 13.5)),
            const SizedBox(height: 4),
            _check(context, status['notifications'] == true, 'Notifications', 'Shows your reminders with Done / Snooze buttons.',
                'Allow', () async {
              await Native.requestNotifications();
              await ctl.refreshStatus();
            }),
            _check(context, status['exactAlarms'] == true, 'Alarms & reminders', 'Lets reminders ring at the exact minute.', 'Allow',
                () => Native.openSettings('exact')),
            _check(context, status['battery'] == true, 'No battery restriction',
                'Stops the phone from blocking reminders to save battery.', 'Allow', () => Native.openSettings('battery')),
            _check(context, status['fullScreen'] == true, 'Show on lock screen',
                'Shows the big reminder screen when the phone is locked.', 'Allow', () => Native.openSettings('fullscreen')),
            if (brand != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kWarn.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Extra step for $brand phones', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                      'In the app settings, turn on "Autostart" (or "Allow background activity") and set Battery to "No restrictions". '
                      'Some phones also need the app "locked" in the recent-apps screen.'),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: () => Native.openSettings('app'), child: const Text('Open app settings')),
                ]),
              ),
            const SizedBox(height: 6),
            Text(
                next > 0
                    ? '⏰ Next phone alarm: ${fmtDay(DateTime.fromMillisecondsSinceEpoch(next))} at ${ctl.fmtT(DateTime.fromMillisecondsSinceEpoch(next))}'
                    : '⏰ No reminders scheduled right now.',
                style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
          ]),

          _group(context, '🗣️ Reminder voice', [
            Text('Uses your phone\'s own Text-to-Speech voices. Reminders are spoken at ALARM volume.',
                style: TextStyle(color: muted, fontSize: 13.5)),
            const SizedBox(height: 10),
            if (!ctl.voicesLoaded)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (ctl.voices.isEmpty)
              const Text('⚠️ No voices found. Install or enable "Speech Services by Google" from the Play Store, then come back.')
            else ...[
              Text('Language & accent', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
              DropdownButton<String>(
                isExpanded: true,
                value: langs.containsKey(st.lang) ? st.lang : '',
                items: [
                  const DropdownMenuItem(value: '', child: Text('Phone default')),
                  for (final l in sortedLangs) DropdownMenuItem(value: l, child: Text('${langs[l]}  ($l)')),
                ],
                onChanged: (v) => ctl.updateSettings((x) {
                  x.lang = v ?? '';
                  final first = ctl.voices.where((e) => '${e['lang']}' == x.lang).firstOrNull;
                  if (first != null) {
                    x.voiceName = '${first['name']}';
                    x.voiceLang = x.lang;
                  } else if (x.lang.isEmpty) {
                    x.voiceName = '';
                    x.voiceLang = '';
                  }
                }),
              ),
              const SizedBox(height: 6),
              Text('Android doesn\'t say which voices are male or female — tap ▶ to hear each one. ☁ = needs internet.',
                  style: TextStyle(color: muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              for (final v in shown)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: st.voiceName == v['name'] ? softPrimary(context) : null,
                    border: Border.all(color: st.voiceName == v['name'] ? primary : muted.withValues(alpha: 0.25), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    onTap: () async {
                      await ctl.updateSettings((x) {
                        x.voiceName = '${v['name']}';
                        x.voiceLang = '${v['lang']}';
                      });
                      Native.speak(ctl.s.settings.sample, ctl.settingsJson);
                    },
                    leading: Icon(st.voiceName == v['name'] ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: st.voiceName == v['name'] ? primary : muted),
                    title: Text('${_voiceLabel(v)}${v['network'] == true ? '  ☁' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${v['langName']} · ${v['network'] == true ? 'Online' : 'Offline'}${((v['quality'] as num?) ?? 0) >= 400 ? ' · High quality' : ''}'),
                    trailing: IconButton(
                      icon: Icon(Icons.play_circle_fill, color: primary, size: 32),
                      tooltip: 'Test this voice',
                      onPressed: () {
                        final m = st.toJson();
                        m['voiceName'] = '${v['name']}';
                        m['voiceLang'] = '${v['lang']}';
                        Native.speak(st.sample, jsonEncode(m));
                      },
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () => Native.openSettings('tts'),
                icon: const Icon(Icons.download),
                label: const Text('Get more voices (phone settings)'),
              ),
            ],
            const SizedBox(height: 6),
            _slider('Speaking speed', rate ?? st.rate, 0.5, 1.6, (v) => '${v.toStringAsFixed(2)}×', (v) => setState(() => rate = v),
                (v) => ctl.updateSettings((x) => x.rate = v)),
            _slider('Voice pitch', pitch ?? st.pitch, 0.5, 1.8, (v) => v.toStringAsFixed(1), (v) => setState(() => pitch = v),
                (v) => ctl.updateSettings((x) => x.pitch = v)),
            _slider('Voice volume', volume ?? st.volume, 0.1, 1.0, (v) => '${(v * 100).round()}%',
                (v) => setState(() => volume = v), (v) => ctl.updateSettings((x) => x.volume = v)),
            const SizedBox(height: 8),
            TextField(
              controller: sample,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Sample sentence'),
              onChanged: (v) => ctl.s.settings.sample = v,
            ),
            const SizedBox(height: 10),
            BigButton('TEST VOICE', icon: Icons.volume_up, bg: primary, fg: Colors.white, onPressed: () async {
              final txt = sample.text.trim().isEmpty ? Settings.defaultSample : sample.text.trim();
              await ctl.updateSettings((x) => x.sample = txt);
              final ok = await Native.speak(txt, ctl.settingsJson, sound: false);
              if (!ok) toast('The voice engine is starting — tap again in a moment.');
            }),
          ]),

          _group(context, '🔔 Reminders', [
            Text('Sound before the voice', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in const [['chime', 'Phone notification sound'], ['beep', 'Beeps'], ['none', 'Voice only']])
                ChoiceChip(
                  label: Text(s[1]),
                  selected: st.sound == s[0],
                  onSelected: (_) {
                    ctl.updateSettings((x) => x.sound = s[0]);
                    Native.playSound(s[0]);
                  },
                ),
            ]),
            const SizedBox(height: 14),
            Text('Default snooze', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final m in const [5, 10, 15])
                ChoiceChip(
                    label: Text('$m minutes'), selected: st.snooze == m, onSelected: (_) => ctl.updateSettings((x) => x.snooze = m)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat the spoken reminder', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Speak again every 45 seconds (up to 3 times) until you press a button'),
              value: st.repeatSpeak,
              onChanged: (v) => ctl.updateSettings((x) => x.repeatSpeak = v),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kOk, minimumSize: const Size.fromHeight(50)),
                  onPressed: () async {
                    await Native.testIn(10);
                    toast('Test reminder in 10 seconds — you can lock the phone now.');
                    ctl.refreshStatus();
                  },
                  child: const Text('Test in 10 seconds', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () async {
                    await Native.testIn(60);
                    toast('Test reminder in 1 minute — close the app and lock the phone to try it.');
                    ctl.refreshStatus();
                  },
                  child: const Text('Test in 1 minute', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('These use the real alarm, so they also show whether reminders work with the app closed.',
                style: TextStyle(color: muted, fontSize: 12.5)),
          ]),

          _group(context, '🎨 Display', [
            Text('Time format', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('12-hour (3:00 PM)'),
                  selected: st.timeFormat == '12',
                  onSelected: (_) => ctl.updateSettings((x) => x.timeFormat = '12')),
              ChoiceChip(
                  label: const Text('24-hour (15:00)'),
                  selected: st.timeFormat == '24',
                  onSelected: (_) => ctl.updateSettings((x) => x.timeFormat = '24')),
            ]),
            const SizedBox(height: 14),
            Text('Theme', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final t in const [['light', '☀️ Light'], ['dark', '🌙 Dark'], ['system', '📱 Match phone']])
                ChoiceChip(label: Text(t[1]), selected: st.theme == t[0], onSelected: (_) => ctl.updateSettings((x) => x.theme = t[0])),
            ]),
            const SizedBox(height: 10),
            Text('Times follow your phone\'s clock and time zone, including daylight-saving changes.',
                style: TextStyle(color: muted, fontSize: 12.5)),
          ]),

          _group(context, '💾 Backup', [
            Text('Your tasks are stored only on this phone. Make a backup before changing phones.',
                style: TextStyle(color: muted, fontSize: 13.5)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Native.share(ctl.backupJson()),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Back up'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _restoreDialog(context),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore'),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('"Back up" lets you send the backup to yourself (WhatsApp, email, Google Drive).',
                style: TextStyle(color: muted, fontSize: 12.5)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: kBad),
              onPressed: () async {
                if (await confirm(context, 'Delete ALL tasks and history?', ok: 'Delete everything', danger: true)) {
                  await ctl.deleteAll();
                  toast('All tasks deleted');
                }
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete all tasks'),
            ),
          ]),

          _group(context, 'ℹ️ About', [
            Text(
              'Talking Reminder speaks your reminders using the phone\'s alarm system, so they work even when the app is closed '
              'and after the phone restarts. Nothing is sent to the internet — except "☁ online" voices, which use Google\'s '
              'speech service.',
              style: TextStyle(color: muted, height: 1.45),
            ),
          ]),
          const SizedBox(height: 110),
        ]);
      },
    );
  }

  Widget _slider(String label, double value, double min, double max, String Function(double) fmt, ValueChanged<double> onChanged,
      ValueChanged<double> onEnd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(fmt(value), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged, onChangeEnd: onEnd),
    ]);
  }

  Future<void> _restoreDialog(BuildContext context) async {
    final c = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    if (clip?.text != null && clip!.text!.contains('talking-reminder')) c.text = clip.text!;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore from backup'),
        content: TextField(
          controller: c,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Paste the backup text here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ctl.restoreBackup(c.text);
    toast(n < 0 ? 'That doesn\'t look like a Talking Reminder backup.' : 'Restored $n tasks ✓');
    sample.text = ctl.s.settings.sample;
  }
}
