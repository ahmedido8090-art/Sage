// screens/notification_settings_screen.dart
//
// Where the user decides how Sage nudges them: a master switch (which is also
// where the system permission is requested), which categories they want,
// quiet hours, a peek at what is coming up, and a test notification.
import 'package:material_ui/material_ui.dart';
import '../notifications/notification_category.dart';
import '../notifications/notification_gateway.dart';
import '../notifications/notification_prefs.dart';
import '../notifications/notification_service.dart';
import '../notifications/schedule_planner.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../services/system_settings.dart';
import '../widgets/sage_card.dart';
import '../widgets/sage_feedback.dart';
import '../widgets/sage_illustration.dart';
import '../widgets/sage_states.dart';
import '../widgets/state_copy.dart';
import '../widgets/sage_screen_header.dart';
import '../widgets/sage_settings_row.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  final NotificationService _service = NotificationService.instance;
  late NotificationPrefs _prefs;
  bool _busy = false;
  bool _askedAndDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prefs = _service.prefs;
    _service.refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user may have changed the system setting while away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service.refreshPermission();
  }

  Future<void> _save(NotificationPrefs next) async {
    setState(() {
      _prefs = next;
      _busy = true;
    });
    await _service.savePrefs(next);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setMaster(bool on) async {
    if (!on) {
      await _save(_prefs.copyWith(enabled: false));
      setState(() => _askedAndDenied = false);
      return;
    }
    setState(() => _busy = true);
    final ok = await _service.enable();
    if (!mounted) return;
    setState(() {
      _prefs = _service.prefs;
      _busy = false;
      _askedAndDenied = !ok;
    });
    if (ok)
      SageFeedback.success(
          context, 'Nudges are on. Sage will keep them gentle.');
  }

  Future<void> _pickQuiet({required bool start}) async {
    final minutes = start ? _prefs.quietStartMinutes : _prefs.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: start ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (picked == null) return;
    final value = picked.hour * 60 + picked.minute;
    await _save(start
        ? _prefs.copyWith(quietStartMinutes: value)
        : _prefs.copyWith(quietEndMinutes: value));
  }

  String _formatMinutes(int minutes) => MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));

  String _formatPlanned(PlannedNotification n) {
    final now = DateTime.now();
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay(hour: n.at.hour, minute: n.at.minute));
    final sameDay = n.at.day == now.day && n.at.month == now.month;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = n.at.day == tomorrow.day && n.at.month == tomorrow.month;
    return '${sameDay ? 'Today' : isTomorrow ? 'Tomorrow' : 'Later'}, $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: SafeArea(
        child: ValueListenableBuilder<NotificationPermission>(
          valueListenable: _service.permission,
          builder: (context, permission, _) {
            final granted = permission == NotificationPermission.granted;
            final blockedBySystem = _prefs.enabled && !granted;
            return ListView(
              padding: const EdgeInsets.fromLTRB(SageSpace.gutter, SageSpace.sm,
                  SageSpace.gutter, SageSpace.xxl),
              children: [
                _header(),
                const SizedBox(height: SageSpace.lg),
                _masterCard(granted, blockedBySystem),
                const SizedBox(height: SageSpace.lg),
                _categoriesCard(),
                const SizedBox(height: SageSpace.lg),
                _quietHoursCard(),
                const SizedBox(height: SageSpace.lg),
                _upcomingCard(),
                const SizedBox(height: SageSpace.lg),
                _testButton(granted),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() => const SageScreenHeader(title: 'Notifications');

  Widget _masterCard(bool granted, bool blockedBySystem) {
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SageSettingsRow(
            icon: Icons.notifications_active_outlined,
            title: 'Gentle nudges from Sage',
            subtitle: _prefs.enabled
                ? 'On. A few friendly reminders a day, at most.'
                : 'Off. Sage will not send anything.',
            trailing: Switch(
              value: _prefs.enabled && granted,
              activeThumbColor: SageColors.moss,
              onChanged: _busy ? null : _setMaster,
            ),
          ),
          if (blockedBySystem || _askedAndDenied) ...[
            const SizedBox(height: SageSpace.md),
            PermissionState(
              kind: PermissionKind.notifications,
              blocked: true,
              compact: true,
              onAllow: () => _setMaster(true),
              onOpenSettings: SystemSettings.openNotifications,
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoriesCard() {
    final master = _prefs.enabled;
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
              title: 'What Sage nudges you about',
              subtitle: 'Pick what is useful. Skip the rest.'),
          const SizedBox(height: SageSpace.sm),
          for (final c in NotificationCategory.values)
            SageSettingsRow(
              icon: c.icon,
              title: c.label,
              subtitle: c.description,
              trailing: Switch(
                value: _prefs.categories.contains(c),
                activeThumbColor: SageColors.moss,
                onChanged: master && !_busy
                    ? (on) => _save(_prefs.copyWith(
                          categories: on
                              ? {..._prefs.categories, c}
                              : _prefs.categories.where((x) => x != c).toSet(),
                        ))
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _quietHoursCard() {
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
              title: 'Quiet hours',
              subtitle: 'Sage stays silent between these times.'),
          const SizedBox(height: SageSpace.sm),
          SageSettingsRow(
            icon: Icons.bedtime_outlined,
            title: 'From',
            subtitle: _formatMinutes(_prefs.quietStartMinutes),
            onTap: () => _pickQuiet(start: true),
            trailing: Icon(Icons.chevron_right, color: SageColors.inkSoft),
          ),
          SageSettingsRow(
            icon: Icons.wb_sunny_outlined,
            title: 'Until',
            subtitle: _formatMinutes(_prefs.quietEndMinutes),
            accent: SageColors.amber,
            onTap: () => _pickQuiet(start: false),
            trailing: Icon(Icons.chevron_right, color: SageColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _upcomingCard() {
    final upcoming = _prefs.enabled ? _service.upcoming() : const [];
    return SageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Coming up'),
          const SizedBox(height: SageSpace.sm),
          if (upcoming.isEmpty)
            EmptyState.topic(
              StateTopic.notifications,
              art: SageArt.bell,
              compact: true,
              variant: _prefs.enabled ? 1 : 0,
            )
          else
            for (final n in upcoming)
              SageSettingsRow(
                icon: n.category.icon,
                title: n.message.title,
                subtitle: _formatPlanned(n),
              ),
        ],
      ),
    );
  }

  Widget _testButton(bool granted) {
    return Semantics(
      button: true,
      child: OutlinedButton.icon(
        onPressed: granted
            ? () async {
                await _service.sendTest();
                if (!mounted) return;
                SageFeedback.success(
                    context, 'Sent. Check your notification shade.');
              }
            : null,
        icon: const Icon(Icons.send_outlined, size: 18),
        label: const Text('Send a test notification'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(kSageMinTapTarget),
        ),
      ),
    );
  }
}
