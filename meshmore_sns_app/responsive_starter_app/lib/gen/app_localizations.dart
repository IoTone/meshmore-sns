import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Meshmore SNS'**
  String get appName;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mesh messaging over radio'**
  String get appSubtitle;

  /// No description provided for @tabDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get tabDashboard;

  /// No description provided for @dashboardPinsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get dashboardPinsTitle;

  /// No description provided for @dashboardPinsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit pins'**
  String get dashboardPinsEdit;

  /// No description provided for @dashboardPinsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dashboardPinsDone;

  /// No description provided for @dashboardPinsMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get dashboardPinsMoveUp;

  /// No description provided for @dashboardPinsMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get dashboardPinsMoveDown;

  /// No description provided for @dashboardPinAdd.
  ///
  /// In en, this message translates to:
  /// **'Pin to dashboard'**
  String get dashboardPinAdd;

  /// No description provided for @dashboardPinRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from dashboard'**
  String get dashboardPinRemove;

  /// No description provided for @pinCoverageNone.
  ///
  /// In en, this message translates to:
  /// **'No pings yet'**
  String get pinCoverageNone;

  /// No description provided for @pinCoverageAnswered.
  ///
  /// In en, this message translates to:
  /// **'{answered} of {tried} answered'**
  String pinCoverageAnswered(int answered, int tried);

  /// No description provided for @tabChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get tabChat;

  /// No description provided for @tabNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get tabNodes;

  /// No description provided for @tabMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get tabMap;

  /// No description provided for @tabDocs.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get tabDocs;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @tabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get tabAbout;

  /// No description provided for @dashboardPeersInRange.
  ///
  /// In en, this message translates to:
  /// **'NODES IN RANGE'**
  String get dashboardPeersInRange;

  /// No description provided for @dashboardKnownCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{0 known} =1{1 known} other{{n} known}}'**
  String dashboardKnownCount(int n);

  /// One line on the dashboard: how many nodes the app knows, and the radio's own contact table. One localised sentence rather than fragments joined with literal separators.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{0 known} =1{1 known} other{{n} known}} · contacts {contacts}'**
  String dashboardKnownAndContacts(int n, String contacts);

  /// No description provided for @dashboardMyPubkey.
  ///
  /// In en, this message translates to:
  /// **'my pubkey · {hex}'**
  String dashboardMyPubkey(String hex);

  /// No description provided for @dashboardPubkeyAwaiting.
  ///
  /// In en, this message translates to:
  /// **'my pubkey · awaiting device'**
  String get dashboardPubkeyAwaiting;

  /// No description provided for @dashboardPubkeyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy. This is what someone else needs to add you as a contact.'**
  String get dashboardPubkeyHint;

  /// No description provided for @botTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-reply bot'**
  String get botTitle;

  /// No description provided for @botSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Answers messages here automatically. Off by default.'**
  String get botSubtitle;

  /// No description provided for @botOnWire.
  ///
  /// In en, this message translates to:
  /// **'Replies are sent with a [bot] prefix, so the person on the other end can tell a machine wrote them.'**
  String get botOnWire;

  /// No description provided for @botRefusedPublicSlot.
  ///
  /// In en, this message translates to:
  /// **'Not available on the public channel.'**
  String get botRefusedPublicSlot;

  /// No description provided for @botRefusedPublicPsk.
  ///
  /// In en, this message translates to:
  /// **'This channel still uses the public key, so it is public whatever its number. Give it a private key first.'**
  String get botRefusedPublicPsk;

  /// No description provided for @botRefusedUnknownPsk.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the radio to send this channel\'s key.'**
  String get botRefusedUnknownPsk;

  /// No description provided for @botMode.
  ///
  /// In en, this message translates to:
  /// **'Reply mode'**
  String get botMode;

  /// No description provided for @botModeDeterministic.
  ///
  /// In en, this message translates to:
  /// **'Deterministic'**
  String get botModeDeterministic;

  /// No description provided for @botModeRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get botModeRandom;

  /// No description provided for @botModeDeterministicSub.
  ///
  /// In en, this message translates to:
  /// **'The first matching rule always wins, so two runs can be compared.'**
  String get botModeDeterministicSub;

  /// No description provided for @botModeRandomSub.
  ///
  /// In en, this message translates to:
  /// **'Picks among matching rules, replayable from the seed.'**
  String get botModeRandomSub;

  /// No description provided for @botSeed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get botSeed;

  /// No description provided for @botBudget.
  ///
  /// In en, this message translates to:
  /// **'{n} replies left this window'**
  String botBudget(int n);

  /// No description provided for @botCounters.
  ///
  /// In en, this message translates to:
  /// **'received {r} · replied {p} · held back {s}'**
  String botCounters(int r, int p, int s);

  /// No description provided for @botResetCounters.
  ///
  /// In en, this message translates to:
  /// **'Reset counters'**
  String get botResetCounters;

  /// No description provided for @botEditRules.
  ///
  /// In en, this message translates to:
  /// **'Edit rules'**
  String get botEditRules;

  /// No description provided for @botRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rulepack'**
  String get botRulesTitle;

  /// No description provided for @botRulesRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore default'**
  String get botRulesRestore;

  /// No description provided for @botRulesErrors.
  ///
  /// In en, this message translates to:
  /// **'{n} line(s) could not be read and were skipped'**
  String botRulesErrors(int n);

  /// No description provided for @botRulesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get botRulesSave;

  /// No description provided for @botFromBot.
  ///
  /// In en, this message translates to:
  /// **'bot'**
  String get botFromBot;

  /// No description provided for @dashboardRadio.
  ///
  /// In en, this message translates to:
  /// **'RADIO'**
  String get dashboardRadio;

  /// No description provided for @dashNervLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get dashNervLink;

  /// No description provided for @dashNervNode.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get dashNervNode;

  /// No description provided for @dashNervRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get dashNervRegion;

  /// No description provided for @dashContacts.
  ///
  /// In en, this message translates to:
  /// **'CONTACTS'**
  String get dashContacts;

  /// No description provided for @dashNervMesh.
  ///
  /// In en, this message translates to:
  /// **'Mesh'**
  String get dashNervMesh;

  /// No description provided for @dashNervKnown.
  ///
  /// In en, this message translates to:
  /// **'Known'**
  String get dashNervKnown;

  /// No description provided for @dashNervEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get dashNervEvents;

  /// No description provided for @dashHyperEmpty.
  ///
  /// In en, this message translates to:
  /// **'Listening for nodes…'**
  String get dashHyperEmpty;

  /// No description provided for @dashPeers.
  ///
  /// In en, this message translates to:
  /// **'NODES'**
  String get dashPeers;

  /// No description provided for @dashAgHudSignal.
  ///
  /// In en, this message translates to:
  /// **'SIGNAL'**
  String get dashAgHudSignal;

  /// No description provided for @dashAgHudTraffic.
  ///
  /// In en, this message translates to:
  /// **'ch traffic'**
  String get dashAgHudTraffic;

  /// No description provided for @dashDrPopLink.
  ///
  /// In en, this message translates to:
  /// **'LINK'**
  String get dashDrPopLink;

  /// No description provided for @dashReconNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts in range'**
  String get dashReconNoContacts;

  /// No description provided for @dashAgHudOfKnown.
  ///
  /// In en, this message translates to:
  /// **'of {count} known'**
  String dashAgHudOfKnown(String count);

  /// No description provided for @dashboardLocation.
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get dashboardLocation;

  /// No description provided for @dashboardBattery.
  ///
  /// In en, this message translates to:
  /// **'BATTERY'**
  String get dashboardBattery;

  /// No description provided for @dashboardRecent.
  ///
  /// In en, this message translates to:
  /// **'RECENT'**
  String get dashboardRecent;

  /// No description provided for @dashboardNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get dashboardNoActivity;

  /// No description provided for @dashboardAwaitingDevice.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the radio…'**
  String get dashboardAwaitingDevice;

  /// No description provided for @dashboardAwaitingDeviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a location…'**
  String get dashboardAwaitingDeviceLocation;

  /// No description provided for @dashboardUnnamed.
  ///
  /// In en, this message translates to:
  /// **'(unnamed)'**
  String get dashboardUnnamed;

  /// No description provided for @dashboardLocationNotSet.
  ///
  /// In en, this message translates to:
  /// **'No location'**
  String get dashboardLocationNotSet;

  /// No description provided for @dashboardLocationConfigure.
  ///
  /// In en, this message translates to:
  /// **'CONFIGURE'**
  String get dashboardLocationConfigure;

  /// No description provided for @statusLinked.
  ///
  /// In en, this message translates to:
  /// **'LINKED'**
  String get statusLinked;

  /// No description provided for @statusSyncing.
  ///
  /// In en, this message translates to:
  /// **'SYNCING…'**
  String get statusSyncing;

  /// No description provided for @statusHandshaking.
  ///
  /// In en, this message translates to:
  /// **'SYNCING…'**
  String get statusHandshaking;

  /// No description provided for @statusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'RECONNECTING…'**
  String get statusReconnecting;

  /// No description provided for @statusLinkLost.
  ///
  /// In en, this message translates to:
  /// **'LINK LOST'**
  String get statusLinkLost;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get statusOffline;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'CONNECTING…'**
  String get statusConnecting;

  /// No description provided for @linkChipLinked.
  ///
  /// In en, this message translates to:
  /// **'LINKED'**
  String get linkChipLinked;

  /// No description provided for @linkChipSync.
  ///
  /// In en, this message translates to:
  /// **'SYNC'**
  String get linkChipSync;

  /// No description provided for @linkChipRetry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get linkChipRetry;

  /// No description provided for @linkChipFail.
  ///
  /// In en, this message translates to:
  /// **'FAIL'**
  String get linkChipFail;

  /// No description provided for @linkChipScan.
  ///
  /// In en, this message translates to:
  /// **'SCAN'**
  String get linkChipScan;

  /// No description provided for @linkChipOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get linkChipOffline;

  /// No description provided for @linkChipSemantics.
  ///
  /// In en, this message translates to:
  /// **'Radio {state}'**
  String linkChipSemantics(String state);

  /// No description provided for @actionConnect.
  ///
  /// In en, this message translates to:
  /// **'CONNECT'**
  String get actionConnect;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @dashboardDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get dashboardDevice;

  /// No description provided for @deviceMgrTitle.
  ///
  /// In en, this message translates to:
  /// **'DEVICE'**
  String get deviceMgrTitle;

  /// No description provided for @deviceMgrNoPair.
  ///
  /// In en, this message translates to:
  /// **'No device paired'**
  String get deviceMgrNoPair;

  /// No description provided for @deviceMgrStateConnected.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED'**
  String get deviceMgrStateConnected;

  /// No description provided for @deviceMgrStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'CONNECTING…'**
  String get deviceMgrStateConnecting;

  /// No description provided for @deviceMgrStateReconnecting.
  ///
  /// In en, this message translates to:
  /// **'RECONNECTING…'**
  String get deviceMgrStateReconnecting;

  /// No description provided for @deviceMgrStateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'DISCONNECTED'**
  String get deviceMgrStateDisconnected;

  /// No description provided for @deviceMgrStateFailed.
  ///
  /// In en, this message translates to:
  /// **'FAILED'**
  String get deviceMgrStateFailed;

  /// No description provided for @deviceMgrDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get deviceMgrDisconnect;

  /// No description provided for @deviceMgrReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get deviceMgrReconnect;

  /// No description provided for @deviceMgrForget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get deviceMgrForget;

  /// No description provided for @deviceMgrPick.
  ///
  /// In en, this message translates to:
  /// **'PICK A DEVICE'**
  String get deviceMgrPick;

  /// No description provided for @deviceMgrScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get deviceMgrScan;

  /// No description provided for @deviceMgrStopScan.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get deviceMgrStopScan;

  /// No description provided for @deviceMgrScanHint.
  ///
  /// In en, this message translates to:
  /// **'Tap Scan to look for nearby MeshCore devices. When two are in range, pick the one you want.'**
  String get deviceMgrScanHint;

  /// No description provided for @deviceMgrScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {message}'**
  String deviceMgrScanFailed(String message);

  /// No description provided for @deviceMgrRecent.
  ///
  /// In en, this message translates to:
  /// **'RECENTLY PAIRED'**
  String get deviceMgrRecent;

  /// No description provided for @deviceMgrAgoNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get deviceMgrAgoNever;

  /// No description provided for @deviceMgrAgoNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get deviceMgrAgoNow;

  /// No description provided for @deviceMgrAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String deviceMgrAgoMinutes(int n);

  /// No description provided for @deviceMgrAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String deviceMgrAgoHours(int n);

  /// No description provided for @deviceMgrAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{n} d ago'**
  String deviceMgrAgoDays(int n);

  /// No description provided for @deviceMgrPairNew.
  ///
  /// In en, this message translates to:
  /// **'Pair a new radio'**
  String get deviceMgrPairNew;

  /// No description provided for @pairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair a radio'**
  String get pairTitle;

  /// No description provided for @pairStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String pairStepOf(int step, int total);

  /// No description provided for @pairPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission'**
  String get pairPermissionTitle;

  /// No description provided for @pairPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'The app needs Nearby devices to find your radio and talk to it. Nothing is paired yet.'**
  String get pairPermissionBody;

  /// No description provided for @pairPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth'**
  String get pairPermissionAllow;

  /// No description provided for @pairPermissionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open OS settings'**
  String get pairPermissionOpenSettings;

  /// No description provided for @pairAdapterTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off'**
  String get pairAdapterTitle;

  /// No description provided for @pairAdapterBody.
  ///
  /// In en, this message translates to:
  /// **'Switch Bluetooth on to find your radio. This screen continues by itself once it is on.'**
  String get pairAdapterBody;

  /// No description provided for @pairAdapterUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This phone reports no usable Bluetooth adapter, so a radio cannot be paired here.'**
  String get pairAdapterUnsupported;

  /// No description provided for @pairRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get pairRetry;

  /// No description provided for @pairScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking for radios'**
  String get pairScanTitle;

  /// No description provided for @pairScanBody.
  ///
  /// In en, this message translates to:
  /// **'A radio advertises as MeshCore-<name>. Keep it switched on and within a metre or two of the phone.'**
  String get pairScanBody;

  /// No description provided for @pairScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get pairScanning;

  /// No description provided for @pairStopScan.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get pairStopScan;

  /// No description provided for @pairScanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get pairScanAgain;

  /// No description provided for @pairNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No radio answered. Check that it is switched on, in range, and not already connected to another phone, then scan again.'**
  String get pairNothingFound;

  /// No description provided for @pairRssi.
  ///
  /// In en, this message translates to:
  /// **'RSSI {rssi}'**
  String pairRssi(int rssi);

  /// No description provided for @pairConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {name}…'**
  String pairConnecting(String name);

  /// No description provided for @pairConnectingBody.
  ///
  /// In en, this message translates to:
  /// **'If the radio shows a PIN, enter it on the phone when asked. Screenless radios use 123456.'**
  String get pairConnectingBody;

  /// No description provided for @pairConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio connected'**
  String get pairConfirmTitle;

  /// No description provided for @pairConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} answered, so the link and the protocol both work. This radio is now the one the app uses.'**
  String pairConfirmBody(String name);

  /// No description provided for @pairConfirmNode.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get pairConfirmNode;

  /// No description provided for @pairConfirmFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get pairConfirmFirmware;

  /// No description provided for @pairConfirmUse.
  ///
  /// In en, this message translates to:
  /// **'Use this radio'**
  String get pairConfirmUse;

  /// No description provided for @pairChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another radio'**
  String get pairChooseAnother;

  /// No description provided for @settingsHeading.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get settingsHeading;

  /// No description provided for @settingsBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay connected in background'**
  String get settingsBackgroundTitle;

  /// No description provided for @settingsBackgroundOn.
  ///
  /// In en, this message translates to:
  /// **'Messages arrive while the app is closed'**
  String get settingsBackgroundOn;

  /// No description provided for @settingsBackgroundOff.
  ///
  /// In en, this message translates to:
  /// **'Messages arrive when you open the app'**
  String get settingsBackgroundOff;

  /// No description provided for @settingsTelemetryPoll.
  ///
  /// In en, this message translates to:
  /// **'Gather node telemetry'**
  String get settingsTelemetryPoll;

  /// No description provided for @settingsTelemetryPollOn.
  ///
  /// In en, this message translates to:
  /// **'Politely polls contacts for temperature / altitude (a little OTA airtime)'**
  String get settingsTelemetryPollOn;

  /// No description provided for @settingsTelemetryPollOff.
  ///
  /// In en, this message translates to:
  /// **'No telemetry requests sent; query a node manually from its detail'**
  String get settingsTelemetryPollOff;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get settingsLanguageJapanese;

  /// No description provided for @settingsSpeech.
  ///
  /// In en, this message translates to:
  /// **'SPEECH'**
  String get settingsSpeech;

  /// No description provided for @settingsSpeechOn.
  ///
  /// In en, this message translates to:
  /// **'Text-to-speech ON · per-channel toggle in Chat'**
  String get settingsSpeechOn;

  /// No description provided for @settingsSpeechOff.
  ///
  /// In en, this message translates to:
  /// **'Text-to-speech OFF (default) · reads channel messages'**
  String get settingsSpeechOff;

  /// No description provided for @settingsSpeechMuted.
  ///
  /// In en, this message translates to:
  /// **'Speech is on but muted with the alert sounds.'**
  String get settingsSpeechMuted;

  /// No description provided for @settingsPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get settingsPermissions;

  /// No description provided for @settingsPermissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth, notifications and location'**
  String get settingsPermissionsSubtitle;

  /// No description provided for @termsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms and privacy'**
  String get termsTitle;

  /// No description provided for @termsLead.
  ///
  /// In en, this message translates to:
  /// **'This app talks to a mesh radio. There is no account, no cloud and no analytics.'**
  String get termsLead;

  /// No description provided for @termsSectionLocal.
  ///
  /// In en, this message translates to:
  /// **'WHAT STAYS ON THIS DEVICE'**
  String get termsSectionLocal;

  /// No description provided for @termsLocalBody.
  ///
  /// In en, this message translates to:
  /// **'Messages, contacts, channels and settings are stored on this device; message history is encrypted with a key this phone holds and cannot export. Places, the trail, coverage and geofences are kept in the clear on this device, because they are what the map draws while you use it. Cloud backup and device transfer are off for all of it, so a new phone does not silently inherit it. Deleting the app deletes that data.'**
  String get termsLocalBody;

  /// No description provided for @termsSectionLeaves.
  ///
  /// In en, this message translates to:
  /// **'WHAT LEAVES THE DEVICE'**
  String get termsSectionLeaves;

  /// No description provided for @termsLeavesBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing leaves except what you send: messages and positions go out over the radio you are connected to. Online map packs are off by default and are fetched only after you turn them on, with the source named on screen. Files you export are yours to place.'**
  String get termsLeavesBody;

  /// No description provided for @termsSectionPermissions.
  ///
  /// In en, this message translates to:
  /// **'PERMISSIONS AND WHY'**
  String get termsSectionPermissions;

  /// No description provided for @termsPermissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth connects to the radio. Location is used for your own position and, on older Android, to allow a Bluetooth scan. Notifications are used for messages that arrive while the app is in the background. Refusing any of them leaves the app usable without a radio.'**
  String get termsPermissionsBody;

  /// No description provided for @termsSectionRetention.
  ///
  /// In en, this message translates to:
  /// **'HOW MUCH IS KEPT'**
  String get termsSectionRetention;

  /// No description provided for @termsRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'Each conversation keeps its newest {cap} messages; older ones are dropped. A place expires when its own timer runs out, and is then gone.'**
  String termsRetentionBody(int cap);

  /// No description provided for @termsSectionChanges.
  ///
  /// In en, this message translates to:
  /// **'CHANGES'**
  String get termsSectionChanges;

  /// No description provided for @termsChangesBody.
  ///
  /// In en, this message translates to:
  /// **'If this text changes in a way that matters, the version below changes and this page is shown again before the app opens.'**
  String get termsChangesBody;

  /// No description provided for @termsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String termsVersion(int version);

  /// No description provided for @termsGateNote.
  ///
  /// In en, this message translates to:
  /// **'Agreeing is required to use the app.'**
  String get termsGateNote;

  /// No description provided for @termsExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get termsExit;

  /// No description provided for @termsAccept.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get termsAccept;

  /// No description provided for @termsAcceptedVersion.
  ///
  /// In en, this message translates to:
  /// **'You agreed to version {version}.'**
  String termsAcceptedVersion(int version);

  /// No description provided for @termsNotAccepted.
  ///
  /// In en, this message translates to:
  /// **'Not agreed.'**
  String get termsNotAccepted;

  /// No description provided for @termsSettingsRow.
  ///
  /// In en, this message translates to:
  /// **'Terms and privacy'**
  String get termsSettingsRow;

  /// No description provided for @termsSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What is stored, what leaves the device, and why each permission is asked for'**
  String get termsSettingsSubtitle;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright (c) 2026 IoTone, Inc.'**
  String get aboutCopyright;

  /// No description provided for @aboutSubtitleEn.
  ///
  /// In en, this message translates to:
  /// **'(Socialrobot Network Service)'**
  String get aboutSubtitleEn;

  /// No description provided for @aboutSubtitleJa.
  ///
  /// In en, this message translates to:
  /// **'(ソーシャルロボット・ネットワークサービス)'**
  String get aboutSubtitleJa;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'A MeshCore companion client.'**
  String get aboutDescription;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'Licensed under the MIT (X11) License.'**
  String get aboutLicense;

  /// No description provided for @aboutMadeWith.
  ///
  /// In en, this message translates to:
  /// **'Made with ♥ in Fukuoka, Japan'**
  String get aboutMadeWith;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutReportProblem.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get aboutReportProblem;

  /// No description provided for @aboutReportProblemSub.
  ///
  /// In en, this message translates to:
  /// **'Opens the issue tracker with the app and radio details filled in. Nothing is sent unless you send it there.'**
  String get aboutReportProblemSub;

  /// No description provided for @aboutLicensesButton.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses & attributions'**
  String get aboutLicensesButton;

  /// No description provided for @aboutAttributions.
  ///
  /// In en, this message translates to:
  /// **'Includes MeshCore documentation (MIT), GeoNames cities (CC-BY 4.0), Natural Earth (public domain), OpenStreetMap map data (ODbL), and the Saira & JetBrains Mono fonts (OFL).'**
  String get aboutAttributions;

  /// No description provided for @personalizationHeading.
  ///
  /// In en, this message translates to:
  /// **'Profile & personalization'**
  String get personalizationHeading;

  /// No description provided for @personalizationThemePreset.
  ///
  /// In en, this message translates to:
  /// **'THEME PRESET'**
  String get personalizationThemePreset;

  /// No description provided for @personalizationType.
  ///
  /// In en, this message translates to:
  /// **'TYPE'**
  String get personalizationType;

  /// No description provided for @personalizationFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get personalizationFontSize;

  /// No description provided for @personalizationAccessibility.
  ///
  /// In en, this message translates to:
  /// **'ACCESSIBILITY'**
  String get personalizationAccessibility;

  /// No description provided for @personalizationHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get personalizationHighContrast;

  /// No description provided for @personalizationHighContrastSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the high-contrast colours'**
  String get personalizationHighContrastSubtitle;

  /// No description provided for @personalizationHighContrastHint.
  ///
  /// In en, this message translates to:
  /// **'High contrast overrides the skin you pick.'**
  String get personalizationHighContrastHint;

  /// No description provided for @personalizationReduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get personalizationReduceMotion;

  /// No description provided for @personalizationVisualHapticOnly.
  ///
  /// In en, this message translates to:
  /// **'Visual + haptic only'**
  String get personalizationVisualHapticOnly;

  /// No description provided for @personalizationVisualHapticOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts by vibration only'**
  String get personalizationVisualHapticOnlySubtitle;

  /// No description provided for @personalizationAudioAlerts.
  ///
  /// In en, this message translates to:
  /// **'AUDIO ALERTS'**
  String get personalizationAudioAlerts;

  /// No description provided for @personalizationAudioMaster.
  ///
  /// In en, this message translates to:
  /// **'Audio alerts'**
  String get personalizationAudioMaster;

  /// No description provided for @personalizationAudioMasterDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled by \"visual + haptic only\"'**
  String get personalizationAudioMasterDisabled;

  /// No description provided for @personalizationAudioMasterEnabled.
  ///
  /// In en, this message translates to:
  /// **'On by default; augmentation only'**
  String get personalizationAudioMasterEnabled;

  /// No description provided for @dashboardAudioMute.
  ///
  /// In en, this message translates to:
  /// **'Mute alert sounds'**
  String get dashboardAudioMute;

  /// No description provided for @dashboardAudioUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute alert sounds'**
  String get dashboardAudioUnmute;

  /// No description provided for @demoBanner.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get demoBanner;

  /// No description provided for @demoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Demo mode — no radio. Explore channels, settings and docs without a companion.'**
  String get demoTooltip;

  /// No description provided for @demoModeRow.
  ///
  /// In en, this message translates to:
  /// **'No radio'**
  String get demoModeRow;

  /// No description provided for @demoModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore the app offline'**
  String get demoModeSubtitle;

  /// No description provided for @firstRunHeader.
  ///
  /// In en, this message translates to:
  /// **'MESHMORE · WELCOME'**
  String get firstRunHeader;

  /// No description provided for @firstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'What this app will ask for'**
  String get firstRunTitle;

  /// No description provided for @firstRunBleTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get firstRunBleTitle;

  /// No description provided for @firstRunBleBody.
  ///
  /// In en, this message translates to:
  /// **'To pair with your MeshCore radio and exchange messages over the local mesh. Required to send / receive over the air.'**
  String get firstRunBleBody;

  /// No description provided for @firstRunNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get firstRunNotificationsTitle;

  /// No description provided for @firstRunNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'We ask later, only if you keep the app connected in the background.'**
  String get firstRunNotificationsBody;

  /// No description provided for @firstRunOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline is fine'**
  String get firstRunOfflineTitle;

  /// No description provided for @firstRunOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Without Bluetooth the app opens in demo mode: history, channels, settings and docs, with no radio traffic.'**
  String get firstRunOfflineBody;

  /// No description provided for @firstRunGrant.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth'**
  String get firstRunGrant;

  /// No description provided for @firstRunSkip.
  ///
  /// In en, this message translates to:
  /// **'Explore in demo mode (no radio)'**
  String get firstRunSkip;

  /// No description provided for @firstRunDeniedTransient.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off for this app. Continue offline, or allow it in Settings.'**
  String get firstRunDeniedTransient;

  /// No description provided for @firstRunDeniedPermanent.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is blocked for this app. Allow it in Settings, or keep using the app offline.'**
  String get firstRunDeniedPermanent;

  /// No description provided for @firstRunOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open OS settings'**
  String get firstRunOpenSettings;

  /// No description provided for @dashboardPaired.
  ///
  /// In en, this message translates to:
  /// **'paired: {name}'**
  String dashboardPaired(String name);

  /// No description provided for @dashboardCharging.
  ///
  /// In en, this message translates to:
  /// **'CHARGING'**
  String get dashboardCharging;

  /// No description provided for @dashboardBatteryReadout.
  ///
  /// In en, this message translates to:
  /// **'{volts}V · ~{percent}%'**
  String dashboardBatteryReadout(String volts, int percent);

  /// No description provided for @dashboardBatteryLeft.
  ///
  /// In en, this message translates to:
  /// **'~{time} left'**
  String dashboardBatteryLeft(String time);

  /// No description provided for @nodesScanArea.
  ///
  /// In en, this message translates to:
  /// **'Scan area'**
  String get nodesScanArea;

  /// No description provided for @nodesScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get nodesScanning;

  /// No description provided for @nodesAdvertise.
  ///
  /// In en, this message translates to:
  /// **'Advertise'**
  String get nodesAdvertise;

  /// No description provided for @nodesSyncContacts.
  ///
  /// In en, this message translates to:
  /// **'Sync contacts'**
  String get nodesSyncContacts;

  /// No description provided for @nodesFloodAdvert.
  ///
  /// In en, this message translates to:
  /// **'Flood advert'**
  String get nodesFloodAdvert;

  /// No description provided for @nodesFloodAdvertBody.
  ///
  /// In en, this message translates to:
  /// **'Whole mesh — neighbours + repeaters. Best for discovery.'**
  String get nodesFloodAdvertBody;

  /// No description provided for @nodesZeroHopAdvert.
  ///
  /// In en, this message translates to:
  /// **'Direct advert'**
  String get nodesZeroHopAdvert;

  /// No description provided for @nodesZeroHopAdvertBody.
  ///
  /// In en, this message translates to:
  /// **'Direct neighbours only — not rebroadcast. Quieter on a busy mesh.'**
  String get nodesZeroHopAdvertBody;

  /// No description provided for @nodesFloodAdvertSent.
  ///
  /// In en, this message translates to:
  /// **'Flood advert sent — propagates across the whole mesh (neighbours + repeaters). The other node must Advertise too before it appears here.'**
  String get nodesFloodAdvertSent;

  /// No description provided for @nodesZeroHopAdvertSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to radios in direct range only.'**
  String get nodesZeroHopAdvertSent;

  /// No description provided for @nodesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, shortId, or pubkey…'**
  String get nodesSearchHint;

  /// No description provided for @nodesFilterStarred.
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get nodesFilterStarred;

  /// No description provided for @nodesFilterInRange.
  ///
  /// In en, this message translates to:
  /// **'In range'**
  String get nodesFilterInRange;

  /// No description provided for @nodesFilterClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get nodesFilterClear;

  /// No description provided for @nodesFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get nodesFiltersTitle;

  /// No description provided for @nodesFilterLastSeenTitle.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get nodesFilterLastSeenTitle;

  /// No description provided for @nodesFilterWithinTitle.
  ///
  /// In en, this message translates to:
  /// **'Within'**
  String get nodesFilterWithinTitle;

  /// No description provided for @nodesFiltersDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get nodesFiltersDone;

  /// No description provided for @nodesTagFilter.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get nodesTagFilter;

  /// No description provided for @nodesAgeAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get nodesAgeAny;

  /// No description provided for @nodesAgeHour.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get nodesAgeHour;

  /// No description provided for @nodesAge24h.
  ///
  /// In en, this message translates to:
  /// **'Last 24 h'**
  String get nodesAge24h;

  /// No description provided for @nodesAge7d.
  ///
  /// In en, this message translates to:
  /// **'Last 7 d'**
  String get nodesAge7d;

  /// No description provided for @nodesDistAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get nodesDistAny;

  /// No description provided for @nodesDist100m.
  ///
  /// In en, this message translates to:
  /// **'≤ 100 m'**
  String get nodesDist100m;

  /// No description provided for @nodesDist500m.
  ///
  /// In en, this message translates to:
  /// **'≤ 500 m'**
  String get nodesDist500m;

  /// No description provided for @nodesDist5km.
  ///
  /// In en, this message translates to:
  /// **'≤ 5 km'**
  String get nodesDist5km;

  /// No description provided for @nodesDist25km.
  ///
  /// In en, this message translates to:
  /// **'≤ 25 km'**
  String get nodesDist25km;

  /// No description provided for @nodesStatusReady.
  ///
  /// In en, this message translates to:
  /// **'{shown} of {total} shown · {inRange} in range · {favs, plural, =0{0 contacts} =1{1 contact} other{{favs} contacts}}'**
  String nodesStatusReady(int shown, int total, int inRange, int favs);

  /// No description provided for @nodesStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected — Settings → Diagnostics & connect'**
  String get nodesStatusOffline;

  /// No description provided for @nodesFarBadge.
  ///
  /// In en, this message translates to:
  /// **'FAR'**
  String get nodesFarBadge;

  /// No description provided for @nodesEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'No nodes match this filter.'**
  String get nodesEmptyFiltered;

  /// No description provided for @nodesEmptyReady.
  ///
  /// In en, this message translates to:
  /// **'No nodes yet. A node appears once it announces itself.'**
  String get nodesEmptyReady;

  /// No description provided for @nodesEmptyOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio to discover nearby nodes.'**
  String get nodesEmptyOffline;

  /// No description provided for @nodesFavTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get nodesFavTooltip;

  /// No description provided for @nodesUnfavTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get nodesUnfavTooltip;

  /// No description provided for @gridTitle.
  ///
  /// In en, this message translates to:
  /// **'Hyperlocal grid'**
  String get gridTitle;

  /// No description provided for @gridShowLegend.
  ///
  /// In en, this message translates to:
  /// **'Show legend'**
  String get gridShowLegend;

  /// No description provided for @gridHideLegend.
  ///
  /// In en, this message translates to:
  /// **'Hide legend'**
  String get gridHideLegend;

  /// No description provided for @gridPlayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Play (refresh every interval)'**
  String get gridPlayTooltip;

  /// No description provided for @gridPauseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pause updates'**
  String get gridPauseTooltip;

  /// No description provided for @gridIntervalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh interval (when playing)'**
  String get gridIntervalTooltip;

  /// No description provided for @gridRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get gridRange;

  /// No description provided for @gridRangeRoom.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get gridRangeRoom;

  /// No description provided for @gridRangeHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get gridRangeHome;

  /// No description provided for @gridRangeBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get gridRangeBlock;

  /// No description provided for @gridRangeNeighborhood.
  ///
  /// In en, this message translates to:
  /// **'Neighborhood'**
  String get gridRangeNeighborhood;

  /// No description provided for @gridRangeArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get gridRangeArea;

  /// No description provided for @gridRangeWide.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get gridRangeWide;

  /// No description provided for @gridRangeCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get gridRangeCity;

  /// No description provided for @gridRangeRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get gridRangeRegion;

  /// No description provided for @gridLegend.
  ///
  /// In en, this message translates to:
  /// **'LEGEND'**
  String get gridLegend;

  /// No description provided for @gridLegendRings.
  ///
  /// In en, this message translates to:
  /// **'Rings are distance bands. With GPS at both ends the outer ring is the Range scale above (about {value} now). Without GPS they are signal bands: near, mid, far.'**
  String gridLegendRings(String value);

  /// No description provided for @gridLegendSelf.
  ///
  /// In en, this message translates to:
  /// **'Centre marker = you. Cross-hair = N-S / E-W guide.'**
  String get gridLegendSelf;

  /// No description provided for @gridLegendDot.
  ///
  /// In en, this message translates to:
  /// **'A dot is a node we have heard. Brighter means more recent; it fades out over a day.'**
  String get gridLegendDot;

  /// No description provided for @gridLegendKnown.
  ///
  /// In en, this message translates to:
  /// **'A slow growing halo is a node we have messaged directly.'**
  String get gridLegendKnown;

  /// No description provided for @gridLegendFavourite.
  ///
  /// In en, this message translates to:
  /// **'Rapid blink in alt-colour = a favourited node.'**
  String get gridLegendFavourite;

  /// No description provided for @gridLegendRipple.
  ///
  /// In en, this message translates to:
  /// **'A ripple from the centre is a channel message from someone we cannot name.'**
  String get gridLegendRipple;

  /// No description provided for @gridLegendTap.
  ///
  /// In en, this message translates to:
  /// **'Tap a node to see details + Message / Favourite.'**
  String get gridLegendTap;

  /// No description provided for @gridViewRadial.
  ///
  /// In en, this message translates to:
  /// **'Radial'**
  String get gridViewRadial;

  /// No description provided for @gridViewGlobe.
  ///
  /// In en, this message translates to:
  /// **'Globe'**
  String get gridViewGlobe;

  /// No description provided for @gridViewEqualGrid.
  ///
  /// In en, this message translates to:
  /// **'Equal grid'**
  String get gridViewEqualGrid;

  /// No description provided for @gridViewPicker.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get gridViewPicker;

  /// No description provided for @gridViewFabric.
  ///
  /// In en, this message translates to:
  /// **'Mesh survey'**
  String get gridViewFabric;

  /// No description provided for @gridViewElevation.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get gridViewElevation;

  /// No description provided for @fujiLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'FUJIさん'**
  String get fujiLegendTitle;

  /// No description provided for @fujiLegendDesc.
  ///
  /// In en, this message translates to:
  /// **'Altitude survey. Heights on a √-scaled axis against famous landmarks. Your device\'s altitude comes from device GPS telemetry or the phone fix.'**
  String get fujiLegendDesc;

  /// No description provided for @fujiLegendMe.
  ///
  /// In en, this message translates to:
  /// **'Dashed line = you. At your altitude, or pinned to the ground with ALT? until it resolves.'**
  String get fujiLegendMe;

  /// No description provided for @fujiLegendRefs.
  ///
  /// In en, this message translates to:
  /// **'Silhouettes = real-world references (person → Mt Fuji) for scale.'**
  String get fujiLegendRefs;

  /// No description provided for @fujiLegendPeers.
  ///
  /// In en, this message translates to:
  /// **'Dots are nodes, plotted at their altitude once asked.'**
  String get fujiLegendPeers;

  /// No description provided for @fujiLegendUnknown.
  ///
  /// In en, this message translates to:
  /// **'A striped band along the ground is a node with no altitude yet.'**
  String get fujiLegendUnknown;

  /// No description provided for @fujiLegendAutoQuery.
  ///
  /// In en, this message translates to:
  /// **'The auto-query box asks for altitudes slowly. Tap it to start again.'**
  String get fujiLegendAutoQuery;

  /// No description provided for @elevationProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'MESHMORE :: FUJIさん'**
  String get elevationProfileTitle;

  /// No description provided for @elevationProfileAltLabel.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get elevationProfileAltLabel;

  /// No description provided for @elevationProfileMeLabel.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get elevationProfileMeLabel;

  /// No description provided for @elevationProfileUnknownLabel.
  ///
  /// In en, this message translates to:
  /// **'altitude unknown'**
  String get elevationProfileUnknownLabel;

  /// No description provided for @elevationProfilePeers.
  ///
  /// In en, this message translates to:
  /// **'{n} nodes tracked'**
  String elevationProfilePeers(int n);

  /// No description provided for @elevationRefPerson.
  ///
  /// In en, this message translates to:
  /// **'Human'**
  String get elevationRefPerson;

  /// No description provided for @elevationRefHouse.
  ///
  /// In en, this message translates to:
  /// **'House'**
  String get elevationRefHouse;

  /// No description provided for @elevationRefRedwood.
  ///
  /// In en, this message translates to:
  /// **'Redwood'**
  String get elevationRefRedwood;

  /// No description provided for @elevationRefEmpireState.
  ///
  /// In en, this message translates to:
  /// **'Empire State'**
  String get elevationRefEmpireState;

  /// No description provided for @elevationRefBurj.
  ///
  /// In en, this message translates to:
  /// **'Burj Khalifa'**
  String get elevationRefBurj;

  /// No description provided for @elevationRefMtFuji.
  ///
  /// In en, this message translates to:
  /// **'Mt Fuji'**
  String get elevationRefMtFuji;

  /// No description provided for @fabricCoverageCount.
  ///
  /// In en, this message translates to:
  /// **'MESH SURVEY · {n} CELLS'**
  String fabricCoverageCount(int n);

  /// No description provided for @fabricResetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset coverage'**
  String get fabricResetTooltip;

  /// No description provided for @fabricResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset mesh-coverage survey?'**
  String get fabricResetTitle;

  /// No description provided for @fabricResetBody.
  ///
  /// In en, this message translates to:
  /// **'Drops every recorded cell. New observations will start filling the map again as you move and the mesh reports nearby nodes.'**
  String get fabricResetBody;

  /// No description provided for @fabricResetApply.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get fabricResetApply;

  /// No description provided for @streetMapRecenter.
  ///
  /// In en, this message translates to:
  /// **'Re-centre on me'**
  String get streetMapRecenter;

  /// R69: quiet banner on the Map tab when there is no position fix.
  ///
  /// In en, this message translates to:
  /// **'No position fix yet. This is a world view, not centred on you.'**
  String get mapNoFixBanner;

  /// No description provided for @mapPackZoomOutside.
  ///
  /// In en, this message translates to:
  /// **'This pack covers zoom {min} to {max}. Coarser tiles stand in outside that range.'**
  String mapPackZoomOutside(int min, int max);

  /// No description provided for @mapHideTiles.
  ///
  /// In en, this message translates to:
  /// **'Hide map tiles'**
  String get mapHideTiles;

  /// No description provided for @mapShowTiles.
  ///
  /// In en, this message translates to:
  /// **'Show map tiles'**
  String get mapShowTiles;

  /// No description provided for @deviceRegionLoadedOffline.
  ///
  /// In en, this message translates to:
  /// **'{label} loaded — Apply when a device is connected.'**
  String deviceRegionLoadedOffline(String label);

  /// No description provided for @equalGridAwaitingFix.
  ///
  /// In en, this message translates to:
  /// **'Equal-grid view needs your own location — waiting for a GPS fix (phone or device).'**
  String get equalGridAwaitingFix;

  /// No description provided for @equalGridCellSize.
  ///
  /// In en, this message translates to:
  /// **'CELL {size}'**
  String equalGridCellSize(String size);

  /// No description provided for @equalGridZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in (tighter cells)'**
  String get equalGridZoomIn;

  /// No description provided for @equalGridZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out (wider cells)'**
  String get equalGridZoomOut;

  /// No description provided for @equalGridShowStats.
  ///
  /// In en, this message translates to:
  /// **'Show targeting panel'**
  String get equalGridShowStats;

  /// No description provided for @equalGridHideStats.
  ///
  /// In en, this message translates to:
  /// **'Hide targeting panel'**
  String get equalGridHideStats;

  /// No description provided for @globeFooter.
  ///
  /// In en, this message translates to:
  /// **'Showing {n} nodes with a known location'**
  String globeFooter(int n);

  /// No description provided for @globeOverlayArcs.
  ///
  /// In en, this message translates to:
  /// **'arcs'**
  String get globeOverlayArcs;

  /// No description provided for @globeOverlayRegion.
  ///
  /// In en, this message translates to:
  /// **'region'**
  String get globeOverlayRegion;

  /// No description provided for @globeOverlayLabels.
  ///
  /// In en, this message translates to:
  /// **'labels'**
  String get globeOverlayLabels;

  /// No description provided for @globeAltitude.
  ///
  /// In en, this message translates to:
  /// **'ALT'**
  String get globeAltitude;

  /// No description provided for @globePaused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get globePaused;

  /// No description provided for @voiceOfflineBadge.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get voiceOfflineBadge;

  /// No description provided for @dashboardLocationRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh location from device'**
  String get dashboardLocationRefresh;

  /// No description provided for @dashboardLocationAltitude.
  ///
  /// In en, this message translates to:
  /// **'alt {meters} m'**
  String dashboardLocationAltitude(int meters);

  /// No description provided for @deviceLocReportsAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Device reports: (awaiting)'**
  String get deviceLocReportsAwaiting;

  /// No description provided for @deviceLocReportsNone.
  ///
  /// In en, this message translates to:
  /// **'Device reports: no GPS fix (0, 0)'**
  String get deviceLocReportsNone;

  /// No description provided for @deviceLocReportsValue.
  ///
  /// In en, this message translates to:
  /// **'Device reports: {lat}, {lon}'**
  String deviceLocReportsValue(String lat, String lon);

  /// No description provided for @deviceLocUnsaved.
  ///
  /// In en, this message translates to:
  /// **'✱ unsaved'**
  String get deviceLocUnsaved;

  /// No description provided for @deviceGpsModule.
  ///
  /// In en, this message translates to:
  /// **'ON-BOARD GPS MODULE'**
  String get deviceGpsModule;

  /// No description provided for @deviceGpsEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable on-board GPS'**
  String get deviceGpsEnable;

  /// No description provided for @deviceGpsEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'Device firmware polls its GPS chip and updates location automatically.'**
  String get deviceGpsEnabledHint;

  /// No description provided for @deviceGpsDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Off. The radio does not read its GPS, so it keeps announcing the last position set.'**
  String get deviceGpsDisabledHint;

  /// No description provided for @deviceGpsUnknown.
  ///
  /// In en, this message translates to:
  /// **'Waiting for device…'**
  String get deviceGpsUnknown;

  /// No description provided for @deviceGpsInterval.
  ///
  /// In en, this message translates to:
  /// **'GPS update interval'**
  String get deviceGpsInterval;

  /// No description provided for @deviceGpsIntervalOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get deviceGpsIntervalOff;

  /// No description provided for @deviceGpsIntervalSec.
  ///
  /// In en, this message translates to:
  /// **'Every {n} s'**
  String deviceGpsIntervalSec(int n);

  /// No description provided for @deviceGpsIntervalMin.
  ///
  /// In en, this message translates to:
  /// **'Every {n} min'**
  String deviceGpsIntervalMin(int n);

  /// No description provided for @deviceGpsIntervalHour.
  ///
  /// In en, this message translates to:
  /// **'Every {n} h'**
  String deviceGpsIntervalHour(int n);

  /// No description provided for @deviceGpsIntervalFixedByFirmware.
  ///
  /// In en, this message translates to:
  /// **'Set on the radio'**
  String get deviceGpsIntervalFixedByFirmware;

  /// No description provided for @locTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-publish location'**
  String get locTitle;

  /// No description provided for @locTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sends the phone\'s position to the radio'**
  String get locTileSubtitle;

  /// No description provided for @deviceGpsIntervalWhy.
  ///
  /// In en, this message translates to:
  /// **'This firmware build decides how often the sensors are read, so the app cannot change it.'**
  String get deviceGpsIntervalWhy;

  /// No description provided for @locMaster.
  ///
  /// In en, this message translates to:
  /// **'Auto-publish'**
  String get locMaster;

  /// No description provided for @locMasterOn.
  ///
  /// In en, this message translates to:
  /// **'On — using phone GPS'**
  String get locMasterOn;

  /// No description provided for @locMasterOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get locMasterOff;

  /// No description provided for @locInterval.
  ///
  /// In en, this message translates to:
  /// **'Periodic interval'**
  String get locInterval;

  /// No description provided for @locMovement.
  ///
  /// In en, this message translates to:
  /// **'Smart broadcast (on movement)'**
  String get locMovement;

  /// No description provided for @locOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get locOff;

  /// No description provided for @locIntervalMin.
  ///
  /// In en, this message translates to:
  /// **'Every {n} min'**
  String locIntervalMin(int n);

  /// No description provided for @locIntervalHour.
  ///
  /// In en, this message translates to:
  /// **'Every {n} h'**
  String locIntervalHour(int n);

  /// No description provided for @locMovementM.
  ///
  /// In en, this message translates to:
  /// **'{m} m'**
  String locMovementM(int m);

  /// No description provided for @locMovementKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String locMovementKm(int km);

  /// No description provided for @locPublishNow.
  ///
  /// In en, this message translates to:
  /// **'Publish now'**
  String get locPublishNow;

  /// No description provided for @locPublishNowSub.
  ///
  /// In en, this message translates to:
  /// **'One-shot manual push to verify the loop.'**
  String get locPublishNowSub;

  /// No description provided for @locLastPublished.
  ///
  /// In en, this message translates to:
  /// **'Last: {lat}, {lon}  ·  {time}  ·  {trigger}'**
  String locLastPublished(String lat, String lon, String time, String trigger);

  /// No description provided for @locBeacon.
  ///
  /// In en, this message translates to:
  /// **'Periodic position beacon'**
  String get locBeacon;

  /// No description provided for @locBeaconSub.
  ///
  /// In en, this message translates to:
  /// **'Every 60 s, send your position. Uses airtime and battery.'**
  String get locBeaconSub;

  /// No description provided for @locBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'Streaming GPS reacts faster and uses more battery.'**
  String get locBatteryHint;

  /// No description provided for @gridEmpty.
  ///
  /// In en, this message translates to:
  /// **'No nodes in range yet.\n\nA node appears once it announces itself.'**
  String get gridEmpty;

  /// No description provided for @gridStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected — Settings → Diagnostics & connect'**
  String get gridStatusOffline;

  /// No description provided for @gridSwipeModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Swipe mode: swipe left/right for other screens. Tap to pan and zoom this map'**
  String get gridSwipeModeTooltip;

  /// No description provided for @gridPanModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pan & zoom mode: drags move the map. Tap to swipe between screens again'**
  String get gridPanModeTooltip;

  /// No description provided for @gridStatusCounts.
  ///
  /// In en, this message translates to:
  /// **'{visible} shown · {known} known · {favs, plural, =0{0 contacts} =1{1 contact} other{{favs} contacts}}'**
  String gridStatusCounts(int visible, int known, int favs);

  /// No description provided for @gridNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not Connected to Mesh'**
  String get gridNotConnected;

  /// No description provided for @voiceSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice (TTS quality)'**
  String get voiceSettingsTitle;

  /// No description provided for @voiceSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Off until you turn on SPEECH in App settings. Rate / pitch / voice take effect on the next utterance.'**
  String get voiceSettingsHint;

  /// No description provided for @voiceRate.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get voiceRate;

  /// No description provided for @voicePitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get voicePitch;

  /// No description provided for @voicePicker.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voicePicker;

  /// No description provided for @voicePickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No voices reported by the platform engine — using the system default.'**
  String get voicePickerEmpty;

  /// No description provided for @voicePickerOnlyMyLanguage.
  ///
  /// In en, this message translates to:
  /// **'Only show my language'**
  String get voicePickerOnlyMyLanguage;

  /// No description provided for @voicePickerOnlyMyLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Limits the list to voices matching the phone\'s current language ({lang}). Turn off to see every voice the OS reports.'**
  String voicePickerOnlyMyLanguageHint(String lang);

  /// No description provided for @voicePickerFilteredCount.
  ///
  /// In en, this message translates to:
  /// **'{n} · {lang}'**
  String voicePickerFilteredCount(int n, String lang);

  /// No description provided for @voicePickerAllCount.
  ///
  /// In en, this message translates to:
  /// **'{n} · ALL'**
  String voicePickerAllCount(int n);

  /// No description provided for @voicePickerNoMatchForLanguage.
  ///
  /// In en, this message translates to:
  /// **'No voices installed for {lang}. Turn off the filter above to see other languages, or install a {lang} voice in your OS settings.'**
  String voicePickerNoMatchForLanguage(String lang);

  /// No description provided for @voicePickerSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get voicePickerSystem;

  /// No description provided for @voicePreview.
  ///
  /// In en, this message translates to:
  /// **'Try a phrase'**
  String get voicePreview;

  /// No description provided for @voicePreviewPhrase.
  ///
  /// In en, this message translates to:
  /// **'This is a Meshmore SNS voice preview.'**
  String get voicePreviewPhrase;

  /// No description provided for @voicePreviewDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on SPEECH in App settings to audition a phrase.'**
  String get voicePreviewDisabledHint;

  /// No description provided for @settingsHubDevice.
  ///
  /// In en, this message translates to:
  /// **'Device configuration'**
  String get settingsHubDevice;

  /// No description provided for @settingsGroupRadio.
  ///
  /// In en, this message translates to:
  /// **'RADIO'**
  String get settingsGroupRadio;

  /// No description provided for @settingsGroupApp.
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get settingsGroupApp;

  /// No description provided for @settingsGroupConnect.
  ///
  /// In en, this message translates to:
  /// **'CONNECTION'**
  String get settingsGroupConnect;

  /// No description provided for @settingsGroupAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get settingsGroupAbout;

  /// No description provided for @settingsHubApp.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get settingsHubApp;

  /// No description provided for @settingsHubProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile & personalization'**
  String get settingsHubProfile;

  /// No description provided for @settingsHubChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get settingsHubChannels;

  /// No description provided for @settingsHubDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics & connect'**
  String get settingsHubDiagnostics;

  /// No description provided for @bootHeader.
  ///
  /// In en, this message translates to:
  /// **'MESHMORE  /  SYNCHRONIZING'**
  String get bootHeader;

  /// No description provided for @bootConnecting.
  ///
  /// In en, this message translates to:
  /// **'CONNECTING TO RADIO…'**
  String get bootConnecting;

  /// No description provided for @bootHandshaking.
  ///
  /// In en, this message translates to:
  /// **'HANDSHAKING…'**
  String get bootHandshaking;

  /// No description provided for @bootReady.
  ///
  /// In en, this message translates to:
  /// **'MESH ONLINE'**
  String get bootReady;

  /// No description provided for @bootOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE — Settings → Diagnostics & connect'**
  String get bootOffline;

  /// No description provided for @bootSkip.
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get bootSkip;

  /// No description provided for @bootSubtitle.
  ///
  /// In en, this message translates to:
  /// **'WAIT  /  進行中'**
  String get bootSubtitle;

  /// No description provided for @eventAdvert.
  ///
  /// In en, this message translates to:
  /// **'advert · {name}'**
  String eventAdvert(String name);

  /// No description provided for @eventChannelMsg.
  ///
  /// In en, this message translates to:
  /// **'ch{channel} · \"{text}\"'**
  String eventChannelMsg(String channel, String text);

  /// No description provided for @eventDm.
  ///
  /// In en, this message translates to:
  /// **'dm · \"{text}\"'**
  String eventDm(String text);

  /// No description provided for @eventContact.
  ///
  /// In en, this message translates to:
  /// **'contact · {name}'**
  String eventContact(String name);

  /// No description provided for @eventBattery.
  ///
  /// In en, this message translates to:
  /// **'battery {volts}V'**
  String eventBattery(String volts);

  /// No description provided for @eventDeviceError.
  ///
  /// In en, this message translates to:
  /// **'device error (code {code})'**
  String eventDeviceError(String code);

  /// No description provided for @eventDeviceClockSynced.
  ///
  /// In en, this message translates to:
  /// **'device clock in sync'**
  String get eventDeviceClockSynced;

  /// No description provided for @eventDeviceClockSkew.
  ///
  /// In en, this message translates to:
  /// **'device clock read (offset {seconds}s)'**
  String eventDeviceClockSkew(String seconds);

  /// No description provided for @eventMsgSent.
  ///
  /// In en, this message translates to:
  /// **'sent (confirmed by {ack})'**
  String eventMsgSent(String ack);

  /// No description provided for @eventDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'device {version}'**
  String eventDeviceInfo(String version);

  /// No description provided for @eventSelfInfo.
  ///
  /// In en, this message translates to:
  /// **'self-info · {name}'**
  String eventSelfInfo(String name);

  /// No description provided for @eventQueuedWaiting.
  ///
  /// In en, this message translates to:
  /// **'queued items waiting'**
  String get eventQueuedWaiting;

  /// No description provided for @eventQueuedWaitingN.
  ///
  /// In en, this message translates to:
  /// **'queued items waiting ({count})'**
  String eventQueuedWaitingN(String count);

  /// No description provided for @chatManageChannels.
  ///
  /// In en, this message translates to:
  /// **'Manage channels'**
  String get chatManageChannels;

  /// No description provided for @chatTtsMuted.
  ///
  /// In en, this message translates to:
  /// **'TTS muted for this channel'**
  String get chatTtsMuted;

  /// No description provided for @chatTtsActive.
  ///
  /// In en, this message translates to:
  /// **'TTS reading this channel'**
  String get chatTtsActive;

  /// No description provided for @chatRetentionDropped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 older message is gone} other{{count} older messages are gone}} — each conversation keeps its newest {cap}'**
  String chatRetentionDropped(int count, int cap);

  /// No description provided for @chatHistoryUnreadableTitle.
  ///
  /// In en, this message translates to:
  /// **'History cannot be opened on this device'**
  String get chatHistoryUnreadableTitle;

  /// No description provided for @chatHistoryUnreadableBody.
  ///
  /// In en, this message translates to:
  /// **'The messages are still saved here. They were sealed with a key this phone no longer has, so they cannot be read until they are restored from an encrypted export.'**
  String get chatHistoryUnreadableBody;

  /// No description provided for @diagnosticsHistoryStore.
  ///
  /// In en, this message translates to:
  /// **'History store'**
  String get diagnosticsHistoryStore;

  /// No description provided for @diagnosticsHistoryStoreOk.
  ///
  /// In en, this message translates to:
  /// **'sealed and readable'**
  String get diagnosticsHistoryStoreOk;

  /// No description provided for @diagnosticsHistoryStoreKeyLost.
  ///
  /// In en, this message translates to:
  /// **'sealed, but the key is gone from this device'**
  String get diagnosticsHistoryStoreKeyLost;

  /// No description provided for @diagnosticsHistoryStoreWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'last write did not reach the store ({code})'**
  String diagnosticsHistoryStoreWriteFailed(String code);

  /// No description provided for @chatHistoryRestoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore from an export'**
  String get chatHistoryRestoreAction;

  /// No description provided for @chatRestoreMenu.
  ///
  /// In en, this message translates to:
  /// **'Restore from export…'**
  String get chatRestoreMenu;

  /// No description provided for @chatRestoreNothing.
  ///
  /// In en, this message translates to:
  /// **'Open the export file with this app, or share it here, and then run restore again.'**
  String get chatRestoreNothing;

  /// No description provided for @chatRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore a conversation'**
  String get chatRestoreTitle;

  /// No description provided for @chatRestorePassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase for the export'**
  String get chatRestorePassphrase;

  /// No description provided for @chatRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get chatRestoreConfirm;

  /// No description provided for @chatRestoreDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message restored} other{{count} messages restored}}'**
  String chatRestoreDone(int count);

  /// No description provided for @chatRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'That file could not be opened with that passphrase, or it is not an export.'**
  String get chatRestoreFailed;

  /// No description provided for @diagnosticsPlaceStore.
  ///
  /// In en, this message translates to:
  /// **'Places store'**
  String get diagnosticsPlaceStore;

  /// No description provided for @diagnosticsPlaceStoreWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'the last save did not land — pins will not survive a restart'**
  String get diagnosticsPlaceStoreWriteFailed;

  /// No description provided for @diagnosticsPlaceStoreOk.
  ///
  /// In en, this message translates to:
  /// **'saved'**
  String get diagnosticsPlaceStoreOk;

  /// No description provided for @mediaReceiveDropped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One earlier transfer was dropped to make room, so that picture stopped} other{{count} earlier transfers were dropped to make room, so those pictures stopped}}'**
  String mediaReceiveDropped(int count);

  /// No description provided for @diagnosticsPlaceStoreCorruptKept.
  ///
  /// In en, this message translates to:
  /// **'the last document was unreadable, and its bytes were kept aside'**
  String get diagnosticsPlaceStoreCorruptKept;

  /// No description provided for @chatEmpty.
  ///
  /// In en, this message translates to:
  /// **'— no messages on this channel —'**
  String get chatEmpty;

  /// No description provided for @chatJumpToNewest.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new} other{{count} new}}'**
  String chatJumpToNewest(int count);

  /// No description provided for @chatComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Message {channel}'**
  String chatComposerHint(String channel);

  /// No description provided for @chatComposerOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio to send'**
  String get chatComposerOffline;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatBudgetRemaining.
  ///
  /// In en, this message translates to:
  /// **'{remaining} of {max} bytes left'**
  String chatBudgetRemaining(int remaining, int max);

  /// No description provided for @chatBudgetEstimate.
  ///
  /// In en, this message translates to:
  /// **'about {remaining} of {max} bytes left — the radio\'s name is not known yet'**
  String chatBudgetEstimate(int remaining, int max);

  /// No description provided for @chatBudgetNear.
  ///
  /// In en, this message translates to:
  /// **'Nearly at the limit: the radio counts its own name in these bytes'**
  String get chatBudgetNear;

  /// No description provided for @chatBudgetTooLong.
  ///
  /// In en, this message translates to:
  /// **'Too long by {over} bytes — the radio would cut the rest without telling you'**
  String chatBudgetTooLong(int over);

  /// No description provided for @chatMessageActions.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get chatMessageActions;

  /// No description provided for @chatSinceNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get chatSinceNow;

  /// No description provided for @chatSinceMinutes.
  ///
  /// In en, this message translates to:
  /// **'{m}m'**
  String chatSinceMinutes(int m);

  /// No description provided for @chatSinceHours.
  ///
  /// In en, this message translates to:
  /// **'{h}h'**
  String chatSinceHours(int h);

  /// No description provided for @chatSinceDays.
  ///
  /// In en, this message translates to:
  /// **'{d}d'**
  String chatSinceDays(int d);

  /// No description provided for @dmTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct · {peer}'**
  String dmTitle(String peer);

  /// No description provided for @dmPubkeyLabel.
  ///
  /// In en, this message translates to:
  /// **'pubkey · {hex}'**
  String dmPubkeyLabel(String hex);

  /// No description provided for @nodeDetailSignature.
  ///
  /// In en, this message translates to:
  /// **'Message sound'**
  String get nodeDetailSignature;

  /// No description provided for @nodeDetailSignatureHint.
  ///
  /// In en, this message translates to:
  /// **'Plays for messages from this person instead of the usual sound.'**
  String get nodeDetailSignatureHint;

  /// No description provided for @nodeDetailSignatureNone.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get nodeDetailSignatureNone;

  /// No description provided for @nodeDetailSignatureSlot.
  ///
  /// In en, this message translates to:
  /// **'Sound {n}'**
  String nodeDetailSignatureSlot(int n);

  /// No description provided for @nodeDetailSignatureMutedHint.
  ///
  /// In en, this message translates to:
  /// **'Audio is muted — you will feel the vibration but not hear it.'**
  String get nodeDetailSignatureMutedHint;

  /// No description provided for @dmEmpty.
  ///
  /// In en, this message translates to:
  /// **'— no messages yet —'**
  String get dmEmpty;

  /// No description provided for @dmOpenPeerDetail.
  ///
  /// In en, this message translates to:
  /// **'Contact details'**
  String get dmOpenPeerDetail;

  /// No description provided for @dmSpeech.
  ///
  /// In en, this message translates to:
  /// **'Read this conversation aloud'**
  String get dmSpeech;

  /// No description provided for @dmSpeechInherit.
  ///
  /// In en, this message translates to:
  /// **'Follow global speech setting'**
  String get dmSpeechInherit;

  /// No description provided for @dmSpeechAlways.
  ///
  /// In en, this message translates to:
  /// **'Always speak'**
  String get dmSpeechAlways;

  /// No description provided for @dmSpeechNever.
  ///
  /// In en, this message translates to:
  /// **'Never speak'**
  String get dmSpeechNever;

  /// No description provided for @dmSpeechMutedByMaster.
  ///
  /// In en, this message translates to:
  /// **'Silenced by the audio mute'**
  String get dmSpeechMutedByMaster;

  /// No description provided for @dmPeerNotInFabric.
  ///
  /// In en, this message translates to:
  /// **'This person has not been heard on the mesh yet.'**
  String get dmPeerNotInFabric;

  /// No description provided for @dmComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Message {peer}'**
  String dmComposerHint(String peer);

  /// No description provided for @dmSend.
  ///
  /// In en, this message translates to:
  /// **'Send DM'**
  String get dmSend;

  /// No description provided for @actionRetrySub.
  ///
  /// In en, this message translates to:
  /// **'Send this message again'**
  String get actionRetrySub;

  /// No description provided for @actionReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get actionReply;

  /// No description provided for @actionReplySub.
  ///
  /// In en, this message translates to:
  /// **'Quote this message in your reply'**
  String get actionReplySub;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionCopySub.
  ///
  /// In en, this message translates to:
  /// **'Copy the message text to the clipboard'**
  String get actionCopySub;

  /// No description provided for @actionDeleteLocal.
  ///
  /// In en, this message translates to:
  /// **'Delete locally'**
  String get actionDeleteLocal;

  /// No description provided for @actionDeleteLocalSub.
  ///
  /// In en, this message translates to:
  /// **'Removes this row from your history only — over-the-air messages cannot be recalled.'**
  String get actionDeleteLocalSub;

  /// No description provided for @actionCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get actionCopied;

  /// No description provided for @actionDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this message locally?'**
  String get actionDeleteConfirmTitle;

  /// No description provided for @actionDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the row from your local history. MeshCore has no recall — the recipient still has it.'**
  String get actionDeleteConfirmBody;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @nodeDetailSelf.
  ///
  /// In en, this message translates to:
  /// **'This is your own node — no Message / Favourite.'**
  String get nodeDetailSelf;

  /// No description provided for @nodeDetailShareTelemetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Share my telemetry with this contact'**
  String get nodeDetailShareTelemetryTitle;

  /// No description provided for @nodeDetailShareTelemetryHelp.
  ///
  /// In en, this message translates to:
  /// **'Only applies when your telemetry mode is Contacts and Base is on.'**
  String get nodeDetailShareTelemetryHelp;

  /// No description provided for @nodeDetailRecentDms.
  ///
  /// In en, this message translates to:
  /// **'RECENT DMS'**
  String get nodeDetailRecentDms;

  /// No description provided for @nodeDetailMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get nodeDetailMessage;

  /// No description provided for @nodeIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact key changed'**
  String get nodeIdentityTitle;

  /// No description provided for @nodeIdentityBody.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is active under a new key — likely deleted and re-added on their device. Move your star, tags, and {count} saved messages to the current key?'**
  String nodeIdentityBody(String name, int count);

  /// No description provided for @nodeIdentityOldKey.
  ///
  /// In en, this message translates to:
  /// **'Old key …{shortId}'**
  String nodeIdentityOldKey(String shortId);

  /// No description provided for @nodeIdentityAction.
  ///
  /// In en, this message translates to:
  /// **'Move to current key'**
  String get nodeIdentityAction;

  /// No description provided for @nodeIdentityMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved your data to “{name}”’s current key'**
  String nodeIdentityMoved(String name);

  /// No description provided for @nodeIdentityLinkAction.
  ///
  /// In en, this message translates to:
  /// **'New key: link this contact'**
  String get nodeIdentityLinkAction;

  /// No description provided for @nodeIdentityLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link a changed key'**
  String get nodeIdentityLinkTitle;

  /// No description provided for @nodeIdentityLinkHelp.
  ///
  /// In en, this message translates to:
  /// **'Same contact, new key. Pick the node or paste the key; your star, tags and messages move over.'**
  String get nodeIdentityLinkHelp;

  /// No description provided for @nodeIdentityLinkEmpty.
  ///
  /// In en, this message translates to:
  /// **'No other nodes yet. Wait for the new key to advertise, or paste it.'**
  String get nodeIdentityLinkEmpty;

  /// No description provided for @nodeIdentityLinkSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by name, or paste a public key'**
  String get nodeIdentityLinkSearchHint;

  /// No description provided for @nodeIdentityLinkNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No nodes match — clear the search, or paste the full key to link directly.'**
  String get nodeIdentityLinkNoMatch;

  /// No description provided for @nodeIdentityLinkUseKey.
  ///
  /// In en, this message translates to:
  /// **'Link to this key'**
  String get nodeIdentityLinkUseKey;

  /// No description provided for @nodeDetailNotDeviceContact.
  ///
  /// In en, this message translates to:
  /// **'Not in your radio\'s contact list, so DMs may not route. Channels still work.'**
  String get nodeDetailNotDeviceContact;

  /// No description provided for @nodeDetailAddDeviceContact.
  ///
  /// In en, this message translates to:
  /// **'Add to device contacts'**
  String get nodeDetailAddDeviceContact;

  /// No description provided for @nodeDetailAddDeviceContactDone.
  ///
  /// In en, this message translates to:
  /// **'Added. DMs will route now. If they don\'t, your contact list may be full.'**
  String get nodeDetailAddDeviceContactDone;

  /// No description provided for @nodeDetailAddDeviceContactFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the contact — check the link and try again.'**
  String get nodeDetailAddDeviceContactFailed;

  /// No description provided for @nodeDetailRemoveDeviceContact.
  ///
  /// In en, this message translates to:
  /// **'Remove from device contacts'**
  String get nodeDetailRemoveDeviceContact;

  /// No description provided for @nodeDetailRemoveDeviceContactConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}” from the radio\'s contacts? You can add them again later.'**
  String nodeDetailRemoveDeviceContactConfirm(String name);

  /// No description provided for @nodeDetailRemoveDeviceContactDone.
  ///
  /// In en, this message translates to:
  /// **'Removed from your radio\'s contacts.'**
  String get nodeDetailRemoveDeviceContactDone;

  /// No description provided for @deviceContactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio contacts'**
  String get deviceContactsTitle;

  /// No description provided for @deviceContactsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get deviceContactsRefresh;

  /// No description provided for @deviceContactsSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing contacts from the radio…'**
  String get deviceContactsSyncing;

  /// No description provided for @deviceContactsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your radio has no contacts.'**
  String get deviceContactsEmpty;

  /// No description provided for @deviceContactsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} contacts on the radio'**
  String deviceContactsCount(int count, int max);

  /// No description provided for @deviceContactsCountOnly.
  ///
  /// In en, this message translates to:
  /// **'{count} contacts on the radio'**
  String deviceContactsCountOnly(int count);

  /// No description provided for @deviceContactsFullHelp.
  ///
  /// In en, this message translates to:
  /// **'Contact list is full. Remove entries below to add new ones.'**
  String get deviceContactsFullHelp;

  /// No description provided for @deviceContactsChannelsNote.
  ///
  /// In en, this message translates to:
  /// **'You only need a contact to send a direct message. Channel messages work without contacts — you\'ll still see everyone on channels.'**
  String get deviceContactsChannelsNote;

  /// No description provided for @deviceContactsScrub.
  ///
  /// In en, this message translates to:
  /// **'Scrub contacts'**
  String get deviceContactsScrub;

  /// No description provided for @deviceContactsRemoveOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Remove out of range'**
  String get deviceContactsRemoveOutOfRange;

  /// No description provided for @deviceContactsOutOfRangeIntro.
  ///
  /// In en, this message translates to:
  /// **'Removes contacts far away, and those that do not share a position. Favourites and known contacts are kept.'**
  String get deviceContactsOutOfRangeIntro;

  /// No description provided for @deviceContactsBeyondKm.
  ///
  /// In en, this message translates to:
  /// **'Beyond {km} km (+ location-hidden)'**
  String deviceContactsBeyondKm(int km);

  /// No description provided for @deviceContactsNeedLocation.
  ///
  /// In en, this message translates to:
  /// **'No location set, so distance can\'t be measured — only location-hidden contacts are caught. Set your position (GPS or a manual pin) to also remove far-away GPS contacts.'**
  String get deviceContactsNeedLocation;

  /// No description provided for @deviceContactsRemoveOutOfRangeDone.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} out-of-range contacts.'**
  String deviceContactsRemoveOutOfRangeDone(int count);

  /// No description provided for @deviceContactsRemoveStale.
  ///
  /// In en, this message translates to:
  /// **'Remove not heard recently'**
  String get deviceContactsRemoveStale;

  /// No description provided for @deviceContactsStaleIntro.
  ///
  /// In en, this message translates to:
  /// **'Removes contacts you haven\'t heard from in a while. Favourites and known contacts are kept.'**
  String get deviceContactsStaleIntro;

  /// No description provided for @deviceContactsNotHeardDays.
  ///
  /// In en, this message translates to:
  /// **'Not heard in {days} days'**
  String deviceContactsNotHeardDays(int days);

  /// No description provided for @deviceContactsRemoveStaleDone.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} stale contacts.'**
  String deviceContactsRemoveStaleDone(int count);

  /// No description provided for @deviceContactsRemoveAll.
  ///
  /// In en, this message translates to:
  /// **'Remove all'**
  String get deviceContactsRemoveAll;

  /// No description provided for @deviceContactsRemoveAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove all {count} contacts? You only need them to send direct messages, and you can add anyone back later.'**
  String deviceContactsRemoveAllConfirm(int count);

  /// No description provided for @deviceContactsRemoveAllDone.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} contacts from the radio.'**
  String deviceContactsRemoveAllDone(int count);

  /// No description provided for @deviceContactsFlood.
  ///
  /// In en, this message translates to:
  /// **'flood'**
  String get deviceContactsFlood;

  /// No description provided for @deviceContactsDirect.
  ///
  /// In en, this message translates to:
  /// **'direct'**
  String get deviceContactsDirect;

  /// No description provided for @deviceContactsHops.
  ///
  /// In en, this message translates to:
  /// **'{n} hops'**
  String deviceContactsHops(int n);

  /// No description provided for @nodeIdentityLinkConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move star, tags, and messages from “{from}” to “{to}”, and retire the old key?'**
  String nodeIdentityLinkConfirm(String from, String to);

  /// No description provided for @nodeDetailFavourite.
  ///
  /// In en, this message translates to:
  /// **'Favourite'**
  String get nodeDetailFavourite;

  /// No description provided for @nodeDetailContact.
  ///
  /// In en, this message translates to:
  /// **'Favourited'**
  String get nodeDetailContact;

  /// No description provided for @nodeDetailShowOnMap.
  ///
  /// In en, this message translates to:
  /// **'Show on geocoded map'**
  String get nodeDetailShowOnMap;

  /// No description provided for @nodeDetailShowOnMapFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the maps app.'**
  String get nodeDetailShowOnMapFailed;

  /// No description provided for @nodeDetailCopyPubkey.
  ///
  /// In en, this message translates to:
  /// **'Copy full pubkey'**
  String get nodeDetailCopyPubkey;

  /// No description provided for @nodeDetailPubkeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Pubkey copied'**
  String get nodeDetailPubkeyCopied;

  /// No description provided for @nodeDetailTags.
  ///
  /// In en, this message translates to:
  /// **'TAGS'**
  String get nodeDetailTags;

  /// No description provided for @nodeDetailAddTag.
  ///
  /// In en, this message translates to:
  /// **'tag'**
  String get nodeDetailAddTag;

  /// No description provided for @nodeDetailAddTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get nodeDetailAddTagTitle;

  /// No description provided for @nodeDetailAddTagHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. repeater, work, ham-club'**
  String get nodeDetailAddTagHint;

  /// No description provided for @nodeDetailAddTagSuggestions.
  ///
  /// In en, this message translates to:
  /// **'RECENTLY USED'**
  String get nodeDetailAddTagSuggestions;

  /// No description provided for @nodeDetailAddTagApply.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get nodeDetailAddTagApply;

  /// No description provided for @nodeDetailInRange.
  ///
  /// In en, this message translates to:
  /// **'IN RANGE'**
  String get nodeDetailInRange;

  /// No description provided for @nodeDetailKnown.
  ///
  /// In en, this message translates to:
  /// **'KNOWN'**
  String get nodeDetailKnown;

  /// No description provided for @nodeDetailContactBadge.
  ///
  /// In en, this message translates to:
  /// **'FAVOURITE'**
  String get nodeDetailContactBadge;

  /// No description provided for @nodeDetailShortIdKv.
  ///
  /// In en, this message translates to:
  /// **'shortId'**
  String get nodeDetailShortIdKv;

  /// No description provided for @nodeDetailPubkeyKv.
  ///
  /// In en, this message translates to:
  /// **'pubkey'**
  String get nodeDetailPubkeyKv;

  /// No description provided for @nodeDetailSignalKv.
  ///
  /// In en, this message translates to:
  /// **'signal'**
  String get nodeDetailSignalKv;

  /// No description provided for @nodeDetailLastHeardKv.
  ///
  /// In en, this message translates to:
  /// **'last heard'**
  String get nodeDetailLastHeardKv;

  /// No description provided for @nodeDetailDistanceKv.
  ///
  /// In en, this message translates to:
  /// **'distance'**
  String get nodeDetailDistanceKv;

  /// No description provided for @nodeDetailLatLonKv.
  ///
  /// In en, this message translates to:
  /// **'lat / lon'**
  String get nodeDetailLatLonKv;

  /// No description provided for @gridViewTree.
  ///
  /// In en, this message translates to:
  /// **'Mesh tree'**
  String get gridViewTree;

  /// No description provided for @gridViewSnsCells.
  ///
  /// In en, this message translates to:
  /// **'SNS cells (heat)'**
  String get gridViewSnsCells;

  /// No description provided for @gridViewWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather (environment)'**
  String get gridViewWeather;

  /// No description provided for @gridViewMeshbook.
  ///
  /// In en, this message translates to:
  /// **'Meshbook (channel activity)'**
  String get gridViewMeshbook;

  /// No description provided for @meshbookTitle.
  ///
  /// In en, this message translates to:
  /// **'MESHBOOK'**
  String get meshbookTitle;

  /// No description provided for @meshbookLast24h.
  ///
  /// In en, this message translates to:
  /// **'last 24h'**
  String get meshbookLast24h;

  /// No description provided for @meshbookEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages on this channel in the last 24h.'**
  String get meshbookEmpty;

  /// No description provided for @meshbookByHour.
  ///
  /// In en, this message translates to:
  /// **'BY HOUR'**
  String get meshbookByHour;

  /// No description provided for @meshbookTopVoices.
  ///
  /// In en, this message translates to:
  /// **'TOP VOICES'**
  String get meshbookTopVoices;

  /// No description provided for @meshbookTopics.
  ///
  /// In en, this message translates to:
  /// **'TOPICS'**
  String get meshbookTopics;

  /// No description provided for @meshbookClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get meshbookClear;

  /// No description provided for @meshbookClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear the last 24h of Meshbook data for CH{channel}? It rebuilds as new channel messages arrive. (Each channel is stored separately.)'**
  String meshbookClearConfirm(String channel);

  /// No description provided for @meshbookStats.
  ///
  /// In en, this message translates to:
  /// **'{total} msgs · {replies} replies ({pct}%) · {voices} voices'**
  String meshbookStats(int total, int replies, int pct, int voices);

  /// No description provided for @weatherSelf.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get weatherSelf;

  /// No description provided for @weatherMeasuredHeader.
  ///
  /// In en, this message translates to:
  /// **'MEASURED (sensors)'**
  String get weatherMeasuredHeader;

  /// No description provided for @wxMicroclimateTitle.
  ///
  /// In en, this message translates to:
  /// **'MICROCLIMATE'**
  String get wxMicroclimateTitle;

  /// No description provided for @wxMicroclimatesHeader.
  ///
  /// In en, this message translates to:
  /// **'MICROCLIMATES (by place)'**
  String get wxMicroclimatesHeader;

  /// No description provided for @wxMicroclimateNearby.
  ///
  /// In en, this message translates to:
  /// **'nearby'**
  String get wxMicroclimateNearby;

  /// No description provided for @wxMeasured.
  ///
  /// In en, this message translates to:
  /// **'measured'**
  String get wxMeasured;

  /// No description provided for @wxAmbientEmpty.
  ///
  /// In en, this message translates to:
  /// **'No weather chatter on this channel yet.'**
  String get wxAmbientEmpty;

  /// No description provided for @wxMentionsShort.
  ///
  /// In en, this message translates to:
  /// **'{count} mentions'**
  String wxMentionsShort(int count);

  /// No description provided for @wxLastHour.
  ///
  /// In en, this message translates to:
  /// **'1H'**
  String get wxLastHour;

  /// No description provided for @wxLast24h.
  ///
  /// In en, this message translates to:
  /// **'24H'**
  String get wxLast24h;

  /// No description provided for @wxCondClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get wxCondClear;

  /// No description provided for @wxCondClouds.
  ///
  /// In en, this message translates to:
  /// **'Cloudy'**
  String get wxCondClouds;

  /// No description provided for @wxCondFog.
  ///
  /// In en, this message translates to:
  /// **'Fog'**
  String get wxCondFog;

  /// No description provided for @wxCondRain.
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get wxCondRain;

  /// No description provided for @wxCondSnow.
  ///
  /// In en, this message translates to:
  /// **'Snow'**
  String get wxCondSnow;

  /// No description provided for @wxCondWind.
  ///
  /// In en, this message translates to:
  /// **'Windy'**
  String get wxCondWind;

  /// No description provided for @wxCondStorm.
  ///
  /// In en, this message translates to:
  /// **'Storm'**
  String get wxCondStorm;

  /// No description provided for @wxCondHeat.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get wxCondHeat;

  /// No description provided for @wxCondCold.
  ///
  /// In en, this message translates to:
  /// **'Cold'**
  String get wxCondCold;

  /// No description provided for @weatherEmpty.
  ///
  /// In en, this message translates to:
  /// **'No nodes are reporting environment data yet.\nReadings appear as sensor-equipped nodes are polled — enable \"Gather node telemetry\" in App settings.'**
  String get weatherEmpty;

  /// No description provided for @weatherSelfNoTelemetry.
  ///
  /// In en, this message translates to:
  /// **'This device hasn\'t returned telemetry yet. Make sure you\'re connected, then reopen this view.'**
  String get weatherSelfNoTelemetry;

  /// No description provided for @weatherSelfNoEnv.
  ///
  /// In en, this message translates to:
  /// **'Environment telemetry isn\'t supported by this device\'s firmware.\nIt reported: {types}.\nThe sensor (e.g. the T1000-E\'s BME280) needs a MeshCore sensor firmware build — the standard build sends only battery/GPS, and the device clamps the environment mode back to off. This is a device limitation, not an app setting.'**
  String weatherSelfNoEnv(String types);

  /// No description provided for @weatherReporting.
  ///
  /// In en, this message translates to:
  /// **'{count} reporting'**
  String weatherReporting(int count);

  /// No description provided for @docsHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Protocol, firmware, app and field notes, offline.'**
  String get docsHubSubtitle;

  /// No description provided for @docsHubFooter.
  ///
  /// In en, this message translates to:
  /// **'Documentation is cached on-device for offline reading. Tap a doc, then ↻ to pull the latest. Upstream: meshcore-dev/MeshCore.'**
  String get docsHubFooter;

  /// No description provided for @docsProtocolTitle.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get docsProtocolTitle;

  /// No description provided for @docsProtocolSub.
  ///
  /// In en, this message translates to:
  /// **'MeshCore companion radio protocol — frames, opcodes, and flow.'**
  String get docsProtocolSub;

  /// No description provided for @docsFirmwareTitle.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get docsFirmwareTitle;

  /// No description provided for @docsFirmwareSub.
  ///
  /// In en, this message translates to:
  /// **'MeshCore firmware overview (README).'**
  String get docsFirmwareSub;

  /// No description provided for @docsFirmwareSubVersion.
  ///
  /// In en, this message translates to:
  /// **'MeshCore firmware — matched to {version}.'**
  String docsFirmwareSubVersion(String version);

  /// No description provided for @docsAppTitle.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get docsAppTitle;

  /// No description provided for @docsAppSub.
  ///
  /// In en, this message translates to:
  /// **'How Meshmore SNS works, and how it uses the mesh.'**
  String get docsAppSub;

  /// No description provided for @docsDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get docsDevicesTitle;

  /// No description provided for @docsDevicesSub.
  ///
  /// In en, this message translates to:
  /// **'Field notes and quirks for the radios we run — T1000-E, Wio Tracker L1 Pro, Heltec V3.'**
  String get docsDevicesSub;

  /// No description provided for @docsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh from GitHub'**
  String get docsRefresh;

  /// No description provided for @docsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated to the latest version'**
  String get docsUpdated;

  /// No description provided for @docsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get docsUpToDate;

  /// No description provided for @docsOriginBundled.
  ///
  /// In en, this message translates to:
  /// **'Included copy'**
  String get docsOriginBundled;

  /// No description provided for @docsOriginUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {when}'**
  String docsOriginUpdated(String when);

  /// No description provided for @docsFirmwareForVersion.
  ///
  /// In en, this message translates to:
  /// **'device {version}'**
  String docsFirmwareForVersion(String version);

  /// No description provided for @docsFirmwareNoDevice.
  ///
  /// In en, this message translates to:
  /// **'no device connected'**
  String get docsFirmwareNoDevice;

  /// No description provided for @docsAgoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get docsAgoJustNow;

  /// No description provided for @docsAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String docsAgoMinutes(int n);

  /// No description provided for @docsAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String docsAgoHours(int n);

  /// No description provided for @docsAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String docsAgoDays(int n);

  /// No description provided for @weatherMin.
  ///
  /// In en, this message translates to:
  /// **'MIN'**
  String get weatherMin;

  /// No description provided for @weatherAvg.
  ///
  /// In en, this message translates to:
  /// **'AVG'**
  String get weatherAvg;

  /// No description provided for @weatherMax.
  ///
  /// In en, this message translates to:
  /// **'MAX'**
  String get weatherMax;

  /// No description provided for @weatherAgoSeconds.
  ///
  /// In en, this message translates to:
  /// **'{s}s ago'**
  String weatherAgoSeconds(int s);

  /// No description provided for @weatherAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{m}m ago'**
  String weatherAgoMinutes(int m);

  /// No description provided for @weatherAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{h}h ago'**
  String weatherAgoHours(int h);

  /// No description provided for @snsCellsAwaitingFix.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a location fix — the heat map centres on you.'**
  String get snsCellsAwaitingFix;

  /// No description provided for @snsCellsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get snsCellsClear;

  /// No description provided for @snsCellsStatus.
  ///
  /// In en, this message translates to:
  /// **'{active} cells · {hot} hot'**
  String snsCellsStatus(int active, int hot);

  /// No description provided for @snsFrameMetro.
  ///
  /// In en, this message translates to:
  /// **'Metro · ~20 km'**
  String get snsFrameMetro;

  /// No description provided for @snsFrameRegion.
  ///
  /// In en, this message translates to:
  /// **'Region · ~300 km'**
  String get snsFrameRegion;

  /// No description provided for @snsFrameMesh.
  ///
  /// In en, this message translates to:
  /// **'Mesh · fit all'**
  String get snsFrameMesh;

  /// No description provided for @snsCellsLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'SNS CELLS'**
  String get snsCellsLegendTitle;

  /// No description provided for @snsCellsLegendDesc.
  ///
  /// In en, this message translates to:
  /// **'A live social-activity heat map. Each observed message warms its cell; cells cool over a one-hour horizon.'**
  String get snsCellsLegendDesc;

  /// No description provided for @snsCellsLegendHot.
  ///
  /// In en, this message translates to:
  /// **'Bright red = busy (≈5+ messages in the last minute).'**
  String get snsCellsLegendHot;

  /// No description provided for @snsCellsLegendCool.
  ///
  /// In en, this message translates to:
  /// **'Fading to white = quieting down; gone after ~1 h idle.'**
  String get snsCellsLegendCool;

  /// No description provided for @snsCellsLegendToast.
  ///
  /// In en, this message translates to:
  /// **'New messages flash as a toast near their source, then vanish.'**
  String get snsCellsLegendToast;

  /// No description provided for @snsCellsLegendChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel messages carry the sender\'s name — they warm the sender\'s cell when we know their location, otherwise your own cell (the receive point).'**
  String get snsCellsLegendChannel;

  /// No description provided for @snsCellsLegendDecay.
  ///
  /// In en, this message translates to:
  /// **'Only the last hour is tracked; nothing is stored.'**
  String get snsCellsLegendDecay;

  /// No description provided for @meshTreeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Waiting for contact sync — the tree is built from each contact\'s outPath.'**
  String get meshTreeEmpty;

  /// No description provided for @meshTreeHopsDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get meshTreeHopsDirect;

  /// No description provided for @meshTreeHopsFlood.
  ///
  /// In en, this message translates to:
  /// **'Flood / All'**
  String get meshTreeHopsFlood;

  /// No description provided for @meshTreeHopsN.
  ///
  /// In en, this message translates to:
  /// **'≤{n} hops'**
  String meshTreeHopsN(int n);

  /// No description provided for @meshTreeRecenter.
  ///
  /// In en, this message translates to:
  /// **'Recenter'**
  String get meshTreeRecenter;

  /// No description provided for @meshTreeLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'MESH TREE'**
  String get meshTreeLegendTitle;

  /// No description provided for @meshTreeLegendDesc.
  ///
  /// In en, this message translates to:
  /// **'A directed graph of how the radio reaches each contact. Edges come from Contact.outPath — the exact repeater chain the device uses to send.'**
  String get meshTreeLegendDesc;

  /// No description provided for @meshTreeLegendSelf.
  ///
  /// In en, this message translates to:
  /// **'You — pinned at the centre.'**
  String get meshTreeLegendSelf;

  /// No description provided for @meshTreeLegendRepeater.
  ///
  /// In en, this message translates to:
  /// **'A square is a repeater: a radio that passes other radios\' messages.'**
  String get meshTreeLegendRepeater;

  /// No description provided for @meshTreeLegendRoom.
  ///
  /// In en, this message translates to:
  /// **'A diamond is a room server: a radio that hosts named rooms.'**
  String get meshTreeLegendRoom;

  /// No description provided for @meshTreeLegendChat.
  ///
  /// In en, this message translates to:
  /// **'A circle is a node you can message directly.'**
  String get meshTreeLegendChat;

  /// No description provided for @meshTreeLegendSensor.
  ///
  /// In en, this message translates to:
  /// **'A small dim circle is a sensor: it only reports readings.'**
  String get meshTreeLegendSensor;

  /// No description provided for @meshTreeLegendFlood.
  ///
  /// In en, this message translates to:
  /// **'Dashed edge to you = flood-routed contact. Reachable, but with no fixed path.'**
  String get meshTreeLegendFlood;

  /// No description provided for @meshTreeLegendFloat.
  ///
  /// In en, this message translates to:
  /// **'Floating (no edges) — heard via advert only; route unknown.'**
  String get meshTreeLegendFloat;

  /// No description provided for @meshTreeLegendArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrows point away from us, toward the destination peer.'**
  String get meshTreeLegendArrow;

  /// No description provided for @meshTreeLegendInteract.
  ///
  /// In en, this message translates to:
  /// **'Tap a node for details, or Recenter to reset the view.'**
  String get meshTreeLegendInteract;

  /// No description provided for @fabricLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'MESH SURVEY'**
  String get fabricLegendTitle;

  /// No description provided for @fabricLegendDesc.
  ///
  /// In en, this message translates to:
  /// **'A persistent record of where the mesh has been observed. Each rectangle is a small geographic cell (~220 m × 220 m) the device logged on contact with this location.'**
  String get fabricLegendDesc;

  /// No description provided for @fabricLegendCell.
  ///
  /// In en, this message translates to:
  /// **'Filled cell — the mesh reached here at some point.'**
  String get fabricLegendCell;

  /// No description provided for @fabricLegendRecency.
  ///
  /// In en, this message translates to:
  /// **'Brighter is more recent: under an hour, under a day, under a week, older.'**
  String get fabricLegendRecency;

  /// No description provided for @fabricLegendMarker.
  ///
  /// In en, this message translates to:
  /// **'Filled pins are the nodes in range now. Tap one for details.'**
  String get fabricLegendMarker;

  /// No description provided for @fabricLegendSelf.
  ///
  /// In en, this message translates to:
  /// **'The primary-coloured pin is you.'**
  String get fabricLegendSelf;

  /// No description provided for @fabricLegendReset.
  ///
  /// In en, this message translates to:
  /// **'Reset the survey from the overflow menu when you move to a new area.'**
  String get fabricLegendReset;

  /// No description provided for @nodeDetailHopsKv.
  ///
  /// In en, this message translates to:
  /// **'hops'**
  String get nodeDetailHopsKv;

  /// No description provided for @nodeDetailHopsDirect.
  ///
  /// In en, this message translates to:
  /// **'direct (0 hops)'**
  String get nodeDetailHopsDirect;

  /// No description provided for @nodeDetailHopsViaRepeaters.
  ///
  /// In en, this message translates to:
  /// **'{n} via repeater(s)'**
  String nodeDetailHopsViaRepeaters(int n);

  /// No description provided for @nodeDetailHopsUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get nodeDetailHopsUnknown;

  /// No description provided for @nodeDetailHopsFlood.
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get nodeDetailHopsFlood;

  /// No description provided for @nodeDetailAltitudeKv.
  ///
  /// In en, this message translates to:
  /// **'altitude'**
  String get nodeDetailAltitudeKv;

  /// No description provided for @nodeDetailAltitudeMeters.
  ///
  /// In en, this message translates to:
  /// **'{m} m'**
  String nodeDetailAltitudeMeters(String m);

  /// No description provided for @nodeDetailTempKv.
  ///
  /// In en, this message translates to:
  /// **'temperature'**
  String get nodeDetailTempKv;

  /// No description provided for @nodeDetailTempValue.
  ///
  /// In en, this message translates to:
  /// **'{c} °C'**
  String nodeDetailTempValue(String c);

  /// No description provided for @nodeDetailHumidityKv.
  ///
  /// In en, this message translates to:
  /// **'humidity'**
  String get nodeDetailHumidityKv;

  /// No description provided for @nodeDetailHumidityValue.
  ///
  /// In en, this message translates to:
  /// **'{p}%'**
  String nodeDetailHumidityValue(String p);

  /// No description provided for @nodeDetailPressureKv.
  ///
  /// In en, this message translates to:
  /// **'pressure'**
  String get nodeDetailPressureKv;

  /// No description provided for @nodeDetailPressureValue.
  ///
  /// In en, this message translates to:
  /// **'{hpa} hPa'**
  String nodeDetailPressureValue(String hpa);

  /// No description provided for @nodeDetailLuminosityKv.
  ///
  /// In en, this message translates to:
  /// **'luminosity'**
  String get nodeDetailLuminosityKv;

  /// No description provided for @nodeDetailQueryTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Query telemetry'**
  String get nodeDetailQueryTelemetry;

  /// No description provided for @nodeDetailRefreshTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Refresh telemetry'**
  String get nodeDetailRefreshTelemetry;

  /// No description provided for @nodeDetailTelemetryQuerying.
  ///
  /// In en, this message translates to:
  /// **'Asking the radio for readings…'**
  String get nodeDetailTelemetryQuerying;

  /// No description provided for @nodeDetailTelemetryNotContact.
  ///
  /// In en, this message translates to:
  /// **'Not a device contact, so telemetry is unavailable.'**
  String get nodeDetailTelemetryNotContact;

  /// No description provided for @nodeDetailTelemetryAge.
  ///
  /// In en, this message translates to:
  /// **'telemetry from {age}'**
  String nodeDetailTelemetryAge(String age);

  /// No description provided for @nodeDetailAgoSeconds.
  ///
  /// In en, this message translates to:
  /// **'{n}s ago'**
  String nodeDetailAgoSeconds(int n);

  /// No description provided for @nodeDetailAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String nodeDetailAgoMinutes(int n);

  /// No description provided for @nodeDetailAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String nodeDetailAgoHours(int n);

  /// No description provided for @nodeDetailAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{n} d ago'**
  String nodeDetailAgoDays(int n);

  /// No description provided for @channelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channelsTitle;

  /// No description provided for @channelsHelp.
  ///
  /// In en, this message translates to:
  /// **'Channel 0 is the shared public one. A private group needs the same channel number, name and key on every radio.'**
  String get channelsHelp;

  /// No description provided for @channelsOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio (Diagnostics) to edit channels.'**
  String get channelsOfflineHint;

  /// No description provided for @channelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'— empty —'**
  String get channelsEmpty;

  /// No description provided for @channelsSlotLabel.
  ///
  /// In en, this message translates to:
  /// **'channel {idx}'**
  String channelsSlotLabel(int idx);

  /// No description provided for @channelsSlotActive.
  ///
  /// In en, this message translates to:
  /// **'channel {idx} · ACTIVE'**
  String channelsSlotActive(int idx);

  /// No description provided for @channelsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get channelsEdit;

  /// No description provided for @channelsSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get channelsSet;

  /// No description provided for @channelsSetSnack.
  ///
  /// In en, this message translates to:
  /// **'Channel {idx} set to \"{name}\" — every radio needs the same name and key here'**
  String channelsSetSnack(int idx, String name);

  /// No description provided for @channelsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel {idx}'**
  String channelsDialogTitle(int idx);

  /// No description provided for @channelsName.
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get channelsName;

  /// No description provided for @channelsInferPlaces.
  ///
  /// In en, this message translates to:
  /// **'Infer places from messages'**
  String get channelsInferPlaces;

  /// No description provided for @channelsInferPlacesSub.
  ///
  /// In en, this message translates to:
  /// **'Scan this channel\'s banter for place names and plot them on the SNS grid.'**
  String get channelsInferPlacesSub;

  /// OS notification title for a channel message.
  ///
  /// In en, this message translates to:
  /// **'Message on {name}'**
  String notifTitleChannel(String name);

  /// OS notification title for a direct message.
  ///
  /// In en, this message translates to:
  /// **'Direct message from {name}'**
  String notifTitleDirect(String name);

  /// OS notification title for an SOS or its acknowledgement.
  ///
  /// In en, this message translates to:
  /// **'Emergency alert'**
  String get notifTitleSos;

  /// OS notification body for an SOS. Deliberately omits the coordinates: the lock screen is not where a position should be published.
  ///
  /// In en, this message translates to:
  /// **'Open the app for the position. The alert carries coordinates that this phone does not show on the lock screen.'**
  String get notifBodySos;

  /// Section heading in the channel editor for the per-channel notification bundle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifSectionTitle;

  /// Per-channel: post an OS notification.
  ///
  /// In en, this message translates to:
  /// **'Show a notification'**
  String get notifOs;

  /// Per-channel: play the theme's audio cue.
  ///
  /// In en, this message translates to:
  /// **'Play a sound'**
  String get notifAudio;

  /// Per-channel: vibrate.
  ///
  /// In en, this message translates to:
  /// **'Vibrate'**
  String get notifHaptic;

  /// Per-channel: read the message aloud.
  ///
  /// In en, this message translates to:
  /// **'Speak the message'**
  String get notifTts;

  /// Per-channel: alert only when the message names this device.
  ///
  /// In en, this message translates to:
  /// **'Only when someone names me'**
  String get notifMentionsOnly;

  /// Explains the mentions-only mode.
  ///
  /// In en, this message translates to:
  /// **'Whole word or @name. Off means every message alerts.'**
  String get notifMentionsOnlySub;

  /// Per-channel opt-in: treat the public key's hex suffix as a mention.
  ///
  /// In en, this message translates to:
  /// **'Also match the last 4 characters of my ID'**
  String get notifKeySuffix;

  /// Warns about the key-suffix opt-in.
  ///
  /// In en, this message translates to:
  /// **'Anyone can choose those four characters, so leave this off unless you know the sender.'**
  String get notifKeySuffixSub;

  /// Shown when the OS notification permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off for this app, so messages will not appear on your lock screen.'**
  String get notifDeniedBanner;

  /// No description provided for @channelsKeySource.
  ///
  /// In en, this message translates to:
  /// **'Key source'**
  String get channelsKeySource;

  /// No description provided for @channelsKeyPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get channelsKeyPublic;

  /// No description provided for @channelsKeyHashtag.
  ///
  /// In en, this message translates to:
  /// **'#tag'**
  String get channelsKeyHashtag;

  /// No description provided for @channelsKeyHex.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get channelsKeyHex;

  /// No description provided for @channelsKeyPublicBody.
  ///
  /// In en, this message translates to:
  /// **'Uses the well-known Public channel key.'**
  String get channelsKeyPublicBody;

  /// No description provided for @channelsKeyHashtagHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. #mygroup'**
  String get channelsKeyHashtagHint;

  /// No description provided for @channelsKeyHashtagHelper.
  ///
  /// In en, this message translates to:
  /// **'Key derived from sha256(\"#tag\") — the # is part of the key'**
  String get channelsKeyHashtagHelper;

  /// No description provided for @channelsKeyHexHint.
  ///
  /// In en, this message translates to:
  /// **'32 hex chars (16 bytes)'**
  String get channelsKeyHexHint;

  /// No description provided for @channelsErrorTag.
  ///
  /// In en, this message translates to:
  /// **'Enter a #hashtag'**
  String get channelsErrorTag;

  /// No description provided for @channelsErrorHex.
  ///
  /// In en, this message translates to:
  /// **'The key must be 32 characters, 0-9 or A-F'**
  String get channelsErrorHex;

  /// No description provided for @channelsErrorName.
  ///
  /// In en, this message translates to:
  /// **'Enter a channel name'**
  String get channelsErrorName;

  /// No description provided for @channelsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get channelsCancel;

  /// No description provided for @channelsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get channelsSave;

  /// No description provided for @channelsHelpEncryption.
  ///
  /// In en, this message translates to:
  /// **'Channel 0\'s key is public. Other channels use the key you set.'**
  String get channelsHelpEncryption;

  /// No description provided for @channelsHexGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate a random key'**
  String get channelsHexGenerate;

  /// No description provided for @channelsHexCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get channelsHexCopy;

  /// No description provided for @channelsHexCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get channelsHexCopied;

  /// No description provided for @channelsTagWeakShort.
  ///
  /// In en, this message translates to:
  /// **'Short tags are guessable. Use 12+ chars or unusual phrasing.'**
  String get channelsTagWeakShort;

  /// No description provided for @channelsTagWeakCommon.
  ///
  /// In en, this message translates to:
  /// **'Common words are guessable — an attacker can grind tags. Use unusual phrasing.'**
  String get channelsTagWeakCommon;

  /// No description provided for @channelsSlot0WarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Overwriting the Public channel?'**
  String get channelsSlot0WarnTitle;

  /// No description provided for @channelsSlot0WarnBody.
  ///
  /// In en, this message translates to:
  /// **'Channel 0 is the shared public channel. A private key here means you can only talk to radios using that same key, and you lose the public channel. Continue?'**
  String get channelsSlot0WarnBody;

  /// No description provided for @channelsSlot0WarnContinue.
  ///
  /// In en, this message translates to:
  /// **'Overwrite channel 0'**
  String get channelsSlot0WarnContinue;

  /// No description provided for @channelsSlot0WarnCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get channelsSlot0WarnCancel;

  /// No description provided for @channelsCurrentKey.
  ///
  /// In en, this message translates to:
  /// **'Current key'**
  String get channelsCurrentKey;

  /// No description provided for @channelsRevealKey.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get channelsRevealKey;

  /// No description provided for @channelsHideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get channelsHideKey;

  /// No description provided for @channelsClear.
  ///
  /// In en, this message translates to:
  /// **'Reset channel'**
  String get channelsClear;

  /// No description provided for @channelsClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset channel {idx}?'**
  String channelsClearConfirmTitle(int idx);

  /// No description provided for @channelsClearConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The radio has no empty channel, so this one goes back to the public name and key. Other radios need the same to talk here again.'**
  String get channelsClearConfirmBody;

  /// No description provided for @channelsClearConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get channelsClearConfirmAction;

  /// No description provided for @channelsClearSnack.
  ///
  /// In en, this message translates to:
  /// **'Channel {idx} reset to the public defaults'**
  String channelsClearSnack(int idx);

  /// No description provided for @channelsDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get channelsDefaultBadge;

  /// No description provided for @channelsSetDefaultTooltip.
  ///
  /// In en, this message translates to:
  /// **'Set as default channel on launch'**
  String get channelsSetDefaultTooltip;

  /// No description provided for @channelsClearDefaultTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear default channel preference'**
  String get channelsClearDefaultTooltip;

  /// No description provided for @channelsSetDefaultSnack.
  ///
  /// In en, this message translates to:
  /// **'Channel {idx} is now the one the app opens on'**
  String channelsSetDefaultSnack(int idx);

  /// No description provided for @channelsClearedDefaultSnack.
  ///
  /// In en, this message translates to:
  /// **'Launch default cleared'**
  String get channelsClearedDefaultSnack;

  /// No description provided for @channelsKeyShake.
  ///
  /// In en, this message translates to:
  /// **'Shake'**
  String get channelsKeyShake;

  /// No description provided for @channelsShakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Shake to roll dice'**
  String get channelsShakeTitle;

  /// No description provided for @channelsShakeBody.
  ///
  /// In en, this message translates to:
  /// **'Shake your phone — each accepted motion sample feeds the hash. Stop once the ring fills.'**
  String get channelsShakeBody;

  /// No description provided for @channelsShakeProgress.
  ///
  /// In en, this message translates to:
  /// **'{accepted} of {target} samples · {pct}%'**
  String channelsShakeProgress(int accepted, int target, int pct);

  /// No description provided for @channelsShakeReroll.
  ///
  /// In en, this message translates to:
  /// **'Reroll'**
  String get channelsShakeReroll;

  /// No description provided for @channelsShakeTapFallback.
  ///
  /// In en, this message translates to:
  /// **'Tap to roll (reduceMotion is on — uses Random.secure instead)'**
  String get channelsShakeTapFallback;

  /// No description provided for @channelsShareQr.
  ///
  /// In en, this message translates to:
  /// **'Share via QR'**
  String get channelsShareQr;

  /// No description provided for @channelsQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Share channel {idx}'**
  String channelsQrTitle(int idx);

  /// No description provided for @channelsQrBody.
  ///
  /// In en, this message translates to:
  /// **'Scan with a Meshmore device or any QR reader. Anyone with this code can join the channel, so share it only with people you trust.'**
  String get channelsQrBody;

  /// No description provided for @channelsQrPayload.
  ///
  /// In en, this message translates to:
  /// **'Channel code (you can copy it)'**
  String get channelsQrPayload;

  /// No description provided for @channelsQrClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get channelsQrClose;

  /// No description provided for @deviceConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Device configuration'**
  String get deviceConfigTitle;

  /// No description provided for @deviceRegionBand.
  ///
  /// In en, this message translates to:
  /// **'Band preset'**
  String get deviceRegionBand;

  /// No description provided for @deviceRegionWhy.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get deviceRegionWhy;

  /// No description provided for @deviceRegionCaveatTitle.
  ///
  /// In en, this message translates to:
  /// **'Region caveat'**
  String get deviceRegionCaveatTitle;

  /// No description provided for @deviceRegionCaveatClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get deviceRegionCaveatClose;

  /// No description provided for @deviceRegionCurrent.
  ///
  /// In en, this message translates to:
  /// **'CURRENTLY APPLIED'**
  String get deviceRegionCurrent;

  /// No description provided for @deviceRegionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Waiting for device…'**
  String get deviceRegionUnknown;

  /// No description provided for @deviceRegionCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get deviceRegionCustom;

  /// No description provided for @deviceRegionSuggestFromLocation.
  ///
  /// In en, this message translates to:
  /// **'Suggest from my location'**
  String get deviceRegionSuggestFromLocation;

  /// No description provided for @deviceRegionFamilyAmericas.
  ///
  /// In en, this message translates to:
  /// **'Americas'**
  String get deviceRegionFamilyAmericas;

  /// No description provided for @deviceRegionFamilyEurope.
  ///
  /// In en, this message translates to:
  /// **'Europe'**
  String get deviceRegionFamilyEurope;

  /// No description provided for @deviceRegionFamilyAsiaPacific.
  ///
  /// In en, this message translates to:
  /// **'Asia-Pacific'**
  String get deviceRegionFamilyAsiaPacific;

  /// No description provided for @deviceRegionFamilyOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get deviceRegionFamilyOther;

  /// No description provided for @deviceRegionSuggestTitle.
  ///
  /// In en, this message translates to:
  /// **'Use the preset for your location?'**
  String get deviceRegionSuggestTitle;

  /// No description provided for @deviceRegionSuggestBody.
  ///
  /// In en, this message translates to:
  /// **'Based on your phone GPS ({lat}, {lon}), the matching preset is {label}. Verify this is legal where you are before applying — particularly outside the country you set up in.'**
  String deviceRegionSuggestBody(String lat, String lon, String label);

  /// No description provided for @deviceRegionSuggestApply.
  ///
  /// In en, this message translates to:
  /// **'Use it'**
  String get deviceRegionSuggestApply;

  /// No description provided for @deviceRegionSuggestNoFix.
  ///
  /// In en, this message translates to:
  /// **'No GPS fix yet. Try outdoors with location on.'**
  String get deviceRegionSuggestNoFix;

  /// No description provided for @deviceRegionSuggestNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Your location doesn\'t match any shipped country preset — pick one manually.'**
  String get deviceRegionSuggestNoMatch;

  /// No description provided for @deviceRegionDisclaimerShort.
  ///
  /// In en, this message translates to:
  /// **'Shared by users, not checked by a regulator.'**
  String get deviceRegionDisclaimerShort;

  /// No description provided for @deviceRegionDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'These presets are shared by users, not checked by a regulator. Pick one that is legal where you are and use the same settings on every radio. In Japan the radio itself must carry 技適 (giteki) certification; most imported boards do not, and using one is an offence under the Radio Act whatever the settings. The Japan (ARIB STD-T108) preset is a community proposal that has not been widely tested.'**
  String get deviceRegionDisclaimer;

  /// No description provided for @presetUsCanada.
  ///
  /// In en, this message translates to:
  /// **'USA / Canada'**
  String get presetUsCanada;

  /// No description provided for @presetUsArizona.
  ///
  /// In en, this message translates to:
  /// **'USA — Arizona'**
  String get presetUsArizona;

  /// No description provided for @presetJpAribT108.
  ///
  /// In en, this message translates to:
  /// **'Japan (ARIB STD-T108)'**
  String get presetJpAribT108;

  /// No description provided for @presetJpMeshcore.
  ///
  /// In en, this message translates to:
  /// **'Japan (MeshCore-JP)'**
  String get presetJpMeshcore;

  /// No description provided for @presetEuUkLong.
  ///
  /// In en, this message translates to:
  /// **'EU / UK (Long Range)'**
  String get presetEuUkLong;

  /// No description provided for @presetEuUkMedium.
  ///
  /// In en, this message translates to:
  /// **'EU / UK (Medium Range)'**
  String get presetEuUkMedium;

  /// No description provided for @presetEuUkNarrow.
  ///
  /// In en, this message translates to:
  /// **'EU / UK (Narrow)'**
  String get presetEuUkNarrow;

  /// No description provided for @presetCh.
  ///
  /// In en, this message translates to:
  /// **'Switzerland'**
  String get presetCh;

  /// No description provided for @presetCz.
  ///
  /// In en, this message translates to:
  /// **'Czech Republic'**
  String get presetCz;

  /// No description provided for @presetPt869.
  ///
  /// In en, this message translates to:
  /// **'Portugal (869 MHz)'**
  String get presetPt869;

  /// No description provided for @presetAu.
  ///
  /// In en, this message translates to:
  /// **'Australia'**
  String get presetAu;

  /// No description provided for @presetAuNarrow.
  ///
  /// In en, this message translates to:
  /// **'Australia (Narrow)'**
  String get presetAuNarrow;

  /// No description provided for @presetAuSaWaQld.
  ///
  /// In en, this message translates to:
  /// **'Australia (SA / WA / QLD)'**
  String get presetAuSaWaQld;

  /// No description provided for @presetNz.
  ///
  /// In en, this message translates to:
  /// **'New Zealand'**
  String get presetNz;

  /// No description provided for @presetVn.
  ///
  /// In en, this message translates to:
  /// **'Vietnam'**
  String get presetVn;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @closeSheet.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeSheet;

  /// No description provided for @deviceRadioParams.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get deviceRadioParams;

  /// No description provided for @deviceIdentityAdvert.
  ///
  /// In en, this message translates to:
  /// **'Identity and advert'**
  String get deviceIdentityAdvert;

  /// No description provided for @deviceChannelsSection.
  ///
  /// In en, this message translates to:
  /// **'CHANNELS'**
  String get deviceChannelsSection;

  /// No description provided for @deviceOtherParamsSection.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get deviceOtherParamsSection;

  /// No description provided for @deviceDeviceSection.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get deviceDeviceSection;

  /// No description provided for @deviceFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency (MHz)'**
  String get deviceFrequency;

  /// No description provided for @deviceBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth (kHz)'**
  String get deviceBandwidth;

  /// No description provided for @deviceSpreadingFactor.
  ///
  /// In en, this message translates to:
  /// **'Spreading factor (5–12)'**
  String get deviceSpreadingFactor;

  /// No description provided for @deviceCodingRate.
  ///
  /// In en, this message translates to:
  /// **'Coding rate (5–8)'**
  String get deviceCodingRate;

  /// No description provided for @deviceTxPower.
  ///
  /// In en, this message translates to:
  /// **'TX power (dBm)'**
  String get deviceTxPower;

  /// Radio/network setting. MeshCore path hash length.
  ///
  /// In en, this message translates to:
  /// **'Path hash size'**
  String get devicePathHashSize;

  /// No description provided for @devicePathHashSizeHelp.
  ///
  /// In en, this message translates to:
  /// **'The hash length this radio stamps on the packets it sends. Repeaters follow each packet\'s own length, so nodes need not agree. Longer hashes tell repeaters apart better but shrink the directed payload budget.'**
  String get devicePathHashSizeHelp;

  /// No description provided for @devicePathHashUnread.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get devicePathHashUnread;

  /// No description provided for @devicePathHashMismatch.
  ///
  /// In en, this message translates to:
  /// **'On the radio: {device}. Yours: {form}. Tap Apply to send yours.'**
  String devicePathHashMismatch(String device, String form);

  /// No description provided for @deviceRadioApplied.
  ///
  /// In en, this message translates to:
  /// **'The radio confirmed the change.'**
  String get deviceRadioApplied;

  /// No description provided for @deviceRadioRefused.
  ///
  /// In en, this message translates to:
  /// **'The radio refused {param} (error {code}). Later writes were not sent.'**
  String deviceRadioRefused(String param, String code);

  /// No description provided for @deviceRadioSilent.
  ///
  /// In en, this message translates to:
  /// **'No answer for {param} within five seconds — the write may not have applied.'**
  String deviceRadioSilent(String param);

  /// No description provided for @deviceRadioUnsupported.
  ///
  /// In en, this message translates to:
  /// **'{param} is not in this firmware build.'**
  String deviceRadioUnsupported(String param);

  /// No description provided for @deviceRadioUnknownState.
  ///
  /// In en, this message translates to:
  /// **'Cannot change radio settings yet: this radio has not reported its path-hash size, so there is no value to undo back to.'**
  String get deviceRadioUnknownState;

  /// No description provided for @deviceRadioRevert.
  ///
  /// In en, this message translates to:
  /// **'Undo radio change'**
  String get deviceRadioRevert;

  /// No description provided for @deviceRadioReverted.
  ///
  /// In en, this message translates to:
  /// **'Previous operating point restored.'**
  String get deviceRadioReverted;

  /// No description provided for @deviceRadioRevertUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Undo is one use only.'**
  String get deviceRadioRevertUnavailable;

  /// No description provided for @deviceRadioRevertFailed.
  ///
  /// In en, this message translates to:
  /// **'Undo did not apply — the radio kept its last values.'**
  String get deviceRadioRevertFailed;

  /// No description provided for @radioHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio health'**
  String get radioHealthTitle;

  /// No description provided for @radioHealthRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get radioHealthRead;

  /// No description provided for @radioHealthReading.
  ///
  /// In en, this message translates to:
  /// **'Reading…'**
  String get radioHealthReading;

  /// No description provided for @radioHealthUnread.
  ///
  /// In en, this message translates to:
  /// **'Tap Read'**
  String get radioHealthUnread;

  /// No description provided for @radioHealthNoise.
  ///
  /// In en, this message translates to:
  /// **'Noise {dbm} dBm'**
  String radioHealthNoise(String dbm);

  /// No description provided for @radioHealthLast.
  ///
  /// In en, this message translates to:
  /// **'Last {rssi} dBm · {snr} dB SNR'**
  String radioHealthLast(String rssi, String snr);

  /// No description provided for @radioHealthBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery {volts} V'**
  String radioHealthBattery(String volts);

  /// No description provided for @radioHealthNotReported.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get radioHealthNotReported;

  /// No description provided for @radioHealthUptime.
  ///
  /// In en, this message translates to:
  /// **'Up {uptime}'**
  String radioHealthUptime(String uptime);

  /// No description provided for @radioHealthSource.
  ///
  /// In en, this message translates to:
  /// **'From the radio'**
  String get radioHealthSource;

  /// No description provided for @deviceLoadFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Load from device'**
  String get deviceLoadFromDevice;

  /// No description provided for @deviceApplyRadio.
  ///
  /// In en, this message translates to:
  /// **'Apply radio params'**
  String get deviceApplyRadio;

  /// No description provided for @deviceConnectFirst.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio first (Diagnostics & connect).'**
  String get deviceConnectFirst;

  /// No description provided for @deviceAdvertName.
  ///
  /// In en, this message translates to:
  /// **'Advert name'**
  String get deviceAdvertName;

  /// No description provided for @deviceSetName.
  ///
  /// In en, this message translates to:
  /// **'Set name'**
  String get deviceSetName;

  /// No description provided for @deviceAdvertLatitude.
  ///
  /// In en, this message translates to:
  /// **'Advert latitude (°)'**
  String get deviceAdvertLatitude;

  /// No description provided for @deviceAdvertLongitude.
  ///
  /// In en, this message translates to:
  /// **'Advert longitude (°)'**
  String get deviceAdvertLongitude;

  /// No description provided for @deviceUsePhoneLocation.
  ///
  /// In en, this message translates to:
  /// **'Use phone location'**
  String get deviceUsePhoneLocation;

  /// No description provided for @deviceReadDeviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Read device location'**
  String get deviceReadDeviceLocation;

  /// No description provided for @deviceSetAdvertLocation.
  ///
  /// In en, this message translates to:
  /// **'Set advert location'**
  String get deviceSetAdvertLocation;

  /// No description provided for @deviceAdvertSource.
  ///
  /// In en, this message translates to:
  /// **'Advert location source'**
  String get deviceAdvertSource;

  /// No description provided for @deviceAdvertSourceNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get deviceAdvertSourceNone;

  /// No description provided for @deviceAdvertSourcePinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get deviceAdvertSourcePinned;

  /// No description provided for @deviceAdvertSourceGps.
  ///
  /// In en, this message translates to:
  /// **'Device GPS'**
  String get deviceAdvertSourceGps;

  /// No description provided for @deviceToastNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a node name'**
  String get deviceToastNameEmpty;

  /// No description provided for @deviceToastNameSet.
  ///
  /// In en, this message translates to:
  /// **'Name updated — re-advertising to neighbours'**
  String get deviceToastNameSet;

  /// No description provided for @deviceToastSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String deviceToastSendFailed(String error);

  /// No description provided for @deviceToastNoDeviceYet.
  ///
  /// In en, this message translates to:
  /// **'Device hasn\'t reported yet — try once linked'**
  String get deviceToastNoDeviceYet;

  /// No description provided for @deviceToastNoGpsYet.
  ///
  /// In en, this message translates to:
  /// **'Device has no location yet (no GPS fix)'**
  String get deviceToastNoGpsYet;

  /// No description provided for @deviceToastLoadedDeviceLoc.
  ///
  /// In en, this message translates to:
  /// **'Loaded device location · tap Set advert location to broadcast'**
  String get deviceToastLoadedDeviceLoc;

  /// No description provided for @deviceToastGettingPhoneFix.
  ///
  /// In en, this message translates to:
  /// **'Getting phone GPS fix…'**
  String get deviceToastGettingPhoneFix;

  /// No description provided for @deviceToastPhoneFixFailed.
  ///
  /// In en, this message translates to:
  /// **'Phone GPS fix failed (services off or timeout)'**
  String get deviceToastPhoneFixFailed;

  /// No description provided for @deviceToastNoFixReturned.
  ///
  /// In en, this message translates to:
  /// **'No fix returned'**
  String get deviceToastNoFixReturned;

  /// No description provided for @deviceToastGotPhoneLoc.
  ///
  /// In en, this message translates to:
  /// **'Got phone location · tap Set advert location to broadcast'**
  String get deviceToastGotPhoneLoc;

  /// No description provided for @deviceToastInvalidLatLon.
  ///
  /// In en, this message translates to:
  /// **'Enter valid lat (−90..90) and lon (−180..180)'**
  String get deviceToastInvalidLatLon;

  /// No description provided for @deviceToastAdvertLocSet.
  ///
  /// In en, this message translates to:
  /// **'Advert location set'**
  String get deviceToastAdvertLocSet;

  /// No description provided for @deviceToastInvalidRadio.
  ///
  /// In en, this message translates to:
  /// **'Enter valid numbers for freq/BW/SF/CR'**
  String get deviceToastInvalidRadio;

  /// No description provided for @deviceLocPermDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission needed for a phone GPS fix.'**
  String get deviceLocPermDenied;

  /// No description provided for @deviceLocPermDeniedPerm.
  ///
  /// In en, this message translates to:
  /// **'Location permission permanently denied — open OS settings to grant it.'**
  String get deviceLocPermDeniedPerm;

  /// No description provided for @deviceOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get deviceOpenSettings;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics & connect'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsRawFrameLog.
  ///
  /// In en, this message translates to:
  /// **'RAW FRAME LOG (newest first)'**
  String get diagnosticsRawFrameLog;

  /// No description provided for @diagnosticsDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get diagnosticsDisconnect;

  /// No description provided for @diagnosticsCopyLog.
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get diagnosticsCopyLog;

  /// No description provided for @otherManualAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual-add contacts'**
  String get otherManualAddTitle;

  /// No description provided for @otherManualAddSubOn.
  ///
  /// In en, this message translates to:
  /// **'You add heard nodes as contacts on demand.'**
  String get otherManualAddSubOn;

  /// No description provided for @otherManualAddSubOff.
  ///
  /// In en, this message translates to:
  /// **'Nodes you hear are saved as contacts.'**
  String get otherManualAddSubOff;

  /// No description provided for @otherTelemetryModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Who may read telemetry'**
  String get otherTelemetryModeTitle;

  /// No description provided for @otherTelemetryBase.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get otherTelemetryBase;

  /// No description provided for @otherTelemetryLoc.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get otherTelemetryLoc;

  /// No description provided for @otherTelemetryEnv.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get otherTelemetryEnv;

  /// No description provided for @otherTelemetryDeny.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get otherTelemetryDeny;

  /// No description provided for @otherTelemetryFlags.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get otherTelemetryFlags;

  /// No description provided for @otherTelemetryAll.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get otherTelemetryAll;

  /// No description provided for @otherTelemetryModeHelp.
  ///
  /// In en, this message translates to:
  /// **'Who may request battery, GPS and environment data from this device.'**
  String get otherTelemetryModeHelp;

  /// No description provided for @otherMultiAcksLabel.
  ///
  /// In en, this message translates to:
  /// **'Extra confirmations (0–3)'**
  String get otherMultiAcksLabel;

  /// No description provided for @otherMultiAcksHelper.
  ///
  /// In en, this message translates to:
  /// **'0 is the default. Higher waits for that many more radios to confirm before calling a send confirmed.'**
  String get otherMultiAcksHelper;

  /// No description provided for @otherSentSnack.
  ///
  /// In en, this message translates to:
  /// **'OTHER PARAMS sent — device-side write may take a moment.'**
  String get otherSentSnack;

  /// No description provided for @otherAwaitingDevice.
  ///
  /// In en, this message translates to:
  /// **'— awaiting device —'**
  String get otherAwaitingDevice;

  /// No description provided for @batteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get batteryTitle;

  /// No description provided for @batteryConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Charge, drain rate, and time-to-empty estimate'**
  String get batteryConfigSubtitle;

  /// No description provided for @batteryAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a battery reading from the device…'**
  String get batteryAwaiting;

  /// No description provided for @batteryReset.
  ///
  /// In en, this message translates to:
  /// **'Reset history'**
  String get batteryReset;

  /// No description provided for @batteryResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all stored battery history? The runtime estimate will rebuild as new readings arrive.'**
  String get batteryResetConfirm;

  /// No description provided for @batteryVoltageLabel.
  ///
  /// In en, this message translates to:
  /// **'VOLTAGE'**
  String get batteryVoltageLabel;

  /// No description provided for @batteryCharging.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get batteryCharging;

  /// No description provided for @batteryChargingNote.
  ///
  /// In en, this message translates to:
  /// **'Charging — runtime estimate paused.'**
  String get batteryChargingNote;

  /// No description provided for @batteryTimeToEmpty.
  ///
  /// In en, this message translates to:
  /// **'TIME TO EMPTY'**
  String get batteryTimeToEmpty;

  /// No description provided for @batteryEstimating.
  ///
  /// In en, this message translates to:
  /// **'Gathering drain data — an estimate appears after a few minutes of discharge.'**
  String get batteryEstimating;

  /// No description provided for @batteryDrainRate.
  ///
  /// In en, this message translates to:
  /// **'Drain rate'**
  String get batteryDrainRate;

  /// No description provided for @batteryBasis.
  ///
  /// In en, this message translates to:
  /// **'Basis'**
  String get batteryBasis;

  /// No description provided for @batteryBasisObserved.
  ///
  /// In en, this message translates to:
  /// **'measured over {span} of discharge'**
  String batteryBasisObserved(String span);

  /// No description provided for @batteryBasisRated.
  ///
  /// In en, this message translates to:
  /// **'nameplate (capacity ÷ typical draw)'**
  String get batteryBasisRated;

  /// No description provided for @batteryConfidence.
  ///
  /// In en, this message translates to:
  /// **'confidence'**
  String get batteryConfidence;

  /// No description provided for @batteryConfHigh.
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get batteryConfHigh;

  /// No description provided for @batteryConfMedium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get batteryConfMedium;

  /// No description provided for @batteryConfLow.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get batteryConfLow;

  /// No description provided for @batteryMethodObserved.
  ///
  /// In en, this message translates to:
  /// **'Measured discharge'**
  String get batteryMethodObserved;

  /// No description provided for @batteryMethodRated.
  ///
  /// In en, this message translates to:
  /// **'Rated estimate'**
  String get batteryMethodRated;

  /// No description provided for @batteryMethodNone.
  ///
  /// In en, this message translates to:
  /// **'Gathering data'**
  String get batteryMethodNone;

  /// No description provided for @batterySpecTitle.
  ///
  /// In en, this message translates to:
  /// **'DEVICE MODEL'**
  String get batterySpecTitle;

  /// No description provided for @batterySpecGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unknown hardware — using a generic single-cell Li-ion model. The estimate relies on observed drain (no nameplate capacity to cross-check).'**
  String get batterySpecGeneric;

  /// No description provided for @batterySpecCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity: {mah} mAh'**
  String batterySpecCapacity(int mah);

  /// No description provided for @batterySpecCapacityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Capacity: user-supplied (unknown)'**
  String get batterySpecCapacityUnknown;

  /// No description provided for @batterySpecDraw.
  ///
  /// In en, this message translates to:
  /// **'Typical draw: ~{ma} mA (radio receiving)'**
  String batterySpecDraw(int ma);

  /// No description provided for @batteryHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'VOLTAGE HISTORY'**
  String get batteryHistoryTitle;

  /// No description provided for @batteryHistorySpan.
  ///
  /// In en, this message translates to:
  /// **'{span} · {count} samples'**
  String batteryHistorySpan(String span, int count);

  /// No description provided for @batteryDurDH.
  ///
  /// In en, this message translates to:
  /// **'{days}d {hours}h'**
  String batteryDurDH(int days, int hours);

  /// No description provided for @batteryDurHM.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {mins}m'**
  String batteryDurHM(int hours, int mins);

  /// No description provided for @batteryDurM.
  ///
  /// In en, this message translates to:
  /// **'{mins}m'**
  String batteryDurM(int mins);

  /// No description provided for @deliverySending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get deliverySending;

  /// No description provided for @deliverySent.
  ///
  /// In en, this message translates to:
  /// **'Sent into the mesh'**
  String get deliverySent;

  /// No description provided for @deliveryDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered (recipient acknowledged)'**
  String get deliveryDelivered;

  /// No description provided for @deliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Not delivered — no acknowledgement or send failed'**
  String get deliveryFailed;

  /// No description provided for @deliveryUnknown.
  ///
  /// In en, this message translates to:
  /// **'Sent while the app was closing — whether the radio transmitted it is not knowable'**
  String get deliveryUnknown;

  /// No description provided for @settingsHubTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get settingsHubTools;

  /// No description provided for @toolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsTitle;

  /// No description provided for @toolsOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected — the tools need the radio.'**
  String get toolsOffline;

  /// No description provided for @toolsRunning.
  ///
  /// In en, this message translates to:
  /// **'RUNNING'**
  String get toolsRunning;

  /// No description provided for @toolsStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get toolsStart;

  /// No description provided for @toolsStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get toolsStop;

  /// No description provided for @toolsCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get toolsCopyReport;

  /// No description provided for @toolsCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to the clipboard'**
  String get toolsCopied;

  /// No description provided for @toolsCount.
  ///
  /// In en, this message translates to:
  /// **'COUNT'**
  String get toolsCount;

  /// No description provided for @toolsInterval.
  ///
  /// In en, this message translates to:
  /// **'INTERVAL'**
  String get toolsInterval;

  /// No description provided for @toolsSeconds.
  ///
  /// In en, this message translates to:
  /// **'{n} s'**
  String toolsSeconds(int n);

  /// No description provided for @toolsMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String toolsMinutes(int n);

  /// No description provided for @toolsMs.
  ///
  /// In en, this message translates to:
  /// **'{n} ms'**
  String toolsMs(int n);

  /// No description provided for @toolsDb.
  ///
  /// In en, this message translates to:
  /// **'{v} dB'**
  String toolsDb(String v);

  /// No description provided for @toolsChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get toolsChoose;

  /// No description provided for @toolStatsName.
  ///
  /// In en, this message translates to:
  /// **'Radio stats'**
  String get toolStatsName;

  /// No description provided for @toolStatsSub.
  ///
  /// In en, this message translates to:
  /// **'Noise floor, airtime, packet counters'**
  String get toolStatsSub;

  /// No description provided for @toolPingName.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get toolPingName;

  /// No description provided for @toolPingSub.
  ///
  /// In en, this message translates to:
  /// **'Round-trip to a contact: loss and RTT'**
  String get toolPingSub;

  /// No description provided for @toolTraceName.
  ///
  /// In en, this message translates to:
  /// **'Trace path'**
  String get toolTraceName;

  /// No description provided for @toolTraceSub.
  ///
  /// In en, this message translates to:
  /// **'Per-hop SNR along a repeater chain'**
  String get toolTraceSub;

  /// No description provided for @toolDiscoverName.
  ///
  /// In en, this message translates to:
  /// **'Discover nearby'**
  String get toolDiscoverName;

  /// No description provided for @toolDiscoverSub.
  ///
  /// In en, this message translates to:
  /// **'Repeaters that hear us, SNR both ways'**
  String get toolDiscoverSub;

  /// No description provided for @toolSoakName.
  ///
  /// In en, this message translates to:
  /// **'Soak test'**
  String get toolSoakName;

  /// No description provided for @toolSoakSub.
  ///
  /// In en, this message translates to:
  /// **'Sequenced messages, counted — pairs with the bot'**
  String get toolSoakSub;

  /// No description provided for @toolRangeName.
  ///
  /// In en, this message translates to:
  /// **'Range test'**
  String get toolRangeName;

  /// No description provided for @toolRangeSub.
  ///
  /// In en, this message translates to:
  /// **'Beacon or log, with SNR and distance'**
  String get toolRangeSub;

  /// No description provided for @toolFailNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a radio.'**
  String get toolFailNotConnected;

  /// No description provided for @toolFailBusy.
  ///
  /// In en, this message translates to:
  /// **'Another tool is using the radio. Stop it first.'**
  String get toolFailBusy;

  /// No description provided for @toolFailUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Your radio\'s firmware doesn\'t support this.'**
  String get toolFailUnsupported;

  /// No description provided for @toolFailNotFound.
  ///
  /// In en, this message translates to:
  /// **'The radio doesn\'t have this contact.'**
  String get toolFailNotFound;

  /// No description provided for @toolFailTableFull.
  ///
  /// In en, this message translates to:
  /// **'The radio is busy (send table full). Try again shortly.'**
  String get toolFailTableFull;

  /// No description provided for @toolFailRejected.
  ///
  /// In en, this message translates to:
  /// **'The radio refused the request.'**
  String get toolFailRejected;

  /// No description provided for @toolFailNoConfirm.
  ///
  /// In en, this message translates to:
  /// **'The radio didn\'t confirm the send.'**
  String get toolFailNoConfirm;

  /// No description provided for @toolFailPublic.
  ///
  /// In en, this message translates to:
  /// **'Public is refused: everything sent there reaches every radio. Use a private channel or a DM.'**
  String get toolFailPublic;

  /// No description provided for @toolFailUnknownChannel.
  ///
  /// In en, this message translates to:
  /// **'This channel\'s key hasn\'t been read from the radio yet.'**
  String get toolFailUnknownChannel;

  /// No description provided for @toolFailNoTarget.
  ///
  /// In en, this message translates to:
  /// **'Choose a target first.'**
  String get toolFailNoTarget;

  /// No description provided for @statsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get statsRefresh;

  /// No description provided for @statsAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (every 5 s)'**
  String get statsAuto;

  /// No description provided for @statsSectionRadio.
  ///
  /// In en, this message translates to:
  /// **'RADIO'**
  String get statsSectionRadio;

  /// No description provided for @statsSectionPackets.
  ///
  /// In en, this message translates to:
  /// **'PACKETS'**
  String get statsSectionPackets;

  /// No description provided for @statsSectionCore.
  ///
  /// In en, this message translates to:
  /// **'CORE'**
  String get statsSectionCore;

  /// No description provided for @statsNoise.
  ///
  /// In en, this message translates to:
  /// **'Noise floor'**
  String get statsNoise;

  /// No description provided for @statsLastRssi.
  ///
  /// In en, this message translates to:
  /// **'Last RSSI'**
  String get statsLastRssi;

  /// No description provided for @statsLastSnr.
  ///
  /// In en, this message translates to:
  /// **'Last SNR'**
  String get statsLastSnr;

  /// No description provided for @statsTxAir.
  ///
  /// In en, this message translates to:
  /// **'TX airtime'**
  String get statsTxAir;

  /// No description provided for @statsRxAir.
  ///
  /// In en, this message translates to:
  /// **'RX airtime'**
  String get statsRxAir;

  /// No description provided for @statsDuty.
  ///
  /// In en, this message translates to:
  /// **'Duty cycle (TX)'**
  String get statsDuty;

  /// No description provided for @statsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get statsReceived;

  /// No description provided for @statsSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get statsSent;

  /// No description provided for @statsSplit.
  ///
  /// In en, this message translates to:
  /// **'flood {flood} · direct {direct}'**
  String statsSplit(int flood, int direct);

  /// No description provided for @statsRxErrors.
  ///
  /// In en, this message translates to:
  /// **'Receive errors'**
  String get statsRxErrors;

  /// No description provided for @statsUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get statsUptime;

  /// No description provided for @statsQueue.
  ///
  /// In en, this message translates to:
  /// **'Send queue'**
  String get statsQueue;

  /// No description provided for @statsErrFlags.
  ///
  /// In en, this message translates to:
  /// **'Error flags'**
  String get statsErrFlags;

  /// No description provided for @statsBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get statsBattery;

  /// No description provided for @statsNotFetched.
  ///
  /// In en, this message translates to:
  /// **'Not fetched yet.'**
  String get statsNotFetched;

  /// No description provided for @pingTarget.
  ///
  /// In en, this message translates to:
  /// **'TARGET'**
  String get pingTarget;

  /// No description provided for @pingMethodStatus.
  ///
  /// In en, this message translates to:
  /// **'Status request — repeaters, rooms and sensors answer this.'**
  String get pingMethodStatus;

  /// No description provided for @pingMethodTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Asks for readings. The other radio answers only if it shares them with you.'**
  String get pingMethodTelemetry;

  /// No description provided for @pingSummary.
  ///
  /// In en, this message translates to:
  /// **'{sent} sent · {replied} replied · {lost} lost'**
  String pingSummary(int sent, int replied, int lost);

  /// No description provided for @pingRtt.
  ///
  /// In en, this message translates to:
  /// **'RTT min {min} · avg {avg} · max {max} ms'**
  String pingRtt(int min, int avg, int max);

  /// No description provided for @pingLost.
  ///
  /// In en, this message translates to:
  /// **'lost'**
  String get pingLost;

  /// No description provided for @pingWaiting.
  ///
  /// In en, this message translates to:
  /// **'waiting…'**
  String get pingWaiting;

  /// No description provided for @pingNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No synced contacts yet — only contacts can be pinged.'**
  String get pingNoContacts;

  /// No description provided for @pingLastStatus.
  ///
  /// In en, this message translates to:
  /// **'LAST STATUS'**
  String get pingLastStatus;

  /// No description provided for @traceToNode.
  ///
  /// In en, this message translates to:
  /// **'To a node'**
  String get traceToNode;

  /// No description provided for @traceManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get traceManual;

  /// No description provided for @traceRoundTrip.
  ///
  /// In en, this message translates to:
  /// **'Round trip (come back to us)'**
  String get traceRoundTrip;

  /// No description provided for @traceNoRoute.
  ///
  /// In en, this message translates to:
  /// **'no route — send it a message first'**
  String get traceNoRoute;

  /// No description provided for @tracePath.
  ///
  /// In en, this message translates to:
  /// **'path {path}'**
  String tracePath(String path);

  /// No description provided for @traceManualHint.
  ///
  /// In en, this message translates to:
  /// **'hashes, e.g. a1,7f,a1'**
  String get traceManualHint;

  /// No description provided for @traceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter one or more hex bytes.'**
  String get traceInvalid;

  /// No description provided for @traceRun.
  ///
  /// In en, this message translates to:
  /// **'Trace'**
  String get traceRun;

  /// No description provided for @traceNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'no answer'**
  String get traceNoAnswer;

  /// No description provided for @traceToUs.
  ///
  /// In en, this message translates to:
  /// **'→ us'**
  String get traceToUs;

  /// No description provided for @traceWeakest.
  ///
  /// In en, this message translates to:
  /// **'weakest: {hop}, {snr} dB'**
  String traceWeakest(String hop, String snr);

  /// No description provided for @traceReset.
  ///
  /// In en, this message translates to:
  /// **'Reset route'**
  String get traceReset;

  /// No description provided for @traceResetDone.
  ///
  /// In en, this message translates to:
  /// **'Route reset — the next message floods.'**
  String get traceResetDone;

  /// No description provided for @traceNoRepeaters.
  ///
  /// In en, this message translates to:
  /// **'Trace needs a repeater on the way: pick a repeater, or a contact reached through one.'**
  String get traceNoRepeaters;

  /// No description provided for @discoverStart.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverStart;

  /// No description provided for @discoverListening.
  ///
  /// In en, this message translates to:
  /// **'Listening… {s} s'**
  String discoverListening(int s);

  /// No description provided for @discoverNone.
  ///
  /// In en, this message translates to:
  /// **'No repeater answered.'**
  String get discoverNone;

  /// No description provided for @discoverTheyHearUs.
  ///
  /// In en, this message translates to:
  /// **'they hear us {snr} dB'**
  String discoverTheyHearUs(String snr);

  /// No description provided for @discoverWeHearThem.
  ///
  /// In en, this message translates to:
  /// **'we hear them {snr} dB / {rssi} dBm'**
  String discoverWeHearThem(String snr, int rssi);

  /// No description provided for @discoverAsymmetric.
  ///
  /// In en, this message translates to:
  /// **'asymmetric link'**
  String get discoverAsymmetric;

  /// No description provided for @soakScope.
  ///
  /// In en, this message translates to:
  /// **'CONVERSATION'**
  String get soakScope;

  /// No description provided for @soakPairHint.
  ///
  /// In en, this message translates to:
  /// **'Pairs with an R59 bot answering on the other radio: echoes show drops, duplicates and reordering.'**
  String get soakPairHint;

  /// No description provided for @soakSummary.
  ///
  /// In en, this message translates to:
  /// **'{sent} sent · {delivered} delivered · {failed} failed'**
  String soakSummary(int sent, int delivered, int failed);

  /// No description provided for @soakEchoes.
  ///
  /// In en, this message translates to:
  /// **'{echoed} echoed · {dup} duplicate · {reordered} reordered'**
  String soakEchoes(int echoed, int dup, int reordered);

  /// No description provided for @soakListening.
  ///
  /// In en, this message translates to:
  /// **'Sends done — listening for late echoes…'**
  String get soakListening;

  /// No description provided for @soakRun.
  ///
  /// In en, this message translates to:
  /// **'run {id}'**
  String soakRun(String id);

  /// No description provided for @soakEcho.
  ///
  /// In en, this message translates to:
  /// **'echo {ms} ms'**
  String soakEcho(int ms);

  /// No description provided for @soakDm.
  ///
  /// In en, this message translates to:
  /// **'DM · {name}'**
  String soakDm(String name);

  /// No description provided for @rangeSender.
  ///
  /// In en, this message translates to:
  /// **'Sender'**
  String get rangeSender;

  /// No description provided for @rangeReceiver.
  ///
  /// In en, this message translates to:
  /// **'Receiver'**
  String get rangeReceiver;

  /// No description provided for @rangeChannel.
  ///
  /// In en, this message translates to:
  /// **'CHANNEL'**
  String get rangeChannel;

  /// No description provided for @rangeHint.
  ///
  /// In en, this message translates to:
  /// **'Both radios on the same private channel. The sender beacons; the receiver walks and logs.'**
  String get rangeHint;

  /// No description provided for @rangeBeacons.
  ///
  /// In en, this message translates to:
  /// **'{n} beacons sent'**
  String rangeBeacons(int n);

  /// No description provided for @rangeSummary.
  ///
  /// In en, this message translates to:
  /// **'{heard} heard · {missing} missing'**
  String rangeSummary(int heard, int missing);

  /// No description provided for @rangeBest.
  ///
  /// In en, this message translates to:
  /// **'best SNR {snr} dB'**
  String rangeBest(String snr);

  /// No description provided for @rangeFarthest.
  ///
  /// In en, this message translates to:
  /// **'farthest {d}'**
  String rangeFarthest(String d);

  /// No description provided for @rangeCopyCsv.
  ///
  /// In en, this message translates to:
  /// **'Copy CSV'**
  String get rangeCopyCsv;

  /// No description provided for @rangeFlood.
  ///
  /// In en, this message translates to:
  /// **'flood'**
  String get rangeFlood;

  /// No description provided for @settingsHubInfo.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get settingsHubInfo;

  /// No description provided for @settingsNotifDeniedPermanent.
  ///
  /// In en, this message translates to:
  /// **'Notifications were permanently denied. The background service needs a persistent notification.'**
  String get settingsNotifDeniedPermanent;

  /// No description provided for @settingsNotifDeniedTransient.
  ///
  /// In en, this message translates to:
  /// **'Keeping the app connected in the background needs notifications. Allow them in Settings.'**
  String get settingsNotifDeniedTransient;

  /// No description provided for @deviceAdvertPropagatesHint.
  ///
  /// In en, this message translates to:
  /// **'Takes effect the next time the radio announces itself.'**
  String get deviceAdvertPropagatesHint;

  /// No description provided for @settingsHubMaps.
  ///
  /// In en, this message translates to:
  /// **'Offline maps'**
  String get settingsHubMaps;

  /// No description provided for @mapsTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline maps'**
  String get mapsTitle;

  /// No description provided for @mapsOffline.
  ///
  /// In en, this message translates to:
  /// **'No network. New maps can be set up only while online; downloads resume on their own.'**
  String get mapsOffline;

  /// No description provided for @mapsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get mapsStorage;

  /// No description provided for @mapsUsed.
  ///
  /// In en, this message translates to:
  /// **'{used} of {budget} used'**
  String mapsUsed(String used, String budget);

  /// No description provided for @mapsBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Regions {packs} · Event maps {layers} · Cached tiles {view}'**
  String mapsBreakdown(String packs, String layers, String view);

  /// No description provided for @mapsBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get mapsBudget;

  /// No description provided for @mapsViewKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep viewed'**
  String get mapsViewKeep;

  /// No description provided for @mapsClearView.
  ///
  /// In en, this message translates to:
  /// **'Clear viewed tiles'**
  String get mapsClearView;

  /// No description provided for @mapsPacks.
  ///
  /// In en, this message translates to:
  /// **'Region downloads'**
  String get mapsPacks;

  /// No description provided for @mapsAddPack.
  ///
  /// In en, this message translates to:
  /// **'Download a region'**
  String get mapsAddPack;

  /// No description provided for @mapsNoPacks.
  ///
  /// In en, this message translates to:
  /// **'No regions yet. Regions come from servers that allow offline use: USGS inside the US, or a tile server you add.'**
  String get mapsNoPacks;

  /// No description provided for @mapsArchives.
  ///
  /// In en, this message translates to:
  /// **'Region files'**
  String get mapsArchives;

  /// No description provided for @mapsNoArchives.
  ///
  /// In en, this message translates to:
  /// **'No region files. A region file is one download for a whole area: a .pmtiles file from a host you trust. Add its link.'**
  String get mapsNoArchives;

  /// No description provided for @mapsAddArchive.
  ///
  /// In en, this message translates to:
  /// **'Add region file'**
  String get mapsAddArchive;

  /// No description provided for @archiveUrl.
  ///
  /// In en, this message translates to:
  /// **'Link (https)'**
  String get archiveUrl;

  /// No description provided for @archiveSize.
  ///
  /// In en, this message translates to:
  /// **'Size in MB (optional)'**
  String get archiveSize;

  /// No description provided for @archiveSha.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 (optional)'**
  String get archiveSha;

  /// No description provided for @archiveStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get archiveStateFailed;

  /// No description provided for @archiveFailBadHash.
  ///
  /// In en, this message translates to:
  /// **'Checksum does not match.'**
  String get archiveFailBadHash;

  /// No description provided for @archiveFailBadSize.
  ///
  /// In en, this message translates to:
  /// **'Size does not match.'**
  String get archiveFailBadSize;

  /// No description provided for @archiveFailNotPm.
  ///
  /// In en, this message translates to:
  /// **'Not a PMTiles file.'**
  String get archiveFailNotPm;

  /// No description provided for @archiveFailSchema.
  ///
  /// In en, this message translates to:
  /// **'Wrong map layout. This file is not a compatible basemap.'**
  String get archiveFailSchema;

  /// No description provided for @archiveFailNotFound.
  ///
  /// In en, this message translates to:
  /// **'Link not found.'**
  String get archiveFailNotFound;

  /// No description provided for @archiveFailStorage.
  ///
  /// In en, this message translates to:
  /// **'The app could not write to its storage. Free some space and try again.'**
  String get archiveFailStorage;

  /// No description provided for @archiveRefusalDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Already added.'**
  String get archiveRefusalDuplicate;

  /// No description provided for @archiveStateWaitingWifi.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi-Fi'**
  String get archiveStateWaitingWifi;

  /// No description provided for @archiveRefusalNoSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough free space. Free up some and try again.'**
  String get archiveRefusalNoSpace;

  /// No description provided for @mapsPacksPublished.
  ///
  /// In en, this message translates to:
  /// **'Available packs'**
  String get mapsPacksPublished;

  /// No description provided for @mapsPacksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No offline maps published yet. You can still install one from a link.'**
  String get mapsPacksEmpty;

  /// No description provided for @mapsPacksFrom.
  ///
  /// In en, this message translates to:
  /// **'List from {source}'**
  String mapsPacksFrom(String source);

  /// No description provided for @mapsPacksBundle.
  ///
  /// In en, this message translates to:
  /// **'Built-in list'**
  String get mapsPacksBundle;

  /// No description provided for @mapsPacksUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The published list could not be read. Showing the built-in one.'**
  String get mapsPacksUnreadable;

  /// No description provided for @mapsPackInstall.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get mapsPackInstall;

  /// No description provided for @mapsPackLicence.
  ///
  /// In en, this message translates to:
  /// **'{licence} · {attribution}'**
  String mapsPackLicence(String licence, String attribution);

  /// No description provided for @mapsWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Download over Wi-Fi only'**
  String get mapsWifiOnly;

  /// No description provided for @mapsWifiOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'A pack can be hundreds of megabytes.'**
  String get mapsWifiOnlyHint;

  /// No description provided for @mapsOutsidePacks.
  ///
  /// In en, this message translates to:
  /// **'Outside your offline maps, the map needs a connection.'**
  String get mapsOutsidePacks;

  /// No description provided for @mapsLayers.
  ///
  /// In en, this message translates to:
  /// **'Event maps'**
  String get mapsLayers;

  /// No description provided for @mapsNoLayersShort.
  ///
  /// In en, this message translates to:
  /// **'No event maps added'**
  String get mapsNoLayersShort;

  /// No description provided for @mapsManageLayers.
  ///
  /// In en, this message translates to:
  /// **'Manage event maps…'**
  String get mapsManageLayers;

  /// No description provided for @mapsAddLayer.
  ///
  /// In en, this message translates to:
  /// **'Add event map'**
  String get mapsAddLayer;

  /// No description provided for @mapsNoLayers.
  ///
  /// In en, this message translates to:
  /// **'No event maps. Add a GeoJSON URL: a festival\'s street plan, a race course, a camp layout.'**
  String get mapsNoLayers;

  /// No description provided for @mapsSources.
  ///
  /// In en, this message translates to:
  /// **'Map sources'**
  String get mapsSources;

  /// No description provided for @mapsAddSource.
  ///
  /// In en, this message translates to:
  /// **'Add tile server'**
  String get mapsAddSource;

  /// No description provided for @mapsSourcePacks.
  ///
  /// In en, this message translates to:
  /// **'Offline download allowed'**
  String get mapsSourcePacks;

  /// No description provided for @mapsSourcePacksUs.
  ///
  /// In en, this message translates to:
  /// **'Offline download allowed (US only)'**
  String get mapsSourcePacksUs;

  /// No description provided for @mapsSourceViewOnly.
  ///
  /// In en, this message translates to:
  /// **'Viewed tiles only: the server forbids bulk download'**
  String get mapsSourceViewOnly;

  /// No description provided for @mapsSourcePick.
  ///
  /// In en, this message translates to:
  /// **'Basemap'**
  String get mapsSourcePick;

  /// No description provided for @packStateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get packStateDownloading;

  /// No description provided for @packStateUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating'**
  String get packStateUpdating;

  /// No description provided for @packStateWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for network'**
  String get packStateWaiting;

  /// No description provided for @packStateOverBudget.
  ///
  /// In en, this message translates to:
  /// **'Stopped: over budget'**
  String get packStateOverBudget;

  /// No description provided for @packStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get packStatePaused;

  /// No description provided for @packStateComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get packStateComplete;

  /// No description provided for @mapsPackLine.
  ///
  /// In en, this message translates to:
  /// **'{source} · zoom {minZ}–{maxZ}'**
  String mapsPackLine(String source, int minZ, int maxZ);

  /// No description provided for @mapsProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} tiles'**
  String mapsProgress(int done, int total);

  /// No description provided for @mapsMissing.
  ///
  /// In en, this message translates to:
  /// **'{n} not on server'**
  String mapsMissing(int n);

  /// No description provided for @mapsExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Deletes in {days} d'**
  String mapsExpiresIn(int days);

  /// No description provided for @mapsKeepForever.
  ///
  /// In en, this message translates to:
  /// **'Kept until deleted'**
  String get mapsKeepForever;

  /// No description provided for @mapsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get mapsPause;

  /// No description provided for @mapsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get mapsResume;

  /// No description provided for @mapsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get mapsUpdate;

  /// No description provided for @mapsRedownload.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get mapsRedownload;

  /// No description provided for @mapsKeepFor.
  ///
  /// In en, this message translates to:
  /// **'Delete after…'**
  String get mapsKeepFor;

  /// No description provided for @mapsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get mapsDelete;

  /// No description provided for @mapsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String mapsDeleteConfirm(String name);

  /// No description provided for @mapsKeepNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get mapsKeepNever;

  /// No description provided for @mapsKeepDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String mapsKeepDays(int days);

  /// No description provided for @mapsLayerFeatures.
  ///
  /// In en, this message translates to:
  /// **'{n} features'**
  String mapsLayerFeatures(int n);

  /// No description provided for @mapsLayerName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mapsLayerName;

  /// No description provided for @mapsLayerUrl.
  ///
  /// In en, this message translates to:
  /// **'GeoJSON URL (https)'**
  String get mapsLayerUrl;

  /// No description provided for @mapsLayerTerms.
  ///
  /// In en, this message translates to:
  /// **'The publisher\'s terms apply to their data.'**
  String get mapsLayerTerms;

  /// No description provided for @mapsSourceName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mapsSourceName;

  /// No description provided for @mapsSourceUrl.
  ///
  /// In en, this message translates to:
  /// **'Tile URL template'**
  String get mapsSourceUrl;

  /// No description provided for @mapsSourceAttr.
  ///
  /// In en, this message translates to:
  /// **'Attribution'**
  String get mapsSourceAttr;

  /// No description provided for @mapsSourceAllowsPacks.
  ///
  /// In en, this message translates to:
  /// **'This server allows offline download'**
  String get mapsSourceAllowsPacks;

  /// No description provided for @mapsSourceBad.
  ///
  /// In en, this message translates to:
  /// **'Needs a name and an https template with z, x and y placeholders.'**
  String get mapsSourceBad;

  /// No description provided for @mapsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get mapsAdd;

  /// No description provided for @mapsWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get mapsWorking;

  /// No description provided for @newPackName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get newPackName;

  /// No description provided for @newPackSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get newPackSource;

  /// No description provided for @newPackCenter.
  ///
  /// In en, this message translates to:
  /// **'Centre'**
  String get newPackCenter;

  /// No description provided for @newPackMyLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get newPackMyLocation;

  /// No description provided for @newPackNoLocation.
  ///
  /// In en, this message translates to:
  /// **'No location yet: enter lat, lon'**
  String get newPackNoLocation;

  /// No description provided for @newPackLatLon.
  ///
  /// In en, this message translates to:
  /// **'lat, lon'**
  String get newPackLatLon;

  /// No description provided for @newPackRadius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get newPackRadius;

  /// No description provided for @newPackZoomFrom.
  ///
  /// In en, this message translates to:
  /// **'Zoom from'**
  String get newPackZoomFrom;

  /// No description provided for @newPackZoomTo.
  ///
  /// In en, this message translates to:
  /// **'Zoom to'**
  String get newPackZoomTo;

  /// No description provided for @newPackKeep.
  ///
  /// In en, this message translates to:
  /// **'Delete after'**
  String get newPackKeep;

  /// No description provided for @newPackEstimate.
  ///
  /// In en, this message translates to:
  /// **'{tiles} tiles · about {size}'**
  String newPackEstimate(int tiles, String size);

  /// No description provided for @newPackCreate.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get newPackCreate;

  /// No description provided for @newPackNoSource.
  ///
  /// In en, this message translates to:
  /// **'No source here allows offline download. Add a tile server that does, under Map sources.'**
  String get newPackNoSource;

  /// No description provided for @packRefusalNoName.
  ///
  /// In en, this message translates to:
  /// **'Give it a name.'**
  String get packRefusalNoName;

  /// No description provided for @packRefusalOffline.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Set up maps while online.'**
  String get packRefusalOffline;

  /// No description provided for @packRefusalViewOnly.
  ///
  /// In en, this message translates to:
  /// **'This server doesn\'t allow offline download.'**
  String get packRefusalViewOnly;

  /// No description provided for @packRefusalCoverage.
  ///
  /// In en, this message translates to:
  /// **'This source has no data there.'**
  String get packRefusalCoverage;

  /// No description provided for @packRefusalTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many tiles. Shrink the area or lower the top zoom.'**
  String get packRefusalTooMany;

  /// No description provided for @packRefusalBudget.
  ///
  /// In en, this message translates to:
  /// **'Won\'t fit in the storage budget.'**
  String get packRefusalBudget;

  /// No description provided for @layerRefusalBadUrl.
  ///
  /// In en, this message translates to:
  /// **'Needs an https URL.'**
  String get layerRefusalBadUrl;

  /// No description provided for @layerRefusalNotGeoJson.
  ///
  /// In en, this message translates to:
  /// **'That URL didn\'t return GeoJSON.'**
  String get layerRefusalNotGeoJson;

  /// No description provided for @layerRefusalTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Over 10 MB: too big for an overlay.'**
  String get layerRefusalTooLarge;

  /// No description provided for @mapsSelfTest.
  ///
  /// In en, this message translates to:
  /// **'Self-test'**
  String get mapsSelfTest;

  /// No description provided for @selfTestIntro.
  ///
  /// In en, this message translates to:
  /// **'Checks map downloads end to end: the real servers, storage, downloads, pause and resume, expiry. It runs in a sandbox and deletes it afterwards, so your maps are not touched. Takes about a minute and under 1 MB of data.'**
  String get selfTestIntro;

  /// No description provided for @selfTestRun.
  ///
  /// In en, this message translates to:
  /// **'Run self-test'**
  String get selfTestRun;

  /// No description provided for @selfTestRunning.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get selfTestRunning;

  /// No description provided for @selfTestPass.
  ///
  /// In en, this message translates to:
  /// **'All checks passed'**
  String get selfTestPass;

  /// No description provided for @selfTestFail.
  ///
  /// In en, this message translates to:
  /// **'{n} checks failed'**
  String selfTestFail(int n);

  /// No description provided for @selfTestCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get selfTestCopy;

  /// No description provided for @selfTestCopied.
  ///
  /// In en, this message translates to:
  /// **'Report copied'**
  String get selfTestCopied;

  /// No description provided for @selfCheckReach.
  ///
  /// In en, this message translates to:
  /// **'Map servers reachable'**
  String get selfCheckReach;

  /// No description provided for @selfCheckViewCache.
  ///
  /// In en, this message translates to:
  /// **'Viewed tiles are kept'**
  String get selfCheckViewCache;

  /// No description provided for @selfCheckRevalidate.
  ///
  /// In en, this message translates to:
  /// **'Stale tiles re-checked politely'**
  String get selfCheckRevalidate;

  /// No description provided for @selfCheckPack.
  ///
  /// In en, this message translates to:
  /// **'Region download'**
  String get selfCheckPack;

  /// No description provided for @selfCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Region update'**
  String get selfCheckUpdate;

  /// No description provided for @selfCheckEventLayer.
  ///
  /// In en, this message translates to:
  /// **'Event map (GeoJSON)'**
  String get selfCheckEventLayer;

  /// No description provided for @selfCheckOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline behaviour'**
  String get selfCheckOffline;

  /// No description provided for @selfCheckResume.
  ///
  /// In en, this message translates to:
  /// **'Pause and resume on network loss'**
  String get selfCheckResume;

  /// No description provided for @selfCheckGuards.
  ///
  /// In en, this message translates to:
  /// **'Refusals (size, budget, policy, coverage)'**
  String get selfCheckGuards;

  /// No description provided for @selfCheckExpiry.
  ///
  /// In en, this message translates to:
  /// **'Delete-after expiry'**
  String get selfCheckExpiry;

  /// No description provided for @selfCheckDisk.
  ///
  /// In en, this message translates to:
  /// **'Storage matches the books'**
  String get selfCheckDisk;

  /// No description provided for @locGroupAutoPublish.
  ///
  /// In en, this message translates to:
  /// **'Publishing'**
  String get locGroupAutoPublish;

  /// No description provided for @locGroupBeacon.
  ///
  /// In en, this message translates to:
  /// **'Beacon'**
  String get locGroupBeacon;

  /// No description provided for @locGroupManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get locGroupManual;

  /// No description provided for @deviceManageChannels.
  ///
  /// In en, this message translates to:
  /// **'Manage channels'**
  String get deviceManageChannels;

  /// No description provided for @deviceActiveChannelSub.
  ///
  /// In en, this message translates to:
  /// **'Using: {name} · channels and keys'**
  String deviceActiveChannelSub(String name);

  /// No description provided for @locationSourceDevice.
  ///
  /// In en, this message translates to:
  /// **'device'**
  String get locationSourceDevice;

  /// No description provided for @locationSourcePhone.
  ///
  /// In en, this message translates to:
  /// **'phone GPS'**
  String get locationSourcePhone;

  /// No description provided for @locationSourceNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get locationSourceNone;

  /// No description provided for @batteryChargingShort.
  ///
  /// In en, this message translates to:
  /// **'CHG'**
  String get batteryChargingShort;

  /// No description provided for @elevationSelfTelemetry.
  ///
  /// In en, this message translates to:
  /// **'SELF TELEMETRY'**
  String get elevationSelfTelemetry;

  /// No description provided for @elevationSelfAlt.
  ///
  /// In en, this message translates to:
  /// **'alt: {m} m'**
  String elevationSelfAlt(String m);

  /// No description provided for @elevationSelfAltUnknown.
  ///
  /// In en, this message translates to:
  /// **'alt: —'**
  String get elevationSelfAltUnknown;

  /// No description provided for @elevationSelfTemp.
  ///
  /// In en, this message translates to:
  /// **'temp: {c} °C'**
  String elevationSelfTemp(String c);

  /// No description provided for @elevationPolling.
  ///
  /// In en, this message translates to:
  /// **'polling…'**
  String get elevationPolling;

  /// No description provided for @elevationTapToUpdate.
  ///
  /// In en, this message translates to:
  /// **'tap to update'**
  String get elevationTapToUpdate;

  /// No description provided for @diagnosticsSectionConnection.
  ///
  /// In en, this message translates to:
  /// **'CONNECTION'**
  String get diagnosticsSectionConnection;

  /// No description provided for @diagnosticsStateLine.
  ///
  /// In en, this message translates to:
  /// **'State: {state}'**
  String diagnosticsStateLine(String state);

  /// No description provided for @diagnosticsStateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'disconnected'**
  String get diagnosticsStateDisconnected;

  /// No description provided for @diagnosticsStateHandshaking.
  ///
  /// In en, this message translates to:
  /// **'handshaking'**
  String get diagnosticsStateHandshaking;

  /// No description provided for @diagnosticsStateReady.
  ///
  /// In en, this message translates to:
  /// **'ready'**
  String get diagnosticsStateReady;

  /// No description provided for @diagnosticsStateReconnecting.
  ///
  /// In en, this message translates to:
  /// **'reconnecting'**
  String get diagnosticsStateReconnecting;

  /// No description provided for @diagnosticsStateFailed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get diagnosticsStateFailed;

  /// No description provided for @diagnosticsConnectingSuffix.
  ///
  /// In en, this message translates to:
  /// **' · connecting…'**
  String get diagnosticsConnectingSuffix;

  /// No description provided for @diagnosticsDeviceLine.
  ///
  /// In en, this message translates to:
  /// **'device: {name} · {freq}MHz SF{sf}'**
  String diagnosticsDeviceLine(String name, String freq, String sf);

  /// No description provided for @diagnosticsBatteryLine.
  ///
  /// In en, this message translates to:
  /// **'battery: {volts}V (~{pct}%)'**
  String diagnosticsBatteryLine(String volts, String pct);

  /// No description provided for @diagnosticsChargingSuffix.
  ///
  /// In en, this message translates to:
  /// **' ⚡ charging'**
  String get diagnosticsChargingSuffix;

  /// No description provided for @diagnosticsReconnectLine.
  ///
  /// In en, this message translates to:
  /// **'reconnect attempt {n}'**
  String diagnosticsReconnectLine(String n);

  /// No description provided for @diagnosticsGaveUpSuffix.
  ///
  /// In en, this message translates to:
  /// **' (gave up)'**
  String get diagnosticsGaveUpSuffix;

  /// No description provided for @diagnosticsErrorLine.
  ///
  /// In en, this message translates to:
  /// **'error: {error}'**
  String diagnosticsErrorLine(String error);

  /// No description provided for @diagnosticsMtuLine.
  ///
  /// In en, this message translates to:
  /// **'Link size {mtu} bytes, {need} needed for a full frame'**
  String diagnosticsMtuLine(String mtu, String need);

  /// No description provided for @diagnosticsMtuRefusedLine.
  ///
  /// In en, this message translates to:
  /// **'This phone link is {mtu} bytes and a full radio frame needs {need}. Reconnect to try again; a radio that caps the link smaller cannot carry every frame.'**
  String diagnosticsMtuRefusedLine(String mtu, String need);

  /// No description provided for @diagnosticsDatagramLine.
  ///
  /// In en, this message translates to:
  /// **'datagram: channel {ch}, via {via}, type {type}'**
  String diagnosticsDatagramLine(String ch, String via, String type);

  /// No description provided for @rxViaPrimary.
  ///
  /// In en, this message translates to:
  /// **'the primary radio'**
  String get rxViaPrimary;

  /// No description provided for @rxViaSecondary.
  ///
  /// In en, this message translates to:
  /// **'radio 2'**
  String get rxViaSecondary;

  /// No description provided for @rxViaUnknown.
  ///
  /// In en, this message translates to:
  /// **'an unreported radio'**
  String get rxViaUnknown;

  /// No description provided for @diagnosticsFramingLine.
  ///
  /// In en, this message translates to:
  /// **'incomplete frames: {truncated} cut short, {trailing} with bytes left over'**
  String diagnosticsFramingLine(String truncated, String trailing);

  /// No description provided for @diagnosticsScanConnect.
  ///
  /// In en, this message translates to:
  /// **'Scan & connect'**
  String get diagnosticsScanConnect;

  /// No description provided for @diagnosticsForgetShort.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get diagnosticsForgetShort;

  /// No description provided for @diagnosticsPairedLine.
  ///
  /// In en, this message translates to:
  /// **'Paired: {name} — auto-reconnects on startup'**
  String diagnosticsPairedLine(String name);

  /// No description provided for @diagnosticsSectionDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get diagnosticsSectionDeveloper;

  /// No description provided for @diagnosticsPairRadio.
  ///
  /// In en, this message translates to:
  /// **'Pair a radio'**
  String get diagnosticsPairRadio;

  /// No description provided for @diagnosticsForgetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this radio?'**
  String get diagnosticsForgetConfirmTitle;

  /// No description provided for @diagnosticsForgetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to pair it again, and this clears its bond. Do not do this while the radio is out of reach.'**
  String get diagnosticsForgetConfirmBody;

  /// No description provided for @diagnosticsSectionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get diagnosticsSectionSend;

  /// No description provided for @diagnosticsSendSelfAdvert.
  ///
  /// In en, this message translates to:
  /// **'Send self-advert'**
  String get diagnosticsSendSelfAdvert;

  /// No description provided for @diagnosticsReadClock.
  ///
  /// In en, this message translates to:
  /// **'Read the radio\'s clock'**
  String get diagnosticsReadClock;

  /// No description provided for @diagnosticsPullMessage.
  ///
  /// In en, this message translates to:
  /// **'Pull the next message'**
  String get diagnosticsPullMessage;

  /// No description provided for @diagnosticsTestMessage.
  ///
  /// In en, this message translates to:
  /// **'Public-channel test message'**
  String get diagnosticsTestMessage;

  /// No description provided for @diagnosticsSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get diagnosticsSend;

  /// No description provided for @diagnosticsSentWhat.
  ///
  /// In en, this message translates to:
  /// **'Sent {what}'**
  String diagnosticsSentWhat(String what);

  /// No description provided for @diagnosticsSendFailed.
  ///
  /// In en, this message translates to:
  /// **'The send failed: {error}'**
  String diagnosticsSendFailed(String error);

  /// No description provided for @diagnosticsSectionM6.
  ///
  /// In en, this message translates to:
  /// **'Channel-tail evidence'**
  String get diagnosticsSectionM6;

  /// No description provided for @diagnosticsResolveTail.
  ///
  /// In en, this message translates to:
  /// **'Resolve channel-tail'**
  String get diagnosticsResolveTail;

  /// No description provided for @diagnosticsExportFixture.
  ///
  /// In en, this message translates to:
  /// **'Export fixture'**
  String get diagnosticsExportFixture;

  /// No description provided for @diagnosticsCopyFixture.
  ///
  /// In en, this message translates to:
  /// **'Copy fixture JSON'**
  String get diagnosticsCopyFixture;

  /// No description provided for @diagnosticsFixtureCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied. Save it under the protocol package\'s captured vectors.'**
  String get diagnosticsFixtureCopied;

  /// No description provided for @diagnosticsNoRfLog.
  ///
  /// In en, this message translates to:
  /// **'No RF-log frame captured yet'**
  String get diagnosticsNoRfLog;

  /// No description provided for @diagnosticsNotRfLog.
  ///
  /// In en, this message translates to:
  /// **'The last RF-log frame did not decode'**
  String get diagnosticsNotRfLog;

  /// No description provided for @diagnosticsNotGrpTxt.
  ///
  /// In en, this message translates to:
  /// **'That packet is not a group text. Send on the Public channel and try again.'**
  String get diagnosticsNotGrpTxt;

  /// No description provided for @diagnosticsExportNeedsCapture.
  ///
  /// In en, this message translates to:
  /// **'Needs a captured RF-log frame first'**
  String get diagnosticsExportNeedsCapture;

  /// No description provided for @diagnosticsNoFrames.
  ///
  /// In en, this message translates to:
  /// **'No frames yet'**
  String get diagnosticsNoFrames;

  /// No description provided for @diagnosticsFramesCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} frames'**
  String diagnosticsFramesCopied(String count);

  /// No description provided for @diagnosticsSectionSoak.
  ///
  /// In en, this message translates to:
  /// **'Soak'**
  String get diagnosticsSectionSoak;

  /// No description provided for @diagnosticsSoakEmpty.
  ///
  /// In en, this message translates to:
  /// **'No scopes bound'**
  String get diagnosticsSoakEmpty;

  /// No description provided for @diagnosticsCopySoak.
  ///
  /// In en, this message translates to:
  /// **'Copy soak report'**
  String get diagnosticsCopySoak;

  /// No description provided for @diagnosticsSoakCopied.
  ///
  /// In en, this message translates to:
  /// **'Soak report copied'**
  String get diagnosticsSoakCopied;

  /// No description provided for @nodesClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get nodesClearSearch;

  /// No description provided for @networksTitle.
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get networksTitle;

  /// No description provided for @networksTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Radio settings shared by a group of radios'**
  String get networksTileSubtitle;

  /// No description provided for @networksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No networks yet. A network is the radio settings your radios agree on.'**
  String get networksEmpty;

  /// No description provided for @networksNew.
  ///
  /// In en, this message translates to:
  /// **'New network'**
  String get networksNew;

  /// No description provided for @networksName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get networksName;

  /// No description provided for @networksNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the network a name.'**
  String get networksNameRequired;

  /// No description provided for @networksPreset.
  ///
  /// In en, this message translates to:
  /// **'Radio settings from'**
  String get networksPreset;

  /// No description provided for @networksPathHash.
  ///
  /// In en, this message translates to:
  /// **'Path hash size'**
  String get networksPathHash;

  /// No description provided for @networksPrivateSwitch.
  ///
  /// In en, this message translates to:
  /// **'Private frequency'**
  String get networksPrivateSwitch;

  /// No description provided for @networksPrivateHelp.
  ///
  /// In en, this message translates to:
  /// **'Use a frequency no public preset uses. Radios on it do not hear the public mesh, and the public mesh does not hear them.'**
  String get networksPrivateHelp;

  /// No description provided for @networksFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency (MHz)'**
  String get networksFrequency;

  /// No description provided for @networksFrequencyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a frequency from 150 to 2500 MHz.'**
  String get networksFrequencyInvalid;

  /// No description provided for @networksFrequencyPublic.
  ///
  /// In en, this message translates to:
  /// **'That frequency, bandwidth and spreading factor belong to the public preset {preset}. Pick a different frequency.'**
  String networksFrequencyPublic(String preset);

  /// No description provided for @networksSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get networksSave;

  /// No description provided for @networksCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get networksCancel;

  /// No description provided for @networksShared.
  ///
  /// In en, this message translates to:
  /// **'Shares the air with the public {preset} mesh. A key or a name does not separate radios on the same frequency, bandwidth and spreading factor.'**
  String networksShared(String preset);

  /// No description provided for @networksIsolated.
  ///
  /// In en, this message translates to:
  /// **'Separate from the public mesh. Radios not set to this frequency cannot hear it.'**
  String get networksIsolated;

  /// No description provided for @networksSummary.
  ///
  /// In en, this message translates to:
  /// **'{freq} MHz · {bw} kHz · SF{sf} · CR{cr} · path hash {ph}'**
  String networksSummary(
      String freq, String bw, String sf, String cr, String ph);

  /// No description provided for @networksMembers.
  ///
  /// In en, this message translates to:
  /// **'Members ({count})'**
  String networksMembers(int count);

  /// No description provided for @networksNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No members yet.'**
  String get networksNoMembers;

  /// No description provided for @networksAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get networksAddMember;

  /// No description provided for @networksNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No known contacts to add.'**
  String get networksNoContacts;

  /// No description provided for @networksRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get networksRemoveMember;

  /// No description provided for @networksApply.
  ///
  /// In en, this message translates to:
  /// **'Apply to this radio'**
  String get networksApply;

  /// No description provided for @networksApplyNeedsRadio.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio to apply.'**
  String get networksApplyNeedsRadio;

  /// No description provided for @networksApplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply {name}?'**
  String networksApplyTitle(String name);

  /// No description provided for @networksApplyBodyShared.
  ///
  /// In en, this message translates to:
  /// **'This radio will switch to {summary}.'**
  String networksApplyBodyShared(String summary);

  /// No description provided for @networksApplyBodyIsolated.
  ///
  /// In en, this message translates to:
  /// **'This radio will switch to {summary}. It will stop hearing the public mesh until you switch it back.'**
  String networksApplyBodyIsolated(String summary);

  /// No description provided for @networksApplyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get networksApplyConfirm;

  /// No description provided for @networksApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied.'**
  String get networksApplied;

  /// No description provided for @networksApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not apply: {error}'**
  String networksApplyFailed(String error);

  /// No description provided for @networksCurrent.
  ///
  /// In en, this message translates to:
  /// **'This radio is on this network'**
  String get networksCurrent;

  /// No description provided for @networksDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete network'**
  String get networksDelete;

  /// No description provided for @networksDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String networksDeleteTitle(String name);

  /// No description provided for @networksDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Only the saved settings are removed. Radios keep what they are set to.'**
  String get networksDeleteBody;

  /// No description provided for @networksDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get networksDeleteConfirm;

  /// No description provided for @placeCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop a place'**
  String get placeCreateTitle;

  /// No description provided for @placeCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get placeCreateAction;

  /// No description provided for @placeLabelField.
  ///
  /// In en, this message translates to:
  /// **'What is here?'**
  String get placeLabelField;

  /// No description provided for @placeLabelHint.
  ///
  /// In en, this message translates to:
  /// **'A few words, 60 characters at most'**
  String get placeLabelHint;

  /// No description provided for @placeTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get placeTypeTitle;

  /// No description provided for @placeTtlTitle.
  ///
  /// In en, this message translates to:
  /// **'How long does it last?'**
  String get placeTtlTitle;

  /// No description provided for @placePrecisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Precision'**
  String get placePrecisionTitle;

  /// No description provided for @placePrecisionExact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get placePrecisionExact;

  /// No description provided for @placePrecision100.
  ///
  /// In en, this message translates to:
  /// **'About 100 m'**
  String get placePrecision100;

  /// No description provided for @placePrecision1000.
  ///
  /// In en, this message translates to:
  /// **'About 1 km'**
  String get placePrecision1000;

  /// No description provided for @placeSent.
  ///
  /// In en, this message translates to:
  /// **'Place reported. It expires on its own.'**
  String get placeSent;

  /// No description provided for @placeBudgetRefused.
  ///
  /// In en, this message translates to:
  /// **'You have sent {n} in the last hour. The next one can go at {time}.'**
  String placeBudgetRefused(int n, String time);

  /// No description provided for @placeNoIdentity.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio first: a place is reported as you.'**
  String get placeNoIdentity;

  /// No description provided for @placeLabelEmpty.
  ///
  /// In en, this message translates to:
  /// **'A place needs a few words.'**
  String get placeLabelEmpty;

  /// No description provided for @placeLabelTooLong.
  ///
  /// In en, this message translates to:
  /// **'A label is at most 60 characters.'**
  String get placeLabelTooLong;

  /// No description provided for @placeLabelCarriesTtl.
  ///
  /// In en, this message translates to:
  /// **'A label cannot contain a TTL token.'**
  String get placeLabelCarriesTtl;

  /// No description provided for @placeExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {value}'**
  String placeExpiresIn(String value);

  /// No description provided for @placeExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get placeExpired;

  /// No description provided for @placeReportedBy.
  ///
  /// In en, this message translates to:
  /// **'Reported by {name}, {time}'**
  String placeReportedBy(String name, String time);

  /// No description provided for @placeTimeUnknown.
  ///
  /// In en, this message translates to:
  /// **'time unknown'**
  String get placeTimeUnknown;

  /// No description provided for @placeSourceGps.
  ///
  /// In en, this message translates to:
  /// **'from the sender\'s GPS'**
  String get placeSourceGps;

  /// No description provided for @placeSourcePhone.
  ///
  /// In en, this message translates to:
  /// **'from their phone'**
  String get placeSourcePhone;

  /// No description provided for @placeSourcePinned.
  ///
  /// In en, this message translates to:
  /// **'placed by hand'**
  String get placeSourcePinned;

  /// No description provided for @placeSourceReceived.
  ///
  /// In en, this message translates to:
  /// **'received over the mesh'**
  String get placeSourceReceived;

  /// No description provided for @placeSourceInferred.
  ///
  /// In en, this message translates to:
  /// **'inferred'**
  String get placeSourceInferred;

  /// No description provided for @placeUnkeyedIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity is a name on a channel, not a key.'**
  String get placeUnkeyedIdentity;

  /// No description provided for @placeUnknownType.
  ///
  /// In en, this message translates to:
  /// **'Sent as {token}'**
  String placeUnknownType(String token);

  /// No description provided for @placeConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Still there'**
  String get placeConfirmAction;

  /// No description provided for @placeRefuteAction.
  ///
  /// In en, this message translates to:
  /// **'Gone'**
  String get placeRefuteAction;

  /// No description provided for @placeConfirmations.
  ///
  /// In en, this message translates to:
  /// **'{n} confirmed'**
  String placeConfirmations(int n);

  /// No description provided for @placeConfirmationsMore.
  ///
  /// In en, this message translates to:
  /// **'+{n} more'**
  String placeConfirmationsMore(int n);

  /// No description provided for @placeClaimedConfirmations.
  ///
  /// In en, this message translates to:
  /// **'{n} claimed'**
  String placeClaimedConfirmations(int n);

  /// No description provided for @placeHiddenByRefutation.
  ///
  /// In en, this message translates to:
  /// **'Hidden here after a refutation from a known key'**
  String get placeHiddenByRefutation;

  /// No description provided for @placeDirections.
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get placeDirections;

  /// No description provided for @placeDirectionsCopied.
  ///
  /// In en, this message translates to:
  /// **'Coordinates copied'**
  String get placeDirectionsCopied;

  /// No description provided for @placeHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get placeHistoryTitle;

  /// No description provided for @placeHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No places yet. Long-press the map to report one.'**
  String get placeHistoryEmpty;

  /// No description provided for @placeStateLive.
  ///
  /// In en, this message translates to:
  /// **'live'**
  String get placeStateLive;

  /// No description provided for @placeStateExpired.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get placeStateExpired;

  /// No description provided for @placeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search label or reporter'**
  String get placeSearchHint;

  /// No description provided for @placeWithinAny.
  ///
  /// In en, this message translates to:
  /// **'Any time left'**
  String get placeWithinAny;

  /// No description provided for @placeWithinHour.
  ///
  /// In en, this message translates to:
  /// **'Expires within 1 h'**
  String get placeWithinHour;

  /// No description provided for @placeWithinDay.
  ///
  /// In en, this message translates to:
  /// **'Expires within 24 h'**
  String get placeWithinDay;

  /// No description provided for @placeKeyedOnly.
  ///
  /// In en, this message translates to:
  /// **'Keyed places only'**
  String get placeKeyedOnly;

  /// No description provided for @placeExportLedger.
  ///
  /// In en, this message translates to:
  /// **'Export places'**
  String get placeExportLedger;

  /// Snackbar after the ledger was handed to the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Places ready to share.'**
  String get placeExportShared;

  /// No description provided for @placeExportDone.
  ///
  /// In en, this message translates to:
  /// **'Places saved to {path}'**
  String placeExportDone(String path);

  /// No description provided for @placeExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the list.'**
  String get placeExportFailed;

  /// No description provided for @placeCoordinatesRefused.
  ///
  /// In en, this message translates to:
  /// **'Those coordinates cannot be sent.'**
  String get placeCoordinatesRefused;

  /// No description provided for @placeEchoLine.
  ///
  /// In en, this message translates to:
  /// **'{label} · {type} · {expiry}'**
  String placeEchoLine(String label, String type, String expiry);

  /// No description provided for @placeTypeHazard.
  ///
  /// In en, this message translates to:
  /// **'Hazard'**
  String get placeTypeHazard;

  /// No description provided for @placeTypeWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get placeTypeWater;

  /// No description provided for @placeTypeFuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get placeTypeFuel;

  /// No description provided for @placeTypeMed.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get placeTypeMed;

  /// No description provided for @placeTypeRally.
  ///
  /// In en, this message translates to:
  /// **'Rally'**
  String get placeTypeRally;

  /// No description provided for @placeTypeView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get placeTypeView;

  /// No description provided for @placeTypeCamp.
  ///
  /// In en, this message translates to:
  /// **'Camp'**
  String get placeTypeCamp;

  /// No description provided for @placeTypeLook.
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get placeTypeLook;

  /// No description provided for @placeTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get placeTypeOther;

  /// No description provided for @failureUnsupportedCommand.
  ///
  /// In en, this message translates to:
  /// **'The radio does not support that command. Its firmware is older than this app expects; update the radio or use a command it lists.'**
  String get failureUnsupportedCommand;

  /// No description provided for @failureNotFound.
  ///
  /// In en, this message translates to:
  /// **'The radio could not find the target of that request: the channel, contact or message is not on it. Refresh the contact list, then retry.'**
  String get failureNotFound;

  /// No description provided for @failureTableFull.
  ///
  /// In en, this message translates to:
  /// **'The radio\'s queue or table is full, so it refused the request. Wait for it to drain, then retry; nothing was lost.'**
  String get failureTableFull;

  /// No description provided for @failureBadState.
  ///
  /// In en, this message translates to:
  /// **'The radio is busy with another operation and cannot start this one. Wait for the current operation to finish, then retry.'**
  String get failureBadState;

  /// No description provided for @failureFileIoError.
  ///
  /// In en, this message translates to:
  /// **'The radio\'s storage refused the write. Its own log has the detail; retry once, and if it repeats the radio\'s filesystem needs attention.'**
  String get failureFileIoError;

  /// No description provided for @failureIllegalArgument.
  ///
  /// In en, this message translates to:
  /// **'The radio rejected the value or length as invalid. Check the field you changed: one value is outside what this firmware accepts.'**
  String get failureIllegalArgument;

  /// No description provided for @failureUnknownDeviceError.
  ///
  /// In en, this message translates to:
  /// **'The radio refused the request without a reason this app knows. The diagnostics page shows the raw frame.'**
  String get failureUnknownDeviceError;

  /// No description provided for @failureBlePermissions.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission was refused, so the app cannot reach the radio. Allow Nearby devices for this app in Android settings, then reconnect.'**
  String get failureBlePermissions;

  /// No description provided for @failureBluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off. Turn it on, then reconnect.'**
  String get failureBluetoothOff;

  /// No description provided for @failureNoRadioFound.
  ///
  /// In en, this message translates to:
  /// **'No radio answered the scan. Check that the radio is powered on, in range, and not already connected to another phone.'**
  String get failureNoRadioFound;

  /// No description provided for @failurePairingFailed.
  ///
  /// In en, this message translates to:
  /// **'The pairing did not complete. Enter the PIN shown on the radio screen (screenless radios use 123456), then retry.'**
  String get failurePairingFailed;

  /// No description provided for @failureStalePairing.
  ///
  /// In en, this message translates to:
  /// **'The radio no longer holds this pairing. Forget it in Android Bluetooth settings, power-cycle the radio, then pair again.'**
  String get failureStalePairing;

  /// No description provided for @failurePairingNotKept.
  ///
  /// In en, this message translates to:
  /// **'The radio paired but then could not encrypt on the next connection, so the pairing is not being kept. Power-cycle it and pair again; if it repeats, the fault is in the radio.'**
  String get failurePairingNotKept;

  /// No description provided for @failureServiceMissing.
  ///
  /// In en, this message translates to:
  /// **'This device does not expose the MeshCore service, so it is probably not a MeshCore radio.'**
  String get failureServiceMissing;

  /// No description provided for @failureCharacteristicMissing.
  ///
  /// In en, this message translates to:
  /// **'The radio\'s link is missing a characteristic the app needs. Its firmware may be older than this app expects.'**
  String get failureCharacteristicMissing;

  /// No description provided for @failureMtuTooSmall.
  ///
  /// In en, this message translates to:
  /// **'This phone link is {mtu} bytes and one radio frame needs {need}. Reconnect to try again; a radio that caps the link smaller cannot carry every frame.'**
  String failureMtuTooSmall(String mtu, String need);

  /// No description provided for @failureFrameTruncated.
  ///
  /// In en, this message translates to:
  /// **'Part of a message did not arrive. The count is in Diagnostics.'**
  String get failureFrameTruncated;

  /// No description provided for @failureFrameTrailingBytes.
  ///
  /// In en, this message translates to:
  /// **'A message carried extra bytes at the end. They were dropped; the count is in Diagnostics.'**
  String get failureFrameTrailingBytes;

  /// No description provided for @failureStorageFull.
  ///
  /// In en, this message translates to:
  /// **'The phone refused a write because storage is full. Nothing is being deleted silently; free space and the history stays as it is.'**
  String get failureStorageFull;

  /// No description provided for @failureRadioSilent.
  ///
  /// In en, this message translates to:
  /// **'The radio accepted the request but did not answer in time. It may still have carried it out; check the radio before retrying.'**
  String get failureRadioSilent;

  /// No description provided for @clockUnknown.
  ///
  /// In en, this message translates to:
  /// **'time unknown'**
  String get clockUnknown;

  /// No description provided for @clockJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get clockJustNow;

  /// No description provided for @clockMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String clockMinutesAgo(String count);

  /// No description provided for @clockHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String clockHoursAgo(String count);

  /// No description provided for @clockDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String clockDaysAgo(String count);

  /// No description provided for @clockAhead.
  ///
  /// In en, this message translates to:
  /// **'sender\'s clock is {count} min ahead'**
  String clockAhead(String count);

  /// No description provided for @degradedStorageFull.
  ///
  /// In en, this message translates to:
  /// **'This phone refused a write because storage is full. Nothing was deleted to make room; free space and history continues.'**
  String get degradedStorageFull;

  /// No description provided for @degradedClockUnset.
  ///
  /// In en, this message translates to:
  /// **'The radio\'s clock has never been set, so times it reports are shown as time unknown until it is.'**
  String get degradedClockUnset;

  /// No description provided for @degradedBatteryCritical.
  ///
  /// In en, this message translates to:
  /// **'The radio\'s battery is low enough that its transmissions may be cut. Charge it before relying on a long send.'**
  String get degradedBatteryCritical;

  /// No description provided for @degradedRadioAbsent.
  ///
  /// In en, this message translates to:
  /// **'No radio is connected. Everything already received stays readable; sending, telemetry and places wait until a radio connects.'**
  String get degradedRadioAbsent;

  /// No description provided for @degradedRadioSilent.
  ///
  /// In en, this message translates to:
  /// **'The radio is paired but has not answered. It may still have carried out the last request; check the radio before retrying.'**
  String get degradedRadioSilent;

  /// No description provided for @degradedNoLocation.
  ///
  /// In en, this message translates to:
  /// **'Location is off, so distances, bearings and place reports have no fix. Everything else works.'**
  String get degradedNoLocation;

  /// No description provided for @degradedMapOffline.
  ///
  /// In en, this message translates to:
  /// **'Map tiles cannot be fetched. The bundled basemap and anything already on disk still draw; the rest of the app is unaffected.'**
  String get degradedMapOffline;

  /// No description provided for @sosTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get sosTitle;

  /// No description provided for @sosEntryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Emergency alarm and check-in'**
  String get sosEntryTooltip;

  /// No description provided for @sosGoesToChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel {name}'**
  String sosGoesToChannel(String name);

  /// No description provided for @sosGoesToContacts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No direct copies} =1{1 contact copy} other{{count} contact copies}}'**
  String sosGoesToContacts(int count);

  /// No description provided for @sosInRange.
  ///
  /// In en, this message translates to:
  /// **'Nobody is notified unless they are in radio range.'**
  String get sosInRange;

  /// No description provided for @sosHoldToArm.
  ///
  /// In en, this message translates to:
  /// **'Hold to raise the alarm'**
  String get sosHoldToArm;

  /// No description provided for @sosHoldRemaining.
  ///
  /// In en, this message translates to:
  /// **'Keep holding · {seconds}s'**
  String sosHoldRemaining(int seconds);

  /// No description provided for @sosHoldReleased.
  ///
  /// In en, this message translates to:
  /// **'Released too early — nothing was sent.'**
  String get sosHoldReleased;

  /// No description provided for @sosNoIdentity.
  ///
  /// In en, this message translates to:
  /// **'The radio has not reported a name yet, so the alarm has no name to send.'**
  String get sosNoIdentity;

  /// No description provided for @sosWords.
  ///
  /// In en, this message translates to:
  /// **'What is happening'**
  String get sosWords;

  /// No description provided for @sosWordsHint.
  ///
  /// In en, this message translates to:
  /// **'Carried by every repeat, up to 96 bytes'**
  String get sosWordsHint;

  /// No description provided for @sosDestination.
  ///
  /// In en, this message translates to:
  /// **'Goes to'**
  String get sosDestination;

  /// No description provided for @sosEmergencyPublicKey.
  ///
  /// In en, this message translates to:
  /// **'The #emergency channel\'s key is derived from its name, so anyone who knows the name can compute it and read this.'**
  String get sosEmergencyPublicKey;

  /// No description provided for @sosEmergencyRepeat.
  ///
  /// In en, this message translates to:
  /// **'The radio repeats each message once, about two minutes later. If the app closes, the rest stops.'**
  String get sosEmergencyRepeat;

  /// No description provided for @sosContactsNone.
  ///
  /// In en, this message translates to:
  /// **'With no contact copies, a channel acknowledgement can never stop this alarm.'**
  String get sosContactsNone;

  /// No description provided for @sosActive.
  ///
  /// In en, this message translates to:
  /// **'Alarm running'**
  String get sosActive;

  /// No description provided for @sosNextSend.
  ///
  /// In en, this message translates to:
  /// **'Next in {seconds}s'**
  String sosNextSend(int seconds);

  /// No description provided for @sosElapsed.
  ///
  /// In en, this message translates to:
  /// **'Running {minutes} min'**
  String sosElapsed(int minutes);

  /// No description provided for @sosRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} left'**
  String sosRemaining(int count, int total);

  /// No description provided for @sosImSafe.
  ///
  /// In en, this message translates to:
  /// **'I\'m safe'**
  String get sosImSafe;

  /// No description provided for @sosImSafeHint.
  ///
  /// In en, this message translates to:
  /// **'Sends one [SAFE] and stops the repeats.'**
  String get sosImSafeHint;

  /// No description provided for @sosStopRepeats.
  ///
  /// In en, this message translates to:
  /// **'Stop the repeats'**
  String get sosStopRepeats;

  /// No description provided for @sosStopHint.
  ///
  /// In en, this message translates to:
  /// **'Stops the repeats on this phone. Nothing is sent, so nobody is told.'**
  String get sosStopHint;

  /// Active alarm: repeats that were due during a sleep window and were skipped rather than fired as a burst.
  ///
  /// In en, this message translates to:
  /// **'Not sent while the app was asleep: {count}'**
  String sosMissedSends(int count);

  /// Active alarm: at least one repeat did not leave the radio.
  ///
  /// In en, this message translates to:
  /// **'The radio refused a repeat. The schedule continues.'**
  String get sosSendFailed;

  /// No description provided for @sosDefaultWords.
  ///
  /// In en, this message translates to:
  /// **'I need help'**
  String get sosDefaultWords;

  /// No description provided for @sosClaimedBy.
  ///
  /// In en, this message translates to:
  /// **'{name} claims to have seen this, on the channel. The alarm keeps going.'**
  String sosClaimedBy(String name);

  /// No description provided for @sosSeenBy.
  ///
  /// In en, this message translates to:
  /// **'{name} has seen this, by direct message.'**
  String sosSeenBy(String name);

  /// No description provided for @sosExpired.
  ///
  /// In en, this message translates to:
  /// **'The alarm has stopped repeating. It is not resolved.'**
  String get sosExpired;

  /// No description provided for @sosCancelled.
  ///
  /// In en, this message translates to:
  /// **'The alarm is stopped.'**
  String get sosCancelled;

  /// No description provided for @sosAcknowledgedHeading.
  ///
  /// In en, this message translates to:
  /// **'Seen'**
  String get sosAcknowledgedHeading;

  /// No description provided for @sosDismiss.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sosDismiss;

  /// No description provided for @sosRefusedAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'An alarm is already running.'**
  String get sosRefusedAlreadyActive;

  /// No description provided for @sosRefusedNoDestination.
  ///
  /// In en, this message translates to:
  /// **'Choose where the alarm goes first.'**
  String get sosRefusedNoDestination;

  /// No description provided for @sosRefusedNoWords.
  ///
  /// In en, this message translates to:
  /// **'Say what is happening first.'**
  String get sosRefusedNoWords;

  /// No description provided for @sosRefusedTooLong.
  ///
  /// In en, this message translates to:
  /// **'Too long to carry a name and a position. Shorten it.'**
  String get sosRefusedTooLong;

  /// No description provided for @sosRefusedHold.
  ///
  /// In en, this message translates to:
  /// **'The hold is not finished.'**
  String get sosRefusedHold;

  /// No description provided for @checkinTitle.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get checkinTitle;

  /// No description provided for @checkinEntryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get checkinEntryTooltip;

  /// No description provided for @checkinIntro.
  ///
  /// In en, this message translates to:
  /// **'One message with a deadline. The app marks it overdue here; the radio keeps no timer.'**
  String get checkinIntro;

  /// No description provided for @checkinInMinutes.
  ///
  /// In en, this message translates to:
  /// **'Deadline in {minutes} min'**
  String checkinInMinutes(int minutes);

  /// No description provided for @checkinSend.
  ///
  /// In en, this message translates to:
  /// **'Send check-in'**
  String get checkinSend;

  /// No description provided for @checkinOneMessage.
  ///
  /// In en, this message translates to:
  /// **'A check-in is one message and does not repeat.'**
  String get checkinOneMessage;

  /// No description provided for @checkinUntil.
  ///
  /// In en, this message translates to:
  /// **'Deadline {time}'**
  String checkinUntil(String time);

  /// No description provided for @checkinWatching.
  ///
  /// In en, this message translates to:
  /// **'Waiting for an answer'**
  String get checkinWatching;

  /// No description provided for @checkinOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue — the deadline passed and no answer came back.'**
  String get checkinOverdue;

  /// No description provided for @checkinAnsweredDirect.
  ///
  /// In en, this message translates to:
  /// **'Answered, by direct message.'**
  String get checkinAnsweredDirect;

  /// No description provided for @checkinAnsweredChannel.
  ///
  /// In en, this message translates to:
  /// **'Answered on the channel by name only, not by their key.'**
  String get checkinAnsweredChannel;

  /// No description provided for @checkinSent.
  ///
  /// In en, this message translates to:
  /// **'Check-in sent. Nothing repeats.'**
  String get checkinSent;

  /// No description provided for @checkinNeedsRadio.
  ///
  /// In en, this message translates to:
  /// **'A check-in needs a connected radio and the radio\'s name.'**
  String get checkinNeedsRadio;

  /// No description provided for @mediaComposerTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a photo'**
  String get mediaComposerTitle;

  /// No description provided for @mediaSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This build cannot read a photo from the device, so nothing can be sent from here.'**
  String get mediaSourceUnavailable;

  /// No description provided for @mediaSourceFailed.
  ///
  /// In en, this message translates to:
  /// **'That photo could not be read. Try another one.'**
  String get mediaSourceFailed;

  /// No description provided for @mediaPickCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get mediaPickCamera;

  /// No description provided for @mediaPickGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get mediaPickGallery;

  /// No description provided for @mediaSourceUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'That file is not an image this build can read. HEIC and AV1 are not supported here, so choose a JPEG or PNG photo.'**
  String get mediaSourceUnsupportedFormat;

  /// No description provided for @mediaEncoding.
  ///
  /// In en, this message translates to:
  /// **'Fitting the photo to the mesh…'**
  String get mediaEncoding;

  /// No description provided for @mediaCostLine.
  ///
  /// In en, this message translates to:
  /// **'{chunks} packets · about {airtime} on air'**
  String mediaCostLine(int chunks, String airtime);

  /// No description provided for @mediaOverBudget.
  ///
  /// In en, this message translates to:
  /// **'This photo will not fit the mesh budget even at the lowest quality. It can still be sent, but it will be cut off.'**
  String get mediaOverBudget;

  /// No description provided for @mediaSendingProgress.
  ///
  /// In en, this message translates to:
  /// **'{sent} of {total} packets sent'**
  String mediaSendingProgress(int sent, int total);

  /// No description provided for @mediaReceiptLine.
  ///
  /// In en, this message translates to:
  /// **'{chunks} packets sent, {resends} of them resent'**
  String mediaReceiptLine(int chunks, int resends);

  /// No description provided for @mediaAcceptedNotDelivered.
  ///
  /// In en, this message translates to:
  /// **'The radio accepted these packets. A broadcast carries no delivery promise.'**
  String get mediaAcceptedNotDelivered;

  /// No description provided for @mediaSendFailed.
  ///
  /// In en, this message translates to:
  /// **'The radio refused {count} packet(s), so this photo did not finish.'**
  String mediaSendFailed(int count);

  /// No description provided for @mediaSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get mediaSend;

  /// No description provided for @mediaRetrySend.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get mediaRetrySend;

  /// No description provided for @mediaClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get mediaClose;

  /// No description provided for @mediaOffOnPublic.
  ///
  /// In en, this message translates to:
  /// **'Media is off on the Public channel. Turn it on for that channel in its settings first.'**
  String get mediaOffOnPublic;

  /// No description provided for @mediaPayloadUnusable.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to send.'**
  String get mediaPayloadUnusable;

  /// No description provided for @mediaChannelUnknown.
  ///
  /// In en, this message translates to:
  /// **'No channel is selected, so there is nobody to send to.'**
  String get mediaChannelUnknown;

  /// No description provided for @mediaReceiveWaiting.
  ///
  /// In en, this message translates to:
  /// **'{received} of {total} packets · waiting for {missing}'**
  String mediaReceiveWaiting(int received, int total, int missing);

  /// No description provided for @mediaReceiveAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask for the missing packets'**
  String get mediaReceiveAsk;

  /// No description provided for @mediaReceiveRequested.
  ///
  /// In en, this message translates to:
  /// **'Asked the sender for {count} packet(s).'**
  String mediaReceiveRequested(int count);

  /// No description provided for @mediaReceiveComplete.
  ///
  /// In en, this message translates to:
  /// **'Photo received.'**
  String get mediaReceiveComplete;

  /// No description provided for @mediaDecodeFailed.
  ///
  /// In en, this message translates to:
  /// **'This photo arrived but cannot be read.'**
  String get mediaDecodeFailed;

  /// No description provided for @mediaPhotoSemantics.
  ///
  /// In en, this message translates to:
  /// **'Photo received over the mesh'**
  String get mediaPhotoSemantics;

  /// No description provided for @placePhotoNotFetched.
  ///
  /// In en, this message translates to:
  /// **'Photo not fetched. The report itself is complete; the picture is optional and may never arrive.'**
  String get placePhotoNotFetched;

  /// No description provided for @placePhotoMayNotArrive.
  ///
  /// In en, this message translates to:
  /// **'The photo may not arrive. The text will.'**
  String get placePhotoMayNotArrive;

  /// No description provided for @placePhotoFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch photo'**
  String get placePhotoFetch;

  /// No description provided for @placePhotoFetching.
  ///
  /// In en, this message translates to:
  /// **'Asking the mesh for the photo…'**
  String get placePhotoFetching;

  /// No description provided for @geofenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Geofences'**
  String get geofenceTitle;

  /// No description provided for @geofenceExplainer.
  ///
  /// In en, this message translates to:
  /// **'A fence is a circle you watch. It tells you once when you enter it and once when you leave, so walking along its edge does not produce a stream of alerts.'**
  String get geofenceExplainer;

  /// No description provided for @geofenceAddSection.
  ///
  /// In en, this message translates to:
  /// **'Add a fence'**
  String get geofenceAddSection;

  /// No description provided for @geofenceRadius.
  ///
  /// In en, this message translates to:
  /// **'{meters} m'**
  String geofenceRadius(int meters);

  /// No description provided for @geofenceNeedsFix.
  ///
  /// In en, this message translates to:
  /// **'A fence needs your position. Connect the radio or allow location first.'**
  String get geofenceNeedsFix;

  /// No description provided for @geofenceAddHere.
  ///
  /// In en, this message translates to:
  /// **'Add a fence here'**
  String get geofenceAddHere;

  /// No description provided for @geofenceListSection.
  ///
  /// In en, this message translates to:
  /// **'Your fences'**
  String get geofenceListSection;

  /// No description provided for @geofenceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No fences yet.'**
  String get geofenceEmpty;

  /// No description provided for @geofenceInsideNow.
  ///
  /// In en, this message translates to:
  /// **'You are inside'**
  String get geofenceInsideNow;

  /// No description provided for @geofenceOutsideNow.
  ///
  /// In en, this message translates to:
  /// **'You are outside'**
  String get geofenceOutsideNow;

  /// No description provided for @geofenceDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete fence'**
  String get geofenceDelete;

  /// No description provided for @geofenceEventsSection.
  ///
  /// In en, this message translates to:
  /// **'Recent crossings'**
  String get geofenceEventsSection;

  /// No description provided for @geofenceEntered.
  ///
  /// In en, this message translates to:
  /// **'Entered {label}'**
  String geofenceEntered(String label);

  /// No description provided for @geofenceLeft.
  ///
  /// In en, this message translates to:
  /// **'Left {label}'**
  String geofenceLeft(String label);

  /// No description provided for @geofenceDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Fence {number}'**
  String geofenceDefaultName(int number);

  /// No description provided for @nodeClosing.
  ///
  /// In en, this message translates to:
  /// **'{name} is {distance} away and closing'**
  String nodeClosing(String name, String distance);

  /// No description provided for @nodeOpening.
  ///
  /// In en, this message translates to:
  /// **'{name} is {distance} away and moving away'**
  String nodeOpening(String name, String distance);

  /// No description provided for @geofenceExplainerShort.
  ///
  /// In en, this message translates to:
  /// **'Circles that tell you when you arrive or leave'**
  String get geofenceExplainerShort;

  /// No description provided for @coverageTitle.
  ///
  /// In en, this message translates to:
  /// **'Coverage'**
  String get coverageTitle;

  /// No description provided for @coverageCountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Coverage'**
  String get coverageCountsTitle;

  /// No description provided for @fieldExportSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'Trail and field record'**
  String get fieldExportSummaryLine;

  /// No description provided for @diagnosticsRadioHealth.
  ///
  /// In en, this message translates to:
  /// **'Radio health'**
  String get diagnosticsRadioHealth;

  /// No description provided for @radioHealthSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'Battery, noise floor, last packet'**
  String get radioHealthSummaryLine;

  /// No description provided for @coverageBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'This records where you are and who answered. It stays on this device, and closing the app ends the record.'**
  String get coverageBeforeStart;

  /// No description provided for @coverageStart.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get coverageStart;

  /// No description provided for @coverageStop.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get coverageStop;

  /// No description provided for @coverageCounts.
  ///
  /// In en, this message translates to:
  /// **'{answered} of {tried} pings answered'**
  String coverageCounts(int answered, int tried);

  /// No description provided for @coverageUnmatched.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One reply could not be identified.} other{{count} replies could not be identified.}}'**
  String coverageUnmatched(int count);

  /// No description provided for @coverageRefusedTooSoon.
  ///
  /// In en, this message translates to:
  /// **'The app paces itself: one ping every thirty seconds, so this one waits.'**
  String get coverageRefusedTooSoon;

  /// No description provided for @coverageRefusedCellFresh.
  ///
  /// In en, this message translates to:
  /// **'This area was pinged within the hour. Standing still costs one ping an hour.'**
  String get coverageRefusedCellFresh;

  /// No description provided for @coverageRefusedManualUsed.
  ///
  /// In en, this message translates to:
  /// **'This hour\'s manual ping is already spent.'**
  String get coverageRefusedManualUsed;

  /// No description provided for @coveragePacingNote.
  ///
  /// In en, this message translates to:
  /// **'This app paces its own pings; it cannot promise other devices do.'**
  String get coveragePacingNote;

  /// No description provided for @coveragePingNow.
  ///
  /// In en, this message translates to:
  /// **'Ping now (once an hour)'**
  String get coveragePingNow;

  /// No description provided for @coverageCellsSection.
  ///
  /// In en, this message translates to:
  /// **'Where you pinged'**
  String get coverageCellsSection;

  /// No description provided for @coverageNoSamples.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet.'**
  String get coverageNoSamples;

  /// No description provided for @coverageCellLine.
  ///
  /// In en, this message translates to:
  /// **'{cell} · {percent}% · {samples} samples'**
  String coverageCellLine(String cell, int percent, int samples);

  /// No description provided for @coverageHidden.
  ///
  /// In en, this message translates to:
  /// **'{count} hidden'**
  String coverageHidden(int count);

  /// No description provided for @coverageEdges.
  ///
  /// In en, this message translates to:
  /// **'{count} answers drawn — answers only, never an inferred link'**
  String coverageEdges(int count);

  /// No description provided for @coverageNotAMap.
  ///
  /// In en, this message translates to:
  /// **'This is where your pings were answered, not where the mesh reaches.'**
  String get coverageNotAMap;

  /// No description provided for @coverageExplainerShort.
  ///
  /// In en, this message translates to:
  /// **'Which pings were answered, here'**
  String get coverageExplainerShort;

  /// No description provided for @fieldExportSection.
  ///
  /// In en, this message translates to:
  /// **'Field record'**
  String get fieldExportSection;

  /// No description provided for @fieldExportExplainer.
  ///
  /// In en, this message translates to:
  /// **'One file with the trail, the places, the answered pings and the check-in. It is plain JSON, not encrypted, so it can be handed on.'**
  String get fieldExportExplainer;

  /// No description provided for @fieldExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export this session'**
  String get fieldExportAction;

  /// Snackbar after the field record was handed to the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Field record ready to share.'**
  String get fieldExportShared;

  /// No description provided for @fieldExportDone.
  ///
  /// In en, this message translates to:
  /// **'Field record written. The path is on the clipboard: {path}'**
  String fieldExportDone(String path);

  /// No description provided for @gpxExportExplainer.
  ///
  /// In en, this message translates to:
  /// **'The trail as a GPX track any mapping app can read. It is plain text, not encrypted, unlike your messages.'**
  String get gpxExportExplainer;

  /// No description provided for @gpxExportAction.
  ///
  /// In en, this message translates to:
  /// **'Share trail as GPX'**
  String get gpxExportAction;

  /// No description provided for @gpxExportTrackName.
  ///
  /// In en, this message translates to:
  /// **'MeshMore trail'**
  String get gpxExportTrackName;

  /// No description provided for @gpxExportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No trail yet. Positions are recorded while the app runs, so there is nothing to write.'**
  String get gpxExportEmpty;

  /// Snackbar after the trail file was handed to the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Trail ready to share.'**
  String get gpxExportShared;

  /// No description provided for @gpxExportDone.
  ///
  /// In en, this message translates to:
  /// **'Trail written. The path is on the clipboard: {path}'**
  String gpxExportDone(String path);

  /// Icon tooltip in the chat channel strip: opens search over stored history.
  ///
  /// In en, this message translates to:
  /// **'Search messages'**
  String get chatSearchAction;

  /// Tooltip on the chat header action that exports one conversation.
  ///
  /// In en, this message translates to:
  /// **'Export this conversation'**
  String get chatExportAction;

  /// Dialog title when exporting a conversation.
  ///
  /// In en, this message translates to:
  /// **'Passphrase for the exported file'**
  String get chatExportTitle;

  /// Label for the passphrase field on a conversation export.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get chatExportPassphrase;

  /// Confirm the conversation export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get chatExportConfirm;

  /// The exported file was handed to the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Conversation ready to share.'**
  String get chatExportShared;

  /// Fallback when there is nothing to share with.
  ///
  /// In en, this message translates to:
  /// **'Conversation saved to {path}'**
  String chatExportDone(String path);

  /// An export refused, for example an empty passphrase.
  ///
  /// In en, this message translates to:
  /// **'The conversation could not be written. Nothing was exported.'**
  String get chatExportFailed;

  /// No description provided for @chatSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search stored history'**
  String get chatSearchHint;

  /// No description provided for @chatSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type to search the messages this device stored.'**
  String get chatSearchPrompt;

  /// No description provided for @chatSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No message matches “{query}”.'**
  String chatSearchNoResults(String query);

  /// No description provided for @chatSearchHidden.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match hidden by a block} other{{count} matches hidden by a block}}'**
  String chatSearchHidden(int count);

  /// No description provided for @chatSearchTruncated.
  ///
  /// In en, this message translates to:
  /// **'Showing the newest {count} matches. Narrow the search to see the rest.'**
  String chatSearchTruncated(int count);

  /// No description provided for @chatSearchRetention.
  ///
  /// In en, this message translates to:
  /// **'This device keeps the newest {cap} messages, so older ones are not searched.'**
  String chatSearchRetention(int cap);

  /// No description provided for @chatSearchDm.
  ///
  /// In en, this message translates to:
  /// **'Direct message'**
  String get chatSearchDm;

  /// Screen-reader label on a channel's unread badge; the badge itself is a count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread} other{{count} unread}}'**
  String chatUnread(int count);

  /// No description provided for @blockedKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked keys'**
  String get blockedKeysTitle;

  /// No description provided for @blockedKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No key is blocked} =1{1 key blocked} other{{count} keys blocked}}'**
  String blockedKeysSubtitle(int count);

  /// No description provided for @blockedKeysEmpty.
  ///
  /// In en, this message translates to:
  /// **'No key is blocked. Blocking a key hides what it sends — messages, notifications, places — on this device.'**
  String get blockedKeysEmpty;

  /// No description provided for @blockedKeysCannotStop.
  ///
  /// In en, this message translates to:
  /// **'A block is local to this app. The radio still receives and relays the packet; what stops is what this app shows.'**
  String get blockedKeysCannotStop;

  /// No description provided for @blockedKeysUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get blockedKeysUnblock;

  /// No description provided for @blockedKeysSince.
  ///
  /// In en, this message translates to:
  /// **'Blocked {when}'**
  String blockedKeysSince(String when);

  /// No description provided for @blockedKeysUnknownName.
  ///
  /// In en, this message translates to:
  /// **'No name known'**
  String get blockedKeysUnknownName;

  /// No description provided for @blockedKeysCapacity.
  ///
  /// In en, this message translates to:
  /// **'The list is full: {cap} keys. Unblock one before adding another.'**
  String blockedKeysCapacity(int cap);

  /// No description provided for @blockedKeysUnblocked.
  ///
  /// In en, this message translates to:
  /// **'{name} is unblocked. Their messages appear again.'**
  String blockedKeysUnblocked(String name);

  /// No description provided for @blockedKeysUnblockedUnnamed.
  ///
  /// In en, this message translates to:
  /// **'The key is unblocked. Its messages appear again.'**
  String get blockedKeysUnblockedUnnamed;

  /// No description provided for @reportAction.
  ///
  /// In en, this message translates to:
  /// **'Report…'**
  String get reportAction;

  /// No description provided for @reportSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Report this message'**
  String get reportSheetTitle;

  /// No description provided for @reportObservationLabel.
  ///
  /// In en, this message translates to:
  /// **'What did you see? (optional)'**
  String get reportObservationLabel;

  /// No description provided for @reportNothingSent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent. The app wrote a file on this device; you decide where it goes.'**
  String get reportNothingSent;

  /// No description provided for @reportBundleWritten.
  ///
  /// In en, this message translates to:
  /// **'Report saved to {path}'**
  String reportBundleWritten(String path);

  /// No description provided for @reportCopyBundle.
  ///
  /// In en, this message translates to:
  /// **'Copy the report'**
  String get reportCopyBundle;

  /// No description provided for @reportCopied.
  ///
  /// In en, this message translates to:
  /// **'Report copied.'**
  String get reportCopied;

  /// No description provided for @blockedKeysNotPersisted.
  ///
  /// In en, this message translates to:
  /// **'This list could not be saved on this device. It filters for now and will be empty after a restart.'**
  String get blockedKeysNotPersisted;

  /// No description provided for @reportActionSub.
  ///
  /// In en, this message translates to:
  /// **'Writes a file on this device for you to send. Nothing is transmitted.'**
  String get reportActionSub;

  /// No description provided for @sosDestinationContactsLimit.
  ///
  /// In en, this message translates to:
  /// **'Up to {count} contacts'**
  String sosDestinationContactsLimit(int count);

  /// No description provided for @sosDestinationChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get sosDestinationChange;

  /// No description provided for @sosDestinationPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Where the alarm goes'**
  String get sosDestinationPickerTitle;

  /// No description provided for @sosDestinationChannelHeader.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get sosDestinationChannelHeader;

  /// No description provided for @sosDestinationContactsHeader.
  ///
  /// In en, this message translates to:
  /// **'Direct copies'**
  String get sosDestinationContactsHeader;

  /// No description provided for @sosDestinationContactsHelp.
  ///
  /// In en, this message translates to:
  /// **'A direct copy from one of these keys can stop the alarm. A channel reply cannot.'**
  String get sosDestinationContactsHelp;

  /// No description provided for @sosDestinationMissing.
  ///
  /// In en, this message translates to:
  /// **'The channel this alarm was set to is gone. Choose another.'**
  String get sosDestinationMissing;

  /// No description provided for @sosDestinationNoContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get sosDestinationNoContacts;

  /// No description provided for @sosDestinationNotAContact.
  ///
  /// In en, this message translates to:
  /// **'not in contacts'**
  String get sosDestinationNotAContact;

  /// No description provided for @sosDestinationDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sosDestinationDone;

  /// No description provided for @sosEmergencyShort.
  ///
  /// In en, this message translates to:
  /// **'Public channel, one repeat if the app closes'**
  String get sosEmergencyShort;

  /// No description provided for @sosAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About this destination'**
  String get sosAboutTitle;

  /// No description provided for @sosRepeatsShort.
  ///
  /// In en, this message translates to:
  /// **'repeats up to 1 h'**
  String get sosRepeatsShort;

  /// No description provided for @placeTtlMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String placeTtlMinutes(int count);

  /// No description provided for @placeTtlHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String placeTtlHours(int count);

  /// No description provided for @placeTtlDays.
  ///
  /// In en, this message translates to:
  /// **'{count} d'**
  String placeTtlDays(int count);

  /// No description provided for @mapReportPlace.
  ///
  /// In en, this message translates to:
  /// **'Report a place'**
  String get mapReportPlace;

  /// No description provided for @settingsAppGroupRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get settingsAppGroupRadio;

  /// No description provided for @settingsAppGroupSound.
  ///
  /// In en, this message translates to:
  /// **'Reading and sound'**
  String get settingsAppGroupSound;

  /// No description provided for @settingsAppGroupData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsAppGroupData;

  /// No description provided for @settingsAppGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsAppGroupSystem;

  /// No description provided for @aboutReplayIntro.
  ///
  /// In en, this message translates to:
  /// **'Replay the first-run screens'**
  String get aboutReplayIntro;

  /// No description provided for @toolsGroupDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Radio diagnostics'**
  String get toolsGroupDiagnostics;

  /// No description provided for @nodeMarkerSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name} — tap for details'**
  String nodeMarkerSemantics(String name);

  /// No description provided for @placePinSemantics.
  ///
  /// In en, this message translates to:
  /// **'{label}, {expiry}'**
  String placePinSemantics(String label, String expiry);

  /// No description provided for @placeClusterSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count} places here'**
  String placeClusterSemantics(int count);

  /// No description provided for @mapCanvasSemantics.
  ///
  /// In en, this message translates to:
  /// **'Tap a marker on the map to open it'**
  String get mapCanvasSemantics;

  /// No description provided for @gridLegendSignalOnly.
  ///
  /// In en, this message translates to:
  /// **'Hollow · no position'**
  String get gridLegendSignalOnly;

  /// No description provided for @gridOpenMap.
  ///
  /// In en, this message translates to:
  /// **'Open the map'**
  String get gridOpenMap;

  /// No description provided for @gridMoreViews.
  ///
  /// In en, this message translates to:
  /// **'More views'**
  String get gridMoreViews;

  /// No description provided for @gridLegendMore.
  ///
  /// In en, this message translates to:
  /// **'Full legend'**
  String get gridLegendMore;

  /// No description provided for @gridLegendRingsShort.
  ///
  /// In en, this message translates to:
  /// **'Rings · distance'**
  String get gridLegendRingsShort;

  /// No description provided for @gridLegendSelfShort.
  ///
  /// In en, this message translates to:
  /// **'Centre · you'**
  String get gridLegendSelfShort;

  /// No description provided for @gridLegendDotShort.
  ///
  /// In en, this message translates to:
  /// **'Dot · heard here'**
  String get gridLegendDotShort;

  /// No description provided for @gridLegendKnownShort.
  ///
  /// In en, this message translates to:
  /// **'Pulse · known'**
  String get gridLegendKnownShort;

  /// No description provided for @gridLegendFavShort.
  ///
  /// In en, this message translates to:
  /// **'Blink · favourite'**
  String get gridLegendFavShort;

  /// No description provided for @gridLegendRippleShort.
  ///
  /// In en, this message translates to:
  /// **'Ripple · channel message'**
  String get gridLegendRippleShort;

  /// No description provided for @gridLegendTapShort.
  ///
  /// In en, this message translates to:
  /// **'Tap · details'**
  String get gridLegendTapShort;

  /// No description provided for @treeSelfShort.
  ///
  /// In en, this message translates to:
  /// **'Centre · you'**
  String get treeSelfShort;

  /// No description provided for @treeRepeaterShort.
  ///
  /// In en, this message translates to:
  /// **'Square · repeater'**
  String get treeRepeaterShort;

  /// No description provided for @treeRoomShort.
  ///
  /// In en, this message translates to:
  /// **'Diamond · room'**
  String get treeRoomShort;

  /// No description provided for @treeChatShort.
  ///
  /// In en, this message translates to:
  /// **'Circle · chat'**
  String get treeChatShort;

  /// No description provided for @treeSensorShort.
  ///
  /// In en, this message translates to:
  /// **'Wave · sensor'**
  String get treeSensorShort;

  /// No description provided for @treeFloodShort.
  ///
  /// In en, this message translates to:
  /// **'Dots · flood hop'**
  String get treeFloodShort;

  /// No description provided for @treeArrowShort.
  ///
  /// In en, this message translates to:
  /// **'Arrow · route out'**
  String get treeArrowShort;

  /// No description provided for @fabricCellShort.
  ///
  /// In en, this message translates to:
  /// **'Cell · mesh heard here'**
  String get fabricCellShort;

  /// No description provided for @fabricRecencyShort.
  ///
  /// In en, this message translates to:
  /// **'Brighter · more recent'**
  String get fabricRecencyShort;

  /// No description provided for @fabricMarkerShort.
  ///
  /// In en, this message translates to:
  /// **'Pin · peer now'**
  String get fabricMarkerShort;

  /// No description provided for @snsHotShort.
  ///
  /// In en, this message translates to:
  /// **'Red · busy now'**
  String get snsHotShort;

  /// No description provided for @snsCoolShort.
  ///
  /// In en, this message translates to:
  /// **'Fading · cooling'**
  String get snsCoolShort;

  /// No description provided for @snsToastShort.
  ///
  /// In en, this message translates to:
  /// **'Flash · new message'**
  String get snsToastShort;

  /// No description provided for @snsDecayShort.
  ///
  /// In en, this message translates to:
  /// **'Last hour only'**
  String get snsDecayShort;

  /// No description provided for @fujiMeShort.
  ///
  /// In en, this message translates to:
  /// **'Dashed · you'**
  String get fujiMeShort;

  /// No description provided for @fujiRefsShort.
  ///
  /// In en, this message translates to:
  /// **'Silhouettes · scale'**
  String get fujiRefsShort;

  /// No description provided for @fujiPeersShort.
  ///
  /// In en, this message translates to:
  /// **'Dots · peers'**
  String get fujiPeersShort;

  /// No description provided for @fujiUnknownShort.
  ///
  /// In en, this message translates to:
  /// **'Striped · no altitude'**
  String get fujiUnknownShort;

  /// No description provided for @chatSpeechOffAction.
  ///
  /// In en, this message translates to:
  /// **'Speech is off in App settings'**
  String get chatSpeechOffAction;

  /// No description provided for @nodeDetailAltitudeNotReported.
  ///
  /// In en, this message translates to:
  /// **'not reported'**
  String get nodeDetailAltitudeNotReported;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
