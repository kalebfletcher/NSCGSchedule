# NSCGSchedule

A student timetable and scheduling app for NSCG. This Flutter application helps students view timetables, exam schedules, notifications, and manage friends' schedules.

Key features
- View personal timetable and exam timetables.
- Notifications and schedule updates.
- Friends list, gaps, QR sharing, and profile views.
- Local encrypted storage with Hive.

Prerequisites
- Flutter SDK (stable channel) installed and configured.
- A connected device or emulator.

Quick start
1. Install dependencies:

	`flutter pub get`
2. Run on connected device or emulator:

	`flutter run`
3. Build release APK:

	`flutter build apk --release``

Project layout
- `lib/` — app source code (screens, services, models).
- `assets/` — images and icons.

Development notes
- Uses Hive for local persistence (see generated `hive_registrar.g.dart`).
- Routes and navigation defined in `lib/router.dart`.
- Background services and notifications in `lib/watch_service.dart` and `lib/notifications.dart`.

Contributing
- Open an issue to discuss changes.
- Fork, create a branch, and submit a pull request.

## Legal Disclaimer & Limitation of Liability

> [!IMPORTANT]
> **Independent Community Project:** This software is an independent, open-source tool developed for students. It is **not affiliated with, endorsed by, sponsored by, or operated by Newcastle and Stafford Colleges Group (NSCG)**. All trademarks and logos are the property of their respective owners.

- **"As-Is" Provision:** This software and any associated services are provided *"as is"*, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, uptime, or non-infringement.
- **Limitation of Liability:** In no event shall the authors, maintainers, or contributors be liable for any claim, damages, data loss, schedule inaccuracies, missed deadlines, or other liabilities arising from the use or inability to use this software.
- **User Responsibility:** Users are solely responsible for verifying their class and exam schedules against official college portals, and for managing who they share their schedule invite keys and QR codes with.

## License
- See the `LICENSE` file for license details.

## Contact
- If you're with the college, you can use C243879; please also open a GitHub issue so I'm aware to actually respond. For everyone else, opening a GitHub issue is the best way to get my attention — I check issues and will respond as soon as I can.
