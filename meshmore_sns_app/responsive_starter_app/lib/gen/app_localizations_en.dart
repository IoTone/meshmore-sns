// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Meshmore SNS';

  @override
  String get appSubtitle => 'Mesh messaging over radio';

  @override
  String get tabDashboard => 'Dashboard';

  @override
  String get dashboardPinsTitle => 'Pinned';

  @override
  String get dashboardPinsEdit => 'Edit pins';

  @override
  String get dashboardPinsDone => 'Done';

  @override
  String get dashboardPinsMoveUp => 'Move up';

  @override
  String get dashboardPinsMoveDown => 'Move down';

  @override
  String get dashboardPinAdd => 'Pin to dashboard';

  @override
  String get dashboardPinRemove => 'Remove from dashboard';

  @override
  String get pinCoverageNone => 'No pings yet';

  @override
  String pinCoverageAnswered(int answered, int tried) {
    return '$answered of $tried answered';
  }

  @override
  String get tabChat => 'Chat';

  @override
  String get tabNodes => 'Nodes';

  @override
  String get tabMap => 'Map';

  @override
  String get tabDocs => 'Docs';

  @override
  String get tabSettings => 'Settings';

  @override
  String get tabAbout => 'About';

  @override
  String get dashboardPeersInRange => 'NODES IN RANGE';

  @override
  String dashboardKnownCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n known',
      one: '1 known',
      zero: '0 known',
    );
    return '$_temp0';
  }

  @override
  String dashboardKnownAndContacts(int n, String contacts) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n known',
      one: '1 known',
      zero: '0 known',
    );
    return '$_temp0 · contacts $contacts';
  }

  @override
  String dashboardMyPubkey(String hex) {
    return 'my pubkey · $hex';
  }

  @override
  String get dashboardPubkeyAwaiting => 'my pubkey · awaiting device';

  @override
  String get dashboardPubkeyHint =>
      'Tap to copy. This is what someone else needs to add you as a contact.';

  @override
  String get botTitle => 'Auto-reply bot';

  @override
  String get botSubtitle =>
      'Answers messages here automatically. Off by default.';

  @override
  String get botOnWire =>
      'Replies are sent with a [bot] prefix, so the person on the other end can tell a machine wrote them.';

  @override
  String get botRefusedPublicSlot => 'Not available on the public channel.';

  @override
  String get botRefusedPublicPsk =>
      'This channel still uses the public key, so it is public whatever its number. Give it a private key first.';

  @override
  String get botRefusedUnknownPsk =>
      'Waiting for the radio to send this channel\'s key.';

  @override
  String get botMode => 'Reply mode';

  @override
  String get botModeDeterministic => 'Deterministic';

  @override
  String get botModeRandom => 'Random';

  @override
  String get botModeDeterministicSub =>
      'The first matching rule always wins, so two runs can be compared.';

  @override
  String get botModeRandomSub =>
      'Picks among matching rules, replayable from the seed.';

  @override
  String get botSeed => 'Seed';

  @override
  String botBudget(int n) {
    return '$n replies left this window';
  }

  @override
  String botCounters(int r, int p, int s) {
    return 'received $r · replied $p · held back $s';
  }

  @override
  String get botResetCounters => 'Reset counters';

  @override
  String get botEditRules => 'Edit rules';

  @override
  String get botRulesTitle => 'Rulepack';

  @override
  String get botRulesRestore => 'Restore default';

  @override
  String botRulesErrors(int n) {
    return '$n line(s) could not be read and were skipped';
  }

  @override
  String get botRulesSave => 'Save';

  @override
  String get botFromBot => 'bot';

  @override
  String get dashboardRadio => 'RADIO';

  @override
  String get dashNervLink => 'Link';

  @override
  String get dashNervNode => 'Node';

  @override
  String get dashNervRegion => 'Region';

  @override
  String get dashContacts => 'CONTACTS';

  @override
  String get dashNervMesh => 'Mesh';

  @override
  String get dashNervKnown => 'Known';

  @override
  String get dashNervEvents => 'Events';

  @override
  String get dashHyperEmpty => 'Listening for nodes…';

  @override
  String get dashPeers => 'NODES';

  @override
  String get dashAgHudSignal => 'SIGNAL';

  @override
  String get dashAgHudTraffic => 'ch traffic';

  @override
  String get dashDrPopLink => 'LINK';

  @override
  String get dashReconNoContacts => 'No contacts in range';

  @override
  String dashAgHudOfKnown(String count) {
    return 'of $count known';
  }

  @override
  String get dashboardLocation => 'LOCATION';

  @override
  String get dashboardBattery => 'BATTERY';

  @override
  String get dashboardRecent => 'RECENT';

  @override
  String get dashboardNoActivity => 'No activity yet';

  @override
  String get dashboardAwaitingDevice => 'Waiting for the radio…';

  @override
  String get dashboardAwaitingDeviceLocation => 'Waiting for a location…';

  @override
  String get dashboardUnnamed => '(unnamed)';

  @override
  String get dashboardLocationNotSet => 'No location';

  @override
  String get dashboardLocationConfigure => 'CONFIGURE';

  @override
  String get statusLinked => 'LINKED';

  @override
  String get statusSyncing => 'SYNCING…';

  @override
  String get statusHandshaking => 'SYNCING…';

  @override
  String get statusReconnecting => 'RECONNECTING…';

  @override
  String get statusLinkLost => 'LINK LOST';

  @override
  String get statusOffline => 'OFFLINE';

  @override
  String get statusConnecting => 'CONNECTING…';

  @override
  String get linkChipLinked => 'LINKED';

  @override
  String get linkChipSync => 'SYNC';

  @override
  String get linkChipRetry => 'RETRY';

  @override
  String get linkChipFail => 'FAIL';

  @override
  String get linkChipScan => 'SCAN';

  @override
  String get linkChipOffline => 'OFFLINE';

  @override
  String linkChipSemantics(String state) {
    return 'Radio $state';
  }

  @override
  String get actionConnect => 'CONNECT';

  @override
  String get actionRetry => 'Retry';

  @override
  String get dashboardDevice => 'Device';

  @override
  String get deviceMgrTitle => 'DEVICE';

  @override
  String get deviceMgrNoPair => 'No device paired';

  @override
  String get deviceMgrStateConnected => 'CONNECTED';

  @override
  String get deviceMgrStateConnecting => 'CONNECTING…';

  @override
  String get deviceMgrStateReconnecting => 'RECONNECTING…';

  @override
  String get deviceMgrStateDisconnected => 'DISCONNECTED';

  @override
  String get deviceMgrStateFailed => 'FAILED';

  @override
  String get deviceMgrDisconnect => 'Disconnect';

  @override
  String get deviceMgrReconnect => 'Reconnect';

  @override
  String get deviceMgrForget => 'Forget';

  @override
  String get deviceMgrPick => 'PICK A DEVICE';

  @override
  String get deviceMgrScan => 'Scan';

  @override
  String get deviceMgrStopScan => 'Stop';

  @override
  String get deviceMgrScanHint =>
      'Tap Scan to look for nearby MeshCore devices. When two are in range, pick the one you want.';

  @override
  String deviceMgrScanFailed(String message) {
    return 'Scan failed: $message';
  }

  @override
  String get deviceMgrRecent => 'RECENTLY PAIRED';

  @override
  String get deviceMgrAgoNever => 'never';

  @override
  String get deviceMgrAgoNow => 'just now';

  @override
  String deviceMgrAgoMinutes(int n) {
    return '$n min ago';
  }

  @override
  String deviceMgrAgoHours(int n) {
    return '$n h ago';
  }

  @override
  String deviceMgrAgoDays(int n) {
    return '$n d ago';
  }

  @override
  String get deviceMgrPairNew => 'Pair a new radio';

  @override
  String get pairTitle => 'Pair a radio';

  @override
  String pairStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get pairPermissionTitle => 'Bluetooth permission';

  @override
  String get pairPermissionBody =>
      'The app needs Nearby devices to find your radio and talk to it. Nothing is paired yet.';

  @override
  String get pairPermissionAllow => 'Allow Bluetooth';

  @override
  String get pairPermissionOpenSettings => 'Open OS settings';

  @override
  String get pairAdapterTitle => 'Bluetooth is off';

  @override
  String get pairAdapterBody =>
      'Switch Bluetooth on to find your radio. This screen continues by itself once it is on.';

  @override
  String get pairAdapterUnsupported =>
      'This phone reports no usable Bluetooth adapter, so a radio cannot be paired here.';

  @override
  String get pairRetry => 'Try again';

  @override
  String get pairScanTitle => 'Looking for radios';

  @override
  String get pairScanBody =>
      'A radio advertises as MeshCore-<name>. Keep it switched on and within a metre or two of the phone.';

  @override
  String get pairScanning => 'Scanning…';

  @override
  String get pairStopScan => 'Stop';

  @override
  String get pairScanAgain => 'Scan again';

  @override
  String get pairNothingFound =>
      'No radio answered. Check that it is switched on, in range, and not already connected to another phone, then scan again.';

  @override
  String pairRssi(int rssi) {
    return 'RSSI $rssi';
  }

  @override
  String pairConnecting(String name) {
    return 'Connecting to $name…';
  }

  @override
  String get pairConnectingBody =>
      'If the radio shows a PIN, enter it on the phone when asked. Screenless radios use 123456.';

  @override
  String get pairConfirmTitle => 'Radio connected';

  @override
  String pairConfirmBody(String name) {
    return '$name answered, so the link and the protocol both work. This radio is now the one the app uses.';
  }

  @override
  String get pairConfirmNode => 'Node';

  @override
  String get pairConfirmFirmware => 'Firmware';

  @override
  String get pairConfirmUse => 'Use this radio';

  @override
  String get pairChooseAnother => 'Choose another radio';

  @override
  String get settingsHeading => 'App settings';

  @override
  String get settingsBackgroundTitle => 'Stay connected in background';

  @override
  String get settingsBackgroundOn => 'Messages arrive while the app is closed';

  @override
  String get settingsBackgroundOff => 'Messages arrive when you open the app';

  @override
  String get settingsTelemetryPoll => 'Gather node telemetry';

  @override
  String get settingsTelemetryPollOn =>
      'Politely polls contacts for temperature / altitude (a little OTA airtime)';

  @override
  String get settingsTelemetryPollOff =>
      'No telemetry requests sent; query a node manually from its detail';

  @override
  String get settingsLanguage => 'LANGUAGE';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageJapanese => '日本語';

  @override
  String get settingsSpeech => 'SPEECH';

  @override
  String get settingsSpeechOn =>
      'Text-to-speech ON · per-channel toggle in Chat';

  @override
  String get settingsSpeechOff =>
      'Text-to-speech OFF (default) · reads channel messages';

  @override
  String get settingsSpeechMuted =>
      'Speech is on but muted with the alert sounds.';

  @override
  String get settingsPermissions => 'Permissions';

  @override
  String get settingsPermissionsSubtitle =>
      'Bluetooth, notifications and location';

  @override
  String get termsTitle => 'Terms and privacy';

  @override
  String get termsLead =>
      'This app talks to a mesh radio. There is no account, no cloud and no analytics.';

  @override
  String get termsSectionLocal => 'WHAT STAYS ON THIS DEVICE';

  @override
  String get termsLocalBody =>
      'Messages, contacts, channels, settings and the trail you record are stored on this device. Cloud backup and device transfer are switched off for the app\'s own data, so a new phone does not silently inherit it. Deleting the app deletes that data.';

  @override
  String get termsSectionLeaves => 'WHAT LEAVES THE DEVICE';

  @override
  String get termsLeavesBody =>
      'Nothing leaves except what you send: messages and positions go out over the radio you are connected to. Online map packs are off by default and are fetched only after you turn them on, with the source named on screen. Files you export are yours to place.';

  @override
  String get termsSectionPermissions => 'PERMISSIONS AND WHY';

  @override
  String get termsPermissionsBody =>
      'Bluetooth connects to the radio. Location is used for your own position and, on older Android, to allow a Bluetooth scan. Notifications are used for messages that arrive while the app is in the background. Refusing any of them leaves the app usable without a radio.';

  @override
  String get termsSectionRetention => 'HOW MUCH IS KEPT';

  @override
  String termsRetentionBody(int cap) {
    return 'Each conversation keeps its newest $cap messages; older ones are dropped. A place expires when its own timer runs out, and is then gone.';
  }

  @override
  String get termsSectionChanges => 'CHANGES';

  @override
  String get termsChangesBody =>
      'If this text changes in a way that matters, the version below changes and this page is shown again before the app opens.';

  @override
  String termsVersion(int version) {
    return 'Version $version';
  }

  @override
  String get termsGateNote => 'Agreeing is required to use the app.';

  @override
  String get termsExit => 'Exit';

  @override
  String get termsAccept => 'Agree and continue';

  @override
  String termsAcceptedVersion(int version) {
    return 'You agreed to version $version.';
  }

  @override
  String get termsNotAccepted => 'Not agreed.';

  @override
  String get termsSettingsRow => 'Terms and privacy';

  @override
  String get termsSettingsSubtitle =>
      'What is stored, what leaves the device, and why each permission is asked for';

  @override
  String get aboutCopyright => 'Copyright (c) 2026 IoTone, Inc.';

  @override
  String get aboutSubtitleEn => '(Socialrobot Network Service)';

  @override
  String get aboutSubtitleJa => '(ソーシャルロボット・ネットワークサービス)';

  @override
  String get aboutDescription => 'A MeshCore companion client.';

  @override
  String get aboutLicense => 'Licensed under the MIT (X11) License.';

  @override
  String get aboutMadeWith => 'Made with ♥ in Fukuoka, Japan';

  @override
  String aboutVersion(String version) {
    return 'v$version';
  }

  @override
  String get aboutReportProblem => 'Report a problem';

  @override
  String get aboutReportProblemSub =>
      'Opens the issue tracker with the app and radio details filled in. Nothing is sent unless you send it there.';

  @override
  String get aboutLicensesButton => 'Open-source licenses & attributions';

  @override
  String get aboutAttributions =>
      'Includes MeshCore documentation (MIT), GeoNames cities (CC-BY 4.0), Natural Earth (public domain), OpenStreetMap map data (ODbL), and the Saira & JetBrains Mono fonts (OFL).';

  @override
  String get personalizationHeading => 'Profile & personalization';

  @override
  String get personalizationThemePreset => 'THEME PRESET';

  @override
  String get personalizationType => 'TYPE';

  @override
  String get personalizationFontSize => 'Font size';

  @override
  String get personalizationAccessibility => 'ACCESSIBILITY';

  @override
  String get personalizationHighContrast => 'High contrast';

  @override
  String get personalizationHighContrastSubtitle =>
      'Use the high-contrast colours';

  @override
  String get personalizationHighContrastHint =>
      'High contrast overrides the skin you pick.';

  @override
  String get personalizationReduceMotion => 'Reduce motion';

  @override
  String get personalizationVisualHapticOnly => 'Visual + haptic only';

  @override
  String get personalizationVisualHapticOnlySubtitle =>
      'Alerts by vibration only';

  @override
  String get personalizationAudioAlerts => 'AUDIO ALERTS';

  @override
  String get personalizationAudioMaster => 'Audio alerts';

  @override
  String get personalizationAudioMasterDisabled =>
      'Disabled by \"visual + haptic only\"';

  @override
  String get personalizationAudioMasterEnabled =>
      'On by default; augmentation only';

  @override
  String get dashboardAudioMute => 'Mute alert sounds';

  @override
  String get dashboardAudioUnmute => 'Unmute alert sounds';

  @override
  String get demoBanner => 'DEMO';

  @override
  String get demoTooltip =>
      'Demo mode — no radio. Explore channels, settings and docs without a companion.';

  @override
  String get demoModeRow => 'No radio';

  @override
  String get demoModeSubtitle => 'Explore the app offline';

  @override
  String get firstRunHeader => 'MESHMORE · WELCOME';

  @override
  String get firstRunTitle => 'What this app will ask for';

  @override
  String get firstRunBleTitle => 'Bluetooth';

  @override
  String get firstRunBleBody =>
      'To pair with your MeshCore radio and exchange messages over the local mesh. Required to send / receive over the air.';

  @override
  String get firstRunNotificationsTitle => 'Notifications';

  @override
  String get firstRunNotificationsBody =>
      'We ask later, only if you keep the app connected in the background.';

  @override
  String get firstRunOfflineTitle => 'Offline is fine';

  @override
  String get firstRunOfflineBody =>
      'Without Bluetooth the app opens in demo mode: history, channels, settings and docs, with no radio traffic.';

  @override
  String get firstRunGrant => 'Allow Bluetooth';

  @override
  String get firstRunSkip => 'Explore in demo mode (no radio)';

  @override
  String get firstRunDeniedTransient =>
      'Bluetooth is off for this app. Continue offline, or allow it in Settings.';

  @override
  String get firstRunDeniedPermanent =>
      'Bluetooth is blocked for this app. Allow it in Settings, or keep using the app offline.';

  @override
  String get firstRunOpenSettings => 'Open OS settings';

  @override
  String dashboardPaired(String name) {
    return 'paired: $name';
  }

  @override
  String get dashboardCharging => 'CHARGING';

  @override
  String dashboardBatteryReadout(String volts, int percent) {
    return '${volts}V · ~$percent%';
  }

  @override
  String dashboardBatteryLeft(String time) {
    return '~$time left';
  }

  @override
  String get nodesScanArea => 'Scan area';

  @override
  String get nodesScanning => 'Scanning…';

  @override
  String get nodesAdvertise => 'Advertise';

  @override
  String get nodesSyncContacts => 'Sync contacts';

  @override
  String get nodesFloodAdvert => 'Flood advert';

  @override
  String get nodesFloodAdvertBody =>
      'Whole mesh — neighbours + repeaters. Best for discovery.';

  @override
  String get nodesZeroHopAdvert => 'Direct advert';

  @override
  String get nodesZeroHopAdvertBody =>
      'Direct neighbours only — not rebroadcast. Quieter on a busy mesh.';

  @override
  String get nodesFloodAdvertSent =>
      'Flood advert sent — propagates across the whole mesh (neighbours + repeaters). The other node must Advertise too before it appears here.';

  @override
  String get nodesZeroHopAdvertSent => 'Sent to radios in direct range only.';

  @override
  String get nodesSearchHint => 'Search by name, shortId, or pubkey…';

  @override
  String get nodesFilterStarred => 'Starred';

  @override
  String get nodesFilterInRange => 'In range';

  @override
  String get nodesFilterClear => 'Clear';

  @override
  String get nodesFiltersTitle => 'Filters';

  @override
  String get nodesFilterLastSeenTitle => 'Last seen';

  @override
  String get nodesFilterWithinTitle => 'Within';

  @override
  String get nodesFiltersDone => 'Done';

  @override
  String get nodesTagFilter => 'Tags';

  @override
  String get nodesAgeAny => 'Any';

  @override
  String get nodesAgeHour => 'Last hour';

  @override
  String get nodesAge24h => 'Last 24 h';

  @override
  String get nodesAge7d => 'Last 7 d';

  @override
  String get nodesDistAny => 'Any';

  @override
  String get nodesDist100m => '≤ 100 m';

  @override
  String get nodesDist500m => '≤ 500 m';

  @override
  String get nodesDist5km => '≤ 5 km';

  @override
  String get nodesDist25km => '≤ 25 km';

  @override
  String nodesStatusReady(int shown, int total, int inRange, int favs) {
    String _temp0 = intl.Intl.pluralLogic(
      favs,
      locale: localeName,
      other: '$favs contacts',
      one: '1 contact',
      zero: '0 contacts',
    );
    return '$shown of $total shown · $inRange in range · $_temp0';
  }

  @override
  String get nodesStatusOffline =>
      'Not connected — Settings → Diagnostics & connect';

  @override
  String get nodesFarBadge => 'FAR';

  @override
  String get nodesEmptyFiltered => 'No nodes match this filter.';

  @override
  String get nodesEmptyReady =>
      'No nodes yet. A node appears once it announces itself.';

  @override
  String get nodesEmptyOffline => 'Connect a radio to discover nearby nodes.';

  @override
  String get nodesFavTooltip => 'Add to favourites';

  @override
  String get nodesUnfavTooltip => 'Remove from favourites';

  @override
  String get gridTitle => 'Hyperlocal grid';

  @override
  String get gridShowLegend => 'Show legend';

  @override
  String get gridHideLegend => 'Hide legend';

  @override
  String get gridPlayTooltip => 'Play (refresh every interval)';

  @override
  String get gridPauseTooltip => 'Pause updates';

  @override
  String get gridIntervalTooltip => 'Refresh interval (when playing)';

  @override
  String get gridRange => 'Range';

  @override
  String get gridRangeRoom => 'Room';

  @override
  String get gridRangeHome => 'Home';

  @override
  String get gridRangeBlock => 'Block';

  @override
  String get gridRangeNeighborhood => 'Neighborhood';

  @override
  String get gridRangeArea => 'Area';

  @override
  String get gridRangeWide => 'Wide';

  @override
  String get gridRangeCity => 'City';

  @override
  String get gridRangeRegion => 'Region';

  @override
  String get gridLegend => 'LEGEND';

  @override
  String gridLegendRings(String value) {
    return 'Rings are distance bands. With GPS at both ends the outer ring is the Range scale above (about $value now). Without GPS they are signal bands: near, mid, far.';
  }

  @override
  String get gridLegendSelf =>
      'Centre marker = you. Cross-hair = N-S / E-W guide.';

  @override
  String get gridLegendDot =>
      'A dot is a node we have heard. Brighter means more recent; it fades out over a day.';

  @override
  String get gridLegendKnown =>
      'A slow growing halo is a node we have messaged directly.';

  @override
  String get gridLegendFavourite =>
      'Rapid blink in alt-colour = a favourited node.';

  @override
  String get gridLegendRipple =>
      'A ripple from the centre is a channel message from someone we cannot name.';

  @override
  String get gridLegendTap =>
      'Tap a node to see details + Message / Favourite.';

  @override
  String get gridViewRadial => 'Radial';

  @override
  String get gridViewGlobe => 'Globe';

  @override
  String get gridViewEqualGrid => 'Equal grid';

  @override
  String get gridViewPicker => 'View';

  @override
  String get gridViewFabric => 'Mesh survey';

  @override
  String get gridViewElevation => 'Altitude';

  @override
  String get fujiLegendTitle => 'FUJIさん';

  @override
  String get fujiLegendDesc =>
      'Altitude survey. Heights on a √-scaled axis against famous landmarks. Your device\'s altitude comes from device GPS telemetry or the phone fix.';

  @override
  String get fujiLegendMe =>
      'Dashed line = you. At your altitude, or pinned to the ground with ALT? until it resolves.';

  @override
  String get fujiLegendRefs =>
      'Silhouettes = real-world references (person → Mt Fuji) for scale.';

  @override
  String get fujiLegendPeers =>
      'Dots are nodes, plotted at their altitude once asked.';

  @override
  String get fujiLegendUnknown =>
      'A striped band along the ground is a node with no altitude yet.';

  @override
  String get fujiLegendAutoQuery =>
      'The auto-query box asks for altitudes slowly. Tap it to start again.';

  @override
  String get elevationProfileTitle => 'MESHMORE :: FUJIさん';

  @override
  String get elevationProfileAltLabel => 'Altitude';

  @override
  String get elevationProfileMeLabel => 'Me';

  @override
  String get elevationProfileUnknownLabel => 'altitude unknown';

  @override
  String elevationProfilePeers(int n) {
    return '$n nodes tracked';
  }

  @override
  String get elevationRefPerson => 'Human';

  @override
  String get elevationRefHouse => 'House';

  @override
  String get elevationRefRedwood => 'Redwood';

  @override
  String get elevationRefEmpireState => 'Empire State';

  @override
  String get elevationRefBurj => 'Burj Khalifa';

  @override
  String get elevationRefMtFuji => 'Mt Fuji';

  @override
  String fabricCoverageCount(int n) {
    return 'MESH SURVEY · $n CELLS';
  }

  @override
  String get fabricResetTooltip => 'Reset coverage';

  @override
  String get fabricResetTitle => 'Reset mesh-coverage survey?';

  @override
  String get fabricResetBody =>
      'Drops every recorded cell. New observations will start filling the map again as you move and the mesh reports nearby nodes.';

  @override
  String get fabricResetApply => 'Reset';

  @override
  String get streetMapRecenter => 'Re-centre on me';

  @override
  String get mapNoFixBanner =>
      'No position fix yet. This is a world view, not centred on you.';

  @override
  String mapPackZoomOutside(int min, int max) {
    return 'This pack covers zoom $min to $max. Coarser tiles stand in outside that range.';
  }

  @override
  String get mapHideTiles => 'Hide map tiles';

  @override
  String get mapShowTiles => 'Show map tiles';

  @override
  String deviceRegionLoadedOffline(String label) {
    return '$label loaded — Apply when a device is connected.';
  }

  @override
  String get equalGridAwaitingFix =>
      'Equal-grid view needs your own location — waiting for a GPS fix (phone or device).';

  @override
  String equalGridCellSize(String size) {
    return 'CELL $size';
  }

  @override
  String get equalGridZoomIn => 'Zoom in (tighter cells)';

  @override
  String get equalGridZoomOut => 'Zoom out (wider cells)';

  @override
  String get equalGridShowStats => 'Show targeting panel';

  @override
  String get equalGridHideStats => 'Hide targeting panel';

  @override
  String globeFooter(int n) {
    return 'Showing $n nodes with a known location';
  }

  @override
  String get globeOverlayArcs => 'arcs';

  @override
  String get globeOverlayRegion => 'region';

  @override
  String get globeOverlayLabels => 'labels';

  @override
  String get globeAltitude => 'ALT';

  @override
  String get globePaused => 'PAUSED';

  @override
  String get voiceOfflineBadge => 'OFFLINE';

  @override
  String get dashboardLocationRefresh => 'Refresh location from device';

  @override
  String dashboardLocationAltitude(int meters) {
    return 'alt $meters m';
  }

  @override
  String get deviceLocReportsAwaiting => 'Device reports: (awaiting)';

  @override
  String get deviceLocReportsNone => 'Device reports: no GPS fix (0, 0)';

  @override
  String deviceLocReportsValue(String lat, String lon) {
    return 'Device reports: $lat, $lon';
  }

  @override
  String get deviceLocUnsaved => '✱ unsaved';

  @override
  String get deviceGpsModule => 'ON-BOARD GPS MODULE';

  @override
  String get deviceGpsEnable => 'Enable on-board GPS';

  @override
  String get deviceGpsEnabledHint =>
      'Device firmware polls its GPS chip and updates location automatically.';

  @override
  String get deviceGpsDisabledHint =>
      'Off. The radio does not read its GPS, so it keeps announcing the last position set.';

  @override
  String get deviceGpsUnknown => 'Waiting for device…';

  @override
  String get deviceGpsInterval => 'GPS update interval';

  @override
  String get deviceGpsIntervalOff => 'Off';

  @override
  String deviceGpsIntervalSec(int n) {
    return 'Every $n s';
  }

  @override
  String deviceGpsIntervalMin(int n) {
    return 'Every $n min';
  }

  @override
  String deviceGpsIntervalHour(int n) {
    return 'Every $n h';
  }

  @override
  String get deviceGpsIntervalFixedByFirmware => 'Set on the radio';

  @override
  String get locTitle => 'Auto-publish location';

  @override
  String get locTileSubtitle => 'Sends the phone\'s position to the radio';

  @override
  String get deviceGpsIntervalWhy =>
      'This firmware build decides how often the sensors are read, so the app cannot change it.';

  @override
  String get locMaster => 'Auto-publish';

  @override
  String get locMasterOn => 'On — using phone GPS';

  @override
  String get locMasterOff => 'Off';

  @override
  String get locInterval => 'Periodic interval';

  @override
  String get locMovement => 'Smart broadcast (on movement)';

  @override
  String get locOff => 'Off';

  @override
  String locIntervalMin(int n) {
    return 'Every $n min';
  }

  @override
  String locIntervalHour(int n) {
    return 'Every $n h';
  }

  @override
  String locMovementM(int m) {
    return '$m m';
  }

  @override
  String locMovementKm(int km) {
    return '$km km';
  }

  @override
  String get locPublishNow => 'Publish now';

  @override
  String get locPublishNowSub => 'One-shot manual push to verify the loop.';

  @override
  String locLastPublished(String lat, String lon, String time, String trigger) {
    return 'Last: $lat, $lon  ·  $time  ·  $trigger';
  }

  @override
  String get locBeacon => 'Periodic position beacon';

  @override
  String get locBeaconSub =>
      'Every 60 s, send your position. Uses airtime and battery.';

  @override
  String get locBatteryHint =>
      'Streaming GPS reacts faster and uses more battery.';

  @override
  String get gridEmpty =>
      'No nodes in range yet.\n\nA node appears once it announces itself.';

  @override
  String get gridStatusOffline =>
      'Not connected — Settings → Diagnostics & connect';

  @override
  String get gridSwipeModeTooltip =>
      'Swipe mode: swipe left/right for other screens. Tap to pan and zoom this map';

  @override
  String get gridPanModeTooltip =>
      'Pan & zoom mode: drags move the map. Tap to swipe between screens again';

  @override
  String gridStatusCounts(int visible, int known, int favs) {
    String _temp0 = intl.Intl.pluralLogic(
      favs,
      locale: localeName,
      other: '$favs contacts',
      one: '1 contact',
      zero: '0 contacts',
    );
    return '$visible shown · $known known · $_temp0';
  }

  @override
  String get gridNotConnected => 'Not Connected to Mesh';

  @override
  String get voiceSettingsTitle => 'Voice (TTS quality)';

  @override
  String get voiceSettingsHint =>
      'Off until you turn on SPEECH in App settings. Rate / pitch / voice take effect on the next utterance.';

  @override
  String get voiceRate => 'Speed';

  @override
  String get voicePitch => 'Pitch';

  @override
  String get voicePicker => 'Voice';

  @override
  String get voicePickerEmpty =>
      'No voices reported by the platform engine — using the system default.';

  @override
  String get voicePickerOnlyMyLanguage => 'Only show my language';

  @override
  String voicePickerOnlyMyLanguageHint(String lang) {
    return 'Limits the list to voices matching the phone\'s current language ($lang). Turn off to see every voice the OS reports.';
  }

  @override
  String voicePickerFilteredCount(int n, String lang) {
    return '$n · $lang';
  }

  @override
  String voicePickerAllCount(int n) {
    return '$n · ALL';
  }

  @override
  String voicePickerNoMatchForLanguage(String lang) {
    return 'No voices installed for $lang. Turn off the filter above to see other languages, or install a $lang voice in your OS settings.';
  }

  @override
  String get voicePickerSystem => 'System default';

  @override
  String get voicePreview => 'Try a phrase';

  @override
  String get voicePreviewPhrase => 'This is a Meshmore SNS voice preview.';

  @override
  String get voicePreviewDisabledHint =>
      'Turn on SPEECH in App settings to audition a phrase.';

  @override
  String get settingsHubDevice => 'Device configuration';

  @override
  String get settingsGroupRadio => 'RADIO';

  @override
  String get settingsGroupApp => 'APP';

  @override
  String get settingsGroupConnect => 'CONNECTION';

  @override
  String get settingsGroupAbout => 'ABOUT';

  @override
  String get settingsHubApp => 'App settings';

  @override
  String get settingsHubProfile => 'Profile & personalization';

  @override
  String get settingsHubChannels => 'Channels';

  @override
  String get settingsHubDiagnostics => 'Diagnostics & connect';

  @override
  String get bootHeader => 'MESHMORE  /  SYNCHRONIZING';

  @override
  String get bootConnecting => 'CONNECTING TO RADIO…';

  @override
  String get bootHandshaking => 'HANDSHAKING…';

  @override
  String get bootReady => 'MESH ONLINE';

  @override
  String get bootOffline => 'OFFLINE — Settings → Diagnostics & connect';

  @override
  String get bootSkip => 'SKIP';

  @override
  String get bootSubtitle => 'WAIT  /  進行中';

  @override
  String eventAdvert(String name) {
    return 'advert · $name';
  }

  @override
  String eventChannelMsg(String channel, String text) {
    return 'ch$channel · \"$text\"';
  }

  @override
  String eventDm(String text) {
    return 'dm · \"$text\"';
  }

  @override
  String eventContact(String name) {
    return 'contact · $name';
  }

  @override
  String eventBattery(String volts) {
    return 'battery ${volts}V';
  }

  @override
  String eventDeviceError(String code) {
    return 'device error (code $code)';
  }

  @override
  String get eventDeviceClockSynced => 'device clock in sync';

  @override
  String eventDeviceClockSkew(String seconds) {
    return 'device clock read (offset ${seconds}s)';
  }

  @override
  String eventMsgSent(String ack) {
    return 'sent (confirmed by $ack)';
  }

  @override
  String eventDeviceInfo(String version) {
    return 'device $version';
  }

  @override
  String eventSelfInfo(String name) {
    return 'self-info · $name';
  }

  @override
  String get eventQueuedWaiting => 'queued items waiting';

  @override
  String eventQueuedWaitingN(String count) {
    return 'queued items waiting ($count)';
  }

  @override
  String get chatManageChannels => 'Manage channels';

  @override
  String get chatTtsMuted => 'TTS muted for this channel';

  @override
  String get chatTtsActive => 'TTS reading this channel';

  @override
  String chatRetentionDropped(int count, int cap) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count older messages are gone',
      one: '1 older message is gone',
    );
    return '$_temp0 — each conversation keeps its newest $cap';
  }

  @override
  String get chatHistoryUnreadableTitle =>
      'History cannot be opened on this device';

  @override
  String get chatHistoryUnreadableBody =>
      'The messages are still saved here. They were sealed with a key this phone no longer has, so they cannot be read until they are restored from an encrypted export.';

  @override
  String get diagnosticsHistoryStore => 'History store';

  @override
  String get diagnosticsHistoryStoreOk => 'sealed and readable';

  @override
  String get diagnosticsHistoryStoreKeyLost =>
      'sealed, but the key is gone from this device';

  @override
  String diagnosticsHistoryStoreWriteFailed(String code) {
    return 'last write did not reach the store ($code)';
  }

  @override
  String get chatHistoryRestoreAction => 'Restore from an export';

  @override
  String get chatRestoreMenu => 'Restore from export…';

  @override
  String get chatRestoreNothing =>
      'Open the export file with this app, or share it here, and then run restore again.';

  @override
  String get chatRestoreTitle => 'Restore a conversation';

  @override
  String get chatRestorePassphrase => 'Passphrase for the export';

  @override
  String get chatRestoreConfirm => 'Restore';

  @override
  String chatRestoreDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages restored',
      one: '1 message restored',
    );
    return '$_temp0';
  }

  @override
  String get chatRestoreFailed =>
      'That file could not be opened with that passphrase, or it is not an export.';

  @override
  String get chatEmpty => '— no messages on this channel —';

  @override
  String chatJumpToNewest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new',
      one: '1 new',
    );
    return '$_temp0';
  }

  @override
  String chatComposerHint(String channel) {
    return 'Message $channel';
  }

  @override
  String get chatComposerOffline => 'Connect a radio to send';

  @override
  String get chatSend => 'Send';

  @override
  String chatBudgetRemaining(int remaining, int max) {
    return '$remaining of $max bytes left';
  }

  @override
  String chatBudgetEstimate(int remaining, int max) {
    return 'about $remaining of $max bytes left — the radio\'s name is not known yet';
  }

  @override
  String get chatBudgetNear =>
      'Nearly at the limit: the radio counts its own name in these bytes';

  @override
  String chatBudgetTooLong(int over) {
    return 'Too long by $over bytes — the radio would cut the rest without telling you';
  }

  @override
  String get chatMessageActions => 'Message actions';

  @override
  String get chatSinceNow => 'now';

  @override
  String chatSinceMinutes(int m) {
    return '${m}m';
  }

  @override
  String chatSinceHours(int h) {
    return '${h}h';
  }

  @override
  String chatSinceDays(int d) {
    return '${d}d';
  }

  @override
  String dmTitle(String peer) {
    return 'Direct · $peer';
  }

  @override
  String dmPubkeyLabel(String hex) {
    return 'pubkey · $hex';
  }

  @override
  String get nodeDetailSignature => 'Message sound';

  @override
  String get nodeDetailSignatureHint =>
      'Plays for messages from this person instead of the usual sound.';

  @override
  String get nodeDetailSignatureNone => 'Default';

  @override
  String nodeDetailSignatureSlot(int n) {
    return 'Sound $n';
  }

  @override
  String get nodeDetailSignatureMutedHint =>
      'Audio is muted — you will feel the vibration but not hear it.';

  @override
  String get dmEmpty => '— no messages yet —';

  @override
  String get dmOpenPeerDetail => 'Contact details';

  @override
  String get dmSpeech => 'Read this conversation aloud';

  @override
  String get dmSpeechInherit => 'Follow global speech setting';

  @override
  String get dmSpeechAlways => 'Always speak';

  @override
  String get dmSpeechNever => 'Never speak';

  @override
  String get dmSpeechMutedByMaster => 'Silenced by the audio mute';

  @override
  String get dmPeerNotInFabric =>
      'This person has not been heard on the mesh yet.';

  @override
  String dmComposerHint(String peer) {
    return 'Message $peer';
  }

  @override
  String get dmSend => 'Send DM';

  @override
  String get actionRetrySub => 'Send this message again';

  @override
  String get actionReply => 'Reply';

  @override
  String get actionReplySub => 'Quote this message in your reply';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionCopySub => 'Copy the message text to the clipboard';

  @override
  String get actionDeleteLocal => 'Delete locally';

  @override
  String get actionDeleteLocalSub =>
      'Removes this row from your history only — over-the-air messages cannot be recalled.';

  @override
  String get actionCopied => 'Copied to clipboard';

  @override
  String get actionDeleteConfirmTitle => 'Delete this message locally?';

  @override
  String get actionDeleteConfirmBody =>
      'This removes the row from your local history. MeshCore has no recall — the recipient still has it.';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get nodeDetailSelf =>
      'This is your own node — no Message / Favourite.';

  @override
  String get nodeDetailShareTelemetryTitle =>
      'Share my telemetry with this contact';

  @override
  String get nodeDetailShareTelemetryHelp =>
      'Only applies when your telemetry mode is Contacts and Base is on.';

  @override
  String get nodeDetailRecentDms => 'RECENT DMS';

  @override
  String get nodeDetailMessage => 'Message';

  @override
  String get nodeIdentityTitle => 'Contact key changed';

  @override
  String nodeIdentityBody(String name, int count) {
    return '“$name” is active under a new key — likely deleted and re-added on their device. Move your star, tags, and $count saved messages to the current key?';
  }

  @override
  String nodeIdentityOldKey(String shortId) {
    return 'Old key …$shortId';
  }

  @override
  String get nodeIdentityAction => 'Move to current key';

  @override
  String nodeIdentityMoved(String name) {
    return 'Moved your data to “$name”’s current key';
  }

  @override
  String get nodeIdentityLinkAction => 'New key: link this contact';

  @override
  String get nodeIdentityLinkTitle => 'Link a changed key';

  @override
  String get nodeIdentityLinkHelp =>
      'Same contact, new key. Pick the node or paste the key; your star, tags and messages move over.';

  @override
  String get nodeIdentityLinkEmpty =>
      'No other nodes yet. Wait for the new key to advertise, or paste it.';

  @override
  String get nodeIdentityLinkSearchHint =>
      'Filter by name, or paste a public key';

  @override
  String get nodeIdentityLinkNoMatch =>
      'No nodes match — clear the search, or paste the full key to link directly.';

  @override
  String get nodeIdentityLinkUseKey => 'Link to this key';

  @override
  String get nodeDetailNotDeviceContact =>
      'Not in your radio\'s contact list, so DMs may not route. Channels still work.';

  @override
  String get nodeDetailAddDeviceContact => 'Add to device contacts';

  @override
  String get nodeDetailAddDeviceContactDone =>
      'Added. DMs will route now. If they don\'t, your contact list may be full.';

  @override
  String get nodeDetailAddDeviceContactFailed =>
      'Couldn\'t add the contact — check the link and try again.';

  @override
  String get nodeDetailRemoveDeviceContact => 'Remove from device contacts';

  @override
  String nodeDetailRemoveDeviceContactConfirm(String name) {
    return 'Remove “$name” from the radio\'s contacts? You can add them again later.';
  }

  @override
  String get nodeDetailRemoveDeviceContactDone =>
      'Removed from your radio\'s contacts.';

  @override
  String get deviceContactsTitle => 'Radio contacts';

  @override
  String get deviceContactsRefresh => 'Refresh';

  @override
  String get deviceContactsSyncing => 'Syncing contacts from the radio…';

  @override
  String get deviceContactsEmpty => 'Your radio has no contacts.';

  @override
  String deviceContactsCount(int count, int max) {
    return '$count of $max contacts on the radio';
  }

  @override
  String deviceContactsCountOnly(int count) {
    return '$count contacts on the radio';
  }

  @override
  String get deviceContactsFullHelp =>
      'Contact list is full. Remove entries below to add new ones.';

  @override
  String get deviceContactsChannelsNote =>
      'You only need a contact to send a direct message. Channel messages work without contacts — you\'ll still see everyone on channels.';

  @override
  String get deviceContactsScrub => 'Scrub contacts';

  @override
  String get deviceContactsRemoveOutOfRange => 'Remove out of range';

  @override
  String get deviceContactsOutOfRangeIntro =>
      'Removes contacts far away, and those that do not share a position. Favourites and known contacts are kept.';

  @override
  String deviceContactsBeyondKm(int km) {
    return 'Beyond $km km (+ location-hidden)';
  }

  @override
  String get deviceContactsNeedLocation =>
      'No location set, so distance can\'t be measured — only location-hidden contacts are caught. Set your position (GPS or a manual pin) to also remove far-away GPS contacts.';

  @override
  String deviceContactsRemoveOutOfRangeDone(int count) {
    return 'Removed $count out-of-range contacts.';
  }

  @override
  String get deviceContactsRemoveStale => 'Remove not heard recently';

  @override
  String get deviceContactsStaleIntro =>
      'Removes contacts you haven\'t heard from in a while. Favourites and known contacts are kept.';

  @override
  String deviceContactsNotHeardDays(int days) {
    return 'Not heard in $days days';
  }

  @override
  String deviceContactsRemoveStaleDone(int count) {
    return 'Removed $count stale contacts.';
  }

  @override
  String get deviceContactsRemoveAll => 'Remove all';

  @override
  String deviceContactsRemoveAllConfirm(int count) {
    return 'Remove all $count contacts? You only need them to send direct messages, and you can add anyone back later.';
  }

  @override
  String deviceContactsRemoveAllDone(int count) {
    return 'Removed $count contacts from the radio.';
  }

  @override
  String get deviceContactsFlood => 'flood';

  @override
  String get deviceContactsDirect => 'direct';

  @override
  String deviceContactsHops(int n) {
    return '$n hops';
  }

  @override
  String nodeIdentityLinkConfirm(String from, String to) {
    return 'Move star, tags, and messages from “$from” to “$to”, and retire the old key?';
  }

  @override
  String get nodeDetailFavourite => 'Favourite';

  @override
  String get nodeDetailContact => 'Favourited';

  @override
  String get nodeDetailShowOnMap => 'Show on geocoded map';

  @override
  String get nodeDetailShowOnMapFailed => 'Couldn\'t open the maps app.';

  @override
  String get nodeDetailCopyPubkey => 'Copy full pubkey';

  @override
  String get nodeDetailPubkeyCopied => 'Pubkey copied';

  @override
  String get nodeDetailTags => 'TAGS';

  @override
  String get nodeDetailAddTag => 'tag';

  @override
  String get nodeDetailAddTagTitle => 'Add tag';

  @override
  String get nodeDetailAddTagHint => 'e.g. repeater, work, ham-club';

  @override
  String get nodeDetailAddTagSuggestions => 'RECENTLY USED';

  @override
  String get nodeDetailAddTagApply => 'Add';

  @override
  String get nodeDetailInRange => 'IN RANGE';

  @override
  String get nodeDetailKnown => 'KNOWN';

  @override
  String get nodeDetailContactBadge => 'FAVOURITE';

  @override
  String get nodeDetailShortIdKv => 'shortId';

  @override
  String get nodeDetailPubkeyKv => 'pubkey';

  @override
  String get nodeDetailSignalKv => 'signal';

  @override
  String get nodeDetailLastHeardKv => 'last heard';

  @override
  String get nodeDetailDistanceKv => 'distance';

  @override
  String get nodeDetailLatLonKv => 'lat / lon';

  @override
  String get gridViewTree => 'Mesh tree';

  @override
  String get gridViewSnsCells => 'SNS cells (heat)';

  @override
  String get gridViewWeather => 'Weather (environment)';

  @override
  String get gridViewMeshbook => 'Meshbook (channel activity)';

  @override
  String get meshbookTitle => 'MESHBOOK';

  @override
  String get meshbookLast24h => 'last 24h';

  @override
  String get meshbookEmpty => 'No messages on this channel in the last 24h.';

  @override
  String get meshbookByHour => 'BY HOUR';

  @override
  String get meshbookTopVoices => 'TOP VOICES';

  @override
  String get meshbookTopics => 'TOPICS';

  @override
  String get meshbookClear => 'Clear';

  @override
  String meshbookClearConfirm(String channel) {
    return 'Clear the last 24h of Meshbook data for CH$channel? It rebuilds as new channel messages arrive. (Each channel is stored separately.)';
  }

  @override
  String meshbookStats(int total, int replies, int pct, int voices) {
    return '$total msgs · $replies replies ($pct%) · $voices voices';
  }

  @override
  String get weatherSelf => 'This device';

  @override
  String get weatherMeasuredHeader => 'MEASURED (sensors)';

  @override
  String get wxMicroclimateTitle => 'MICROCLIMATE';

  @override
  String get wxMicroclimatesHeader => 'MICROCLIMATES (by place)';

  @override
  String get wxMicroclimateNearby => 'nearby';

  @override
  String get wxMeasured => 'measured';

  @override
  String get wxAmbientEmpty => 'No weather chatter on this channel yet.';

  @override
  String wxMentionsShort(int count) {
    return '$count mentions';
  }

  @override
  String get wxLastHour => '1H';

  @override
  String get wxLast24h => '24H';

  @override
  String get wxCondClear => 'Clear';

  @override
  String get wxCondClouds => 'Cloudy';

  @override
  String get wxCondFog => 'Fog';

  @override
  String get wxCondRain => 'Rain';

  @override
  String get wxCondSnow => 'Snow';

  @override
  String get wxCondWind => 'Windy';

  @override
  String get wxCondStorm => 'Storm';

  @override
  String get wxCondHeat => 'Hot';

  @override
  String get wxCondCold => 'Cold';

  @override
  String get weatherEmpty =>
      'No nodes are reporting environment data yet.\nReadings appear as sensor-equipped nodes are polled — enable \"Gather node telemetry\" in App settings.';

  @override
  String get weatherSelfNoTelemetry =>
      'This device hasn\'t returned telemetry yet. Make sure you\'re connected, then reopen this view.';

  @override
  String weatherSelfNoEnv(String types) {
    return 'Environment telemetry isn\'t supported by this device\'s firmware.\nIt reported: $types.\nThe sensor (e.g. the T1000-E\'s BME280) needs a MeshCore sensor firmware build — the standard build sends only battery/GPS, and the device clamps the environment mode back to off. This is a device limitation, not an app setting.';
  }

  @override
  String weatherReporting(int count) {
    return '$count reporting';
  }

  @override
  String get docsHubSubtitle =>
      'Protocol, firmware, app and field notes, offline.';

  @override
  String get docsHubFooter =>
      'Documentation is cached on-device for offline reading. Tap a doc, then ↻ to pull the latest. Upstream: meshcore-dev/MeshCore.';

  @override
  String get docsProtocolTitle => 'Protocol';

  @override
  String get docsProtocolSub =>
      'MeshCore companion radio protocol — frames, opcodes, and flow.';

  @override
  String get docsFirmwareTitle => 'Firmware';

  @override
  String get docsFirmwareSub => 'MeshCore firmware overview (README).';

  @override
  String docsFirmwareSubVersion(String version) {
    return 'MeshCore firmware — matched to $version.';
  }

  @override
  String get docsAppTitle => 'App';

  @override
  String get docsAppSub => 'How Meshmore SNS works, and how it uses the mesh.';

  @override
  String get docsDevicesTitle => 'Devices';

  @override
  String get docsDevicesSub =>
      'Field notes and quirks for the radios we run — T1000-E, Wio Tracker L1 Pro, Heltec V3.';

  @override
  String get docsRefresh => 'Refresh from GitHub';

  @override
  String get docsUpdated => 'Updated to the latest version';

  @override
  String get docsUpToDate => 'Already up to date';

  @override
  String get docsOriginBundled => 'Included copy';

  @override
  String docsOriginUpdated(String when) {
    return 'Updated $when';
  }

  @override
  String docsFirmwareForVersion(String version) {
    return 'device $version';
  }

  @override
  String get docsFirmwareNoDevice => 'no device connected';

  @override
  String get docsAgoJustNow => 'just now';

  @override
  String docsAgoMinutes(int n) {
    return '${n}m ago';
  }

  @override
  String docsAgoHours(int n) {
    return '${n}h ago';
  }

  @override
  String docsAgoDays(int n) {
    return '${n}d ago';
  }

  @override
  String get weatherMin => 'MIN';

  @override
  String get weatherAvg => 'AVG';

  @override
  String get weatherMax => 'MAX';

  @override
  String weatherAgoSeconds(int s) {
    return '${s}s ago';
  }

  @override
  String weatherAgoMinutes(int m) {
    return '${m}m ago';
  }

  @override
  String weatherAgoHours(int h) {
    return '${h}h ago';
  }

  @override
  String get snsCellsAwaitingFix =>
      'Waiting for a location fix — the heat map centres on you.';

  @override
  String get snsCellsClear => 'Clear';

  @override
  String snsCellsStatus(int active, int hot) {
    return '$active cells · $hot hot';
  }

  @override
  String get snsFrameMetro => 'Metro · ~20 km';

  @override
  String get snsFrameRegion => 'Region · ~300 km';

  @override
  String get snsFrameMesh => 'Mesh · fit all';

  @override
  String get snsCellsLegendTitle => 'SNS CELLS';

  @override
  String get snsCellsLegendDesc =>
      'A live social-activity heat map. Each observed message warms its cell; cells cool over a one-hour horizon.';

  @override
  String get snsCellsLegendHot =>
      'Bright red = busy (≈5+ messages in the last minute).';

  @override
  String get snsCellsLegendCool =>
      'Fading to white = quieting down; gone after ~1 h idle.';

  @override
  String get snsCellsLegendToast =>
      'New messages flash as a toast near their source, then vanish.';

  @override
  String get snsCellsLegendChannel =>
      'Channel messages carry the sender\'s name — they warm the sender\'s cell when we know their location, otherwise your own cell (the receive point).';

  @override
  String get snsCellsLegendDecay =>
      'Only the last hour is tracked; nothing is stored.';

  @override
  String get meshTreeEmpty =>
      'Waiting for contact sync — the tree is built from each contact\'s outPath.';

  @override
  String get meshTreeHopsDirect => 'Direct';

  @override
  String get meshTreeHopsFlood => 'Flood / All';

  @override
  String meshTreeHopsN(int n) {
    return '≤$n hops';
  }

  @override
  String get meshTreeRecenter => 'Recenter';

  @override
  String get meshTreeLegendTitle => 'MESH TREE';

  @override
  String get meshTreeLegendDesc =>
      'A directed graph of how the radio reaches each contact. Edges come from Contact.outPath — the exact repeater chain the device uses to send.';

  @override
  String get meshTreeLegendSelf => 'You — pinned at the centre.';

  @override
  String get meshTreeLegendRepeater =>
      'A square is a repeater: a radio that passes other radios\' messages.';

  @override
  String get meshTreeLegendRoom =>
      'A diamond is a room server: a radio that hosts named rooms.';

  @override
  String get meshTreeLegendChat =>
      'A circle is a node you can message directly.';

  @override
  String get meshTreeLegendSensor =>
      'A small dim circle is a sensor: it only reports readings.';

  @override
  String get meshTreeLegendFlood =>
      'Dashed edge to you = flood-routed contact. Reachable, but with no fixed path.';

  @override
  String get meshTreeLegendFloat =>
      'Floating (no edges) — heard via advert only; route unknown.';

  @override
  String get meshTreeLegendArrow =>
      'Arrows point away from us, toward the destination peer.';

  @override
  String get meshTreeLegendInteract =>
      'Tap a node for details, or Recenter to reset the view.';

  @override
  String get fabricLegendTitle => 'MESH SURVEY';

  @override
  String get fabricLegendDesc =>
      'A persistent record of where the mesh has been observed. Each rectangle is a small geographic cell (~220 m × 220 m) the device logged on contact with this location.';

  @override
  String get fabricLegendCell =>
      'Filled cell — the mesh reached here at some point.';

  @override
  String get fabricLegendRecency =>
      'Brighter is more recent: under an hour, under a day, under a week, older.';

  @override
  String get fabricLegendMarker =>
      'Filled pins are the nodes in range now. Tap one for details.';

  @override
  String get fabricLegendSelf => 'The primary-coloured pin is you.';

  @override
  String get fabricLegendReset =>
      'Reset the survey from the overflow menu when you move to a new area.';

  @override
  String get nodeDetailHopsKv => 'hops';

  @override
  String get nodeDetailHopsDirect => 'direct (0 hops)';

  @override
  String nodeDetailHopsViaRepeaters(int n) {
    return '$n via repeater(s)';
  }

  @override
  String get nodeDetailHopsUnknown => 'unknown';

  @override
  String get nodeDetailHopsFlood => 'Flood';

  @override
  String get nodeDetailAltitudeKv => 'altitude';

  @override
  String nodeDetailAltitudeMeters(String m) {
    return '$m m';
  }

  @override
  String get nodeDetailTempKv => 'temperature';

  @override
  String nodeDetailTempValue(String c) {
    return '$c °C';
  }

  @override
  String get nodeDetailHumidityKv => 'humidity';

  @override
  String nodeDetailHumidityValue(String p) {
    return '$p%';
  }

  @override
  String get nodeDetailPressureKv => 'pressure';

  @override
  String nodeDetailPressureValue(String hpa) {
    return '$hpa hPa';
  }

  @override
  String get nodeDetailLuminosityKv => 'luminosity';

  @override
  String get nodeDetailQueryTelemetry => 'Query telemetry';

  @override
  String get nodeDetailRefreshTelemetry => 'Refresh telemetry';

  @override
  String get nodeDetailTelemetryQuerying => 'Asking the radio for readings…';

  @override
  String get nodeDetailTelemetryNotContact =>
      'Not a device contact, so telemetry is unavailable.';

  @override
  String nodeDetailTelemetryAge(String age) {
    return 'telemetry from $age';
  }

  @override
  String nodeDetailAgoSeconds(int n) {
    return '${n}s ago';
  }

  @override
  String nodeDetailAgoMinutes(int n) {
    return '$n min ago';
  }

  @override
  String nodeDetailAgoHours(int n) {
    return '$n h ago';
  }

  @override
  String nodeDetailAgoDays(int n) {
    return '$n d ago';
  }

  @override
  String get channelsTitle => 'Channels';

  @override
  String get channelsHelp =>
      'Channel 0 is the shared public one. A private group needs the same channel number, name and key on every radio.';

  @override
  String get channelsOfflineHint =>
      'Connect a radio (Diagnostics) to edit channels.';

  @override
  String get channelsEmpty => '— empty —';

  @override
  String channelsSlotLabel(int idx) {
    return 'channel $idx';
  }

  @override
  String channelsSlotActive(int idx) {
    return 'channel $idx · ACTIVE';
  }

  @override
  String get channelsEdit => 'Edit';

  @override
  String get channelsSet => 'Set';

  @override
  String channelsSetSnack(int idx, String name) {
    return 'Channel $idx set to \"$name\" — every radio needs the same name and key here';
  }

  @override
  String channelsDialogTitle(int idx) {
    return 'Channel $idx';
  }

  @override
  String get channelsName => 'Channel name';

  @override
  String get channelsInferPlaces => 'Infer places from messages';

  @override
  String get channelsInferPlacesSub =>
      'Scan this channel\'s banter for place names and plot them on the SNS grid.';

  @override
  String notifTitleChannel(String name) {
    return 'Message on $name';
  }

  @override
  String notifTitleDirect(String name) {
    return 'Direct message from $name';
  }

  @override
  String get notifTitleSos => 'Emergency alert';

  @override
  String get notifBodySos =>
      'Open the app for the position. The alert carries coordinates that this phone does not show on the lock screen.';

  @override
  String get notifSectionTitle => 'Notifications';

  @override
  String get notifOs => 'Show a notification';

  @override
  String get notifAudio => 'Play a sound';

  @override
  String get notifHaptic => 'Vibrate';

  @override
  String get notifTts => 'Speak the message';

  @override
  String get notifMentionsOnly => 'Only when someone names me';

  @override
  String get notifMentionsOnlySub =>
      'Whole word or @name. Off means every message alerts.';

  @override
  String get notifKeySuffix => 'Also match the last 4 characters of my ID';

  @override
  String get notifKeySuffixSub =>
      'Anyone can choose those four characters, so leave this off unless you know the sender.';

  @override
  String get notifDeniedBanner =>
      'Notifications are turned off for this app, so messages will not appear on your lock screen.';

  @override
  String get channelsKeySource => 'Key source';

  @override
  String get channelsKeyPublic => 'Public';

  @override
  String get channelsKeyHashtag => '#tag';

  @override
  String get channelsKeyHex => 'Hex';

  @override
  String get channelsKeyPublicBody => 'Uses the well-known Public channel key.';

  @override
  String get channelsKeyHashtagHint => 'e.g. #mygroup';

  @override
  String get channelsKeyHashtagHelper =>
      'Key derived from sha256(\"#tag\") — the # is part of the key';

  @override
  String get channelsKeyHexHint => '32 hex chars (16 bytes)';

  @override
  String get channelsErrorTag => 'Enter a #hashtag';

  @override
  String get channelsErrorHex => 'The key must be 32 characters, 0-9 or A-F';

  @override
  String get channelsErrorName => 'Enter a channel name';

  @override
  String get channelsCancel => 'Cancel';

  @override
  String get channelsSave => 'Save';

  @override
  String get channelsHelpEncryption =>
      'Channel 0\'s key is public. Other channels use the key you set.';

  @override
  String get channelsHexGenerate => 'Generate a random key';

  @override
  String get channelsHexCopy => 'Copy';

  @override
  String get channelsHexCopied => 'Key copied';

  @override
  String get channelsTagWeakShort =>
      'Short tags are guessable. Use 12+ chars or unusual phrasing.';

  @override
  String get channelsTagWeakCommon =>
      'Common words are guessable — an attacker can grind tags. Use unusual phrasing.';

  @override
  String get channelsSlot0WarnTitle => 'Overwriting the Public channel?';

  @override
  String get channelsSlot0WarnBody =>
      'Channel 0 is the shared public channel. A private key here means you can only talk to radios using that same key, and you lose the public channel. Continue?';

  @override
  String get channelsSlot0WarnContinue => 'Overwrite channel 0';

  @override
  String get channelsSlot0WarnCancel => 'Cancel';

  @override
  String get channelsCurrentKey => 'Current key';

  @override
  String get channelsRevealKey => 'Reveal';

  @override
  String get channelsHideKey => 'Hide';

  @override
  String get channelsClear => 'Reset channel';

  @override
  String channelsClearConfirmTitle(int idx) {
    return 'Reset channel $idx?';
  }

  @override
  String get channelsClearConfirmBody =>
      'The radio has no empty channel, so this one goes back to the public name and key. Other radios need the same to talk here again.';

  @override
  String get channelsClearConfirmAction => 'Clear';

  @override
  String channelsClearSnack(int idx) {
    return 'Channel $idx reset to the public defaults';
  }

  @override
  String get channelsDefaultBadge => 'DEFAULT';

  @override
  String get channelsSetDefaultTooltip => 'Set as default channel on launch';

  @override
  String get channelsClearDefaultTooltip => 'Clear default channel preference';

  @override
  String channelsSetDefaultSnack(int idx) {
    return 'Channel $idx is now the one the app opens on';
  }

  @override
  String get channelsClearedDefaultSnack => 'Launch default cleared';

  @override
  String get channelsKeyShake => 'Shake';

  @override
  String get channelsShakeTitle => 'Shake to roll dice';

  @override
  String get channelsShakeBody =>
      'Shake your phone — each accepted motion sample feeds the hash. Stop once the ring fills.';

  @override
  String channelsShakeProgress(int accepted, int target, int pct) {
    return '$accepted of $target samples · $pct%';
  }

  @override
  String get channelsShakeReroll => 'Reroll';

  @override
  String get channelsShakeTapFallback =>
      'Tap to roll (reduceMotion is on — uses Random.secure instead)';

  @override
  String get channelsShareQr => 'Share via QR';

  @override
  String channelsQrTitle(int idx) {
    return 'Share channel $idx';
  }

  @override
  String get channelsQrBody =>
      'Scan with a Meshmore device or any QR reader. Anyone with this code can join the channel, so share it only with people you trust.';

  @override
  String get channelsQrPayload => 'Channel code (you can copy it)';

  @override
  String get channelsQrClose => 'Close';

  @override
  String get deviceConfigTitle => 'Device configuration';

  @override
  String get deviceRegionBand => 'Band preset';

  @override
  String get deviceRegionWhy => 'Why';

  @override
  String get deviceRegionCaveatTitle => 'Region caveat';

  @override
  String get deviceRegionCaveatClose => 'Close';

  @override
  String get deviceRegionCurrent => 'CURRENTLY APPLIED';

  @override
  String get deviceRegionUnknown => 'Waiting for device…';

  @override
  String get deviceRegionCustom => 'Custom';

  @override
  String get deviceRegionSuggestFromLocation => 'Suggest from my location';

  @override
  String get deviceRegionFamilyAmericas => 'Americas';

  @override
  String get deviceRegionFamilyEurope => 'Europe';

  @override
  String get deviceRegionFamilyAsiaPacific => 'Asia-Pacific';

  @override
  String get deviceRegionFamilyOther => 'Other';

  @override
  String get deviceRegionSuggestTitle => 'Use the preset for your location?';

  @override
  String deviceRegionSuggestBody(String lat, String lon, String label) {
    return 'Based on your phone GPS ($lat, $lon), the matching preset is $label. Verify this is legal where you are before applying — particularly outside the country you set up in.';
  }

  @override
  String get deviceRegionSuggestApply => 'Use it';

  @override
  String get deviceRegionSuggestNoFix =>
      'No GPS fix yet. Try outdoors with location on.';

  @override
  String get deviceRegionSuggestNoMatch =>
      'Your location doesn\'t match any shipped country preset — pick one manually.';

  @override
  String get deviceRegionDisclaimerShort =>
      'Shared by users, not checked by a regulator.';

  @override
  String get deviceRegionDisclaimer =>
      'These presets are shared by users, not checked by a regulator. Pick one that is legal where you are and use the same settings on every radio. In Japan the radio itself must carry 技適 (giteki) certification; most imported boards do not, and using one is an offence under the Radio Act whatever the settings. The Japan (ARIB STD-T108) preset is a community proposal that has not been widely tested.';

  @override
  String get presetUsCanada => 'USA / Canada';

  @override
  String get presetUsArizona => 'USA — Arizona';

  @override
  String get presetJpAribT108 => 'Japan (ARIB STD-T108)';

  @override
  String get presetJpMeshcore => 'Japan (MeshCore-JP)';

  @override
  String get presetEuUkLong => 'EU / UK (Long Range)';

  @override
  String get presetEuUkMedium => 'EU / UK (Medium Range)';

  @override
  String get presetEuUkNarrow => 'EU / UK (Narrow)';

  @override
  String get presetCh => 'Switzerland';

  @override
  String get presetCz => 'Czech Republic';

  @override
  String get presetPt869 => 'Portugal (869 MHz)';

  @override
  String get presetAu => 'Australia';

  @override
  String get presetAuNarrow => 'Australia (Narrow)';

  @override
  String get presetAuSaWaQld => 'Australia (SA / WA / QLD)';

  @override
  String get presetNz => 'New Zealand';

  @override
  String get presetVn => 'Vietnam';

  @override
  String get cancel => 'Cancel';

  @override
  String get closeSheet => 'Close';

  @override
  String get deviceRadioParams => 'Radio';

  @override
  String get deviceIdentityAdvert => 'Identity and advert';

  @override
  String get deviceChannelsSection => 'CHANNELS';

  @override
  String get deviceOtherParamsSection => 'Advanced';

  @override
  String get deviceDeviceSection => 'Device';

  @override
  String get deviceFrequency => 'Frequency (MHz)';

  @override
  String get deviceBandwidth => 'Bandwidth (kHz)';

  @override
  String get deviceSpreadingFactor => 'Spreading factor (5–12)';

  @override
  String get deviceCodingRate => 'Coding rate (5–8)';

  @override
  String get deviceTxPower => 'TX power (dBm)';

  @override
  String get devicePathHashSize => 'Path hash size';

  @override
  String get devicePathHashSizeHelp =>
      'The hash length this radio stamps on the packets it sends. Repeaters follow each packet\'s own length, so nodes need not agree. Longer hashes tell repeaters apart better but shrink the directed payload budget.';

  @override
  String get devicePathHashUnread => 'unknown';

  @override
  String devicePathHashMismatch(String device, String form) {
    return 'On the radio: $device. Yours: $form. Tap Apply to send yours.';
  }

  @override
  String get deviceRadioApplied => 'The radio confirmed the change.';

  @override
  String deviceRadioRefused(String param, String code) {
    return 'The radio refused $param (error $code). Later writes were not sent.';
  }

  @override
  String deviceRadioSilent(String param) {
    return 'No answer for $param within five seconds — the write may not have applied.';
  }

  @override
  String deviceRadioUnsupported(String param) {
    return '$param is not in this firmware build.';
  }

  @override
  String get deviceRadioUnknownState =>
      'Cannot change radio settings yet: this radio has not reported its path-hash size, so there is no value to undo back to.';

  @override
  String get deviceRadioRevert => 'Undo radio change';

  @override
  String get deviceRadioReverted => 'Previous operating point restored.';

  @override
  String get deviceRadioRevertUnavailable => 'Undo is one use only.';

  @override
  String get deviceRadioRevertFailed =>
      'Undo did not apply — the radio kept its last values.';

  @override
  String get radioHealthTitle => 'Radio health';

  @override
  String get radioHealthRead => 'Read';

  @override
  String get radioHealthReading => 'Reading…';

  @override
  String get radioHealthUnread => 'Tap Read';

  @override
  String radioHealthNoise(String dbm) {
    return 'Noise $dbm dBm';
  }

  @override
  String radioHealthLast(String rssi, String snr) {
    return 'Last $rssi dBm · $snr dB SNR';
  }

  @override
  String radioHealthBattery(String volts) {
    return 'Battery $volts V';
  }

  @override
  String get radioHealthNotReported => 'Not reported';

  @override
  String radioHealthUptime(String uptime) {
    return 'Up $uptime';
  }

  @override
  String get radioHealthSource => 'From the radio';

  @override
  String get deviceLoadFromDevice => 'Load from device';

  @override
  String get deviceApplyRadio => 'Apply radio params';

  @override
  String get deviceConnectFirst =>
      'Connect a radio first (Diagnostics & connect).';

  @override
  String get deviceAdvertName => 'Advert name';

  @override
  String get deviceSetName => 'Set name';

  @override
  String get deviceAdvertLatitude => 'Advert latitude (°)';

  @override
  String get deviceAdvertLongitude => 'Advert longitude (°)';

  @override
  String get deviceUsePhoneLocation => 'Use phone location';

  @override
  String get deviceReadDeviceLocation => 'Read device location';

  @override
  String get deviceSetAdvertLocation => 'Set advert location';

  @override
  String get deviceAdvertSource => 'Advert location source';

  @override
  String get deviceAdvertSourceNone => 'None';

  @override
  String get deviceAdvertSourcePinned => 'Pinned';

  @override
  String get deviceAdvertSourceGps => 'Device GPS';

  @override
  String get deviceToastNameEmpty => 'Enter a node name';

  @override
  String get deviceToastNameSet =>
      'Name updated — re-advertising to neighbours';

  @override
  String deviceToastSendFailed(String error) {
    return 'Send failed: $error';
  }

  @override
  String get deviceToastNoDeviceYet =>
      'Device hasn\'t reported yet — try once linked';

  @override
  String get deviceToastNoGpsYet => 'Device has no location yet (no GPS fix)';

  @override
  String get deviceToastLoadedDeviceLoc =>
      'Loaded device location · tap Set advert location to broadcast';

  @override
  String get deviceToastGettingPhoneFix => 'Getting phone GPS fix…';

  @override
  String get deviceToastPhoneFixFailed =>
      'Phone GPS fix failed (services off or timeout)';

  @override
  String get deviceToastNoFixReturned => 'No fix returned';

  @override
  String get deviceToastGotPhoneLoc =>
      'Got phone location · tap Set advert location to broadcast';

  @override
  String get deviceToastInvalidLatLon =>
      'Enter valid lat (−90..90) and lon (−180..180)';

  @override
  String get deviceToastAdvertLocSet => 'Advert location set';

  @override
  String get deviceToastInvalidRadio => 'Enter valid numbers for freq/BW/SF/CR';

  @override
  String get deviceLocPermDenied =>
      'Location permission needed for a phone GPS fix.';

  @override
  String get deviceLocPermDeniedPerm =>
      'Location permission permanently denied — open OS settings to grant it.';

  @override
  String get deviceOpenSettings => 'Open settings';

  @override
  String get diagnosticsTitle => 'Diagnostics & connect';

  @override
  String get diagnosticsRawFrameLog => 'RAW FRAME LOG (newest first)';

  @override
  String get diagnosticsDisconnect => 'Disconnect';

  @override
  String get diagnosticsCopyLog => 'Copy log';

  @override
  String get otherManualAddTitle => 'Manual-add contacts';

  @override
  String get otherManualAddSubOn =>
      'You add heard nodes as contacts on demand.';

  @override
  String get otherManualAddSubOff => 'Nodes you hear are saved as contacts.';

  @override
  String get otherTelemetryModeTitle => 'Who may read telemetry';

  @override
  String get otherTelemetryBase => 'Base';

  @override
  String get otherTelemetryLoc => 'Location';

  @override
  String get otherTelemetryEnv => 'Environment';

  @override
  String get otherTelemetryDeny => 'Off';

  @override
  String get otherTelemetryFlags => 'Contacts';

  @override
  String get otherTelemetryAll => 'Anyone';

  @override
  String get otherTelemetryModeHelp =>
      'Who may request battery, GPS and environment data from this device.';

  @override
  String get otherMultiAcksLabel => 'Extra confirmations (0–3)';

  @override
  String get otherMultiAcksHelper =>
      '0 is the default. Higher waits for that many more radios to confirm before calling a send confirmed.';

  @override
  String get otherSentSnack =>
      'OTHER PARAMS sent — device-side write may take a moment.';

  @override
  String get otherAwaitingDevice => '— awaiting device —';

  @override
  String get batteryTitle => 'Battery';

  @override
  String get batteryConfigSubtitle =>
      'Charge, drain rate, and time-to-empty estimate';

  @override
  String get batteryAwaiting =>
      'Waiting for a battery reading from the device…';

  @override
  String get batteryReset => 'Reset history';

  @override
  String get batteryResetConfirm =>
      'Clear all stored battery history? The runtime estimate will rebuild as new readings arrive.';

  @override
  String get batteryVoltageLabel => 'VOLTAGE';

  @override
  String get batteryCharging => 'Charging';

  @override
  String get batteryChargingNote => 'Charging — runtime estimate paused.';

  @override
  String get batteryTimeToEmpty => 'TIME TO EMPTY';

  @override
  String get batteryEstimating =>
      'Gathering drain data — an estimate appears after a few minutes of discharge.';

  @override
  String get batteryDrainRate => 'Drain rate';

  @override
  String get batteryBasis => 'Basis';

  @override
  String batteryBasisObserved(String span) {
    return 'measured over $span of discharge';
  }

  @override
  String get batteryBasisRated => 'nameplate (capacity ÷ typical draw)';

  @override
  String get batteryConfidence => 'confidence';

  @override
  String get batteryConfHigh => 'high';

  @override
  String get batteryConfMedium => 'medium';

  @override
  String get batteryConfLow => 'low';

  @override
  String get batteryMethodObserved => 'Measured discharge';

  @override
  String get batteryMethodRated => 'Rated estimate';

  @override
  String get batteryMethodNone => 'Gathering data';

  @override
  String get batterySpecTitle => 'DEVICE MODEL';

  @override
  String get batterySpecGeneric =>
      'Unknown hardware — using a generic single-cell Li-ion model. The estimate relies on observed drain (no nameplate capacity to cross-check).';

  @override
  String batterySpecCapacity(int mah) {
    return 'Capacity: $mah mAh';
  }

  @override
  String get batterySpecCapacityUnknown => 'Capacity: user-supplied (unknown)';

  @override
  String batterySpecDraw(int ma) {
    return 'Typical draw: ~$ma mA (radio receiving)';
  }

  @override
  String get batteryHistoryTitle => 'VOLTAGE HISTORY';

  @override
  String batteryHistorySpan(String span, int count) {
    return '$span · $count samples';
  }

  @override
  String batteryDurDH(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String batteryDurHM(int hours, int mins) {
    return '${hours}h ${mins}m';
  }

  @override
  String batteryDurM(int mins) {
    return '${mins}m';
  }

  @override
  String get deliverySending => 'Sending…';

  @override
  String get deliverySent => 'Sent into the mesh';

  @override
  String get deliveryDelivered => 'Delivered (recipient acknowledged)';

  @override
  String get deliveryFailed =>
      'Not delivered — no acknowledgement or send failed';

  @override
  String get deliveryUnknown =>
      'Sent while the app was closing — whether the radio transmitted it is not knowable';

  @override
  String get settingsHubTools => 'Tools';

  @override
  String get toolsTitle => 'Tools';

  @override
  String get toolsOffline => 'Not connected — the tools need the radio.';

  @override
  String get toolsRunning => 'RUNNING';

  @override
  String get toolsStart => 'Start';

  @override
  String get toolsStop => 'Stop';

  @override
  String get toolsCopyReport => 'Copy report';

  @override
  String get toolsCopied => 'Copied to the clipboard';

  @override
  String get toolsCount => 'COUNT';

  @override
  String get toolsInterval => 'INTERVAL';

  @override
  String toolsSeconds(int n) {
    return '$n s';
  }

  @override
  String toolsMinutes(int n) {
    return '$n min';
  }

  @override
  String toolsMs(int n) {
    return '$n ms';
  }

  @override
  String toolsDb(String v) {
    return '$v dB';
  }

  @override
  String get toolsChoose => 'Choose…';

  @override
  String get toolStatsName => 'Radio stats';

  @override
  String get toolStatsSub => 'Noise floor, airtime, packet counters';

  @override
  String get toolPingName => 'Ping';

  @override
  String get toolPingSub => 'Round-trip to a contact: loss and RTT';

  @override
  String get toolTraceName => 'Trace path';

  @override
  String get toolTraceSub => 'Per-hop SNR along a repeater chain';

  @override
  String get toolDiscoverName => 'Discover nearby';

  @override
  String get toolDiscoverSub => 'Repeaters that hear us, SNR both ways';

  @override
  String get toolSoakName => 'Soak test';

  @override
  String get toolSoakSub => 'Sequenced messages, counted — pairs with the bot';

  @override
  String get toolRangeName => 'Range test';

  @override
  String get toolRangeSub => 'Beacon or log, with SNR and distance';

  @override
  String get toolFailNotConnected => 'Not connected to a radio.';

  @override
  String get toolFailBusy => 'Another tool is using the radio. Stop it first.';

  @override
  String get toolFailUnsupported =>
      'Your radio\'s firmware doesn\'t support this.';

  @override
  String get toolFailNotFound => 'The radio doesn\'t have this contact.';

  @override
  String get toolFailTableFull =>
      'The radio is busy (send table full). Try again shortly.';

  @override
  String get toolFailRejected => 'The radio refused the request.';

  @override
  String get toolFailNoConfirm => 'The radio didn\'t confirm the send.';

  @override
  String get toolFailPublic =>
      'Public is refused: everything sent there reaches every radio. Use a private channel or a DM.';

  @override
  String get toolFailUnknownChannel =>
      'This channel\'s key hasn\'t been read from the radio yet.';

  @override
  String get toolFailNoTarget => 'Choose a target first.';

  @override
  String get statsRefresh => 'Refresh';

  @override
  String get statsAuto => 'Auto (every 5 s)';

  @override
  String get statsSectionRadio => 'RADIO';

  @override
  String get statsSectionPackets => 'PACKETS';

  @override
  String get statsSectionCore => 'CORE';

  @override
  String get statsNoise => 'Noise floor';

  @override
  String get statsLastRssi => 'Last RSSI';

  @override
  String get statsLastSnr => 'Last SNR';

  @override
  String get statsTxAir => 'TX airtime';

  @override
  String get statsRxAir => 'RX airtime';

  @override
  String get statsDuty => 'Duty cycle (TX)';

  @override
  String get statsReceived => 'Received';

  @override
  String get statsSent => 'Sent';

  @override
  String statsSplit(int flood, int direct) {
    return 'flood $flood · direct $direct';
  }

  @override
  String get statsRxErrors => 'Receive errors';

  @override
  String get statsUptime => 'Uptime';

  @override
  String get statsQueue => 'Send queue';

  @override
  String get statsErrFlags => 'Error flags';

  @override
  String get statsBattery => 'Battery';

  @override
  String get statsNotFetched => 'Not fetched yet.';

  @override
  String get pingTarget => 'TARGET';

  @override
  String get pingMethodStatus =>
      'Status request — repeaters, rooms and sensors answer this.';

  @override
  String get pingMethodTelemetry =>
      'Asks for readings. The other radio answers only if it shares them with you.';

  @override
  String pingSummary(int sent, int replied, int lost) {
    return '$sent sent · $replied replied · $lost lost';
  }

  @override
  String pingRtt(int min, int avg, int max) {
    return 'RTT min $min · avg $avg · max $max ms';
  }

  @override
  String get pingLost => 'lost';

  @override
  String get pingWaiting => 'waiting…';

  @override
  String get pingNoContacts =>
      'No synced contacts yet — only contacts can be pinged.';

  @override
  String get pingLastStatus => 'LAST STATUS';

  @override
  String get traceToNode => 'To a node';

  @override
  String get traceManual => 'Manual';

  @override
  String get traceRoundTrip => 'Round trip (come back to us)';

  @override
  String get traceNoRoute => 'no route — send it a message first';

  @override
  String tracePath(String path) {
    return 'path $path';
  }

  @override
  String get traceManualHint => 'hashes, e.g. a1,7f,a1';

  @override
  String get traceInvalid => 'Enter one or more hex bytes.';

  @override
  String get traceRun => 'Trace';

  @override
  String get traceNoAnswer => 'no answer';

  @override
  String get traceToUs => '→ us';

  @override
  String traceWeakest(String hop, String snr) {
    return 'weakest: $hop, $snr dB';
  }

  @override
  String get traceReset => 'Reset route';

  @override
  String get traceResetDone => 'Route reset — the next message floods.';

  @override
  String get traceNoRepeaters =>
      'Trace needs a repeater on the way: pick a repeater, or a contact reached through one.';

  @override
  String get discoverStart => 'Discover';

  @override
  String discoverListening(int s) {
    return 'Listening… $s s';
  }

  @override
  String get discoverNone => 'No repeater answered.';

  @override
  String discoverTheyHearUs(String snr) {
    return 'they hear us $snr dB';
  }

  @override
  String discoverWeHearThem(String snr, int rssi) {
    return 'we hear them $snr dB / $rssi dBm';
  }

  @override
  String get discoverAsymmetric => 'asymmetric link';

  @override
  String get soakScope => 'CONVERSATION';

  @override
  String get soakPairHint =>
      'Pairs with an R59 bot answering on the other radio: echoes show drops, duplicates and reordering.';

  @override
  String soakSummary(int sent, int delivered, int failed) {
    return '$sent sent · $delivered delivered · $failed failed';
  }

  @override
  String soakEchoes(int echoed, int dup, int reordered) {
    return '$echoed echoed · $dup duplicate · $reordered reordered';
  }

  @override
  String get soakListening => 'Sends done — listening for late echoes…';

  @override
  String soakRun(String id) {
    return 'run $id';
  }

  @override
  String soakEcho(int ms) {
    return 'echo $ms ms';
  }

  @override
  String soakDm(String name) {
    return 'DM · $name';
  }

  @override
  String get rangeSender => 'Sender';

  @override
  String get rangeReceiver => 'Receiver';

  @override
  String get rangeChannel => 'CHANNEL';

  @override
  String get rangeHint =>
      'Both radios on the same private channel. The sender beacons; the receiver walks and logs.';

  @override
  String rangeBeacons(int n) {
    return '$n beacons sent';
  }

  @override
  String rangeSummary(int heard, int missing) {
    return '$heard heard · $missing missing';
  }

  @override
  String rangeBest(String snr) {
    return 'best SNR $snr dB';
  }

  @override
  String rangeFarthest(String d) {
    return 'farthest $d';
  }

  @override
  String get rangeCopyCsv => 'Copy CSV';

  @override
  String get rangeFlood => 'flood';

  @override
  String get settingsHubInfo => 'Information';

  @override
  String get settingsNotifDeniedPermanent =>
      'Notifications were permanently denied. The background service needs a persistent notification.';

  @override
  String get settingsNotifDeniedTransient =>
      'Keeping the app connected in the background needs notifications. Allow them in Settings.';

  @override
  String get deviceAdvertPropagatesHint =>
      'Takes effect the next time the radio announces itself.';

  @override
  String get settingsHubMaps => 'Offline maps';

  @override
  String get mapsTitle => 'Offline maps';

  @override
  String get mapsOffline =>
      'No network. New maps can be set up only while online; downloads resume on their own.';

  @override
  String get mapsStorage => 'Storage';

  @override
  String mapsUsed(String used, String budget) {
    return '$used of $budget used';
  }

  @override
  String mapsBreakdown(String packs, String layers, String view) {
    return 'Regions $packs · Event maps $layers · Cached tiles $view';
  }

  @override
  String get mapsBudget => 'Budget';

  @override
  String get mapsViewKeep => 'Keep viewed';

  @override
  String get mapsClearView => 'Clear viewed tiles';

  @override
  String get mapsPacks => 'Region downloads';

  @override
  String get mapsAddPack => 'Download a region';

  @override
  String get mapsNoPacks =>
      'No regions yet. Regions come from servers that allow offline use: USGS inside the US, or a tile server you add.';

  @override
  String get mapsArchives => 'Region files';

  @override
  String get mapsNoArchives =>
      'No region files. A region file is one download for a whole area: a .pmtiles file from a host you trust. Add its link.';

  @override
  String get mapsAddArchive => 'Add region file';

  @override
  String get archiveUrl => 'Link (https)';

  @override
  String get archiveSize => 'Size in MB (optional)';

  @override
  String get archiveSha => 'SHA-256 (optional)';

  @override
  String get archiveStateFailed => 'Rejected';

  @override
  String get archiveFailBadHash => 'Checksum does not match.';

  @override
  String get archiveFailBadSize => 'Size does not match.';

  @override
  String get archiveFailNotPm => 'Not a PMTiles file.';

  @override
  String get archiveFailSchema =>
      'Wrong map layout. This file is not a compatible basemap.';

  @override
  String get archiveFailNotFound => 'Link not found.';

  @override
  String get archiveFailStorage =>
      'The app could not write to its storage. Free some space and try again.';

  @override
  String get archiveRefusalDuplicate => 'Already added.';

  @override
  String get archiveStateWaitingWifi => 'Waiting for Wi-Fi';

  @override
  String get archiveRefusalNoSpace =>
      'Not enough free space. Free up some and try again.';

  @override
  String get mapsPacksPublished => 'Available packs';

  @override
  String get mapsPacksEmpty =>
      'No offline maps published yet. You can still install one from a link.';

  @override
  String mapsPacksFrom(String source) {
    return 'List from $source';
  }

  @override
  String get mapsPacksBundle => 'Built-in list';

  @override
  String get mapsPacksUnreadable =>
      'The published list could not be read. Showing the built-in one.';

  @override
  String get mapsPackInstall => 'Download';

  @override
  String mapsPackLicence(String licence, String attribution) {
    return '$licence · $attribution';
  }

  @override
  String get mapsWifiOnly => 'Download over Wi-Fi only';

  @override
  String get mapsWifiOnlyHint => 'A pack can be hundreds of megabytes.';

  @override
  String get mapsOutsidePacks =>
      'Outside your offline maps, the map needs a connection.';

  @override
  String get mapsLayers => 'Event maps';

  @override
  String get mapsNoLayersShort => 'No event maps added';

  @override
  String get mapsManageLayers => 'Manage event maps…';

  @override
  String get mapsAddLayer => 'Add event map';

  @override
  String get mapsNoLayers =>
      'No event maps. Add a GeoJSON URL: a festival\'s street plan, a race course, a camp layout.';

  @override
  String get mapsSources => 'Map sources';

  @override
  String get mapsAddSource => 'Add tile server';

  @override
  String get mapsSourcePacks => 'Offline download allowed';

  @override
  String get mapsSourcePacksUs => 'Offline download allowed (US only)';

  @override
  String get mapsSourceViewOnly =>
      'Viewed tiles only: the server forbids bulk download';

  @override
  String get mapsSourcePick => 'Basemap';

  @override
  String get packStateDownloading => 'Downloading';

  @override
  String get packStateUpdating => 'Updating';

  @override
  String get packStateWaiting => 'Waiting for network';

  @override
  String get packStateOverBudget => 'Stopped: over budget';

  @override
  String get packStatePaused => 'Paused';

  @override
  String get packStateComplete => 'Complete';

  @override
  String mapsPackLine(String source, int minZ, int maxZ) {
    return '$source · zoom $minZ–$maxZ';
  }

  @override
  String mapsProgress(int done, int total) {
    return '$done / $total tiles';
  }

  @override
  String mapsMissing(int n) {
    return '$n not on server';
  }

  @override
  String mapsExpiresIn(int days) {
    return 'Deletes in $days d';
  }

  @override
  String get mapsKeepForever => 'Kept until deleted';

  @override
  String get mapsPause => 'Pause';

  @override
  String get mapsResume => 'Resume';

  @override
  String get mapsUpdate => 'Update';

  @override
  String get mapsRedownload => 'Download again';

  @override
  String get mapsKeepFor => 'Delete after…';

  @override
  String get mapsDelete => 'Delete';

  @override
  String mapsDeleteConfirm(String name) {
    return 'Delete $name?';
  }

  @override
  String get mapsKeepNever => 'Never';

  @override
  String mapsKeepDays(int days) {
    return '$days days';
  }

  @override
  String mapsLayerFeatures(int n) {
    return '$n features';
  }

  @override
  String get mapsLayerName => 'Name';

  @override
  String get mapsLayerUrl => 'GeoJSON URL (https)';

  @override
  String get mapsLayerTerms => 'The publisher\'s terms apply to their data.';

  @override
  String get mapsSourceName => 'Name';

  @override
  String get mapsSourceUrl => 'Tile URL template';

  @override
  String get mapsSourceAttr => 'Attribution';

  @override
  String get mapsSourceAllowsPacks => 'This server allows offline download';

  @override
  String get mapsSourceBad =>
      'Needs a name and an https template with z, x and y placeholders.';

  @override
  String get mapsAdd => 'Add';

  @override
  String get mapsWorking => 'Working…';

  @override
  String get newPackName => 'Name';

  @override
  String get newPackSource => 'Source';

  @override
  String get newPackCenter => 'Centre';

  @override
  String get newPackMyLocation => 'My location';

  @override
  String get newPackNoLocation => 'No location yet: enter lat, lon';

  @override
  String get newPackLatLon => 'lat, lon';

  @override
  String get newPackRadius => 'Radius';

  @override
  String get newPackZoomFrom => 'Zoom from';

  @override
  String get newPackZoomTo => 'Zoom to';

  @override
  String get newPackKeep => 'Delete after';

  @override
  String newPackEstimate(int tiles, String size) {
    return '$tiles tiles · about $size';
  }

  @override
  String get newPackCreate => 'Download';

  @override
  String get newPackNoSource =>
      'No source here allows offline download. Add a tile server that does, under Map sources.';

  @override
  String get packRefusalNoName => 'Give it a name.';

  @override
  String get packRefusalOffline =>
      'Can\'t reach the server. Set up maps while online.';

  @override
  String get packRefusalViewOnly =>
      'This server doesn\'t allow offline download.';

  @override
  String get packRefusalCoverage => 'This source has no data there.';

  @override
  String get packRefusalTooMany =>
      'Too many tiles. Shrink the area or lower the top zoom.';

  @override
  String get packRefusalBudget => 'Won\'t fit in the storage budget.';

  @override
  String get layerRefusalBadUrl => 'Needs an https URL.';

  @override
  String get layerRefusalNotGeoJson => 'That URL didn\'t return GeoJSON.';

  @override
  String get layerRefusalTooLarge => 'Over 10 MB: too big for an overlay.';

  @override
  String get mapsSelfTest => 'Self-test';

  @override
  String get selfTestIntro =>
      'Checks map downloads end to end: the real servers, storage, downloads, pause and resume, expiry. It runs in a sandbox and deletes it afterwards, so your maps are not touched. Takes about a minute and under 1 MB of data.';

  @override
  String get selfTestRun => 'Run self-test';

  @override
  String get selfTestRunning => 'Running…';

  @override
  String get selfTestPass => 'All checks passed';

  @override
  String selfTestFail(int n) {
    return '$n checks failed';
  }

  @override
  String get selfTestCopy => 'Copy report';

  @override
  String get selfTestCopied => 'Report copied';

  @override
  String get selfCheckReach => 'Map servers reachable';

  @override
  String get selfCheckViewCache => 'Viewed tiles are kept';

  @override
  String get selfCheckRevalidate => 'Stale tiles re-checked politely';

  @override
  String get selfCheckPack => 'Region download';

  @override
  String get selfCheckUpdate => 'Region update';

  @override
  String get selfCheckEventLayer => 'Event map (GeoJSON)';

  @override
  String get selfCheckOffline => 'Offline behaviour';

  @override
  String get selfCheckResume => 'Pause and resume on network loss';

  @override
  String get selfCheckGuards => 'Refusals (size, budget, policy, coverage)';

  @override
  String get selfCheckExpiry => 'Delete-after expiry';

  @override
  String get selfCheckDisk => 'Storage matches the books';

  @override
  String get locGroupAutoPublish => 'Publishing';

  @override
  String get locGroupBeacon => 'Beacon';

  @override
  String get locGroupManual => 'Manual';

  @override
  String get deviceManageChannels => 'Manage channels';

  @override
  String deviceActiveChannelSub(String name) {
    return 'Using: $name · channels and keys';
  }

  @override
  String get locationSourceDevice => 'device';

  @override
  String get locationSourcePhone => 'phone GPS';

  @override
  String get locationSourceNone => 'none';

  @override
  String get batteryChargingShort => 'CHG';

  @override
  String get elevationSelfTelemetry => 'SELF TELEMETRY';

  @override
  String elevationSelfAlt(String m) {
    return 'alt: $m m';
  }

  @override
  String get elevationSelfAltUnknown => 'alt: —';

  @override
  String elevationSelfTemp(String c) {
    return 'temp: $c °C';
  }

  @override
  String get elevationPolling => 'polling…';

  @override
  String get elevationTapToUpdate => 'tap to update';

  @override
  String get diagnosticsSectionConnection => 'CONNECTION';

  @override
  String diagnosticsStateLine(String state) {
    return 'State: $state';
  }

  @override
  String get diagnosticsStateDisconnected => 'disconnected';

  @override
  String get diagnosticsStateHandshaking => 'handshaking';

  @override
  String get diagnosticsStateReady => 'ready';

  @override
  String get diagnosticsStateReconnecting => 'reconnecting';

  @override
  String get diagnosticsStateFailed => 'failed';

  @override
  String get diagnosticsConnectingSuffix => ' · connecting…';

  @override
  String diagnosticsDeviceLine(String name, String freq, String sf) {
    return 'device: $name · ${freq}MHz SF$sf';
  }

  @override
  String diagnosticsBatteryLine(String volts, String pct) {
    return 'battery: ${volts}V (~$pct%)';
  }

  @override
  String get diagnosticsChargingSuffix => ' ⚡ charging';

  @override
  String diagnosticsReconnectLine(String n) {
    return 'reconnect attempt $n';
  }

  @override
  String get diagnosticsGaveUpSuffix => ' (gave up)';

  @override
  String diagnosticsErrorLine(String error) {
    return 'error: $error';
  }

  @override
  String diagnosticsMtuLine(String mtu, String need) {
    return 'Link size $mtu bytes, $need needed for a full frame';
  }

  @override
  String diagnosticsMtuRefusedLine(String mtu, String need) {
    return 'This phone link is $mtu bytes and a full radio frame needs $need. Reconnect to try again; a radio that caps the link smaller cannot carry every frame.';
  }

  @override
  String diagnosticsDatagramLine(String ch, String via, String type) {
    return 'datagram: channel $ch, via $via, type $type';
  }

  @override
  String get rxViaPrimary => 'the primary radio';

  @override
  String get rxViaSecondary => 'radio 2';

  @override
  String get rxViaUnknown => 'an unreported radio';

  @override
  String diagnosticsFramingLine(String truncated, String trailing) {
    return 'incomplete frames: $truncated cut short, $trailing with bytes left over';
  }

  @override
  String get diagnosticsScanConnect => 'Scan & connect';

  @override
  String get diagnosticsForgetShort => 'Forget';

  @override
  String diagnosticsPairedLine(String name) {
    return 'Paired: $name — auto-reconnects on startup';
  }

  @override
  String get diagnosticsSectionDeveloper => 'Developer';

  @override
  String get diagnosticsPairRadio => 'Pair a radio';

  @override
  String get diagnosticsForgetConfirmTitle => 'Forget this radio?';

  @override
  String get diagnosticsForgetConfirmBody =>
      'You will need to pair it again, and this clears its bond. Do not do this while the radio is out of reach.';

  @override
  String get diagnosticsSectionSend => 'Send';

  @override
  String get diagnosticsSendSelfAdvert => 'Send self-advert';

  @override
  String get diagnosticsReadClock => 'Read the radio\'s clock';

  @override
  String get diagnosticsPullMessage => 'Pull the next message';

  @override
  String get diagnosticsTestMessage => 'Public-channel test message';

  @override
  String get diagnosticsSend => 'Send';

  @override
  String diagnosticsSentWhat(String what) {
    return 'Sent $what';
  }

  @override
  String diagnosticsSendFailed(String error) {
    return 'The send failed: $error';
  }

  @override
  String get diagnosticsSectionM6 => 'Channel-tail evidence';

  @override
  String get diagnosticsResolveTail => 'Resolve channel-tail';

  @override
  String get diagnosticsExportFixture => 'Export fixture';

  @override
  String get diagnosticsCopyFixture => 'Copy fixture JSON';

  @override
  String get diagnosticsFixtureCopied =>
      'Copied. Save it under the protocol package\'s captured vectors.';

  @override
  String get diagnosticsNoRfLog => 'No RF-log frame captured yet';

  @override
  String get diagnosticsNotRfLog => 'The last RF-log frame did not decode';

  @override
  String get diagnosticsNotGrpTxt =>
      'That packet is not a group text. Send on the Public channel and try again.';

  @override
  String get diagnosticsExportNeedsCapture =>
      'Needs a captured RF-log frame first';

  @override
  String get diagnosticsNoFrames => 'No frames yet';

  @override
  String diagnosticsFramesCopied(String count) {
    return 'Copied $count frames';
  }

  @override
  String get diagnosticsSectionSoak => 'Soak';

  @override
  String get diagnosticsSoakEmpty => 'No scopes bound';

  @override
  String get diagnosticsCopySoak => 'Copy soak report';

  @override
  String get diagnosticsSoakCopied => 'Soak report copied';

  @override
  String get nodesClearSearch => 'Clear search';

  @override
  String get networksTitle => 'Networks';

  @override
  String get networksTileSubtitle =>
      'Radio settings shared by a group of radios';

  @override
  String get networksEmpty =>
      'No networks yet. A network is the radio settings your radios agree on.';

  @override
  String get networksNew => 'New network';

  @override
  String get networksName => 'Name';

  @override
  String get networksNameRequired => 'Give the network a name.';

  @override
  String get networksPreset => 'Radio settings from';

  @override
  String get networksPathHash => 'Path hash size';

  @override
  String get networksPrivateSwitch => 'Private frequency';

  @override
  String get networksPrivateHelp =>
      'Use a frequency no public preset uses. Radios on it do not hear the public mesh, and the public mesh does not hear them.';

  @override
  String get networksFrequency => 'Frequency (MHz)';

  @override
  String get networksFrequencyInvalid =>
      'Enter a frequency from 150 to 2500 MHz.';

  @override
  String networksFrequencyPublic(String preset) {
    return 'That frequency, bandwidth and spreading factor belong to the public preset $preset. Pick a different frequency.';
  }

  @override
  String get networksSave => 'Save';

  @override
  String get networksCancel => 'Cancel';

  @override
  String networksShared(String preset) {
    return 'Shares the air with the public $preset mesh. A key or a name does not separate radios on the same frequency, bandwidth and spreading factor.';
  }

  @override
  String get networksIsolated =>
      'Separate from the public mesh. Radios not set to this frequency cannot hear it.';

  @override
  String networksSummary(
      String freq, String bw, String sf, String cr, String ph) {
    return '$freq MHz · $bw kHz · SF$sf · CR$cr · path hash $ph';
  }

  @override
  String networksMembers(int count) {
    return 'Members ($count)';
  }

  @override
  String get networksNoMembers => 'No members yet.';

  @override
  String get networksAddMember => 'Add member';

  @override
  String get networksNoContacts => 'No known contacts to add.';

  @override
  String get networksRemoveMember => 'Remove';

  @override
  String get networksApply => 'Apply to this radio';

  @override
  String get networksApplyNeedsRadio => 'Connect a radio to apply.';

  @override
  String networksApplyTitle(String name) {
    return 'Apply $name?';
  }

  @override
  String networksApplyBodyShared(String summary) {
    return 'This radio will switch to $summary.';
  }

  @override
  String networksApplyBodyIsolated(String summary) {
    return 'This radio will switch to $summary. It will stop hearing the public mesh until you switch it back.';
  }

  @override
  String get networksApplyConfirm => 'Apply';

  @override
  String get networksApplied => 'Applied.';

  @override
  String networksApplyFailed(String error) {
    return 'Could not apply: $error';
  }

  @override
  String get networksCurrent => 'This radio is on this network';

  @override
  String get networksDelete => 'Delete network';

  @override
  String networksDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get networksDeleteBody =>
      'Only the saved settings are removed. Radios keep what they are set to.';

  @override
  String get networksDeleteConfirm => 'Delete';

  @override
  String get placeCreateTitle => 'Drop a place';

  @override
  String get placeCreateAction => 'Report';

  @override
  String get placeLabelField => 'What is here?';

  @override
  String get placeLabelHint => 'A few words, 60 characters at most';

  @override
  String get placeTypeTitle => 'Type';

  @override
  String get placeTtlTitle => 'How long does it last?';

  @override
  String get placePrecisionTitle => 'Precision';

  @override
  String get placePrecisionExact => 'Exact';

  @override
  String get placePrecision100 => 'About 100 m';

  @override
  String get placePrecision1000 => 'About 1 km';

  @override
  String get placeSent => 'Place reported. It expires on its own.';

  @override
  String placeBudgetRefused(int n, String time) {
    return 'You have sent $n in the last hour. The next one can go at $time.';
  }

  @override
  String get placeNoIdentity =>
      'Connect a radio first: a place is reported as you.';

  @override
  String get placeLabelEmpty => 'A place needs a few words.';

  @override
  String get placeLabelTooLong => 'A label is at most 60 characters.';

  @override
  String get placeLabelCarriesTtl => 'A label cannot contain a TTL token.';

  @override
  String placeExpiresIn(String value) {
    return 'Expires in $value';
  }

  @override
  String get placeExpired => 'Expired';

  @override
  String placeReportedBy(String name, String time) {
    return 'Reported by $name, $time';
  }

  @override
  String get placeTimeUnknown => 'time unknown';

  @override
  String get placeSourceGps => 'from the sender\'s GPS';

  @override
  String get placeSourcePhone => 'from their phone';

  @override
  String get placeSourcePinned => 'placed by hand';

  @override
  String get placeSourceReceived => 'received over the mesh';

  @override
  String get placeSourceInferred => 'inferred';

  @override
  String get placeUnkeyedIdentity =>
      'Identity is a name on a channel, not a key.';

  @override
  String placeUnknownType(String token) {
    return 'Sent as $token';
  }

  @override
  String get placeConfirmAction => 'Still there';

  @override
  String get placeRefuteAction => 'Gone';

  @override
  String placeConfirmations(int n) {
    return '$n confirmed';
  }

  @override
  String placeConfirmationsMore(int n) {
    return '+$n more';
  }

  @override
  String placeClaimedConfirmations(int n) {
    return '$n claimed';
  }

  @override
  String get placeHiddenByRefutation =>
      'Hidden here after a refutation from a known key';

  @override
  String get placeDirections => 'Directions';

  @override
  String get placeDirectionsCopied => 'Coordinates copied';

  @override
  String get placeHistoryTitle => 'Places';

  @override
  String get placeHistoryEmpty =>
      'No places yet. Long-press the map to report one.';

  @override
  String get placeStateLive => 'live';

  @override
  String get placeStateExpired => 'expired';

  @override
  String get placeSearchHint => 'Search label or reporter';

  @override
  String get placeWithinAny => 'Any time left';

  @override
  String get placeWithinHour => 'Expires within 1 h';

  @override
  String get placeWithinDay => 'Expires within 24 h';

  @override
  String get placeKeyedOnly => 'Keyed places only';

  @override
  String get placeExportLedger => 'Export places';

  @override
  String get placeExportShared => 'Places ready to share.';

  @override
  String placeExportDone(String path) {
    return 'Places saved to $path';
  }

  @override
  String get placeExportFailed => 'Could not save the list.';

  @override
  String get placeCoordinatesRefused => 'Those coordinates cannot be sent.';

  @override
  String placeEchoLine(String label, String type, String expiry) {
    return '$label · $type · $expiry';
  }

  @override
  String get placeTypeHazard => 'Hazard';

  @override
  String get placeTypeWater => 'Water';

  @override
  String get placeTypeFuel => 'Fuel';

  @override
  String get placeTypeMed => 'Medical';

  @override
  String get placeTypeRally => 'Rally';

  @override
  String get placeTypeView => 'View';

  @override
  String get placeTypeCamp => 'Camp';

  @override
  String get placeTypeLook => 'Look';

  @override
  String get placeTypeOther => 'Other';

  @override
  String get failureUnsupportedCommand =>
      'The radio does not support that command. Its firmware is older than this app expects; update the radio or use a command it lists.';

  @override
  String get failureNotFound =>
      'The radio could not find the target of that request: the channel, contact or message is not on it. Refresh the contact list, then retry.';

  @override
  String get failureTableFull =>
      'The radio\'s queue or table is full, so it refused the request. Wait for it to drain, then retry; nothing was lost.';

  @override
  String get failureBadState =>
      'The radio is busy with another operation and cannot start this one. Wait for the current operation to finish, then retry.';

  @override
  String get failureFileIoError =>
      'The radio\'s storage refused the write. Its own log has the detail; retry once, and if it repeats the radio\'s filesystem needs attention.';

  @override
  String get failureIllegalArgument =>
      'The radio rejected the value or length as invalid. Check the field you changed: one value is outside what this firmware accepts.';

  @override
  String get failureUnknownDeviceError =>
      'The radio refused the request without a reason this app knows. The diagnostics page shows the raw frame.';

  @override
  String get failureBlePermissions =>
      'Bluetooth permission was refused, so the app cannot reach the radio. Allow Nearby devices for this app in Android settings, then reconnect.';

  @override
  String get failureBluetoothOff =>
      'Bluetooth is off. Turn it on, then reconnect.';

  @override
  String get failureNoRadioFound =>
      'No radio answered the scan. Check that the radio is powered on, in range, and not already connected to another phone.';

  @override
  String get failurePairingFailed =>
      'The pairing did not complete. Enter the PIN shown on the radio screen (screenless radios use 123456), then retry.';

  @override
  String get failureStalePairing =>
      'The radio no longer holds this pairing. Forget it in Android Bluetooth settings, power-cycle the radio, then pair again.';

  @override
  String get failurePairingNotKept =>
      'The radio paired but then could not encrypt on the next connection, so the pairing is not being kept. Power-cycle it and pair again; if it repeats, the fault is in the radio.';

  @override
  String get failureServiceMissing =>
      'This device does not expose the MeshCore service, so it is probably not a MeshCore radio.';

  @override
  String get failureCharacteristicMissing =>
      'The radio\'s link is missing a characteristic the app needs. Its firmware may be older than this app expects.';

  @override
  String failureMtuTooSmall(String mtu, String need) {
    return 'This phone link is $mtu bytes and one radio frame needs $need. Reconnect to try again; a radio that caps the link smaller cannot carry every frame.';
  }

  @override
  String get failureFrameTruncated =>
      'Part of a message did not arrive. The count is in Diagnostics.';

  @override
  String get failureFrameTrailingBytes =>
      'A message carried extra bytes at the end. They were dropped; the count is in Diagnostics.';

  @override
  String get failureStorageFull =>
      'The phone refused a write because storage is full. Nothing is being deleted silently; free space and the history stays as it is.';

  @override
  String get failureRadioSilent =>
      'The radio accepted the request but did not answer in time. It may still have carried it out; check the radio before retrying.';

  @override
  String get clockUnknown => 'time unknown';

  @override
  String get clockJustNow => 'just now';

  @override
  String clockMinutesAgo(String count) {
    return '$count min ago';
  }

  @override
  String clockHoursAgo(String count) {
    return '$count h ago';
  }

  @override
  String clockDaysAgo(String count) {
    return '$count d ago';
  }

  @override
  String clockAhead(String count) {
    return 'sender\'s clock is $count min ahead';
  }

  @override
  String get degradedStorageFull =>
      'This phone refused a write because storage is full. Nothing was deleted to make room; free space and history continues.';

  @override
  String get degradedClockUnset =>
      'The radio\'s clock has never been set, so times it reports are shown as time unknown until it is.';

  @override
  String get degradedBatteryCritical =>
      'The radio\'s battery is low enough that its transmissions may be cut. Charge it before relying on a long send.';

  @override
  String get degradedRadioAbsent =>
      'No radio is connected. Everything already received stays readable; sending, telemetry and places wait until a radio connects.';

  @override
  String get degradedRadioSilent =>
      'The radio is paired but has not answered. It may still have carried out the last request; check the radio before retrying.';

  @override
  String get degradedNoLocation =>
      'Location is off, so distances, bearings and place reports have no fix. Everything else works.';

  @override
  String get degradedMapOffline =>
      'Map tiles cannot be fetched. The bundled basemap and anything already on disk still draw; the rest of the app is unaffected.';

  @override
  String get sosTitle => 'Emergency';

  @override
  String get sosEntryTooltip => 'Emergency alarm and check-in';

  @override
  String sosGoesToChannel(String name) {
    return 'Channel $name';
  }

  @override
  String sosGoesToContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contact copies',
      one: '1 contact copy',
      zero: 'No direct copies',
    );
    return '$_temp0';
  }

  @override
  String get sosInRange => 'Nobody is notified unless they are in radio range.';

  @override
  String get sosHoldToArm => 'Hold to raise the alarm';

  @override
  String sosHoldRemaining(int seconds) {
    return 'Keep holding · ${seconds}s';
  }

  @override
  String get sosHoldReleased => 'Released too early — nothing was sent.';

  @override
  String get sosNoIdentity =>
      'The radio has not reported a name yet, so the alarm has no name to send.';

  @override
  String get sosWords => 'What is happening';

  @override
  String get sosWordsHint => 'Carried by every repeat, up to 96 bytes';

  @override
  String get sosDestination => 'Goes to';

  @override
  String get sosEmergencyPublicKey =>
      'The #emergency channel\'s key is derived from its name, so anyone who knows the name can compute it and read this.';

  @override
  String get sosEmergencyRepeat =>
      'The radio repeats each message once, about two minutes later. If the app closes, the rest stops.';

  @override
  String get sosContactsNone =>
      'With no contact copies, a channel acknowledgement can never stop this alarm.';

  @override
  String get sosActive => 'Alarm running';

  @override
  String sosNextSend(int seconds) {
    return 'Next in ${seconds}s';
  }

  @override
  String sosElapsed(int minutes) {
    return 'Running $minutes min';
  }

  @override
  String sosRemaining(int count, int total) {
    return '$count of $total left';
  }

  @override
  String get sosImSafe => 'I\'m safe';

  @override
  String get sosImSafeHint => 'Sends one [SAFE] and stops the repeats.';

  @override
  String get sosStopRepeats => 'Stop the repeats';

  @override
  String get sosStopHint =>
      'Stops the repeats on this phone. Nothing is sent, so nobody is told.';

  @override
  String sosMissedSends(int count) {
    return 'Not sent while the app was asleep: $count';
  }

  @override
  String get sosSendFailed =>
      'The radio refused a repeat. The schedule continues.';

  @override
  String get sosDefaultWords => 'I need help';

  @override
  String sosClaimedBy(String name) {
    return '$name claims to have seen this, on the channel. The alarm keeps going.';
  }

  @override
  String sosSeenBy(String name) {
    return '$name has seen this, by direct message.';
  }

  @override
  String get sosExpired =>
      'The alarm has stopped repeating. It is not resolved.';

  @override
  String get sosCancelled => 'The alarm is stopped.';

  @override
  String get sosAcknowledgedHeading => 'Seen';

  @override
  String get sosDismiss => 'Close';

  @override
  String get sosRefusedAlreadyActive => 'An alarm is already running.';

  @override
  String get sosRefusedNoDestination => 'Choose where the alarm goes first.';

  @override
  String get sosRefusedNoWords => 'Say what is happening first.';

  @override
  String get sosRefusedTooLong =>
      'Too long to carry a name and a position. Shorten it.';

  @override
  String get sosRefusedHold => 'The hold is not finished.';

  @override
  String get checkinTitle => 'Check-in';

  @override
  String get checkinEntryTooltip => 'Check-in';

  @override
  String get checkinIntro =>
      'One message with a deadline. The app marks it overdue here; the radio keeps no timer.';

  @override
  String checkinInMinutes(int minutes) {
    return 'Deadline in $minutes min';
  }

  @override
  String get checkinSend => 'Send check-in';

  @override
  String get checkinOneMessage =>
      'A check-in is one message and does not repeat.';

  @override
  String checkinUntil(String time) {
    return 'Deadline $time';
  }

  @override
  String get checkinWatching => 'Waiting for an answer';

  @override
  String get checkinOverdue =>
      'Overdue — the deadline passed and no answer came back.';

  @override
  String get checkinAnsweredDirect => 'Answered, by direct message.';

  @override
  String get checkinAnsweredChannel =>
      'Answered on the channel by name only, not by their key.';

  @override
  String get checkinSent => 'Check-in sent. Nothing repeats.';

  @override
  String get checkinNeedsRadio =>
      'A check-in needs a connected radio and the radio\'s name.';

  @override
  String get mediaComposerTitle => 'Send a photo';

  @override
  String get mediaSourceUnavailable =>
      'This build cannot read a photo from the device, so nothing can be sent from here.';

  @override
  String get mediaSourceFailed =>
      'That photo could not be read. Try another one.';

  @override
  String get mediaPickCamera => 'Take a photo';

  @override
  String get mediaPickGallery => 'Choose a photo';

  @override
  String get mediaSourceUnsupportedFormat =>
      'That file is not an image this build can read. HEIC and AV1 are not supported here, so choose a JPEG or PNG photo.';

  @override
  String get mediaEncoding => 'Fitting the photo to the mesh…';

  @override
  String mediaCostLine(int chunks, String airtime) {
    return '$chunks packets · about $airtime on air';
  }

  @override
  String get mediaOverBudget =>
      'This photo will not fit the mesh budget even at the lowest quality. It can still be sent, but it will be cut off.';

  @override
  String mediaSendingProgress(int sent, int total) {
    return '$sent of $total packets sent';
  }

  @override
  String mediaReceiptLine(int chunks, int resends) {
    return '$chunks packets sent, $resends of them resent';
  }

  @override
  String get mediaAcceptedNotDelivered =>
      'The radio accepted these packets. A broadcast carries no delivery promise.';

  @override
  String mediaSendFailed(int count) {
    return 'The radio refused $count packet(s), so this photo did not finish.';
  }

  @override
  String get mediaSend => 'Send';

  @override
  String get mediaRetrySend => 'Try again';

  @override
  String get mediaClose => 'Close';

  @override
  String get mediaOffOnPublic =>
      'Media is off on the Public channel. Turn it on for that channel in its settings first.';

  @override
  String get mediaPayloadUnusable => 'There is nothing to send.';

  @override
  String get mediaChannelUnknown =>
      'No channel is selected, so there is nobody to send to.';

  @override
  String mediaReceiveWaiting(int received, int total, int missing) {
    return '$received of $total packets · waiting for $missing';
  }

  @override
  String get mediaReceiveAsk => 'Ask for the missing packets';

  @override
  String mediaReceiveRequested(int count) {
    return 'Asked the sender for $count packet(s).';
  }

  @override
  String get mediaReceiveComplete => 'Photo received.';

  @override
  String get mediaDecodeFailed => 'This photo arrived but cannot be read.';

  @override
  String get mediaPhotoSemantics => 'Photo received over the mesh';

  @override
  String get placePhotoNotFetched =>
      'Photo not fetched. The report itself is complete; the picture is optional and may never arrive.';

  @override
  String get placePhotoMayNotArrive =>
      'The photo may not arrive. The text will.';

  @override
  String get placePhotoFetch => 'Fetch photo';

  @override
  String get placePhotoFetching => 'Asking the mesh for the photo…';

  @override
  String get geofenceTitle => 'Geofences';

  @override
  String get geofenceExplainer =>
      'A fence is a circle you watch. It tells you once when you enter it and once when you leave, so walking along its edge does not produce a stream of alerts.';

  @override
  String get geofenceAddSection => 'Add a fence';

  @override
  String geofenceRadius(int meters) {
    return '$meters m';
  }

  @override
  String get geofenceNeedsFix =>
      'A fence needs your position. Connect the radio or allow location first.';

  @override
  String get geofenceAddHere => 'Add a fence here';

  @override
  String get geofenceListSection => 'Your fences';

  @override
  String get geofenceEmpty => 'No fences yet.';

  @override
  String get geofenceInsideNow => 'You are inside';

  @override
  String get geofenceOutsideNow => 'You are outside';

  @override
  String get geofenceDelete => 'Delete fence';

  @override
  String get geofenceEventsSection => 'Recent crossings';

  @override
  String geofenceEntered(String label) {
    return 'Entered $label';
  }

  @override
  String geofenceLeft(String label) {
    return 'Left $label';
  }

  @override
  String geofenceDefaultName(int number) {
    return 'Fence $number';
  }

  @override
  String nodeClosing(String name, String distance) {
    return '$name is $distance away and closing';
  }

  @override
  String nodeOpening(String name, String distance) {
    return '$name is $distance away and moving away';
  }

  @override
  String get geofenceExplainerShort =>
      'Circles that tell you when you arrive or leave';

  @override
  String get coverageTitle => 'Coverage';

  @override
  String get coverageCountsTitle => 'Coverage';

  @override
  String get fieldExportSummaryLine => 'Trail and field record';

  @override
  String get diagnosticsRadioHealth => 'Radio health';

  @override
  String get radioHealthSummaryLine => 'Battery, noise floor, last packet';

  @override
  String get coverageBeforeStart =>
      'This records where you are and who answered. It stays on this device, and closing the app ends the record.';

  @override
  String get coverageStart => 'Start recording';

  @override
  String get coverageStop => 'Stop recording';

  @override
  String coverageCounts(int answered, int tried) {
    return '$answered of $tried pings answered';
  }

  @override
  String coverageUnmatched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count replies could not be identified.',
      one: 'One reply could not be identified.',
    );
    return '$_temp0';
  }

  @override
  String get coverageRefusedTooSoon =>
      'The app paces itself: one ping every thirty seconds, so this one waits.';

  @override
  String get coverageRefusedCellFresh =>
      'This area was pinged within the hour. Standing still costs one ping an hour.';

  @override
  String get coverageRefusedManualUsed =>
      'This hour\'s manual ping is already spent.';

  @override
  String get coveragePacingNote =>
      'This app paces its own pings; it cannot promise other devices do.';

  @override
  String get coveragePingNow => 'Ping now (once an hour)';

  @override
  String get coverageCellsSection => 'Where you pinged';

  @override
  String get coverageNoSamples => 'Nothing recorded yet.';

  @override
  String coverageCellLine(String cell, int percent, int samples) {
    return '$cell · $percent% · $samples samples';
  }

  @override
  String coverageHidden(int count) {
    return '$count hidden';
  }

  @override
  String coverageEdges(int count) {
    return '$count answers drawn — answers only, never an inferred link';
  }

  @override
  String get coverageNotAMap =>
      'This is where your pings were answered, not where the mesh reaches.';

  @override
  String get coverageExplainerShort => 'Which pings were answered, here';

  @override
  String get fieldExportSection => 'Field record';

  @override
  String get fieldExportExplainer =>
      'One file with the trail, the places, the answered pings and the check-in. It is plain JSON, not encrypted, so it can be handed on.';

  @override
  String get fieldExportAction => 'Export this session';

  @override
  String get fieldExportShared => 'Field record ready to share.';

  @override
  String fieldExportDone(String path) {
    return 'Field record written. The path is on the clipboard: $path';
  }

  @override
  String get gpxExportExplainer =>
      'The trail as a GPX track any mapping app can read. It is plain text, not encrypted, unlike your messages.';

  @override
  String get gpxExportAction => 'Share trail as GPX';

  @override
  String get gpxExportTrackName => 'MeshMore trail';

  @override
  String get gpxExportEmpty =>
      'No trail yet. Positions are recorded while the app runs, so there is nothing to write.';

  @override
  String get gpxExportShared => 'Trail ready to share.';

  @override
  String gpxExportDone(String path) {
    return 'Trail written. The path is on the clipboard: $path';
  }

  @override
  String get chatSearchAction => 'Search messages';

  @override
  String get chatExportAction => 'Export this conversation';

  @override
  String get chatExportTitle => 'Passphrase for the exported file';

  @override
  String get chatExportPassphrase => 'Passphrase';

  @override
  String get chatExportConfirm => 'Export';

  @override
  String get chatExportShared => 'Conversation ready to share.';

  @override
  String chatExportDone(String path) {
    return 'Conversation saved to $path';
  }

  @override
  String get chatExportFailed =>
      'The conversation could not be written. Nothing was exported.';

  @override
  String get chatSearchHint => 'Search stored history';

  @override
  String get chatSearchPrompt =>
      'Type to search the messages this device stored.';

  @override
  String chatSearchNoResults(String query) {
    return 'No message matches “$query”.';
  }

  @override
  String chatSearchHidden(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches hidden by a block',
      one: '1 match hidden by a block',
    );
    return '$_temp0';
  }

  @override
  String chatSearchTruncated(int count) {
    return 'Showing the newest $count matches. Narrow the search to see the rest.';
  }

  @override
  String chatSearchRetention(int cap) {
    return 'This device keeps the newest $cap messages, so older ones are not searched.';
  }

  @override
  String get chatSearchDm => 'Direct message';

  @override
  String chatUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread',
      one: '1 unread',
    );
    return '$_temp0';
  }

  @override
  String get blockedKeysTitle => 'Blocked keys';

  @override
  String blockedKeysSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keys blocked',
      one: '1 key blocked',
      zero: 'No key is blocked',
    );
    return '$_temp0';
  }

  @override
  String get blockedKeysEmpty =>
      'No key is blocked. Blocking a key hides what it sends — messages, notifications, places — on this device.';

  @override
  String get blockedKeysCannotStop =>
      'A block is local to this app. The radio still receives and relays the packet; what stops is what this app shows.';

  @override
  String get blockedKeysUnblock => 'Unblock';

  @override
  String blockedKeysSince(String when) {
    return 'Blocked $when';
  }

  @override
  String get blockedKeysUnknownName => 'No name known';

  @override
  String blockedKeysCapacity(int cap) {
    return 'The list is full: $cap keys. Unblock one before adding another.';
  }

  @override
  String blockedKeysUnblocked(String name) {
    return '$name is unblocked. Their messages appear again.';
  }

  @override
  String get blockedKeysUnblockedUnnamed =>
      'The key is unblocked. Its messages appear again.';

  @override
  String get reportAction => 'Report…';

  @override
  String get reportSheetTitle => 'Report this message';

  @override
  String get reportObservationLabel => 'What did you see? (optional)';

  @override
  String get reportNothingSent =>
      'Nothing was sent. The app wrote a file on this device; you decide where it goes.';

  @override
  String reportBundleWritten(String path) {
    return 'Report saved to $path';
  }

  @override
  String get reportCopyBundle => 'Copy the report';

  @override
  String get reportCopied => 'Report copied.';

  @override
  String get blockedKeysNotPersisted =>
      'This list could not be saved on this device. It filters for now and will be empty after a restart.';

  @override
  String get reportActionSub =>
      'Writes a file on this device for you to send. Nothing is transmitted.';

  @override
  String sosDestinationContactsLimit(int count) {
    return 'Up to $count contacts';
  }

  @override
  String get sosDestinationChange => 'Change';

  @override
  String get sosDestinationPickerTitle => 'Where the alarm goes';

  @override
  String get sosDestinationChannelHeader => 'Channel';

  @override
  String get sosDestinationContactsHeader => 'Direct copies';

  @override
  String get sosDestinationContactsHelp =>
      'A direct copy from one of these keys can stop the alarm. A channel reply cannot.';

  @override
  String get sosDestinationMissing =>
      'The channel this alarm was set to is gone. Choose another.';

  @override
  String get sosDestinationNoContacts => 'No contacts yet';

  @override
  String get sosDestinationNotAContact => 'not in contacts';

  @override
  String get sosDestinationDone => 'Done';

  @override
  String get sosEmergencyShort =>
      'Public channel, one repeat if the app closes';

  @override
  String get sosAboutTitle => 'About this destination';

  @override
  String get sosRepeatsShort => 'repeats up to 1 h';

  @override
  String placeTtlMinutes(int count) {
    return '$count min';
  }

  @override
  String placeTtlHours(int count) {
    return '$count h';
  }

  @override
  String placeTtlDays(int count) {
    return '$count d';
  }

  @override
  String get mapReportPlace => 'Report a place';

  @override
  String get settingsAppGroupRadio => 'Radio';

  @override
  String get settingsAppGroupSound => 'Reading and sound';

  @override
  String get settingsAppGroupData => 'Data';

  @override
  String get settingsAppGroupSystem => 'System';

  @override
  String get aboutReplayIntro => 'Replay the first-run screens';

  @override
  String get toolsGroupDiagnostics => 'Radio diagnostics';

  @override
  String nodeMarkerSemantics(String name) {
    return '$name — tap for details';
  }

  @override
  String placePinSemantics(String label, String expiry) {
    return '$label, $expiry';
  }

  @override
  String placeClusterSemantics(int count) {
    return '$count places here';
  }

  @override
  String get mapCanvasSemantics => 'Tap a marker on the map to open it';

  @override
  String get gridLegendSignalOnly => 'Hollow · no position';

  @override
  String get gridOpenMap => 'Open the map';

  @override
  String get gridMoreViews => 'More views';

  @override
  String get gridLegendMore => 'Full legend';

  @override
  String get gridLegendRingsShort => 'Rings · distance';

  @override
  String get gridLegendSelfShort => 'Centre · you';

  @override
  String get gridLegendDotShort => 'Dot · heard here';

  @override
  String get gridLegendKnownShort => 'Pulse · known';

  @override
  String get gridLegendFavShort => 'Blink · favourite';

  @override
  String get gridLegendRippleShort => 'Ripple · channel message';

  @override
  String get gridLegendTapShort => 'Tap · details';

  @override
  String get treeSelfShort => 'Centre · you';

  @override
  String get treeRepeaterShort => 'Square · repeater';

  @override
  String get treeRoomShort => 'Diamond · room';

  @override
  String get treeChatShort => 'Circle · chat';

  @override
  String get treeSensorShort => 'Wave · sensor';

  @override
  String get treeFloodShort => 'Dots · flood hop';

  @override
  String get treeArrowShort => 'Arrow · route out';

  @override
  String get fabricCellShort => 'Cell · mesh heard here';

  @override
  String get fabricRecencyShort => 'Brighter · more recent';

  @override
  String get fabricMarkerShort => 'Pin · peer now';

  @override
  String get snsHotShort => 'Red · busy now';

  @override
  String get snsCoolShort => 'Fading · cooling';

  @override
  String get snsToastShort => 'Flash · new message';

  @override
  String get snsDecayShort => 'Last hour only';

  @override
  String get fujiMeShort => 'Dashed · you';

  @override
  String get fujiRefsShort => 'Silhouettes · scale';

  @override
  String get fujiPeersShort => 'Dots · peers';

  @override
  String get fujiUnknownShort => 'Striped · no altitude';

  @override
  String get chatSpeechOffAction => 'Speech is off in App settings';

  @override
  String get nodeDetailAltitudeNotReported => 'not reported';
}
