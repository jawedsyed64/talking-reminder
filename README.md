# Talking Reminder (Android)

A to-do list and reminder app that **speaks your reminders aloud** using your phone's own voice. It works even when the app is closed and after the phone restarts.

## Install on your phone
1. On your Android phone, open the **Releases** page of this repository and tap **TalkingReminder.apk**.
2. When Android asks, allow your browser to *install unknown apps*, then tap **Install**.
3. Open the app, go to **Settings → Reminder setup**, and tap **Allow** until all four items are green.
4. Tap **Test in 1 minute**, close the app, lock the phone, and wait to hear it.

## How it works
- **Flutter** (`lib/`) provides the screens: dashboard, calendar, task editor, voice settings and sentence understanding.
- **Native Android** (`android/app/src/main/kotlin/`) handles everything that has to work in the background:
  - `Scheduler.kt` sets one exact system alarm (`AlarmManager.setAlarmClock`) for the next reminder.
  - `ReminderService.kt` runs when the alarm fires. It plays a sound and speaks the reminder with Android Text-to-Speech at alarm volume, then shows a notification with **Done / Snooze / Dismiss** buttons.
  - `BootReceiver.kt` sets the alarm again after a restart, an app update, or a time-zone change.
  - `Rec.kt` / `lib/core.dart` contain the same repeat rules (daily, weekly on chosen days, monthly, custom, end date).
- All data is stored in one private file on the phone. Nothing is uploaded.

## Build
Every push to `main` builds a new APK with GitHub Actions (`.github/workflows/build-apk.yml`) and publishes it under **Releases**.
The repository includes a fixed signing key (`android/app/upload.jks`), so each new version installs over the old one without losing your tasks. This key is for personal sideloading only; don't use it to publish on Google Play.
