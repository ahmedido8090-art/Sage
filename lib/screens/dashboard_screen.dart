// screens/dashboard_screen.dart
//
// Signed-in shell: the Home tab plus Wellness, Insights and Profile, kept
// alive in an IndexedStack so switching tabs never loses scroll or form state.
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../models/health_data.dart';
import '../notifications/notification_category.dart';
import '../notifications/notification_service.dart';
import '../band/band_monitor.dart';
import '../band/band_picker.dart';
import '../widgets/band_intro_card.dart';
import '../widgets/band_offline_notice.dart';
import '../widgets/notification_prompt_card.dart';
import '../widgets/sage_feedback.dart';
import '../services/wellness_quote_service.dart';
import '../services/wellness_score_service.dart';
import '../services/user_service.dart';
import '../services/bluetooth_service.dart';
import '../services/bella_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/sage_card.dart';
import '../utils/page_transitions.dart';
import '../widgets/sage_hero_card.dart';
import '../widgets/metric_tile.dart';
import '../widgets/wellness_activity_tile.dart';
import '../widgets/quote_section.dart';
import '../widgets/sage_bottom_nav.dart';
import '../widgets/shimmer_loader.dart';
import 'band_history_screen.dart';
import 'profile_screen.dart';
import 'wellness_screen.dart';
import 'insights_screen.dart';
import 'pure_plate_screen.dart';
import 'zzzify_screen.dart';
import 'chronic_care_screen.dart';
import 'daily_checkin_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final ValueNotifier<int> _wellnessReloadSignal = ValueNotifier(0);
  final ValueNotifier<int> _insightsReloadSignal = ValueNotifier(0);

  /// Tabs are built once and reused, so rebuilding the shell never re-runs
  /// the build of Wellness, Insights or Profile.
  final Map<int, Widget> _tabCache = {};

  bool _initialLoading = true;

  late Quote currentQuote;
  final BluetoothService _bt = BluetoothService.instance;
  final BellaService _bella = BellaService();
  final Set<int> _visitedTabs = {0};
  final NotificationService _notifications = NotificationService.instance;
  bool _promptHidden = false;
  bool _bandIntroHidden = false;

  @override
  void initState() {
    super.initState();

    currentQuote = _pickQuote();

    _notifications.tapped.addListener(_onNotificationTap);
    BellaUserData.dataVersion.addListener(_onDataCleared);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onNotificationTap(); // app launched from a notification
      _notifications.refresh();
    });

    // The first band snapshot ends the skeleton early; otherwise it ends on
    // a timer, so a screen with no band never stays in "loading".
    BandMonitor.instance.snapshot.addListener(_onFirstBandSnapshot);

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _initialLoading = false);
    });
  }

  @override
  void dispose() {
    _notifications.tapped.removeListener(_onNotificationTap);
    BellaUserData.dataVersion.removeListener(_onDataCleared);
    BandMonitor.instance.snapshot.removeListener(_onFirstBandSnapshot);
    _wellnessReloadSignal.dispose();
    _insightsReloadSignal.dispose();
    super.dispose();
  }

  String get _userDisplayName {
    final user = UserService().currentUserObject;
    return user?.username ?? UserService().currentUser ?? 'User';
  }

  Quote _pickQuote() => WellnessQuoteService.getQuoteForState(
        lastCheckin: _bella.lastCheckin,
        lastSleep: _bella.lastNightSleep,
        avgSleepQuality: _bella.averageSleepQuality(),
        totalActivityMinutesToday: _bella.sessionMinutesToday('meditation') +
            _bella.sessionMinutesToday('walking') +
            _bella.sessionsToday('breathwork') * 5 +
            _bella.sessionMinutesToday('sleep_sounds'),
      );

  void _refreshFromBella() {
    if (!mounted) return;
    setState(() => currentQuote = _pickQuote());
    // What the user just logged changes which nudges still make sense today.
    _notifications.refresh();
  }

  /// The user wiped their logged data: tabs that cache what they loaded
  /// reload, and Home recomputes.
  void _onDataCleared() {
    _wellnessReloadSignal.value++;
    _insightsReloadSignal.value++;
    _refreshFromBella();
  }

  void _onFirstBandSnapshot() {
    if (_initialLoading &&
        mounted &&
        BandMonitor.instance.current.lastReadingAt != null) {
      setState(() => _initialLoading = false);
    }
  }

  /// Opens the screen a tapped notification is about.
  void _onNotificationTap() {
    final category = _notifications.tapped.value;
    if (category == null || !mounted) return;
    _notifications.tapped.value = null;
    switch (category) {
      case NotificationCategory.hydration:
        _push(const PurePlateScreen());
      case NotificationCategory.sleep:
        _push(const ZZZifyScreen());
      case NotificationCategory.checkin:
        _push(const DailyCheckinScreen());
      case NotificationCategory.movement:
      case NotificationCategory.streak:
        _switchTab(1);
    }
  }

  bool get _showNotificationPrompt {
    if (_promptHidden) return false;
    final prefs = _notifications.prefs;
    return !prefs.enabled && !prefs.promptDismissed;
  }

  Future<void> _enableNotifications() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _notifications.enable();
    if (!mounted) return;
    setState(() => _promptHidden = ok);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Nudges are on. You can fine-tune them in Profile.'
          : 'No problem. You can turn them on any time in Profile.'),
    ));
    if (!ok) await _dismissNotificationPrompt();
  }

  Future<void> _dismissNotificationPrompt() async {
    await _notifications.dismissPrompt();
    if (mounted) setState(() => _promptHidden = true);
  }

  String _timeOfDayGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String _heartRateStatusLabel(BandSnapshot band) {
    final live = band.liveHeartRate;
    if (live == null) {
      return band.heartRate == null
          ? 'No reading yet'
          : 'Last reading ${band.heartRate} bpm';
    }
    if (live > 100) return 'Elevated';
    if (live < 60) return 'Resting · low';
    return 'Resting · steady';
  }

  void _handleConnectPress() async {
    if (_bt.isConnected.value) {
      await _bt.disconnect();
      if (!mounted) return;
      SageFeedback.info(
          context, 'Your band is disconnected. Reconnect any time.');
    } else {
      _showDevicePicker();
    }
  }

  void _showDevicePicker() => showBandPicker(context);

  List<String> _flaggedConditionsToday() {
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    final flagged = <String>[];
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) continue;
      if (WellnessScoreService.isReadingFlagged(cond, readings.first)) {
        flagged.add(cond);
      }
    }
    return flagged;
  }

  String _chronicCareSubtitle() {
    final conditions = UserService().currentUserObject?.chronicDiseases ?? [];
    if (conditions.isEmpty) return 'Log & manage';

    int stalestDays = 0;
    String? stalestCondition;
    for (final cond in conditions) {
      final readings = _bella.getReadings(condition: cond);
      if (readings.isEmpty) {
        stalestDays = 999;
        stalestCondition = cond;
      } else {
        final d = DateTime.now().difference(readings.first.time).inDays;
        if (d > stalestDays) {
          stalestDays = d;
          stalestCondition = cond;
        }
      }
    }

    final flagged = _flaggedConditionsToday();
    if (flagged.isNotEmpty) {
      if (flagged.length == 1) return '${flagged.first} reading flagged';
      final label = flagged.length == 2
          ? '${flagged[0]} & ${flagged[1]}'
          : '${flagged.sublist(0, flagged.length - 1).join(', ')} & ${flagged.last}';
      return '$label flagged';
    }

    if (stalestDays == 999 && stalestCondition != null) {
      return 'No reading logged for $stalestCondition yet';
    }
    if (stalestDays >= 7 && stalestCondition != null) {
      return '$stalestCondition: ${stalestDays}d since last reading';
    }
    if (stalestDays >= 3 && stalestCondition != null) {
      return '$stalestCondition: log a reading soon';
    }

    final anyReading = conditions
        .any((cond) => _bella.getReadings(condition: cond).isNotEmpty);
    return anyReading ? 'Last reading in range' : 'Log & manage';
  }

  String _purePlateSubtitle() {
    final water = _bella.todayWaterMl();
    final foodCount = _bella.getFoodEntries(onDate: DateTime.now()).length;
    if (water == 0 && foodCount == 0) return 'Plan & hydrate';
    if (water > 0) return '${(water / 1000).toStringAsFixed(1)}L logged today';
    return '$foodCount meal${foodCount == 1 ? '' : 's'} logged';
  }

  String _zzzifySubtitle() {
    final last = _bella.lastNightSleep;
    if (last == null) return 'Track & wind down';
    final q = last.quality;
    if (q >= 4) return 'Last night: great sleep';
    if (q == 3) return 'Last night: decent sleep';
    return 'Last night: poor sleep';
  }

  String _checkinSubtitle() {
    if (_bella.hasCheckedInToday()) {
      final c = _bella.lastCheckin;
      if (c == null) return 'Checked in today';
      final score = c.wellbeingScore;
      if (score >= 7) return 'Feeling good today';
      if (score >= 4.5) return 'Feeling okay today';
      return 'Low wellbeing today';
    }
    return 'How are you?';
  }

  void _push(Widget screen) {
    Navigator.push(context, slideUpRoute(screen))
        .then((_) => _refreshFromBella());
  }

  void _switchTab(int i) {
    if (i == _currentIndex) return;
    setState(() {
      _currentIndex = i;
      _visitedTabs.add(i);
    });
    if (i == 0) _refreshFromBella();
    if (i == 1) _wellnessReloadSignal.value++;
    if (i == 2) _insightsReloadSignal.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SageColors.linen,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < 4; i++)
            TickerMode(
              enabled: i == _currentIndex,
              child: _visitedTabs.contains(i)
                  ? _buildTab(i)
                  : const SizedBox.shrink(),
            ),
        ],
      ),
      bottomNavigationBar: SageBottomNav(
        currentIndex: _currentIndex,
        onTap: _switchTab,
      ),
    );
  }

  Widget _buildTab(int index) {
    // The Home tab depends on this state, so it is rebuilt on purpose; the
    // others are created once and refresh through their reload signals.
    if (index == 0) return _buildDashboardTab();
    return _tabCache.putIfAbsent(index, () {
      switch (index) {
        case 1:
          return WellnessScreen(reloadSignal: _wellnessReloadSignal);
        case 2:
          return InsightsScreen(reloadSignal: _insightsReloadSignal);
        default:
          return const ProfileScreen();
      }
    });
  }

  Widget _buildDashboardTab() {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('sage', style: SageText.wordmark()),
                Semantics(
                  button: true,
                  label: 'Open profile',
                  child: InkResponse(
                    onTap: () => _switchTab(3),
                    radius: kSageMinTapTarget / 2,
                    child: SizedBox(
                      width: kSageMinTapTarget,
                      height: kSageMinTapTarget,
                      child: Center(
                        child: ExcludeSemantics(
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: SageColors.moss,
                            child: Text(
                              _userDisplayName.isNotEmpty
                                  ? _userDisplayName[0].toUpperCase()
                                  : '?',
                              style: SageText.label(color: SageColors.linen),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Good ${_timeOfDayGreeting()}, $_userDisplayName',
              style: SageText.caption().copyWith(fontSize: 13),
            ),
            const SizedBox(height: SageSpace.xs),
            Text('Health Sync Hub', style: SageText.headline()),
            const SizedBox(height: 20),

            // ── Hero card and metric tiles (or shimmers). Only this block
            // listens to the band.
            ValueListenableBuilder<BandSnapshot>(
              valueListenable: BandMonitor.instance.snapshot,
              builder: (context, band, _) => Column(
                children: [
                  if (_initialLoading)
                    const ShimmerHeroCard()
                  else
                    SageHeroCard(
                      isConnected: band.connected,
                      heartRate: band.liveHeartRate ?? 0,
                      subLabel: _heartRateStatusLabel(band),
                      onConnectPressed: _handleConnectPress,
                    ),
                  const SizedBox(height: 20),
                  if (_initialLoading)
                    Row(
                      children: const [
                        Expanded(child: ShimmerMetricTile()),
                        SizedBox(width: 10),
                        Expanded(child: ShimmerMetricTile()),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            icon: const Icon(Icons.directions_walk),
                            value: band.stepsToday?.toString() ?? '—',
                            label: 'Steps today',
                            onTap: () => _push(const BandHistoryScreen()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MetricTile(
                            icon: const Icon(Icons.local_fire_department),
                            value: band.caloriesEstimate?.toString() ?? '—',
                            label: 'Calories (est.)',
                            onTap: () => _push(const BandHistoryScreen()),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (!_initialLoading)
              ValueListenableBuilder<BandSnapshot>(
                valueListenable: BandMonitor.instance.snapshot,
                builder: (context, band, _) {
                  final firstTime = !band.everSeen &&
                      !_bandIntroHidden &&
                      !_bella.bandIntroDismissed;
                  return Padding(
                    padding: const EdgeInsets.only(top: SageSpace.lg),
                    child: firstTime
                        ? BandIntroCard(
                            onConnect: () => showBandPicker(context),
                            onDismiss: () async {
                              await _bella.dismissBandIntro();
                              if (mounted)
                                setState(() => _bandIntroHidden = true);
                            },
                          )
                        : const BandOfflineNotice(
                            featureName: 'Your wellness tools',
                            whatWorks: 'Meditation, breathwork, sleep sounds, '
                                'check-ins and all your logging work without it.',
                          ),
                  );
                },
              ),

            if (_showNotificationPrompt) ...[
              const SizedBox(height: 24),
              NotificationPromptCard(
                onEnable: _enableNotifications,
                onDismiss: _dismissNotificationPrompt,
              ),
            ],

            const SizedBox(height: 24),

            const SectionHeader(title: 'Daily care'),
            const SizedBox(height: 12),

            // ── Bella activity tiles
            if (_initialLoading)
              SizedBox(
                height: 132,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    ShimmerActivityTile(),
                    SizedBox(width: 12),
                    ShimmerActivityTile(),
                    SizedBox(width: 12),
                    ShimmerActivityTile(),
                  ],
                ),
              )
            else
              SizedBox(
                height: 132,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    WellnessActivityTile(
                      icon: Icons.water_drop_outlined,
                      title: 'PurePlate',
                      subtitle: _purePlateSubtitle(),
                      accent: SageColors.clay,
                      onTap: () => _push(const PurePlateScreen()),
                    ),
                    const SizedBox(width: 12),
                    WellnessActivityTile(
                      icon: Icons.nights_stay_outlined,
                      title: 'ZZZify',
                      subtitle: _zzzifySubtitle(),
                      accent: SageColors.moss,
                      onTap: () => _push(const ZZZifyScreen()),
                    ),
                    if ((UserService().currentUserObject?.chronicDiseases ?? [])
                        .isNotEmpty) ...[
                      const SizedBox(width: 12),
                      WellnessActivityTile(
                        icon: Icons.favorite_border,
                        title: 'Chronic Care',
                        subtitle: _chronicCareSubtitle(),
                        accent: SageColors.sage,
                        onTap: () => _push(const ChronicCareScreen()),
                      ),
                    ],
                    const SizedBox(width: 12),
                    WellnessActivityTile(
                      icon: Icons.mood_outlined,
                      title: 'Daily Check-in',
                      subtitle: _checkinSubtitle(),
                      accent: SageColors.amber,
                      onTap: () => _push(const DailyCheckinScreen()),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
            QuoteSection(
              text: currentQuote.text,
              author: currentQuote.author,
              onRefresh: _refreshFromBella,
            ),
          ],
        ),
      ),
    );
  }
}
