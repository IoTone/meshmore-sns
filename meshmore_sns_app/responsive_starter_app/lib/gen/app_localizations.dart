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
  /// **'Mesh messaging over LoRa radio'**
  String get appSubtitle;

  /// No description provided for @tabDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get tabDashboard;

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

  /// No description provided for @dashboardPeersInRangeStale.
  ///
  /// In en, this message translates to:
  /// **'NODES NEAR YOU'**
  String get dashboardPeersInRangeStale;

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
  /// **'Auto-replies here. Off by default.'**
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
  /// **'Waiting for the MeshCore radio to send this channel\'s key.'**
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
  /// **'LoRa radio'**
  String get dashboardRadio;

  /// No description provided for @dashForestCanopy.
  ///
  /// In en, this message translates to:
  /// **'Canopy'**
  String get dashForestCanopy;

  /// No description provided for @dashForestNoRoutes.
  ///
  /// In en, this message translates to:
  /// **'No learned routes yet. The MeshCore radio has not been told how to reach anyone.'**
  String get dashForestNoRoutes;

  /// No description provided for @dashForestContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get dashForestContacts;

  /// No description provided for @dashForestDepthSemantics.
  ///
  /// In en, this message translates to:
  /// **'Mesh depth, {levels} levels'**
  String dashForestDepthSemantics(int levels);

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
  /// **'Waiting for the MeshCore radio…'**
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

  /// No description provided for @linkChipConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio'**
  String get linkChipConnect;

  /// No description provided for @linkChipSemantics.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio {state}'**
  String linkChipSemantics(String state);

  /// No description provided for @actionConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get actionConnect;

  /// No description provided for @actionBlock.
  ///
  /// In en, this message translates to:
  /// **'Block this person'**
  String get actionBlock;

  /// No description provided for @blockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block this key?'**
  String get blockConfirmTitle;

  /// No description provided for @blockConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Hides what this person sends, on this device: messages, notifications and places. The MeshCore radio still receives and relays the packet, and the mesh does not learn about the block.'**
  String get blockConfirmBody;

  /// No description provided for @blockConfirmGo.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockConfirmGo;

  /// No description provided for @blockDone.
  ///
  /// In en, this message translates to:
  /// **'Blocked. This device no longer shows what it sends.'**
  String get blockDone;

  /// No description provided for @blockFull.
  ///
  /// In en, this message translates to:
  /// **'The block list is full. Unblock something first.'**
  String get blockFull;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionRetrySend.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetrySend;

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
  /// **'Pair a new MeshCore radio'**
  String get deviceMgrPairNew;

  /// No description provided for @pairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair a MeshCore radio'**
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
  /// **'The app needs Nearby devices to find your MeshCore radio and talk to it. Nothing is paired yet.'**
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
  /// **'Switch Bluetooth on to find your MeshCore radio. This screen continues by itself once it is on.'**
  String get pairAdapterBody;

  /// No description provided for @pairAdapterUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This phone reports no usable Bluetooth adapter, so a MeshCore radio cannot be paired here.'**
  String get pairAdapterUnsupported;

  /// No description provided for @pairRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get pairRetry;

  /// No description provided for @pairScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking for MeshCore radios'**
  String get pairScanTitle;

  /// No description provided for @pairScanBody.
  ///
  /// In en, this message translates to:
  /// **'A MeshCore radio advertises as MeshCore-<name>. Keep it switched on and within a metre or two of the phone.'**
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
  /// **'If the MeshCore radio shows a PIN, enter it on the phone when asked. Screenless radios use 123456.'**
  String get pairConnectingBody;

  /// No description provided for @pairConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio connected'**
  String get pairConfirmTitle;

  /// No description provided for @pairConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} answered, so the link and the protocol both work. This MeshCore radio is now the one the app uses.'**
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
  /// **'Use this MeshCore radio'**
  String get pairConfirmUse;

  /// No description provided for @pairChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another MeshCore radio'**
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

  /// No description provided for @settingsBackgroundNotRunning.
  ///
  /// In en, this message translates to:
  /// **'On, but the service is not running. Open the app again to restart it.'**
  String get settingsBackgroundNotRunning;

  /// No description provided for @settingsBackgroundOn.
  ///
  /// In en, this message translates to:
  /// **'Messages arrive while the app is closed. After a phone restart, open the app to reconnect.'**
  String get settingsBackgroundOn;

  /// No description provided for @settingsBackgroundOff.
  ///
  /// In en, this message translates to:
  /// **'Messages arrive when you open the app'**
  String get settingsBackgroundOff;

  /// No description provided for @settingsBackgroundFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not keep the app running in the background. Open the app to reconnect.'**
  String get settingsBackgroundFailed;

  /// No description provided for @settingsTelemetryPoll.
  ///
  /// In en, this message translates to:
  /// **'Fetch node temperature and altitude'**
  String get settingsTelemetryPoll;

  /// No description provided for @settingsTelemetryPollOn.
  ///
  /// In en, this message translates to:
  /// **'Costs a little airtime'**
  String get settingsTelemetryPollOn;

  /// No description provided for @settingsTelemetryPollOff.
  ///
  /// In en, this message translates to:
  /// **'Nothing is asked automatically. Open a node to ask it once.'**
  String get settingsTelemetryPollOff;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
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
  /// **'Speech'**
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
  /// **'This app talks to a mesh MeshCore radio. There is no account, no cloud and no analytics.'**
  String get termsLead;

  /// No description provided for @termsSectionLocal.
  ///
  /// In en, this message translates to:
  /// **'WHAT STAYS ON THIS DEVICE'**
  String get termsSectionLocal;

  /// No description provided for @termsLocalBody.
  ///
  /// In en, this message translates to:
  /// **'Messages, contacts, channels and settings are stored on this device. Message history, places, the movement trail and geofences are encrypted with a key this phone holds and cannot export. Coverage cells and the last day of channel activity are kept too, so the map and the activity report survive a restart: they are not encrypted, and Delete everything removes them with the rest. Cloud backup and device transfer are off for everything, so a new phone does not silently inherit it. Deleting the app deletes that data.'**
  String get termsLocalBody;

  /// No description provided for @termsSectionLeaves.
  ///
  /// In en, this message translates to:
  /// **'WHAT LEAVES THE DEVICE'**
  String get termsSectionLeaves;

  /// No description provided for @termsLeavesBody.
  ///
  /// In en, this message translates to:
  /// **'What you send goes out over the MeshCore radio you are connected to: messages, positions and reactions. The map asks a tile server for map squares, which tells that server roughly where you are looking, and it names the source it is using. Offline map packs are off by default and are fetched only after you turn them on. Three other things leave, each only when you ask for it: Directions hands the place to your phone\'s map app, the neural image codec is downloaded from huggingface.co, and the built-in docs are read from raw.githubusercontent.com. Nothing else leaves. Files you export are yours to place.'**
  String get termsLeavesBody;

  /// No description provided for @termsSectionPermissions.
  ///
  /// In en, this message translates to:
  /// **'PERMISSIONS AND WHY'**
  String get termsSectionPermissions;

  /// No description provided for @termsPermissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth connects to the MeshCore radio. Location is used for your own position and, on older Android, to allow a Bluetooth scan. Notifications are used for messages that arrive while the app is in the background. Refusing any of them leaves the app usable without a radio.'**
  String get termsPermissionsBody;

  /// No description provided for @termsSectionRetention.
  ///
  /// In en, this message translates to:
  /// **'HOW MUCH IS KEPT'**
  String get termsSectionRetention;

  /// No description provided for @termsRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'Each conversation keeps its newest {cap} messages. Older ones are dropped. A place expires when its own timer runs out, and is then gone.'**
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

  /// No description provided for @aboutProjectSite.
  ///
  /// In en, this message translates to:
  /// **'The project site'**
  String get aboutProjectSite;

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
  /// **'Opens the issue tracker with this app\'s details filled in.'**
  String get aboutReportProblemSub;

  /// No description provided for @creditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get creditsTitle;

  /// No description provided for @creditsIntro.
  ///
  /// In en, this message translates to:
  /// **'Everything this app is built out of, in one list. Each row names the component, its licence and where it comes from.'**
  String get creditsIntro;

  /// No description provided for @aboutLicensesButton.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses & attributions'**
  String get aboutLicensesButton;

  /// No description provided for @aboutAttributions.
  ///
  /// In en, this message translates to:
  /// **'Includes MeshCore documentation (MIT), OpenStreetMap map data (ODbL), and the Saira & JetBrains Mono fonts (OFL).'**
  String get aboutAttributions;

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
  /// **'On by default. Augmentation only'**
  String get personalizationAudioMasterEnabled;

  /// No description provided for @personalizationCueVolume.
  ///
  /// In en, this message translates to:
  /// **'Cue volume'**
  String get personalizationCueVolume;

  /// No description provided for @personalizationCueVolumeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{percent} % of the phone\'s media volume'**
  String personalizationCueVolumeSubtitle(Object percent);

  /// No description provided for @personalizationCueStreamNote.
  ///
  /// In en, this message translates to:
  /// **'Cues play on the media stream. If you hear nothing, raise the phone media volume. A notification sound can be loud while this is quiet.'**
  String get personalizationCueStreamNote;

  /// No description provided for @personalizationCuePreview.
  ///
  /// In en, this message translates to:
  /// **'Hear this theme'**
  String get personalizationCuePreview;

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
  /// **'Demo: no MeshCore radio'**
  String get demoTooltip;

  /// No description provided for @demoModeRow.
  ///
  /// In en, this message translates to:
  /// **'No MeshCore radio'**
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

  /// No description provided for @firstRunBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get firstRunBack;

  /// No description provided for @firstRunNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get firstRunNext;

  /// No description provided for @firstRunSkipShort.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get firstRunSkipShort;

  /// No description provided for @firstRunThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a theme'**
  String get firstRunThemeTitle;

  /// No description provided for @firstRunThemeBody.
  ///
  /// In en, this message translates to:
  /// **'Each theme is its own colours, type and sounds. Pick one now, change it any time in Appearance.'**
  String get firstRunThemeBody;

  /// No description provided for @firstRunPrefsTitle.
  ///
  /// In en, this message translates to:
  /// **'A few choices'**
  String get firstRunPrefsTitle;

  /// No description provided for @firstRunPrefsBody.
  ///
  /// In en, this message translates to:
  /// **'These are the ones that change every screen. The rest can wait.'**
  String get firstRunPrefsBody;

  /// No description provided for @firstRunConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect your MeshCore radio'**
  String get firstRunConnect;

  /// No description provided for @firstRunRadioLinked.
  ///
  /// In en, this message translates to:
  /// **'{name} is connected'**
  String firstRunRadioLinked(String name);

  /// No description provided for @firstRunKeepRadio.
  ///
  /// In en, this message translates to:
  /// **'Keep this MeshCore radio'**
  String get firstRunKeepRadio;

  /// No description provided for @firstRunUnits.
  ///
  /// In en, this message translates to:
  /// **'Feet and miles'**
  String get firstRunUnits;

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
  /// **'Without Bluetooth the app opens in demo mode: history, channels, settings and docs, with no MeshCore radio traffic.'**
  String get firstRunOfflineBody;

  /// No description provided for @firstRunGrant.
  ///
  /// In en, this message translates to:
  /// **'Allow Bluetooth'**
  String get firstRunGrant;

  /// No description provided for @firstRunSkip.
  ///
  /// In en, this message translates to:
  /// **'Explore without a MeshCore radio'**
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
  /// **'Whole mesh, through repeaters'**
  String get nodesFloodAdvertBody;

  /// No description provided for @nodesZeroHopAdvert.
  ///
  /// In en, this message translates to:
  /// **'Direct advert'**
  String get nodesZeroHopAdvert;

  /// No description provided for @nodesZeroHopAdvertBody.
  ///
  /// In en, this message translates to:
  /// **'Direct neighbours only'**
  String get nodesZeroHopAdvertBody;

  /// No description provided for @nodesFloodAdvertSent.
  ///
  /// In en, this message translates to:
  /// **'Flood advert sent'**
  String get nodesFloodAdvertSent;

  /// No description provided for @nodesZeroHopAdvertSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to radios in direct range only.'**
  String get nodesZeroHopAdvertSent;

  /// No description provided for @nodesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'name, short ID, or pub key…'**
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
  /// **'Not connected'**
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
  /// **'Connect a MeshCore radio to discover nearby nodes.'**
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

  /// No description provided for @gridLegendRings.
  ///
  /// In en, this message translates to:
  /// **'Rings are distance bands. Without GPS at both ends they are signal bands.'**
  String gridLegendRings(String value);

  /// No description provided for @gridViewRadial.
  ///
  /// In en, this message translates to:
  /// **'Radar'**
  String get gridViewRadial;

  /// No description provided for @gridViewPicker.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get gridViewPicker;

  /// No description provided for @gridZoomWider.
  ///
  /// In en, this message translates to:
  /// **'Wider (zoom out)'**
  String get gridZoomWider;

  /// No description provided for @gridZoomTighter.
  ///
  /// In en, this message translates to:
  /// **'Tighter (zoom in)'**
  String get gridZoomTighter;

  /// No description provided for @gridNeedsFix.
  ///
  /// In en, this message translates to:
  /// **'This view needs your position. Waiting for the phone or the MeshCore radio to report one.'**
  String get gridNeedsFix;

  /// No description provided for @gridViewElevation.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get gridViewElevation;

  /// No description provided for @fujiLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'ALTITUDE'**
  String get fujiLegendTitle;

  /// No description provided for @fujiLegendAutoQuery.
  ///
  /// In en, this message translates to:
  /// **'Altitudes arrive slowly. Tap the box to ask again.'**
  String get fujiLegendAutoQuery;

  /// No description provided for @elevationProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'MESHMORE :: ALTITUDE'**
  String get elevationProfileTitle;

  /// Screen-reader description of the elevation chart, which is a painted picture with no text of its own.
  ///
  /// In en, this message translates to:
  /// **'Altitudes from {low} to {high} metres across {count} peers.'**
  String elevationProfileSemantics(int low, int high, int count);

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

  /// No description provided for @streetMapRecenter.
  ///
  /// In en, this message translates to:
  /// **'Re-centre on me'**
  String get streetMapRecenter;

  /// No description provided for @mapPackZoomOutside.
  ///
  /// In en, this message translates to:
  /// **'This pack covers zoom {min} to {max}. Coarser tiles stand in outside that range.'**
  String mapPackZoomOutside(int min, int max);

  /// No description provided for @deviceRegionLoadedOffline.
  ///
  /// In en, this message translates to:
  /// **'{label} loaded. Apply when a device is connected.'**
  String deviceRegionLoadedOffline(String label);

  /// No description provided for @mapFrozenBadge.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get mapFrozenBadge;

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
  /// **'Off. The MeshCore radio does not read its GPS, so it keeps announcing the last position set.'**
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
  /// **'Set on the MeshCore radio'**
  String get deviceGpsIntervalFixedByFirmware;

  /// No description provided for @locTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-publish location'**
  String get locTitle;

  /// No description provided for @locTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio gets position'**
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
  /// **'Position goes out with adverts'**
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
  /// **'Send your position once, now.'**
  String get locPublishNowSub;

  /// No description provided for @locLastPublishedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last published'**
  String get locLastPublishedLabel;

  /// No description provided for @locBeacon.
  ///
  /// In en, this message translates to:
  /// **'Periodic position beacon'**
  String get locBeacon;

  /// No description provided for @locBeaconSub.
  ///
  /// In en, this message translates to:
  /// **'Every 60 s, uses airtime'**
  String get locBeaconSub;

  /// No description provided for @locBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'Streaming GPS reacts faster and uses more battery.'**
  String get locBatteryHint;

  /// No description provided for @gridEmpty.
  ///
  /// In en, this message translates to:
  /// **'No nodes in range yet. A node appears once it announces itself.'**
  String get gridEmpty;

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
  /// **'Spoken messages'**
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
  /// **'No voices reported by the platform engine. Using the system default.'**
  String get voicePickerEmpty;

  /// No description provided for @voicePickerOnlyMyLanguage.
  ///
  /// In en, this message translates to:
  /// **'Only show my language'**
  String get voicePickerOnlyMyLanguage;

  /// No description provided for @voicePickerOnlyMyLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Only voices for {lang}'**
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
  /// **'LORA RADIO'**
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

  /// No description provided for @settingsGroupSafety.
  ///
  /// In en, this message translates to:
  /// **'SAFETY'**
  String get settingsGroupSafety;

  /// No description provided for @settingsGroupLocation.
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get settingsGroupLocation;

  /// No description provided for @settingsHubLocation.
  ///
  /// In en, this message translates to:
  /// **'Location & sharing'**
  String get settingsHubLocation;

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
  /// **'Appearance & accessibility'**
  String get settingsHubProfile;

  /// No description provided for @settingsHubChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get settingsHubChannels;

  /// No description provided for @settingsHubDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio connection'**
  String get settingsHubDiagnostics;

  /// No description provided for @bootStarting.
  ///
  /// In en, this message translates to:
  /// **'STARTING'**
  String get bootStarting;

  /// No description provided for @bootHeader.
  ///
  /// In en, this message translates to:
  /// **'MESHMORE / SYNCHRONIZING'**
  String get bootHeader;

  /// No description provided for @bootConnecting.
  ///
  /// In en, this message translates to:
  /// **'CONNECTING TO MeshCore radio…'**
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
  /// **'OFFLINE. Open Connect a MeshCore radio'**
  String get bootOffline;

  /// No description provided for @bootSkip.
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get bootSkip;

  /// No description provided for @bootSubtitle.
  ///
  /// In en, this message translates to:
  /// **'WAIT / 進行中'**
  String get bootSubtitle;

  /// No description provided for @eventAdvert.
  ///
  /// In en, this message translates to:
  /// **'{name} announced itself'**
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
  /// **'{name} is in the contact table'**
  String eventContact(String name);

  /// No description provided for @eventBattery.
  ///
  /// In en, this message translates to:
  /// **'battery {volts}V'**
  String eventBattery(String volts);

  /// No description provided for @eventDeviceError.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio reported an error ({code})'**
  String eventDeviceError(String code);

  /// No description provided for @eventDeviceClockSynced.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio\'s clock is in sync'**
  String get eventDeviceClockSynced;

  /// No description provided for @eventDeviceClockSkew.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio\'s clock is {seconds}s off'**
  String eventDeviceClockSkew(String seconds);

  /// No description provided for @eventMsgSent.
  ///
  /// In en, this message translates to:
  /// **'sent · the MeshCore radio acknowledged it'**
  String get eventMsgSent;

  /// No description provided for @eventDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio is running {version}'**
  String eventDeviceInfo(String version);

  /// No description provided for @eventSelfInfo.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio checked in · {name}'**
  String eventSelfInfo(String name);

  /// No description provided for @eventQueuedWaiting.
  ///
  /// In en, this message translates to:
  /// **'messages are queued on the MeshCore radio'**
  String get eventQueuedWaiting;

  /// No description provided for @eventQueuedWaitingN.
  ///
  /// In en, this message translates to:
  /// **'{count} messages are queued on the MeshCore radio'**
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
  /// **'{count} older messages dropped'**
  String chatRetentionDropped(int count, int cap);

  /// No description provided for @chatHistoryUnreadableTitle.
  ///
  /// In en, this message translates to:
  /// **'History cannot be opened on this device'**
  String get chatHistoryUnreadableTitle;

  /// No description provided for @chatHistoryUnreadableBody.
  ///
  /// In en, this message translates to:
  /// **'The messages are still saved here, sealed with a key this phone no longer has. They cannot be read until restored from an encrypted export.'**
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
  /// **'Open an export file first'**
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
  /// **'That passphrase did not open the file.'**
  String get chatRestoreFailed;

  /// No description provided for @diagnosticsPlaceStore.
  ///
  /// In en, this message translates to:
  /// **'Places store'**
  String get diagnosticsPlaceStore;

  /// No description provided for @diagnosticsPlaceStoreWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'the last save did not land. Pins will not survive a restart'**
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
  /// **'No messages on this channel'**
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

  /// No description provided for @chatSendNotSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent: no MeshCore radio.'**
  String get chatSendNotSent;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatBudgetNear.
  ///
  /// In en, this message translates to:
  /// **'Nearly at the limit: the MeshCore radio counts its own name in these bytes'**
  String chatBudgetNear(int remaining);

  /// No description provided for @chatBudgetTooLong.
  ///
  /// In en, this message translates to:
  /// **'Too long by {over} bytes. The MeshCore radio would cut the rest without telling you.'**
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
  /// **'Audio is muted. You will feel the vibration but not hear it.'**
  String get nodeDetailSignatureMutedHint;

  /// No description provided for @dmEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
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
  /// **'Not heard yet'**
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

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionDeleteLocal.
  ///
  /// In en, this message translates to:
  /// **'Delete locally'**
  String get actionDeleteLocal;

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
  /// **'This removes the row from your local history. MeshCore has no recall. The recipient still has it.'**
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
  /// **'Your own node.'**
  String get nodeDetailSelf;

  /// No description provided for @nodeDetailShareTelemetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Share my telemetry with this contact'**
  String get nodeDetailShareTelemetryTitle;

  /// No description provided for @nodeDetailShareTelemetryHelp.
  ///
  /// In en, this message translates to:
  /// **'Needs telemetry mode Contacts + Base.'**
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
  /// **'“{name}” is active under a new key. Likely deleted and re-added on their device. Move your star, tags, and {count} saved messages to the current key?'**
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
  /// **'Same contact, new key. Pick the node or paste the key. Your star, tags and messages move over.'**
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
  /// **'No nodes match. Clear the search, or paste the full key to link directly.'**
  String get nodeIdentityLinkNoMatch;

  /// No description provided for @nodeIdentityLinkUseKey.
  ///
  /// In en, this message translates to:
  /// **'Link to this key'**
  String get nodeIdentityLinkUseKey;

  /// No description provided for @nodeDetailNotDeviceContact.
  ///
  /// In en, this message translates to:
  /// **'Not in the MeshCore radio\'s contacts, so DMs may not route.'**
  String get nodeDetailNotDeviceContact;

  /// No description provided for @nodeDetailAddDeviceContact.
  ///
  /// In en, this message translates to:
  /// **'Add to device contacts'**
  String get nodeDetailAddDeviceContact;

  /// No description provided for @nodeDetailAddDeviceContactDone.
  ///
  /// In en, this message translates to:
  /// **'Added. DMs will route.'**
  String get nodeDetailAddDeviceContactDone;

  /// No description provided for @nodeDetailAddDeviceContactFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add the contact'**
  String get nodeDetailAddDeviceContactFailed;

  /// No description provided for @nodeDetailRemoveDeviceContact.
  ///
  /// In en, this message translates to:
  /// **'Remove from device contacts'**
  String get nodeDetailRemoveDeviceContact;

  /// No description provided for @nodeDetailRemoveDeviceContactConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}” from the MeshCore radio\'s contacts? You can add them again later.'**
  String nodeDetailRemoveDeviceContactConfirm(String name);

  /// No description provided for @nodeDetailRemoveDeviceContactDone.
  ///
  /// In en, this message translates to:
  /// **'Removed from your MeshCore radio\'s contacts.'**
  String get nodeDetailRemoveDeviceContactDone;

  /// No description provided for @deviceContactsTitle.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio contacts'**
  String get deviceContactsTitle;

  /// No description provided for @deviceContactsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get deviceContactsRefresh;

  /// No description provided for @deviceContactsSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing contacts from the MeshCore radio…'**
  String get deviceContactsSyncing;

  /// No description provided for @deviceContactsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your MeshCore radio has no contacts.'**
  String get deviceContactsEmpty;

  /// No description provided for @deviceContactsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} contacts on the MeshCore radio'**
  String deviceContactsCount(int count, int max);

  /// No description provided for @deviceContactsCountOnly.
  ///
  /// In en, this message translates to:
  /// **'{count} contacts on the MeshCore radio'**
  String deviceContactsCountOnly(int count);

  /// No description provided for @deviceContactsFullHelp.
  ///
  /// In en, this message translates to:
  /// **'Contact list is full. Remove entries below to add new ones.'**
  String get deviceContactsFullHelp;

  /// No description provided for @deviceContactsChannelsNote.
  ///
  /// In en, this message translates to:
  /// **'Contacts are only for direct messages.'**
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
  /// **'No location set, so distance can\'t be measured. Only location-hidden contacts are caught. Set your position to also remove far-away GPS contacts.'**
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
  /// **'Remove all from the MeshCore radio'**
  String get deviceContactsRemoveAll;

  /// No description provided for @deviceContactsRemoveAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove all {count} contacts? You only need them to send direct messages, and you can add anyone back later.'**
  String deviceContactsRemoveAllConfirm(int count);

  /// No description provided for @deviceContactsRemoveAllDone.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} contacts from the MeshCore radio.'**
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
  /// **'e.g. Repeater, work, ham-club'**
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
  /// **'Message heat'**
  String get gridViewSnsCells;

  /// No description provided for @gridViewWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get gridViewWeather;

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
  /// **'Clear the last 24h of Meshbook data for CH{channel}? It rebuilds as new channel messages arrive.'**
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
  /// **'No measured weather report on this channel in the last 24 h. A number and a unit is a report. \"rain later\" is not.'**
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
  /// **'No nodes are reporting environment data yet.\nReadings appear as sensor-equipped nodes are polled. Enable \"Gather node telemetry\" in App settings.'**
  String get weatherEmpty;

  /// No description provided for @weatherSelfNoTelemetry.
  ///
  /// In en, this message translates to:
  /// **'This device hasn\'t returned telemetry yet. Make sure you\'re connected, then reopen this view.'**
  String get weatherSelfNoTelemetry;

  /// No description provided for @weatherSelfNoEnv.
  ///
  /// In en, this message translates to:
  /// **'Environment telemetry isn\'t supported by this device\'s firmware.\nIt reported: {types}.\nThe sensor (e.g. The T1000-E\'s BME280) needs a MeshCore sensor build. The standard build sends only battery and GPS. This is the device, not a setting.'**
  String weatherSelfNoEnv(String types);

  /// No description provided for @weatherReporting.
  ///
  /// In en, this message translates to:
  /// **'{count} reporting'**
  String weatherReporting(int count);

  /// Under the temperature summary, naming the nodes that reported environment data but no temperature, so they are not silently missing from the count above.
  ///
  /// In en, this message translates to:
  /// **'{count} more report humidity or pressure only'**
  String weatherReportingOther(int count);

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
  /// **'Companion protocol: frames, opcodes'**
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
  /// **'MeshCore firmware. Matched to {version}.'**
  String docsFirmwareSubVersion(String version);

  /// No description provided for @docsAppTitle.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get docsAppTitle;

  /// No description provided for @docsAppSub.
  ///
  /// In en, this message translates to:
  /// **'How the app works'**
  String get docsAppSub;

  /// No description provided for @docsDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get docsDevicesTitle;

  /// No description provided for @docsDevicesSub.
  ///
  /// In en, this message translates to:
  /// **'T1000-E, Wio Tracker, Heltec'**
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

  /// No description provided for @snsCellsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get snsCellsClear;

  /// No description provided for @snsCellsStatus.
  ///
  /// In en, this message translates to:
  /// **'{active, plural, =1{1 cell} other{{active} cells}} · {hot, plural, =1{1 hot} other{{hot} hot}}'**
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
  /// **'MESSAGE HEAT'**
  String get snsCellsLegendTitle;

  /// No description provided for @snsCellsLegendDesc.
  ///
  /// In en, this message translates to:
  /// **'A live social-activity heat map. Each observed message warms its cell. Cells cool over a one-hour horizon.'**
  String get snsCellsLegendDesc;

  /// No description provided for @snsCellsLegendHot.
  ///
  /// In en, this message translates to:
  /// **'Bright red = busy (≈5+ messages in the last minute).'**
  String get snsCellsLegendHot;

  /// No description provided for @snsCellsLegendCool.
  ///
  /// In en, this message translates to:
  /// **'Fading to white = quieting down. Gone after ~1 h idle.'**
  String get snsCellsLegendCool;

  /// No description provided for @snsCellsLegendToast.
  ///
  /// In en, this message translates to:
  /// **'New messages flash as a toast near their source, then vanish.'**
  String get snsCellsLegendToast;

  /// No description provided for @snsCellsLegendChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel messages carry the sender\'s name: they warm the sender\'s cell when we know where they are, otherwise your own cell.'**
  String get snsCellsLegendChannel;

  /// No description provided for @snsCellsLegendDecay.
  ///
  /// In en, this message translates to:
  /// **'Only the last hour is tracked. Nothing is stored.'**
  String get snsCellsLegendDecay;

  /// No description provided for @meshTreeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Waiting for contact sync. The tree is built from each contact\'s outPath.'**
  String get meshTreeEmpty;

  /// Shown instead of the no-peers notice when the hop stop is what emptied the tree. The stop is named by its own label (Direct, <=3 hops, ...) rather than as a number, so it reads the same as the slider above it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{No peer has a learned route at {stop}. 1 is heard without one. Flood / All shows it.} other{No peer has a learned route at {stop}. {count} are heard without one. Flood / All shows them.}}'**
  String meshTreeFilteredEmptyFor(String stop, int count);

  /// No description provided for @meshTreeLearnRoutes.
  ///
  /// In en, this message translates to:
  /// **'Ask the MeshCore radio for routes'**
  String get meshTreeLearnRoutes;

  /// No description provided for @meshTreeLearning.
  ///
  /// In en, this message translates to:
  /// **'Asking the MeshCore radio…'**
  String get meshTreeLearning;

  /// No description provided for @meshTreeNoRoutes.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio has not learned any routes yet, so every peer is drawn. The stop appears once it does.'**
  String get meshTreeNoRoutes;

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

  /// How many peers the hop limit actually reached, shown after the stop name.
  ///
  /// In en, this message translates to:
  /// **'{count} routed'**
  String meshTreeHopsRouted(int count);

  /// Shown instead of a count when the radio has learned no routes at all, so a depth limit cannot reach any peer.
  ///
  /// In en, this message translates to:
  /// **'no routes'**
  String get meshTreeHopsNoRoutes;

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
  /// **'A directed graph of how the MeshCore radio reaches each contact. Each edge is a repeater on the route it actually sends by.'**
  String get meshTreeLegendDesc;

  /// No description provided for @meshTreeLegendFlood.
  ///
  /// In en, this message translates to:
  /// **'Dashed edge = flood-routed. Reachable, no fixed path.'**
  String get meshTreeLegendFlood;

  /// No description provided for @meshTreeLegendFloat.
  ///
  /// In en, this message translates to:
  /// **'No edges = heard by advert only, route unknown.'**
  String get meshTreeLegendFloat;

  /// No description provided for @nodeDetailHopsKv.
  ///
  /// In en, this message translates to:
  /// **'hops'**
  String get nodeDetailHopsKv;

  /// No description provided for @nodeDetailHopsDirect.
  ///
  /// In en, this message translates to:
  /// **'direct'**
  String get nodeDetailHopsDirect;

  /// No description provided for @nodeDetailHopsViaRepeaters.
  ///
  /// In en, this message translates to:
  /// **'{n}'**
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
  /// **'Asking the MeshCore radio for readings…'**
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

  /// No description provided for @networksIntro.
  ///
  /// In en, this message translates to:
  /// **'Who can hear this MeshCore radio'**
  String get networksIntro;

  /// No description provided for @channelsIntro.
  ///
  /// In en, this message translates to:
  /// **'Who can read your messages: a shared key per thread.'**
  String get channelsIntro;

  /// No description provided for @channelsHelp.
  ///
  /// In en, this message translates to:
  /// **'Channel 0 is the shared public one. A private group needs the same channel number, name and key on every MeshCore radio.'**
  String get channelsHelp;

  /// No description provided for @channelsOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio (Diagnostics) to edit channels.'**
  String get channelsOfflineHint;

  /// No description provided for @channelCreateCreated.
  ///
  /// In en, this message translates to:
  /// **'Channel created.'**
  String get channelCreateCreated;

  /// No description provided for @channelCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New channel'**
  String get channelCreateTitle;

  /// Section in the add-a-channel sheet that lists the channels already configured, so removing one is in the same menu as adding one.
  ///
  /// In en, this message translates to:
  /// **'Reset a channel'**
  String get channelRemoveSection;

  /// Explains what removing a channel does and does not do.
  ///
  /// In en, this message translates to:
  /// **'A slot always holds a channel, so this puts the slot back to the shared Public channel. The messages already on this phone stay.'**
  String get channelRemoveBody;

  /// The action on a configured channel row in the remove section.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get channelRemoveAction;

  /// No description provided for @channelCreateIntro.
  ///
  /// In en, this message translates to:
  /// **'Name it, then say who should be able to read it.'**
  String get channelCreateIntro;

  /// No description provided for @channelCreateNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Basecamp'**
  String get channelCreateNameHint;

  /// No description provided for @channelCreateNameKeyedTitle.
  ///
  /// In en, this message translates to:
  /// **'Anyone who knows the name'**
  String get channelCreateNameKeyedTitle;

  /// No description provided for @channelCreateNameKeyedBody.
  ///
  /// In en, this message translates to:
  /// **'The key comes from the name, so every MeshCore radio that types the same name joins. Nothing else can read it.'**
  String get channelCreateNameKeyedBody;

  /// No description provided for @channelCreatePublicTitle.
  ///
  /// In en, this message translates to:
  /// **'The public channel'**
  String get channelCreatePublicTitle;

  /// No description provided for @channelCreatePublicBody.
  ///
  /// In en, this message translates to:
  /// **'Everyone within LoRa radio range on the public channel can read it. Use this only for a channel meant to be open.'**
  String get channelCreatePublicBody;

  /// No description provided for @channelCreateSlotNote.
  ///
  /// In en, this message translates to:
  /// **'Goes in slot {slot}, the first one nothing is using.'**
  String channelCreateSlotNote(Object slot);

  /// No description provided for @channelCreateNoSlot.
  ///
  /// In en, this message translates to:
  /// **'Every channel slot on this MeshCore radio is in use. Free one on the channels screen first.'**
  String get channelCreateNoSlot;

  /// No description provided for @channelCreateAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Slot and key'**
  String get channelCreateAdvanced;

  /// No description provided for @channelCreateSlotTile.
  ///
  /// In en, this message translates to:
  /// **'Channel slot'**
  String get channelCreateSlotTile;

  /// No description provided for @channelCreateSlotHint.
  ///
  /// In en, this message translates to:
  /// **'The first free slot is used unless you pick one.'**
  String get channelCreateSlotHint;

  /// No description provided for @channelCreateSlotNumber.
  ///
  /// In en, this message translates to:
  /// **'Slot {n}'**
  String channelCreateSlotNumber(int n);

  /// No description provided for @channelCreateKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Key, 32 hex characters'**
  String get channelCreateKeyLabel;

  /// No description provided for @channelCreateKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the key another client gave you'**
  String get channelCreateKeyHint;

  /// No description provided for @channelCreateKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'A pasted key wins over the name.'**
  String get channelCreateKeyHelp;

  /// No description provided for @channelCreateKeyRandom.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get channelCreateKeyRandom;

  /// No description provided for @channelCreateExists.
  ///
  /// In en, this message translates to:
  /// **'There is already a channel called {name}.'**
  String channelCreateExists(String name);

  /// No description provided for @channelCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get channelCreateAction;

  /// No description provided for @channelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
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

  /// No description provided for @channelsSetSnack.
  ///
  /// In en, this message translates to:
  /// **'Channel {idx} saved.'**
  String channelsSetSnack(int idx);

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
  /// **'Find place names in messages'**
  String get channelsInferPlaces;

  /// No description provided for @channelsInferPlacesSub.
  ///
  /// In en, this message translates to:
  /// **'Offer places named in messages'**
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
  /// **'Open the app to see the position.'**
  String get notifBodySos;

  /// OS notification body for an acknowledgement of an SOS. The wire form is [ACK:<id>] <callsign> <words>; the lock screen shows a sentence instead.
  ///
  /// In en, this message translates to:
  /// **'{name} answered your alarm.'**
  String notifBodySosAck(String name);

  /// OS notification body for a safe message. The wire form is [SAFE:<id>] <callsign>.
  ///
  /// In en, this message translates to:
  /// **'{name} says they are safe.'**
  String notifBodySosSafe(String name);

  /// OS notification body for a check-in. The wire form carries coordinates, which the lock screen must not publish.
  ///
  /// In en, this message translates to:
  /// **'{name} checked in.'**
  String notifBodySosCheckin(String name);

  /// Ongoing notification shown while an SOS is running.
  ///
  /// In en, this message translates to:
  /// **'The alarm is still repeating. Open the app to stop it.'**
  String get notifAlarmRunningBody;

  /// OS notification body for a fence crossing. States the limit: fences are evaluated against the position fixes the app already has, so a crossing can lag the walk.
  ///
  /// In en, this message translates to:
  /// **'This is based on the last position your phone reported, so it may have happened a little earlier.'**
  String get notifBodyFence;

  /// App settings row shown when this app is still on the battery-optimisation list, which lets an OEM stop the foreground service.
  ///
  /// In en, this message translates to:
  /// **'Android may stop the link'**
  String get settingsBatteryOptimisedTitle;

  /// Explains the consequence and the action beside it.
  ///
  /// In en, this message translates to:
  /// **'Some phones stop backgrounded apps'**
  String get settingsBatteryOptimisedSub;

  /// The action that opens the OS request to stop optimising this app.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get settingsBatteryAllow;

  /// Section heading in the channel editor for the per-channel notification bundle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifSectionTitle;

  /// No description provided for @notifMutedNoticeHere.
  ///
  /// In en, this message translates to:
  /// **'Silenced. Switches apply when unsilenced.'**
  String get notifMutedNoticeHere;

  /// No description provided for @notifMuted.
  ///
  /// In en, this message translates to:
  /// **'Silence this channel'**
  String get notifMuted;

  /// No description provided for @settingsSilencePerChannel.
  ///
  /// In en, this message translates to:
  /// **'Silence a channel'**
  String get settingsSilencePerChannel;

  /// No description provided for @notifMutedSub.
  ///
  /// In en, this message translates to:
  /// **'Messages kept, alerts stopped'**
  String get notifMutedSub;

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
  /// **'Mentions only, off means all'**
  String get notifMentionsOnlySub;

  /// Per-channel opt-in: treat the public key's hex suffix as a mention.
  ///
  /// In en, this message translates to:
  /// **'Match my ID\'s last 4'**
  String get notifKeySuffix;

  /// Warns about the key-suffix opt-in.
  ///
  /// In en, this message translates to:
  /// **'Four characters anyone can choose'**
  String get notifKeySuffixSub;

  /// Shown when the OS notification permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off'**
  String get notifDeniedBanner;

  /// Shown when one of the app's notification channels is below high importance.
  ///
  /// In en, this message translates to:
  /// **'Notifications are silent in Android settings.'**
  String get notifQuietBanner;

  /// Shown when a notification channel was deleted by the user.
  ///
  /// In en, this message translates to:
  /// **'Android had removed this app\'s notification settings, so they were set up again.'**
  String get notifMissingChannelBanner;

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
  /// **'Key derived from sha256(\"#tag\"). The # is part of the key'**
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
  /// **'Channel key copied. It is on the clipboard now, where other apps can read it.'**
  String get channelsHexCopied;

  /// No description provided for @channelsTagWeakShort.
  ///
  /// In en, this message translates to:
  /// **'Short tags are guessable. Use 12+ chars or unusual phrasing.'**
  String get channelsTagWeakShort;

  /// No description provided for @channelsTagWeakCommon.
  ///
  /// In en, this message translates to:
  /// **'Common words are guessable. An attacker can grind tags. Use unusual phrasing.'**
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
  /// **'The MeshCore radio has no empty channel, so this one goes back to the public name and key. Other radios need the same to talk here again.'**
  String get channelsClearConfirmBody;

  /// No description provided for @channelsClearSnack.
  ///
  /// In en, this message translates to:
  /// **'Channel {idx} reset to the shared defaults.'**
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
  /// **'Your phone GPS ({lat}, {lon}) matches {label}. Check it is legal where you are before applying. Especially outside the country you set it up in.'**
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
  /// **'Your location doesn\'t match any shipped country preset. Pick one manually.'**
  String get deviceRegionSuggestNoMatch;

  /// No description provided for @deviceRegionDisclaimerShort.
  ///
  /// In en, this message translates to:
  /// **'Shared by users, not checked by a regulator.'**
  String get deviceRegionDisclaimerShort;

  /// No description provided for @deviceRegionDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Pick a preset that is legal where you are, and use the same settings on every MeshCore radio. In Japan the radio itself must carry 技適 certification, which most imported boards do not.'**
  String get deviceRegionDisclaimer;

  /// No description provided for @presetUsCanada.
  ///
  /// In en, this message translates to:
  /// **'USA / Canada'**
  String get presetUsCanada;

  /// No description provided for @presetUsArizona.
  ///
  /// In en, this message translates to:
  /// **'USA. Arizona'**
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
  /// **'LoRa radio'**
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
  /// **'The hash length the MeshCore radio stamps on its packets. Repeaters follow each packet, so nodes need not agree.'**
  String get devicePathHashSizeHelp;

  /// No description provided for @devicePathHashUnread.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio has not said which length it uses yet.'**
  String get devicePathHashUnread;

  /// No description provided for @devicePathHashMismatch.
  ///
  /// In en, this message translates to:
  /// **'On the MeshCore radio: {device}. Yours: {form}. Tap Apply to send yours.'**
  String devicePathHashMismatch(String device, String form);

  /// No description provided for @deviceRadioApplied.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio confirmed the change.'**
  String get deviceRadioApplied;

  /// No description provided for @deviceRadioRefused.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused {param} (error {code}). Nothing after it was sent.'**
  String deviceRadioRefused(String param, String code);

  /// No description provided for @deviceRadioSilent.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio did not answer {param} within five seconds, so the change may not have taken.'**
  String deviceRadioSilent(String param);

  /// No description provided for @deviceRadioUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio\'s firmware does not have {param}.'**
  String deviceRadioUnsupported(String param);

  /// No description provided for @deviceRadioUnknownState.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio has not said how it labels routes yet, so there is nothing to undo back to. Reconnect and try again.'**
  String get deviceRadioUnknownState;

  /// No description provided for @deviceRadioRevert.
  ///
  /// In en, this message translates to:
  /// **'Undo MeshCore radio change'**
  String get deviceRadioRevert;

  /// No description provided for @deviceRadioReverted.
  ///
  /// In en, this message translates to:
  /// **'Previous operating point restored.'**
  String get deviceRadioReverted;

  /// No description provided for @deviceRadioRevertUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Undo works once. After that, set the value again by hand.'**
  String get deviceRadioRevertUnavailable;

  /// No description provided for @deviceRadioRevertFailed.
  ///
  /// In en, this message translates to:
  /// **'Undo did not apply. The MeshCore radio kept its last values.'**
  String get deviceRadioRevertFailed;

  /// No description provided for @radioHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio health'**
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
  /// **'No reading yet.'**
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
  /// **'From the MeshCore radio'**
  String get radioHealthSource;

  /// No description provided for @radioHealthAckTrip.
  ///
  /// In en, this message translates to:
  /// **'last acknowledgement: {ms} ms round trip (the MeshCore radio\'s own measure)'**
  String radioHealthAckTrip(int ms);

  /// No description provided for @deviceLoadFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Load from device'**
  String get deviceLoadFromDevice;

  /// No description provided for @deviceApplyRadio.
  ///
  /// In en, this message translates to:
  /// **'Apply MeshCore radio params'**
  String get deviceApplyRadio;

  /// No description provided for @deviceConnectFirst.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio first, in Settings under MeshCore radio connection.'**
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
  /// **'Name updated. Neighbours will hear it on the next announcement.'**
  String get deviceToastNameSet;

  /// No description provided for @deviceToastSendFailed.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio did not take it: {error}'**
  String deviceToastSendFailed(String error);

  /// No description provided for @deviceToastNoDeviceYet.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio has not answered yet. Try again once it is connected.'**
  String get deviceToastNoDeviceYet;

  /// No description provided for @deviceToastNoGpsYet.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio has not worked out where it is yet.'**
  String get deviceToastNoGpsYet;

  /// No description provided for @deviceToastLoadedDeviceLoc.
  ///
  /// In en, this message translates to:
  /// **'Loaded the MeshCore radio\'s position. Tap Set advert location to send it.'**
  String get deviceToastLoadedDeviceLoc;

  /// No description provided for @deviceToastGettingPhoneFix.
  ///
  /// In en, this message translates to:
  /// **'Getting your position…'**
  String get deviceToastGettingPhoneFix;

  /// No description provided for @deviceToastPhoneFixFailed.
  ///
  /// In en, this message translates to:
  /// **'The phone could not get a position. Check that location is on, then try again.'**
  String get deviceToastPhoneFixFailed;

  /// No description provided for @deviceToastNoFixReturned.
  ///
  /// In en, this message translates to:
  /// **'The phone did not get a position. Try again outdoors.'**
  String get deviceToastNoFixReturned;

  /// No description provided for @deviceToastGotPhoneLoc.
  ///
  /// In en, this message translates to:
  /// **'Got your position. Tap Set advert location to send it.'**
  String get deviceToastGotPhoneLoc;

  /// No description provided for @deviceToastInvalidLatLon.
  ///
  /// In en, this message translates to:
  /// **'Enter a latitude from -90 to 90 and a longitude from -180 to 180.'**
  String get deviceToastInvalidLatLon;

  /// No description provided for @deviceToastAdvertLocSet.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio will now announce this position.'**
  String get deviceToastAdvertLocSet;

  /// No description provided for @deviceToastInvalidRadio.
  ///
  /// In en, this message translates to:
  /// **'Enter a frequency, a bandwidth, a spreading factor and a coding rate.'**
  String get deviceToastInvalidRadio;

  /// No description provided for @deviceLocPermDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission needed'**
  String get deviceLocPermDenied;

  /// No description provided for @deviceLocPermDeniedPerm.
  ///
  /// In en, this message translates to:
  /// **'Location permission permanently denied. Open OS settings to grant it.'**
  String get deviceLocPermDeniedPerm;

  /// No description provided for @deviceOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get deviceOpenSettings;

  /// No description provided for @connectionDiagnosticsRow.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics and tools'**
  String get connectionDiagnosticsRow;

  /// No description provided for @connectionDiagnosticsExplainer.
  ///
  /// In en, this message translates to:
  /// **'Frames, fixtures, test commands'**
  String get connectionDiagnosticsExplainer;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio diagnostics'**
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
  /// **'OTHER PARAMS sent. Device-side write may take a moment.'**
  String get otherSentSnack;

  /// No description provided for @otherAwaitingDevice.
  ///
  /// In en, this message translates to:
  /// **'Awaiting device'**
  String get otherAwaitingDevice;

  /// No description provided for @batteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get batteryTitle;

  /// No description provided for @batteryConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Charge, drain, time to empty'**
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
  /// **'Charging. Runtime estimate paused.'**
  String get batteryChargingNote;

  /// No description provided for @batteryTimeToEmpty.
  ///
  /// In en, this message translates to:
  /// **'TIME TO EMPTY'**
  String get batteryTimeToEmpty;

  /// No description provided for @batteryEstimating.
  ///
  /// In en, this message translates to:
  /// **'Gathering drain data. An estimate appears after a few minutes of discharge.'**
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
  /// **'Unknown hardware. Using a generic single-cell Li-ion model. The estimate relies on observed drain (no nameplate capacity to cross-check).'**
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
  /// **'Typical draw: ~{ma} mA (LoRa radio receiving)'**
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
  /// **'Not delivered. No acknowledgement or send failed'**
  String get deliveryFailed;

  /// No description provided for @deliveryUnknown.
  ///
  /// In en, this message translates to:
  /// **'Sent while the app was closing. Whether the MeshCore radio transmitted it is not knowable'**
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
  /// **'Not connected. The tools need the MeshCore radio. Open Connect a MeshCore radio'**
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
  /// **'Copy results'**
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
  /// **'MeshCore radio stats'**
  String get toolStatsName;

  /// No description provided for @toolStatsSub.
  ///
  /// In en, this message translates to:
  /// **'MeshCore counters'**
  String get toolStatsSub;

  /// No description provided for @toolPingName.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get toolPingName;

  /// No description provided for @toolPingSub.
  ///
  /// In en, this message translates to:
  /// **'Loss and round trip'**
  String get toolPingSub;

  /// No description provided for @toolTraceName.
  ///
  /// In en, this message translates to:
  /// **'Trace path'**
  String get toolTraceName;

  /// No description provided for @toolTraceSub.
  ///
  /// In en, this message translates to:
  /// **'Per-hop signal'**
  String get toolTraceSub;

  /// No description provided for @toolDiscoverName.
  ///
  /// In en, this message translates to:
  /// **'Discover nearby'**
  String get toolDiscoverName;

  /// No description provided for @toolDiscoverSub.
  ///
  /// In en, this message translates to:
  /// **'Repeaters that answer'**
  String get toolDiscoverSub;

  /// No description provided for @toolSoakName.
  ///
  /// In en, this message translates to:
  /// **'Soak test'**
  String get toolSoakName;

  /// No description provided for @toolSoakSub.
  ///
  /// In en, this message translates to:
  /// **'Message sequencing'**
  String get toolSoakSub;

  /// No description provided for @toolRangeName.
  ///
  /// In en, this message translates to:
  /// **'Range test'**
  String get toolRangeName;

  /// No description provided for @toolRangeSub.
  ///
  /// In en, this message translates to:
  /// **'Signal over distance'**
  String get toolRangeSub;

  /// No description provided for @toolFailNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a MeshCore radio.'**
  String get toolFailNotConnected;

  /// No description provided for @toolFailBusy.
  ///
  /// In en, this message translates to:
  /// **'Another tool is using the MeshCore radio. Stop it first.'**
  String get toolFailBusy;

  /// No description provided for @toolFailUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Your MeshCore radio\'s firmware doesn\'t support this.'**
  String get toolFailUnsupported;

  /// No description provided for @toolFailNotFound.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio doesn\'t have this contact.'**
  String get toolFailNotFound;

  /// No description provided for @toolFailTableFull.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio is busy (send table full). Try again shortly.'**
  String get toolFailTableFull;

  /// No description provided for @toolFailRejected.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused the request.'**
  String get toolFailRejected;

  /// No description provided for @toolFailNoConfirm.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio didn\'t confirm the send.'**
  String get toolFailNoConfirm;

  /// No description provided for @toolFailPublic.
  ///
  /// In en, this message translates to:
  /// **'Public is refused: everything sent there reaches every MeshCore radio. Use a private channel or a DM.'**
  String get toolFailPublic;

  /// No description provided for @toolFailUnknownChannel.
  ///
  /// In en, this message translates to:
  /// **'This channel\'s key hasn\'t been read from the MeshCore radio yet.'**
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
  /// **'LoRa radio'**
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
  /// **'Status request. Repeaters, rooms and sensors answer this.'**
  String get pingMethodStatus;

  /// No description provided for @pingMethodTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Asks for readings. The other MeshCore radio answers only if it shares them with you.'**
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
  /// **'No synced contacts yet. Only contacts can be pinged.'**
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
  /// **'Round trip'**
  String get traceRoundTrip;

  /// No description provided for @traceNoRoute.
  ///
  /// In en, this message translates to:
  /// **'no route. Send it a message first'**
  String get traceNoRoute;

  /// No description provided for @tracePath.
  ///
  /// In en, this message translates to:
  /// **'path {path}'**
  String tracePath(String path);

  /// No description provided for @traceManualHint.
  ///
  /// In en, this message translates to:
  /// **'hashes, e.g. A1,7f,a1'**
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
  /// **'Route cleared. The next message goes out to every MeshCore radio in range.'**
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
  /// **'Pairs with an R59 bot answering on the other MeshCore radio: echoes show drops, duplicates and reordering.'**
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
  /// **'Sends done. Listening for late echoes…'**
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
  /// **'Both radios on the same private channel. The sender beacons. The receiver walks and logs.'**
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
  /// **'About'**
  String get settingsHubInfo;

  /// No description provided for @settingsNotifDeniedPermanent.
  ///
  /// In en, this message translates to:
  /// **'Notifications permanently denied'**
  String get settingsNotifDeniedPermanent;

  /// No description provided for @settingsNotifDeniedTransient.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications to stay connected'**
  String get settingsNotifDeniedTransient;

  /// No description provided for @deviceAdvertPropagatesHint.
  ///
  /// In en, this message translates to:
  /// **'Takes effect the next time the MeshCore radio announces itself.'**
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
  /// **'No network. Downloads resume on their own.'**
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
  /// **'Choose a region to download'**
  String get mapsAddPack;

  /// No description provided for @mapsNoPacks.
  ///
  /// In en, this message translates to:
  /// **'No regions yet.'**
  String get mapsNoPacks;

  /// No description provided for @mapsArchives.
  ///
  /// In en, this message translates to:
  /// **'Region files'**
  String get mapsArchives;

  /// No description provided for @mapsNoArchives.
  ///
  /// In en, this message translates to:
  /// **'No region files yet.'**
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
  /// **'No packs published. Install one from a link.'**
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
  /// **'Couldn\'t read the published list. Showing the built-in one.'**
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
  /// **'Packs can be hundreds of MB'**
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

  /// No description provided for @mapsAddLayer.
  ///
  /// In en, this message translates to:
  /// **'Add event map'**
  String get mapsAddLayer;

  /// No description provided for @mapsNoLayers.
  ///
  /// In en, this message translates to:
  /// **'No event maps yet.'**
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

  /// No description provided for @mapsLayerDense.
  ///
  /// In en, this message translates to:
  /// **'Dense layer: the map draws its first {max} features.'**
  String mapsLayerDense(int max);

  /// No description provided for @mapsLayerFileMissing.
  ///
  /// In en, this message translates to:
  /// **'This file will not open. Refresh it or delete the layer.'**
  String get mapsLayerFileMissing;

  /// No description provided for @layerRefusalEmpty.
  ///
  /// In en, this message translates to:
  /// **'That file is valid GeoJSON with nothing in it to draw.'**
  String get layerRefusalEmpty;

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
  /// **'Checks map downloads end to end: the real servers, storage, pause and resume, expiry. It runs in a sandbox that is deleted afterwards, so your maps are untouched. About a minute, under 1 MB.'**
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
  /// **'Copy results'**
  String get selfTestCopy;

  /// No description provided for @selfTestCopied.
  ///
  /// In en, this message translates to:
  /// **'Results copied'**
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
  /// **'Channels and keys'**
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
  /// **'alt:.'**
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
  /// **'· connecting…'**
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
  /// **'⚡ charging'**
  String get diagnosticsChargingSuffix;

  /// No description provided for @diagnosticsReconnectLine.
  ///
  /// In en, this message translates to:
  /// **'reconnect attempt {n}'**
  String diagnosticsReconnectLine(String n);

  /// No description provided for @diagnosticsGaveUpSuffix.
  ///
  /// In en, this message translates to:
  /// **'(gave up)'**
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
  /// **'This phone link is {mtu} bytes and a full LoRa frame needs {need}. Reconnect to try again. A MeshCore radio that caps the link smaller cannot carry every frame.'**
  String diagnosticsMtuRefusedLine(String mtu, String need);

  /// No description provided for @diagnosticsDatagramLine.
  ///
  /// In en, this message translates to:
  /// **'datagram: channel {ch}, via {via}, type {type}'**
  String diagnosticsDatagramLine(String ch, String via, String type);

  /// No description provided for @rxViaPrimary.
  ///
  /// In en, this message translates to:
  /// **'the primary MeshCore radio'**
  String get rxViaPrimary;

  /// No description provided for @rxViaSecondary.
  ///
  /// In en, this message translates to:
  /// **'radio 2'**
  String get rxViaSecondary;

  /// No description provided for @rxViaUnknown.
  ///
  /// In en, this message translates to:
  /// **'an unreported MeshCore radio'**
  String get rxViaUnknown;

  /// No description provided for @diagnosticsFramesDroppedLine.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 frame arrived in part, so its data may be incomplete} other{{count} frames arrived in part, so their data may be incomplete}}'**
  String diagnosticsFramesDroppedLine(int count);

  /// No description provided for @diagnosticsFramingLine.
  ///
  /// In en, this message translates to:
  /// **'incomplete frames: {truncated} cut short, {trailing} with bytes left over, {empty} empty'**
  String diagnosticsFramingLine(
      String truncated, String trailing, Object empty);

  /// No description provided for @diagnosticsForgetShort.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get diagnosticsForgetShort;

  /// No description provided for @diagnosticsPairedLine.
  ///
  /// In en, this message translates to:
  /// **'Paired: {name}. Auto-reconnects on startup'**
  String diagnosticsPairedLine(String name);

  /// No description provided for @diagnosticsSectionDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get diagnosticsSectionDeveloper;

  /// No description provided for @diagnosticsPairRadio.
  ///
  /// In en, this message translates to:
  /// **'Pair a MeshCore radio'**
  String get diagnosticsPairRadio;

  /// No description provided for @diagnosticsForgetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this MeshCore radio?'**
  String get diagnosticsForgetConfirmTitle;

  /// No description provided for @diagnosticsForgetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to pair it again, and this clears its bond. Do not do this while the MeshCore radio is out of reach.'**
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
  /// **'Read the MeshCore radio\'s clock'**
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
  /// **'The MeshCore radio did not take it: {error}'**
  String diagnosticsSendFailed(String error);

  /// No description provided for @diagnosticsSectionErrors.
  ///
  /// In en, this message translates to:
  /// **'Failures in the app itself'**
  String get diagnosticsSectionErrors;

  /// No description provided for @diagnosticsErrorsCurrent.
  ///
  /// In en, this message translates to:
  /// **'{count} this run'**
  String diagnosticsErrorsCurrent(int count);

  /// No description provided for @diagnosticsErrorsPrevious.
  ///
  /// In en, this message translates to:
  /// **'{count} in the previous run'**
  String diagnosticsErrorsPrevious(int count);

  /// No description provided for @diagnosticsErrorsNone.
  ///
  /// In en, this message translates to:
  /// **'None recorded.'**
  String get diagnosticsErrorsNone;

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
  /// **'Copy fixture JSON (includes your own message text)'**
  String get diagnosticsCopyFixture;

  /// No description provided for @diagnosticsFixtureCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
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
  /// **'Copy soak results'**
  String get diagnosticsCopySoak;

  /// No description provided for @diagnosticsSoakCopied.
  ///
  /// In en, this message translates to:
  /// **'Soak results copied'**
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

  /// No description provided for @networksEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get networksEdit;

  /// No description provided for @networksTxPower.
  ///
  /// In en, this message translates to:
  /// **'Transmit power'**
  String get networksTxPower;

  /// No description provided for @networksCodingRate.
  ///
  /// In en, this message translates to:
  /// **'Coding rate'**
  String get networksCodingRate;

  /// No description provided for @networksSpreading.
  ///
  /// In en, this message translates to:
  /// **'Spreading factor'**
  String get networksSpreading;

  /// No description provided for @networksBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get networksBandwidth;

  /// No description provided for @networksAdvanced.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio settings'**
  String get networksAdvanced;

  /// No description provided for @networksNameTaken.
  ///
  /// In en, this message translates to:
  /// **'Another network already has this name.'**
  String get networksNameTaken;

  /// No description provided for @networksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No networks yet. A network is the MeshCore radio settings your radios agree on.'**
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
  /// **'Settings the members share'**
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
  /// **'A frequency no preset uses'**
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
  /// **'Apply to this MeshCore radio'**
  String get networksApply;

  /// No description provided for @networksApplyNeedsRadio.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio to apply.'**
  String get networksApplyNeedsRadio;

  /// No description provided for @networksApplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply {name}?'**
  String networksApplyTitle(String name);

  /// No description provided for @networksApplyBodyShared.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio will switch to {summary}.'**
  String networksApplyBodyShared(String summary);

  /// No description provided for @networksApplyBodyIsolated.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio will switch to {summary}. It will stop hearing the public mesh until you switch it back.'**
  String networksApplyBodyIsolated(String summary);

  /// No description provided for @networksApplyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get networksApplyConfirm;

  /// No description provided for @networksApplied.
  ///
  /// In en, this message translates to:
  /// **'The network was applied.'**
  String get networksApplied;

  /// No description provided for @networksApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'The network was not applied: {error}'**
  String networksApplyFailed(String error);

  /// No description provided for @networksCurrent.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio is on this network'**
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
  /// **'Tag'**
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

  /// No description provided for @placeRadioRefused.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio refused'**
  String get placeRadioRefused;

  /// No description provided for @placeChannelTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get placeChannelTitle;

  /// The channel line on a place this device reported.
  ///
  /// In en, this message translates to:
  /// **'Sent on {channel}'**
  String placeSentOn(String channel);

  /// The channel line on a place that arrived from another node.
  ///
  /// In en, this message translates to:
  /// **'Arrived on {channel}'**
  String placeArrivedOn(String channel);

  /// No description provided for @placeImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import a place'**
  String get placeImportAction;

  /// No description provided for @placeImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import a place'**
  String get placeImportTitle;

  /// No description provided for @placeImportExplainer.
  ///
  /// In en, this message translates to:
  /// **'Paste a place somebody shared: a name, a coordinate pair or a map link. Nothing is sent until you choose the type and the life.'**
  String get placeImportExplainer;

  /// No description provided for @placeImportField.
  ///
  /// In en, this message translates to:
  /// **'Shared place'**
  String get placeImportField;

  /// No description provided for @placeImportHint.
  ///
  /// In en, this message translates to:
  /// **'51.50074, -0.12460 or a map link'**
  String get placeImportHint;

  /// No description provided for @placeImportGo.
  ///
  /// In en, this message translates to:
  /// **'Read it'**
  String get placeImportGo;

  /// No description provided for @placeImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to read.'**
  String get placeImportEmpty;

  /// No description provided for @placeImportNoCoordinates.
  ///
  /// In en, this message translates to:
  /// **'No coordinates in that text.'**
  String get placeImportNoCoordinates;

  /// No description provided for @placeImportOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Those coordinates are not on the earth.'**
  String get placeImportOutOfRange;

  /// No description provided for @placeImportLabelCut.
  ///
  /// In en, this message translates to:
  /// **'The name was longer than a report can carry, so it was shortened.'**
  String get placeImportLabelCut;

  /// No description provided for @placeSent.
  ///
  /// In en, this message translates to:
  /// **'Place tagged. It expires on its own.'**
  String get placeSent;

  /// Shown when a place confirmation or refutation was attempted and the radio refused it or the link was down.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio did not take it. Nothing was sent.'**
  String get placeSendFailed;

  /// No description provided for @placeBudgetRefused.
  ///
  /// In en, this message translates to:
  /// **'You have sent {n} in the last hour. The next one can go at {time}.'**
  String placeBudgetRefused(int n, String time);

  /// No description provided for @placeNoIdentity.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio first: a place is tagged as you.'**
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
  /// **'Tagged by {name}, {time}'**
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

  /// No description provided for @placeFenceThis.
  ///
  /// In en, this message translates to:
  /// **'Fence this place'**
  String get placeFenceThis;

  /// No description provided for @placeFenceMade.
  ///
  /// In en, this message translates to:
  /// **'Fenced. {n} in your list.'**
  String placeFenceMade(Object n);

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

  /// No description provided for @placeShareAddress.
  ///
  /// In en, this message translates to:
  /// **'Share the address'**
  String get placeShareAddress;

  /// No description provided for @placeShareSubject.
  ///
  /// In en, this message translates to:
  /// **'A place on the mesh'**
  String get placeShareSubject;

  /// No description provided for @placeShareFailed.
  ///
  /// In en, this message translates to:
  /// **'No app took the address.'**
  String get placeShareFailed;

  /// No description provided for @placeHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Places you saved'**
  String get placeHistoryTitle;

  /// No description provided for @placeHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No places yet. Long-press the map to tag one.'**
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
  /// **'Search label or who tagged it'**
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
  /// **'The MeshCore radio does not support that command. Its firmware is older than this app expects. Update the radio or use a command it lists.'**
  String get failureUnsupportedCommand;

  /// No description provided for @failureNotFound.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio could not find the target: the channel, contact or message is not on it. Refresh the contact list, then retry.'**
  String get failureNotFound;

  /// No description provided for @failureTableFull.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio\'s queue or table is full, so it refused the request. Wait for it to drain, then retry. Nothing was lost.'**
  String get failureTableFull;

  /// No description provided for @failureBadState.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio is busy with another operation and cannot start this one. Wait for the current operation to finish, then retry.'**
  String get failureBadState;

  /// No description provided for @failureFileIoError.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio storage refused the write. Its own log has the detail. Retry once, and if it repeats the radio filesystem needs attention.'**
  String get failureFileIoError;

  /// No description provided for @failureIllegalArgument.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio rejected the value or length as invalid. Check the field you changed: one value is outside what this firmware accepts.'**
  String get failureIllegalArgument;

  /// No description provided for @failureUnknownDeviceError.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused the request without a reason this app knows. The diagnostics page shows the raw frame.'**
  String get failureUnknownDeviceError;

  /// No description provided for @failureBlePermissions.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission was refused, so the app cannot reach the MeshCore radio. Allow Nearby devices for this app in Android settings, then reconnect.'**
  String get failureBlePermissions;

  /// No description provided for @failureBluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off. Turn it on, then reconnect.'**
  String get failureBluetoothOff;

  /// No description provided for @failureNoRadioFound.
  ///
  /// In en, this message translates to:
  /// **'No MeshCore radio answered the scan. Check that it is powered on, in range, and not already connected to another phone.'**
  String get failureNoRadioFound;

  /// No description provided for @failurePairingFailed.
  ///
  /// In en, this message translates to:
  /// **'The pairing did not complete. Enter the PIN shown on the MeshCore radio screen (screenless radios use 123456), then retry.'**
  String get failurePairingFailed;

  /// No description provided for @failureStalePairing.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio no longer holds this pairing. Forget it in Android Bluetooth settings, power-cycle the radio, then pair again.'**
  String get failureStalePairing;

  /// No description provided for @failurePairingNotKept.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio paired but could not encrypt on the next connection, so the pairing is not kept. Power-cycle it and pair again. If it repeats, the fault is in the radio.'**
  String get failurePairingNotKept;

  /// Recovery action shown when the radio cannot keep a Bluetooth bond: forgets the OS pairing so the next scan pairs from scratch.
  ///
  /// In en, this message translates to:
  /// **'Forget this MeshCore radio and start again'**
  String get connectForgetRadio;

  /// No description provided for @failureServiceMissing.
  ///
  /// In en, this message translates to:
  /// **'This device does not expose the MeshCore service, so it is probably not a MeshCore radio.'**
  String get failureServiceMissing;

  /// No description provided for @failureCharacteristicMissing.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio\'s link is missing a characteristic the app needs. Its firmware may be older than this app expects.'**
  String get failureCharacteristicMissing;

  /// No description provided for @failureMtuTooSmall.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio link is {mtu} bytes and a full frame needs {need}. Some firmware asks for the smaller size itself, so it cannot carry the largest frames: try newer firmware, or reconnect.'**
  String failureMtuTooSmall(String mtu, String need);

  /// No description provided for @failureFrameTruncated.
  ///
  /// In en, this message translates to:
  /// **'Part of a message did not arrive. The count is in Diagnostics.'**
  String get failureFrameTruncated;

  /// No description provided for @failureFrameTrailingBytes.
  ///
  /// In en, this message translates to:
  /// **'A message carried extra bytes at the end. They were dropped. The count is in Diagnostics.'**
  String get failureFrameTrailingBytes;

  /// No description provided for @failureStorageFull.
  ///
  /// In en, this message translates to:
  /// **'The phone refused a write because storage is full. Nothing is being deleted silently. Free space and the history stays as it is.'**
  String get failureStorageFull;

  /// No description provided for @failureRadioSilent.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio accepted the request but did not answer in time. It may still have carried it out. Check the radio before retrying.'**
  String get failureRadioSilent;

  /// No description provided for @diagnosticsRadioChangedLine.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio is not the one this app last used ({previous} then, {current} now). Your history, tags, favourites and blocks stay. They belong to the app. Contacts, channels and radio settings come from the radio, so they are this one\'s.'**
  String diagnosticsRadioChangedLine(String previous, String current);

  /// No description provided for @diagnosticsRadioChangedAccept.
  ///
  /// In en, this message translates to:
  /// **'This is my MeshCore radio'**
  String get diagnosticsRadioChangedAccept;

  /// No description provided for @failureAirtimeBudget.
  ///
  /// In en, this message translates to:
  /// **'This phone has used its own MeshCore radio time limit for the last hour, so nothing was sent. It sends again as the hour rolls on.'**
  String get failureAirtimeBudget;

  /// No description provided for @failureLinkTimeout.
  ///
  /// In en, this message translates to:
  /// **'The phone did not finish opening the MeshCore radio link in time. Nothing was sent. Retry to open it again.'**
  String get failureLinkTimeout;

  /// No description provided for @diagnosticsHandshakeLine.
  ///
  /// In en, this message translates to:
  /// **'link handshakes: {started} started, {timedOut} with no answer'**
  String diagnosticsHandshakeLine(String started, String timedOut);

  /// No description provided for @diagnosticsLinkCloseLine.
  ///
  /// In en, this message translates to:
  /// **'link teardowns that did not finish: {count}'**
  String diagnosticsLinkCloseLine(String count);

  /// No description provided for @airtimeSpentLine.
  ///
  /// In en, this message translates to:
  /// **'LoRa radio time this hour: {spent} of {budget}'**
  String airtimeSpentLine(String spent, String budget);

  /// No description provided for @airtimeSpentLineUnlimited.
  ///
  /// In en, this message translates to:
  /// **'LoRa radio time this hour: {spent}, with no limit set'**
  String airtimeSpentLineUnlimited(String spent);

  /// No description provided for @airtimeRefusedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 send refused by the limit} other{{count} sends refused by the limit}}'**
  String airtimeRefusedCount(int count);

  /// No description provided for @airtimeCutoffTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop at the limit'**
  String get airtimeCutoffTitle;

  /// No description provided for @airtimeCutoffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Refuse over-budget sends'**
  String get airtimeCutoffSubtitle;

  /// No description provided for @airtimeLeftInHour.
  ///
  /// In en, this message translates to:
  /// **'Time left this hour'**
  String get airtimeLeftInHour;

  /// No description provided for @airtimeLeftValue.
  ///
  /// In en, this message translates to:
  /// **'\$left of \$budget'**
  String airtimeLeftValue(String left, String budget);

  /// No description provided for @airtimeCutoffOff.
  ///
  /// In en, this message translates to:
  /// **'The meter still counts. Nothing is refused.'**
  String get airtimeCutoffOff;

  /// No description provided for @settingsAirtimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Transmit time limit'**
  String get settingsAirtimeTitle;

  /// No description provided for @settingsAirtimeHelp.
  ///
  /// In en, this message translates to:
  /// **'Every frame this app sends counts. At the limit it stops until the hour turns over.'**
  String get settingsAirtimeHelp;

  /// No description provided for @airtimePolicyOnePercent.
  ///
  /// In en, this message translates to:
  /// **'1 % duty cycle'**
  String get airtimePolicyOnePercent;

  /// No description provided for @airtimePolicyOnePercentSub.
  ///
  /// In en, this message translates to:
  /// **'36 seconds of sending per hour. The legal limit in the EU and UK.'**
  String get airtimePolicyOnePercentSub;

  /// No description provided for @airtimePolicyOwned.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get airtimePolicyOwned;

  /// No description provided for @airtimePolicyOwnedSub.
  ///
  /// In en, this message translates to:
  /// **'For a channel you own, where nobody else uses the frequency.'**
  String get airtimePolicyOwnedSub;

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
  /// **'This phone refused a write because storage is full. Nothing was deleted to make room. Free space and history continues.'**
  String get degradedStorageFull;

  /// No description provided for @degradedClockUnset.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio\'s clock has never been set, so times it reports are shown as time unknown until it is.'**
  String get degradedClockUnset;

  /// No description provided for @degradedBatteryCritical.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio\'s battery is low enough that its transmissions may be cut. Charge it before relying on a long send.'**
  String get degradedBatteryCritical;

  /// No description provided for @degradedRadioAbsent.
  ///
  /// In en, this message translates to:
  /// **'No MeshCore radio is connected. Everything already received stays readable. Sending, telemetry and places wait until one connects.'**
  String get degradedRadioAbsent;

  /// No description provided for @degradedRadioSilent.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio is paired but has not answered. It may still have carried out the last request. Check the radio before retrying.'**
  String get degradedRadioSilent;

  /// No description provided for @degradedNoLocation.
  ///
  /// In en, this message translates to:
  /// **'Location is off, so distances, bearings and place tags cannot be worked out. Everything else works.'**
  String get degradedNoLocation;

  /// No description provided for @degradedMapOffline.
  ///
  /// In en, this message translates to:
  /// **'Map tiles cannot be fetched. The bundled basemap and anything already on disk still draw.'**
  String get degradedMapOffline;

  /// No description provided for @sosTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get sosTitle;

  /// No description provided for @sosEntryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Emergency alarm'**
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
  /// **'Nobody is notified unless they are in LoRa radio range.'**
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
  /// **'Released too early. Nothing was sent.'**
  String get sosHoldReleased;

  /// No description provided for @sosNoIdentity.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio has not reported a name yet, so the alarm has no name to send.'**
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
  /// **'The MeshCore radio repeats each message once, about two minutes later. If the app closes, the rest stops.'**
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

  /// Ended panel after I'm safe, when the [SAFE] left the phone.
  ///
  /// In en, this message translates to:
  /// **'Your safe message was sent.'**
  String get sosSafeSent;

  /// Ended panel after I'm safe, when the radio refused it or there was no link.
  ///
  /// In en, this message translates to:
  /// **'Your safe message did not leave this phone. The repeats have stopped here, but nobody was told you are safe.'**
  String get sosSafeNotSent;

  /// Running panel, when the alarm was restored from disk after a restart.
  ///
  /// In en, this message translates to:
  /// **'This alarm was running when the app last closed. What is left of the hour continues. Repeats missed while the app was closed were not sent.'**
  String get sosResumed;

  /// Running panel, honest limit of a one-second timer under Doze.
  ///
  /// In en, this message translates to:
  /// **'Repeats are best effort while the phone sleeps: a delayed tick sends the most recent one, not a burst.'**
  String get sosBestEffort;

  /// Active alarm: at least one repeat did not leave the radio.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused a repeat. The schedule continues.'**
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

  /// No description provided for @checkinIntro.
  ///
  /// In en, this message translates to:
  /// **'One message with a deadline. The app marks it overdue here. The MeshCore radio keeps no timer.'**
  String get checkinIntro;

  /// No description provided for @checkinDeadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get checkinDeadline;

  /// A deadline choice in minutes; the section header above already says what the number is.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String checkinMinutes(int minutes);

  /// No description provided for @checkinSend.
  ///
  /// In en, this message translates to:
  /// **'Send check-in'**
  String get checkinSend;

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
  /// **'Overdue. The deadline passed and no answer came back.'**
  String get checkinOverdue;

  /// No description provided for @checkinAnsweredDirect.
  ///
  /// In en, this message translates to:
  /// **'Answered, by direct message.'**
  String get checkinAnsweredDirect;

  /// No description provided for @checkinAnsweredChannel.
  ///
  /// In en, this message translates to:
  /// **'Answered on the channel by name only, so the app cannot prove who it was.'**
  String get checkinAnsweredChannel;

  /// No description provided for @checkinSent.
  ///
  /// In en, this message translates to:
  /// **'Check-in sent. Nothing repeats.'**
  String get checkinSent;

  /// No description provided for @checkinNeedsRadio.
  ///
  /// In en, this message translates to:
  /// **'A check-in needs a connected MeshCore radio and its name.'**
  String get checkinNeedsRadio;

  /// No description provided for @photoAnnounceLoad.
  ///
  /// In en, this message translates to:
  /// **'Load · {n} packets'**
  String photoAnnounceLoad(Object n);

  /// No description provided for @photoAnnouncePreviewOnly.
  ///
  /// In en, this message translates to:
  /// **'Preview only'**
  String get photoAnnouncePreviewOnly;

  /// No description provided for @photoAnnounceLoaded.
  ///
  /// In en, this message translates to:
  /// **'Loaded'**
  String get photoAnnounceLoaded;

  /// No description provided for @photoAnnounceTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photoAnnounceTitle;

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

  /// No description provided for @mediaInterruptedEarlier.
  ///
  /// In en, this message translates to:
  /// **'An earlier photo did not finish sending.'**
  String get mediaInterruptedEarlier;

  /// No description provided for @mediaInterruptedDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get mediaInterruptedDismiss;

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
  /// **'The MeshCore radio accepted these packets. A broadcast carries no delivery promise.'**
  String get mediaAcceptedNotDelivered;

  /// No description provided for @mediaSendFailed.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused {count} packet(s), so this photo did not finish.'**
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

  /// No description provided for @mediaFullPictureOnChannel.
  ///
  /// In en, this message translates to:
  /// **'A picture is announced with one small preview and then sent to one person who asks for it. It is never broadcast to a channel.'**
  String get mediaFullPictureOnChannel;

  /// No description provided for @mediaOffOnPublic.
  ///
  /// In en, this message translates to:
  /// **'Media stays off on the Public channel. Send it on a private channel instead.'**
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

  /// No description provided for @mediaReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos received'**
  String get mediaReceivedTitle;

  /// No description provided for @mediaReceivedKept.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo, kept until the app closes} other{{count} photos, kept until the app closes}}'**
  String mediaReceivedKept(int count);

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
  /// **'Photo not fetched. The entry itself is complete. The picture is optional and may never arrive.'**
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

  /// No description provided for @geofenceCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Draw a fence here'**
  String get geofenceCreateTitle;

  /// No description provided for @geofenceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get geofenceNameLabel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @geofenceEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Change this fence'**
  String get geofenceEditTitle;

  /// No description provided for @geofenceEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit fence'**
  String get geofenceEdit;

  /// No description provided for @geofenceReshape.
  ///
  /// In en, this message translates to:
  /// **'Reshape on the map'**
  String get geofenceReshape;

  /// No description provided for @geofenceReshapeStarted.
  ///
  /// In en, this message translates to:
  /// **'Drag a corner, then Save. Cancel keeps the old shape.'**
  String get geofenceReshapeStarted;

  /// No description provided for @geofenceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search fences'**
  String get geofenceSearchHint;

  /// No description provided for @geofenceNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No fence has that name.'**
  String get geofenceNoMatches;

  /// No description provided for @geofenceShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all on the map'**
  String get geofenceShowAll;

  /// No description provided for @geofenceFocused.
  ///
  /// In en, this message translates to:
  /// **'Opened from the map'**
  String get geofenceFocused;

  /// No description provided for @geofenceCornerHandle.
  ///
  /// In en, this message translates to:
  /// **'Corner {n}, drag to move'**
  String geofenceCornerHandle(int n);

  /// No description provided for @geofenceCorners.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 corner} other{{n} corners}}'**
  String geofenceCorners(int n);

  /// No description provided for @geofenceCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'Save this fence'**
  String get geofenceCanvasTitle;

  /// No description provided for @geofenceDrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Draw a fence'**
  String get geofenceDrawTitle;

  /// No description provided for @geofenceDrawHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to add a corner. Drag a corner to move it.'**
  String get geofenceDrawHint;

  /// No description provided for @geofenceDrawDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get geofenceDrawDone;

  /// No description provided for @geofenceDrawCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get geofenceDrawCancel;

  /// No description provided for @geofenceDrawNeedThree.
  ///
  /// In en, this message translates to:
  /// **'A fence needs at least three corners.'**
  String get geofenceDrawNeedThree;

  /// No description provided for @geofenceDrawStarted.
  ///
  /// In en, this message translates to:
  /// **'Drawing a fence.'**
  String get geofenceDrawStarted;

  /// No description provided for @geofenceDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this fence?'**
  String get geofenceDeleteConfirmTitle;

  /// No description provided for @geofenceDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Its crossings go with it. The area itself is not changed.'**
  String get geofenceDeleteConfirmBody;

  /// No description provided for @geofenceClearLogConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the crossing log?'**
  String get geofenceClearLogConfirmTitle;

  /// No description provided for @geofenceClearLogConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every recorded crossing is deleted. The fences stay.'**
  String get geofenceClearLogConfirmBody;

  /// No description provided for @geofenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Geofences'**
  String get geofenceTitle;

  /// No description provided for @geofenceExplainer.
  ///
  /// In en, this message translates to:
  /// **'A fence is an area you watch. It tells you once when you enter and once when you leave, so walking along its edge does not produce a stream of alerts.'**
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
  /// **'A fence needs your position. Connect the MeshCore radio or allow location first.'**
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

  /// No description provided for @geofenceSaveAsPlace.
  ///
  /// In en, this message translates to:
  /// **'Save as a place'**
  String get geofenceSaveAsPlace;

  /// No description provided for @geofenceClearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get geofenceClearLog;

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
  /// **'Arrive and leave alerts'**
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
  /// **'This app paces its own pings. It cannot promise other devices do.'**
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
  /// **'{count} answers drawn. Answers only, never an inferred link'**
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
  /// **'One file with the trail, places, answered pings and the check-in. Plain JSON, not encrypted, so it can be handed on.'**
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
  /// **'Record written, path copied'**
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
  /// **'No trail recorded yet'**
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

  /// No description provided for @settingsHistoryExportRow.
  ///
  /// In en, this message translates to:
  /// **'Export all history'**
  String get settingsHistoryExportRow;

  /// No description provided for @settingsHistoryExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One encrypted file, all conversations'**
  String get settingsHistoryExportSubtitle;

  /// No description provided for @settingsHistoryExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Passphrase for the backup'**
  String get settingsHistoryExportTitle;

  /// No description provided for @settingsHistoryExportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsHistoryExportConfirm;

  /// No description provided for @settingsHistoryExportShared.
  ///
  /// In en, this message translates to:
  /// **'History ready to share.'**
  String get settingsHistoryExportShared;

  /// No description provided for @settingsHistoryExportDone.
  ///
  /// In en, this message translates to:
  /// **'History saved to {path}'**
  String settingsHistoryExportDone(String path);

  /// No description provided for @settingsHistoryExportEmpty.
  ///
  /// In en, this message translates to:
  /// **'There is no history to export yet.'**
  String get settingsHistoryExportEmpty;

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
  /// **'Blocked people'**
  String get blockedKeysTitle;

  /// No description provided for @blockedKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No key is blocked} =1{1 key blocked} other{{count} keys blocked}}'**
  String blockedKeysSubtitle(int count);

  /// No description provided for @blockedKeysEmpty.
  ///
  /// In en, this message translates to:
  /// **'No key is blocked. Blocking a key hides what it sends, which is messages, notifications and places, on this device.'**
  String get blockedKeysEmpty;

  /// No description provided for @blockedKeysCannotStopShort.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get blockedKeysCannotStopShort;

  /// No description provided for @blockedKeysCannotStop.
  ///
  /// In en, this message translates to:
  /// **'A block is local to this app. The MeshCore radio still receives and relays the packet. What stops is what this app shows.'**
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
  /// **'Export…'**
  String get reportAction;

  /// No description provided for @reportSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Export this message'**
  String get reportSheetTitle;

  /// No description provided for @reportObservationLabel.
  ///
  /// In en, this message translates to:
  /// **'What did you see? (optional)'**
  String get reportObservationLabel;

  /// No description provided for @reportNothingSent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent. The app wrote a file on this device. You decide where it goes.'**
  String get reportNothingSent;

  /// No description provided for @reportBundleWritten.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String reportBundleWritten(String path);

  /// No description provided for @reportShareBundle.
  ///
  /// In en, this message translates to:
  /// **'Share the file'**
  String get reportShareBundle;

  /// No description provided for @reportCopyBundle.
  ///
  /// In en, this message translates to:
  /// **'Copy the file'**
  String get reportCopyBundle;

  /// No description provided for @reportCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get reportCopied;

  /// No description provided for @blockedKeysNotPersisted.
  ///
  /// In en, this message translates to:
  /// **'This list could not be saved on this device. It filters for now and will be empty after a restart.'**
  String get blockedKeysNotPersisted;

  /// No description provided for @blockedKeysUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The saved list could not be read, so nothing is blocked right now. A copy of the damaged file is kept. New blocks save normally.'**
  String get blockedKeysUnreadable;

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
  /// **'Report a place here'**
  String get mapReportPlace;

  /// No description provided for @settingsAppGroupRadio.
  ///
  /// In en, this message translates to:
  /// **'Connection & background'**
  String get settingsAppGroupRadio;

  /// No description provided for @settingsAppGroupReading.
  ///
  /// In en, this message translates to:
  /// **'Units and time'**
  String get settingsAppGroupReading;

  /// No description provided for @settingsUnits.
  ///
  /// In en, this message translates to:
  /// **'Distance units'**
  String get settingsUnits;

  /// No description provided for @settingsUnitsMetric.
  ///
  /// In en, this message translates to:
  /// **'Metres and kilometres'**
  String get settingsUnitsMetric;

  /// No description provided for @settingsUnitsMetricHint.
  ///
  /// In en, this message translates to:
  /// **'What the MeshCore radio reports'**
  String get settingsUnitsMetricHint;

  /// No description provided for @settingsUnitsImperial.
  ///
  /// In en, this message translates to:
  /// **'Feet and miles'**
  String get settingsUnitsImperial;

  /// No description provided for @settingsUnitsImperialHint.
  ///
  /// In en, this message translates to:
  /// **'Converted from MeshCore radio metres'**
  String get settingsUnitsImperialHint;

  /// No description provided for @settingsClock24.
  ///
  /// In en, this message translates to:
  /// **'24-hour clock'**
  String get settingsClock24;

  /// No description provided for @settingsClock24On.
  ///
  /// In en, this message translates to:
  /// **'14:32'**
  String get settingsClock24On;

  /// No description provided for @settingsClock12On.
  ///
  /// In en, this message translates to:
  /// **'2:32 PM'**
  String get settingsClock12On;

  /// No description provided for @settingsCelsius.
  ///
  /// In en, this message translates to:
  /// **'Celsius'**
  String get settingsCelsius;

  /// No description provided for @settingsCelsiusOn.
  ///
  /// In en, this message translates to:
  /// **'21 °C'**
  String get settingsCelsiusOn;

  /// No description provided for @settingsFahrenheitOn.
  ///
  /// In en, this message translates to:
  /// **'70 °F'**
  String get settingsFahrenheitOn;

  /// No description provided for @settingsAppGroupSound.
  ///
  /// In en, this message translates to:
  /// **'Reading and sound'**
  String get settingsAppGroupSound;

  /// No description provided for @settingsPhotoColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Send photos in colour'**
  String get settingsPhotoColorTitle;

  /// No description provided for @codecUnavailableHere.
  ///
  /// In en, this message translates to:
  /// **'Not in this build yet'**
  String get codecUnavailableHere;

  /// No description provided for @codecLicence.
  ///
  /// In en, this message translates to:
  /// **'MIT · zjs81/aeic-se-onnx'**
  String get codecLicence;

  /// No description provided for @codecCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get codecCancel;

  /// No description provided for @codecRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get codecRetry;

  /// No description provided for @codecFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get codecFailed;

  /// No description provided for @codecRemove.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get codecRemove;

  /// No description provided for @codecInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get codecInstalled;

  /// No description provided for @codecDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get codecDownload;

  /// No description provided for @codecNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed · about 1 GB'**
  String get codecNotInstalled;

  /// No description provided for @codecTitle.
  ///
  /// In en, this message translates to:
  /// **'Neural image codec'**
  String get codecTitle;

  /// No description provided for @photoModeNeedsCodec.
  ///
  /// In en, this message translates to:
  /// **'Needs the neural codec'**
  String get photoModeNeedsCodec;

  /// No description provided for @photoModeOnRequest.
  ///
  /// In en, this message translates to:
  /// **'Full picture on request'**
  String get photoModeOnRequest;

  /// No description provided for @photoModePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview only'**
  String get photoModePreview;

  /// No description provided for @photoModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo mode'**
  String get photoModeTitle;

  /// No description provided for @photoModeSettings.
  ///
  /// In en, this message translates to:
  /// **'Photo settings'**
  String get photoModeSettings;

  /// No description provided for @photoModeLinePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview only · pixels stay here'**
  String get photoModeLinePreview;

  /// No description provided for @photoModeLine.
  ///
  /// In en, this message translates to:
  /// **'{mode} · {cost}'**
  String photoModeLine(String mode, String cost);

  /// No description provided for @photoSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photoSettingsTitle;

  /// No description provided for @chatMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat & photos'**
  String get chatMediaTitle;

  /// No description provided for @chatMediaMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get chatMediaMessages;

  /// No description provided for @chatMediaRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'The newest {count} messages per channel.'**
  String chatMediaRetentionBody(int count);

  /// No description provided for @chatMediaRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'History kept'**
  String get chatMediaRetentionTitle;

  /// No description provided for @settingsPhotoColorSub.
  ///
  /// In en, this message translates to:
  /// **'Grey: one third the data'**
  String get settingsPhotoColorSub;

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
  /// **'MeshCore radio diagnostics'**
  String get toolsGroupDiagnostics;

  /// No description provided for @nodeMarkerSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}. Tap for details'**
  String nodeMarkerSemantics(String name);

  /// No description provided for @placePinSemantics.
  ///
  /// In en, this message translates to:
  /// **'{label}, {expiry}'**
  String placePinSemantics(String label, String expiry);

  /// No description provided for @placePinSemanticsUnkeyed.
  ///
  /// In en, this message translates to:
  /// **'{label}, {expiry}. Sent from a channel name, so anyone with the channel could have written it.'**
  String placePinSemanticsUnkeyed(String label, String expiry);

  /// No description provided for @placeUnkeyedShort.
  ///
  /// In en, this message translates to:
  /// **'name only'**
  String get placeUnkeyedShort;

  /// No description provided for @placeClusterSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count} places here'**
  String placeClusterSemantics(int count);

  /// No description provided for @mapCanvasSemantics.
  ///
  /// In en, this message translates to:
  /// **'Tap a marker to open'**
  String get mapCanvasSemantics;

  /// No description provided for @gridLegendSignalOnly.
  ///
  /// In en, this message translates to:
  /// **'Hollow · no position'**
  String get gridLegendSignalOnly;

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

  /// No description provided for @gridCompassCalibrating.
  ///
  /// In en, this message translates to:
  /// **'Flip the phone end over end a few times to calibrate.'**
  String get gridCompassCalibrating;

  /// No description provided for @gridCompassLowAccuracy.
  ///
  /// In en, this message translates to:
  /// **'The compass is weak here. Flip the phone end over end a few times.'**
  String get gridCompassLowAccuracy;

  /// No description provided for @gridCompassDisturbed.
  ///
  /// In en, this message translates to:
  /// **'No heading, the magnetic field here is too strong. Move away from magnets and flip the phone end over end a few times.'**
  String get gridCompassDisturbed;

  /// No description provided for @gridPurposeRadial.
  ///
  /// In en, this message translates to:
  /// **'How far each node is, and how long ago it was heard.'**
  String get gridPurposeRadial;

  /// No description provided for @gridPurposeWeather.
  ///
  /// In en, this message translates to:
  /// **'Temperature, humidity and pressure, from nodes that report them.'**
  String get gridPurposeWeather;

  /// No description provided for @gridPurposeTree.
  ///
  /// In en, this message translates to:
  /// **'How nodes reach each other, from the routes they advertise.'**
  String get gridPurposeTree;

  /// No description provided for @gridPurposeSnsCells.
  ///
  /// In en, this message translates to:
  /// **'Where messages came from, cooling over the last hour.'**
  String get gridPurposeSnsCells;

  /// No description provided for @gridPurposeElevation.
  ///
  /// In en, this message translates to:
  /// **'How high each node is, against landmarks.'**
  String get gridPurposeElevation;

  /// No description provided for @mapNoPositionYet.
  ///
  /// In en, this message translates to:
  /// **'Your position is not known yet.'**
  String get mapNoPositionYet;

  /// No description provided for @mapNoPositionFind.
  ///
  /// In en, this message translates to:
  /// **'Find me'**
  String get mapNoPositionFind;

  /// No description provided for @mapNoPositionAsking.
  ///
  /// In en, this message translates to:
  /// **'Finding you..'**
  String get mapNoPositionAsking;

  /// No description provided for @mapLocationOffApp.
  ///
  /// In en, this message translates to:
  /// **'Location is off for this app.'**
  String get mapLocationOffApp;

  /// No description provided for @mapLocationAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow location'**
  String get mapLocationAllow;

  /// No description provided for @mapLocationBlockedApp.
  ///
  /// In en, this message translates to:
  /// **'Location is blocked for this app.'**
  String get mapLocationBlockedApp;

  /// No description provided for @mapLocationOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get mapLocationOpenSettings;

  /// No description provided for @mapLocationOffDevice.
  ///
  /// In en, this message translates to:
  /// **'Location is off on this phone.'**
  String get mapLocationOffDevice;

  /// No description provided for @weatherOpenTelemetrySettings.
  ///
  /// In en, this message translates to:
  /// **'Turn on node telemetry'**
  String get weatherOpenTelemetrySettings;

  /// No description provided for @chatNoRadio.
  ///
  /// In en, this message translates to:
  /// **'No MeshCore radio connected'**
  String get chatNoRadio;

  /// No description provided for @chatConnectRadio.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio'**
  String get chatConnectRadio;

  /// No description provided for @chatConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get chatConnecting;

  /// No description provided for @chatBudgetEstimateNear.
  ///
  /// In en, this message translates to:
  /// **'~{remaining} left'**
  String chatBudgetEstimateNear(int remaining);

  /// No description provided for @chatMetaFlood.
  ///
  /// In en, this message translates to:
  /// **'via flood'**
  String get chatMetaFlood;

  /// No description provided for @chatMetaSnr.
  ///
  /// In en, this message translates to:
  /// **'SNR {snr} dB'**
  String chatMetaSnr(String snr);

  /// No description provided for @chatMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get chatMoreActions;

  /// No description provided for @dmKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Peer key copied'**
  String get dmKeyCopied;

  /// No description provided for @channelsInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'How channels work'**
  String get channelsInfoTooltip;

  /// No description provided for @channelsOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Notifications and behaviour'**
  String get channelsOptionsTooltip;

  /// No description provided for @sosSafeUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed. The link dropped while sending, so this may or may not have been heard.'**
  String get sosSafeUnconfirmed;

  /// No description provided for @sosSendUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One repeat was not confirmed. The schedule continues.} other{{count} repeats were not confirmed. The schedule continues.}}'**
  String sosSendUnconfirmed(int count);

  /// No description provided for @rawRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a raw record'**
  String get rawRecordTitle;

  /// No description provided for @rawRecordHelp.
  ///
  /// In en, this message translates to:
  /// **'One record to one contact, addressed over its route. The MeshCore radio answers OK or ERR. The peer sends nothing back.'**
  String get rawRecordHelp;

  /// No description provided for @rawRecordNoContact.
  ///
  /// In en, this message translates to:
  /// **'No contact has a direct route yet. A raw record is addressed, not flooded.'**
  String get rawRecordNoContact;

  /// No description provided for @rawRecordBytes.
  ///
  /// In en, this message translates to:
  /// **'Bytes (hex)'**
  String get rawRecordBytes;

  /// No description provided for @rawRecordEmpty.
  ///
  /// In en, this message translates to:
  /// **'Type the bytes to send.'**
  String get rawRecordEmpty;

  /// No description provided for @rawRecordNotHex.
  ///
  /// In en, this message translates to:
  /// **'Not hex: use pairs such as 01 02 ab, or one run such as 0102ab.'**
  String get rawRecordNotHex;

  /// No description provided for @rawRecordTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least {min} bytes: the firmware drops anything shorter.'**
  String rawRecordTooShort(String min);

  /// No description provided for @rawRecordTooLong.
  ///
  /// In en, this message translates to:
  /// **'Over this contact\'s {max}-byte budget.'**
  String rawRecordTooLong(String max);

  /// No description provided for @rawRecordBudget.
  ///
  /// In en, this message translates to:
  /// **'Frame {frame} bytes · this route leaves {max} for the record · typed {typed}'**
  String rawRecordBudget(String frame, String max, String typed);

  /// No description provided for @rawRecordNotReady.
  ///
  /// In en, this message translates to:
  /// **'No MeshCore radio connected.'**
  String get rawRecordNotReady;

  /// No description provided for @rawRecordSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get rawRecordSending;

  /// No description provided for @rawRecordConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Send these bytes?'**
  String get rawRecordConfirmTitle;

  /// No description provided for @rawRecordConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The app cannot check what these bytes do. {name} receives {count} bytes as one record, and the MeshCore radio answers OK or ERR.'**
  String rawRecordConfirmBody(String name, String count);

  /// No description provided for @rawRecordSent.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio accepted it. This is not delivery: a raw record carries no receipt from the peer.'**
  String get rawRecordSent;

  /// No description provided for @rawRecordRefused.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused it: {reason} (code {code}).'**
  String rawRecordRefused(String reason, String code);

  /// No description provided for @rawRecordNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer in {seconds} s. The MeshCore radio may have sent it anyway.'**
  String rawRecordNoAnswer(String seconds);

  /// No description provided for @rawRecordNoRoute.
  ///
  /// In en, this message translates to:
  /// **'{name} has no direct route now, and a raw record cannot be flooded.'**
  String rawRecordNoRoute(String name);

  /// No description provided for @placeSuggestLooksLike.
  ///
  /// In en, this message translates to:
  /// **'Looks like a place: {name}'**
  String placeSuggestLooksLike(String name);

  /// No description provided for @placeSuggestReport.
  ///
  /// In en, this message translates to:
  /// **'Tag place'**
  String get placeSuggestReport;

  /// No description provided for @placeSuggestDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get placeSuggestDismiss;

  /// No description provided for @placeSuggestNeedsLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on location to tag a place.'**
  String get placeSuggestNeedsLocation;

  /// No description provided for @diagnosticsPosition.
  ///
  /// In en, this message translates to:
  /// **'Position, as the app sees it'**
  String get diagnosticsPosition;

  /// No description provided for @diagnosticsPositionRadio.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio {lat}, {lon}'**
  String diagnosticsPositionRadio(Object lat, Object lon);

  /// No description provided for @diagnosticsPositionPolicy.
  ///
  /// In en, this message translates to:
  /// **'advert policy {policy}'**
  String diagnosticsPositionPolicy(Object policy);

  /// No description provided for @diagnosticsPositionPhone.
  ///
  /// In en, this message translates to:
  /// **'phone fix {source}'**
  String diagnosticsPositionPhone(Object source);

  /// No description provided for @diagnosticsPositionNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get diagnosticsPositionNone;

  /// No description provided for @sosWordsOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional. The default is used if you clear it.'**
  String get sosWordsOptional;

  /// No description provided for @sosHoldSummary.
  ///
  /// In en, this message translates to:
  /// **'Hold to send the words above to {channel}, with your name and position.'**
  String sosHoldSummary(Object channel);

  /// No description provided for @sosUseDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset the destination'**
  String get sosUseDefaults;

  /// No description provided for @wxMicroclimateFromChat.
  ///
  /// In en, this message translates to:
  /// **'Read from this channel\'s messages. Newest {ago}.'**
  String wxMicroclimateFromChat(Object ago);

  /// No description provided for @wxMicroclimateFromChatNoMessages.
  ///
  /// In en, this message translates to:
  /// **'Nothing measured yet: this reads reports people write in this channel, and only ones with a number and a unit.'**
  String get wxMicroclimateFromChatNoMessages;

  /// No description provided for @elevationAskNodes.
  ///
  /// In en, this message translates to:
  /// **'Ask nodes for altitude'**
  String get elevationAskNodes;

  /// No description provided for @elevationAsking.
  ///
  /// In en, this message translates to:
  /// **'Asking…'**
  String get elevationAsking;

  /// No description provided for @elevationNotADistance.
  ///
  /// In en, this message translates to:
  /// **'Dots line up side to side, not by distance.'**
  String get elevationNotADistance;

  /// No description provided for @elevationAltitudesFrom.
  ///
  /// In en, this message translates to:
  /// **'Each height is that node\'s own telemetry. Yours is the phone\'s GPS.'**
  String get elevationAltitudesFrom;

  /// No description provided for @meshbookEmptyDetail.
  ///
  /// In en, this message translates to:
  /// **'Messages on this channel fill it. The window is the last 24 hours.'**
  String get meshbookEmptyDetail;

  /// No description provided for @locTriggerManual.
  ///
  /// In en, this message translates to:
  /// **'you asked'**
  String get locTriggerManual;

  /// No description provided for @locTriggerPeriodic.
  ///
  /// In en, this message translates to:
  /// **'on the timer'**
  String get locTriggerPeriodic;

  /// No description provided for @locTriggerMovement.
  ///
  /// In en, this message translates to:
  /// **'you moved'**
  String get locTriggerMovement;

  /// No description provided for @pingLostMeaning.
  ///
  /// In en, this message translates to:
  /// **'Lost means no answer within the time the MeshCore radio estimated for the reply. A node that ignores requests and one that is asleep look the same.'**
  String get pingLostMeaning;

  /// No description provided for @contactFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Name or key prefix'**
  String get contactFilterHint;

  /// No description provided for @contactFilterNone.
  ///
  /// In en, this message translates to:
  /// **'No contact matches that.'**
  String get contactFilterNone;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @storageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageTitle;

  /// No description provided for @storageMaps.
  ///
  /// In en, this message translates to:
  /// **'Map data {used} MB of {budget} MB'**
  String storageMaps(String used, String budget);

  /// No description provided for @storageMapsSplit.
  ///
  /// In en, this message translates to:
  /// **'Cached tiles {view} MB · downloaded regions {packs} MB'**
  String storageMapsSplit(String view, String packs);

  /// No description provided for @storageMapsUnknown.
  ///
  /// In en, this message translates to:
  /// **'Map data is not open in this session'**
  String get storageMapsUnknown;

  /// No description provided for @storageClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cached tiles'**
  String get storageClearCache;

  /// No description provided for @storageCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cached tiles cleared. Downloaded regions are kept.'**
  String get storageCacheCleared;

  /// No description provided for @storageHistory.
  ///
  /// In en, this message translates to:
  /// **'Message history {kb} KB, sealed'**
  String storageHistory(String kb);

  /// No description provided for @storagePlaces.
  ///
  /// In en, this message translates to:
  /// **'Places {n} of {cap}'**
  String storagePlaces(int n, int cap);

  /// No description provided for @storageTrail.
  ///
  /// In en, this message translates to:
  /// **'Trail {n} points of {cap}, seven days'**
  String storageTrail(int n, int cap);

  /// No description provided for @storageMedia.
  ///
  /// In en, this message translates to:
  /// **'Unfinished media transfers {n}'**
  String storageMedia(int n);

  /// No description provided for @storageClearAll.
  ///
  /// In en, this message translates to:
  /// **'Delete everything the app kept'**
  String get storageClearAll;

  /// No description provided for @storageClearAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete everything?'**
  String get storageClearAllTitle;

  /// No description provided for @storageClearAllGoes.
  ///
  /// In en, this message translates to:
  /// **'This deletes the message history this app kept, places, the movement trail, unfinished media records, the tool runs and their tables, and cached map tiles.'**
  String get storageClearAllGoes;

  /// No description provided for @storageClearAllStays.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio is untouched: its contacts, channels and settings stay, and a sent message is not recalled. Your settings and downloaded map regions stay too.'**
  String get storageClearAllStays;

  /// No description provided for @storageClearAllTypeWord.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String storageClearAllTypeWord(String word);

  /// No description provided for @storageClearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get storageClearAllConfirm;

  /// No description provided for @storageClearAllDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted. The MeshCore radio and your settings are untouched.'**
  String get storageClearAllDone;

  /// No description provided for @storageClearAllPartly.
  ///
  /// In en, this message translates to:
  /// **'{unfinished} of {total} stores did not finish. What is left is listed here. The MeshCore radio and your settings are untouched.'**
  String storageClearAllPartly(int unfinished, int total);

  /// No description provided for @chatMediaPrivateOnly.
  ///
  /// In en, this message translates to:
  /// **'Photos and voice: direct messages and private channels only.'**
  String get chatMediaPrivateOnly;

  /// No description provided for @mediaReachScope.
  ///
  /// In en, this message translates to:
  /// **'Region scope {scope}.'**
  String mediaReachScope(String scope);

  /// No description provided for @mediaReachNoScope.
  ///
  /// In en, this message translates to:
  /// **'No region scope set: everyone in range receives this.'**
  String get mediaReachNoScope;

  /// No description provided for @mediaReachUnknown.
  ///
  /// In en, this message translates to:
  /// **'Reach is the MeshCore radio\'s own scope, which it has not reported yet. A photo is not acknowledged.'**
  String get mediaReachUnknown;

  /// No description provided for @deviceContactsSection.
  ///
  /// In en, this message translates to:
  /// **'Contact table'**
  String get deviceContactsSection;

  /// No description provided for @autoAddIntro.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio decides which nodes it keeps. These are its settings, not the app\'s.'**
  String get autoAddIntro;

  /// No description provided for @autoAddOverwriteOldest.
  ///
  /// In en, this message translates to:
  /// **'Replace the oldest when full'**
  String get autoAddOverwriteOldest;

  /// No description provided for @autoAddOverwriteOldestHint.
  ///
  /// In en, this message translates to:
  /// **'Favourites are never replaced.'**
  String get autoAddOverwriteOldestHint;

  /// No description provided for @autoAddChat.
  ///
  /// In en, this message translates to:
  /// **'Chat nodes'**
  String get autoAddChat;

  /// No description provided for @autoAddRepeater.
  ///
  /// In en, this message translates to:
  /// **'Repeaters'**
  String get autoAddRepeater;

  /// No description provided for @autoAddRoomServer.
  ///
  /// In en, this message translates to:
  /// **'Room servers'**
  String get autoAddRoomServer;

  /// No description provided for @autoAddSensor.
  ///
  /// In en, this message translates to:
  /// **'Sensors'**
  String get autoAddSensor;

  /// No description provided for @autoAddMaxHops.
  ///
  /// In en, this message translates to:
  /// **'Hop limit'**
  String get autoAddMaxHops;

  /// No description provided for @autoAddMaxHopsHint.
  ///
  /// In en, this message translates to:
  /// **'0 = all, N = hops'**
  String get autoAddMaxHopsHint;

  /// No description provided for @autoAddUnknown.
  ///
  /// In en, this message translates to:
  /// **'Reading the MeshCore radio\'s policy…'**
  String get autoAddUnknown;

  /// No description provided for @autoAddManage.
  ///
  /// In en, this message translates to:
  /// **'Manage the table'**
  String get autoAddManage;

  /// No description provided for @nodeAdvertPath.
  ///
  /// In en, this message translates to:
  /// **'Last advert came via'**
  String get nodeAdvertPath;

  /// No description provided for @nodeAdvertPathNone.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio has no advert route for this node.'**
  String get nodeAdvertPathNone;

  /// No description provided for @nodeAdvertPathReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the route…'**
  String get nodeAdvertPathReading;

  /// No description provided for @retryPathReset.
  ///
  /// In en, this message translates to:
  /// **'Route cleared, so this retry goes out over flood.'**
  String get retryPathReset;

  /// No description provided for @nodeFindRoute.
  ///
  /// In en, this message translates to:
  /// **'Find the route'**
  String get nodeFindRoute;

  /// No description provided for @nodeFindRouteHint.
  ///
  /// In en, this message translates to:
  /// **'Costs airtime.'**
  String get nodeFindRouteHint;

  /// No description provided for @nodeFindRouteNone.
  ///
  /// In en, this message translates to:
  /// **'No route came back.'**
  String get nodeFindRouteNone;

  /// No description provided for @nodeFindRouteDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct. A neighbour in range.'**
  String get nodeFindRouteDirect;

  /// No description provided for @nodeFindRouteTwoWay.
  ///
  /// In en, this message translates to:
  /// **'Back by {back}'**
  String nodeFindRouteTwoWay(Object back);

  /// No description provided for @eventOneKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio refused a message from {key}'**
  String eventOneKeyRejected(Object key);

  /// No description provided for @eventRadioRefused.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio refused that command'**
  String get eventRadioRefused;

  /// No description provided for @failureCommandDisabled.
  ///
  /// In en, this message translates to:
  /// **'This MeshCore radio has that command switched off, so it refused. Nothing is wrong with the link.'**
  String get failureCommandDisabled;

  /// No description provided for @nodeShareContact.
  ///
  /// In en, this message translates to:
  /// **'Share this contact'**
  String get nodeShareContact;

  /// No description provided for @nodeShareContactHint.
  ///
  /// In en, this message translates to:
  /// **'Copies a link.'**
  String get nodeShareContactHint;

  /// No description provided for @nodeShareContactFailed.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio did not hand over the contact.'**
  String get nodeShareContactFailed;

  /// No description provided for @shareLinkSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact link'**
  String get shareLinkSheetTitle;

  /// No description provided for @shareLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied. The link carries this MeshCore radio\'s public key and the position it last announced.'**
  String get shareLinkCopied;

  /// No description provided for @deviceContactsImport.
  ///
  /// In en, this message translates to:
  /// **'Import a link'**
  String get deviceContactsImport;

  /// No description provided for @deviceContactsImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a meshcore:// link'**
  String get deviceContactsImportHint;

  /// No description provided for @deviceContactsImportBad.
  ///
  /// In en, this message translates to:
  /// **'That is not a contact link.'**
  String get deviceContactsImportBad;

  /// No description provided for @deviceContactsImportDone.
  ///
  /// In en, this message translates to:
  /// **'Sent, MeshCore radio confirms'**
  String get deviceContactsImportDone;

  /// No description provided for @diagnosticsRestartRadio.
  ///
  /// In en, this message translates to:
  /// **'Restart the MeshCore radio'**
  String get diagnosticsRestartRadio;

  /// No description provided for @diagnosticsRestartConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restart this MeshCore radio now? The link drops for a few seconds while it boots, and anything queued on it is lost.'**
  String get diagnosticsRestartConfirm;

  /// No description provided for @diagnosticsRestartSent.
  ///
  /// In en, this message translates to:
  /// **'Restart sent. The connection will drop.'**
  String get diagnosticsRestartSent;

  /// No description provided for @diagnosticsRestartNoReply.
  ///
  /// In en, this message translates to:
  /// **'Restart sent, but the MeshCore radio did not confirm it.'**
  String get diagnosticsRestartNoReply;

  /// No description provided for @settingsSecuritySection.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio access'**
  String get settingsSecuritySection;

  /// No description provided for @settingsPinIntro.
  ///
  /// In en, this message translates to:
  /// **'A pairing PIN gates a new Bluetooth pairing to this MeshCore radio. The radio still keeps its own list of bonded devices.'**
  String get settingsPinIntro;

  /// No description provided for @settingsPinCurrent.
  ///
  /// In en, this message translates to:
  /// **'Pairing PIN'**
  String get settingsPinCurrent;

  /// No description provided for @settingsPinNone.
  ///
  /// In en, this message translates to:
  /// **'No PIN set'**
  String get settingsPinNone;

  /// No description provided for @settingsPinSet.
  ///
  /// In en, this message translates to:
  /// **'Set a new PIN'**
  String get settingsPinSet;

  /// No description provided for @settingsPinRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the PIN'**
  String get settingsPinRemove;

  /// No description provided for @settingsPinHint.
  ///
  /// In en, this message translates to:
  /// **'Six digits'**
  String get settingsPinHint;

  /// No description provided for @settingsPinBad.
  ///
  /// In en, this message translates to:
  /// **'A PIN is exactly six digits.'**
  String get settingsPinBad;

  /// No description provided for @settingsPinDone.
  ///
  /// In en, this message translates to:
  /// **'PIN set. A new pairing needs it now.'**
  String get settingsPinDone;

  /// No description provided for @settingsPinRemoved.
  ///
  /// In en, this message translates to:
  /// **'PIN removed. Pairing no longer asks for one.'**
  String get settingsPinRemoved;

  /// No description provided for @settingsPinConfirmRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the pairing PIN? Anyone in range could offer to pair, and the MeshCore radio would still keep its own device list.'**
  String get settingsPinConfirmRemove;

  /// No description provided for @repeaterSession.
  ///
  /// In en, this message translates to:
  /// **'Repeater session'**
  String get repeaterSession;

  /// No description provided for @repeaterSessionIntro.
  ///
  /// In en, this message translates to:
  /// **'A password opens a session on this repeater. It is the repeater\'s own secret, kept between it and you. The app does not store it.'**
  String get repeaterSessionIntro;

  /// No description provided for @repeaterSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get repeaterSignIn;

  /// No description provided for @repeaterSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get repeaterSignOut;

  /// No description provided for @repeaterPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Repeater password'**
  String get repeaterPasswordHint;

  /// No description provided for @repeaterSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in (permissions 0x{perm})'**
  String repeaterSignedIn(Object perm);

  /// No description provided for @repeaterRefused.
  ///
  /// In en, this message translates to:
  /// **'The repeater refused that password.'**
  String get repeaterRefused;

  /// No description provided for @repeaterNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer. The repeater may be out of reach.'**
  String get repeaterNoAnswer;

  /// No description provided for @repeaterSignOutDone.
  ///
  /// In en, this message translates to:
  /// **'Signed out.'**
  String get repeaterSignOutDone;

  /// No description provided for @actionForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get actionForward;

  /// No description provided for @forwardNoTarget.
  ///
  /// In en, this message translates to:
  /// **'Nothing to forward into: no channel and no contact.'**
  String get forwardNoTarget;

  /// No description provided for @forwardDone.
  ///
  /// In en, this message translates to:
  /// **'Forwarded to the composer'**
  String get forwardDone;

  /// No description provided for @forwardFailed.
  ///
  /// In en, this message translates to:
  /// **'Draft not saved: store closed'**
  String get forwardFailed;

  /// No description provided for @placeConfirmToSender.
  ///
  /// In en, this message translates to:
  /// **'Confirm to the sender'**
  String get placeConfirmToSender;

  /// No description provided for @placeRefuteToSender.
  ///
  /// In en, this message translates to:
  /// **'Refute to the sender'**
  String get placeRefuteToSender;

  /// No description provided for @placeSentDirect.
  ///
  /// In en, this message translates to:
  /// **'Sent to the sender as a direct message.'**
  String get placeSentDirect;

  /// No description provided for @placeNoSenderKey.
  ///
  /// In en, this message translates to:
  /// **'This place came without a key, so there is nobody to address directly.'**
  String get placeNoSenderKey;

  /// No description provided for @dmWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the message above to settle. One message per contact at a time keeps the MeshCore radio able to say which one was answered.'**
  String get dmWaiting;

  /// Composer line in a direct message whose peer is on the block list. Says what a block does to the conversation rather than only that sending is off.
  ///
  /// In en, this message translates to:
  /// **'This key is blocked, so a reply would be hidden here. Unblock it under Settings, Blocked keys, to talk again.'**
  String get dmBlockedNotice;

  /// Snackbar after a send to a blocked key was refused. Names the limit: a block is this app's filter and does not stop the radio relaying.
  ///
  /// In en, this message translates to:
  /// **'Not sent. This key is blocked, so the reply would be hidden here. The MeshCore radio would still carry the message.'**
  String get dmBlockedRefused;

  /// No description provided for @settingsHubFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get settingsHubFirmware;

  /// No description provided for @firmwareTitle.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get firmwareTitle;

  /// No description provided for @firmwareIntro.
  ///
  /// In en, this message translates to:
  /// **'What the MeshCore radio is running.'**
  String get firmwareIntro;

  /// No description provided for @firmwareRadioLabel.
  ///
  /// In en, this message translates to:
  /// **'MeshCore firmware'**
  String get firmwareRadioLabel;

  /// No description provided for @firmwareAppLabel.
  ///
  /// In en, this message translates to:
  /// **'This app'**
  String get firmwareAppLabel;

  /// No description provided for @firmwareOtaSupported.
  ///
  /// In en, this message translates to:
  /// **'supported'**
  String get firmwareOtaSupported;

  /// No description provided for @firmwareOtaAbsent.
  ///
  /// In en, this message translates to:
  /// **'not in this build'**
  String get firmwareOtaAbsent;

  /// No description provided for @firmwareOtaUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown until it answers'**
  String get firmwareOtaUnknown;

  /// No description provided for @firmwareNoInstallWhy.
  ///
  /// In en, this message translates to:
  /// **'Installs are not offered here: one would drop the messages the MeshCore radio has queued.'**
  String get firmwareNoInstallWhy;

  /// No description provided for @firmwareOtaLabel.
  ///
  /// In en, this message translates to:
  /// **'Over-the-air update'**
  String get firmwareOtaLabel;

  /// No description provided for @deviceRadio2Seen.
  ///
  /// In en, this message translates to:
  /// **'second profile: heard {when}'**
  String deviceRadio2Seen(String when);

  /// No description provided for @deviceRadio2Never.
  ///
  /// In en, this message translates to:
  /// **'second profile: nothing heard this session'**
  String get deviceRadio2Never;

  /// No description provided for @deviceRadio2Note.
  ///
  /// In en, this message translates to:
  /// **'A second profile takes 96 to 99 % of the MeshCore radio transmit time, so it is set on the radio and not here. Both are read.'**
  String get deviceRadio2Note;

  /// No description provided for @deviceReadoutQuerying.
  ///
  /// In en, this message translates to:
  /// **'querying device…'**
  String get deviceReadoutQuerying;

  /// No description provided for @deviceReadoutFirmware.
  ///
  /// In en, this message translates to:
  /// **'firmware: {value}'**
  String deviceReadoutFirmware(String value);

  /// No description provided for @deviceReadoutBuild.
  ///
  /// In en, this message translates to:
  /// **'build: {value}'**
  String deviceReadoutBuild(String value);

  /// No description provided for @deviceReadoutManufacturer.
  ///
  /// In en, this message translates to:
  /// **'mfr: {value}'**
  String deviceReadoutManufacturer(String value);

  /// No description provided for @deviceReadoutContacts.
  ///
  /// In en, this message translates to:
  /// **'max contacts: {maxContacts} · channels: {channels}'**
  String deviceReadoutContacts(int maxContacts, int channels);

  /// No description provided for @deviceReadoutBlePin.
  ///
  /// In en, this message translates to:
  /// **'BLE pin: {value}'**
  String deviceReadoutBlePin(int value);

  /// No description provided for @deviceReadoutPathHash.
  ///
  /// In en, this message translates to:
  /// **'path hash: {bytes} byte(s)'**
  String deviceReadoutPathHash(int bytes);

  /// No description provided for @deviceReadoutBattery.
  ///
  /// In en, this message translates to:
  /// **'battery: {value}'**
  String deviceReadoutBattery(String value);

  /// No description provided for @deviceBatteryValue.
  ///
  /// In en, this message translates to:
  /// **'{volts}V (~{percent}%)'**
  String deviceBatteryValue(String volts, int percent);

  /// No description provided for @deviceAirtimeLimit.
  ///
  /// In en, this message translates to:
  /// **'airtime limit: {share}% (af {af})'**
  String deviceAirtimeLimit(int share, String af);

  /// No description provided for @deviceAirtimeLimitUnknown.
  ///
  /// In en, this message translates to:
  /// **'airtime limit:.'**
  String get deviceAirtimeLimitUnknown;

  /// No description provided for @deviceRepeatRanges.
  ///
  /// In en, this message translates to:
  /// **'repeat: {ranges} MHz'**
  String deviceRepeatRanges(String ranges);

  /// No description provided for @deviceRepeatNone.
  ///
  /// In en, this message translates to:
  /// **'repeat: none reported'**
  String get deviceRepeatNone;

  /// No description provided for @deviceRepeatUnknown.
  ///
  /// In en, this message translates to:
  /// **'repeat:.'**
  String get deviceRepeatUnknown;

  /// No description provided for @diagnosticsSectionRadioAlerts.
  ///
  /// In en, this message translates to:
  /// **'MeshCore radio alerts'**
  String get diagnosticsSectionRadioAlerts;

  /// No description provided for @diagnosticsRadioAlertsWhy.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio\'s own buzzer and vibration, for its own rules. Nothing in this app triggers them, and they keep working while the phone is away.'**
  String get diagnosticsRadioAlertsWhy;

  /// No description provided for @diagnosticsBuzzer.
  ///
  /// In en, this message translates to:
  /// **'Buzzer'**
  String get diagnosticsBuzzer;

  /// No description provided for @diagnosticsVibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get diagnosticsVibration;

  /// No description provided for @diagnosticsAlertNotRead.
  ///
  /// In en, this message translates to:
  /// **'not read yet'**
  String get diagnosticsAlertNotRead;

  /// No description provided for @diagnosticsAlertReading.
  ///
  /// In en, this message translates to:
  /// **'asking the MeshCore radio'**
  String get diagnosticsAlertReading;

  /// No description provided for @diagnosticsAlertRead.
  ///
  /// In en, this message translates to:
  /// **'Ask the MeshCore radio'**
  String get diagnosticsAlertRead;

  /// No description provided for @diagnosticsAlertOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get diagnosticsAlertOn;

  /// No description provided for @diagnosticsAlertOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get diagnosticsAlertOff;

  /// No description provided for @diagnosticsAlertDone.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio accepted it.'**
  String get diagnosticsAlertDone;

  /// No description provided for @diagnosticsAlertSaid.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio said: {text}'**
  String diagnosticsAlertSaid(String text);

  /// No description provided for @diagnosticsAlertRefused.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused: {cause}'**
  String diagnosticsAlertRefused(String cause);

  /// No description provided for @diagnosticsAlertRefusedSaid.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio refused: {cause}. It said: {text}'**
  String diagnosticsAlertRefusedSaid(String cause, String text);

  /// No description provided for @diagnosticsAlertSilent.
  ///
  /// In en, this message translates to:
  /// **'No answer inside six seconds. The MeshCore radio may still have run it.'**
  String get diagnosticsAlertSilent;

  /// No description provided for @diagnosticsAlertSilentPartial.
  ///
  /// In en, this message translates to:
  /// **'No answer inside six seconds. It said: {text}'**
  String diagnosticsAlertSilentPartial(String text);

  /// No description provided for @diagnosticsAlertBusy.
  ///
  /// In en, this message translates to:
  /// **'Another command is still waiting for its answer.'**
  String get diagnosticsAlertBusy;

  /// No description provided for @diagnosticsAlertUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No usable link, so nothing was sent.'**
  String get diagnosticsAlertUnavailable;

  /// No description provided for @voiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceTitle;

  /// No description provided for @voiceLimit.
  ///
  /// In en, this message translates to:
  /// **'20 seconds, then it stops by itself.'**
  String get voiceLimit;

  /// No description provided for @voiceRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get voiceRecord;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStop;

  /// No description provided for @voiceDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get voiceDiscard;

  /// No description provided for @voiceStoppedAtLimit.
  ///
  /// In en, this message translates to:
  /// **'Stopped at 20 seconds.'**
  String get voiceStoppedAtLimit;

  /// No description provided for @voiceNoMicrophone.
  ///
  /// In en, this message translates to:
  /// **'The microphone is not available, so nothing can be recorded.'**
  String get voiceNoMicrophone;

  /// No description provided for @voiceNoCodec.
  ///
  /// In en, this message translates to:
  /// **'This build has no speech codec.'**
  String get voiceNoCodec;

  /// No description provided for @voiceCost.
  ///
  /// In en, this message translates to:
  /// **'{datagrams} packets, about {seconds} s of airtime at {mode}.'**
  String voiceCost(int datagrams, int seconds, String mode);

  /// No description provided for @voiceRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording {seconds} s, {bytes} B, about {datagrams} packets.'**
  String voiceRecording(int seconds, int bytes, int datagrams);

  /// No description provided for @voiceNoteSend.
  ///
  /// In en, this message translates to:
  /// **'Send voice'**
  String get voiceNoteSend;

  /// No description provided for @voiceNotePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get voiceNotePreview;

  /// No description provided for @voiceNotePlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get voiceNotePlaying;

  /// No description provided for @voiceNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice notes'**
  String get voiceNotesTitle;

  /// No description provided for @voiceNotesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No voice notes yet. Record one, then send it.'**
  String get voiceNotesEmpty;

  /// No description provided for @voiceNotesCount.
  ///
  /// In en, this message translates to:
  /// **'Voice notes ({count})'**
  String voiceNotesCount(int count);

  /// No description provided for @voiceNoteDecodeFailed.
  ///
  /// In en, this message translates to:
  /// **'This voice note cannot be decoded.'**
  String get voiceNoteDecodeFailed;

  /// No description provided for @voiceNoteTooShort.
  ///
  /// In en, this message translates to:
  /// **'Too short to decode.'**
  String get voiceNoteTooShort;

  /// No description provided for @mediaStalledTableFull.
  ///
  /// In en, this message translates to:
  /// **'The MeshCore radio\'s packet table stayed full, so the send stopped. Nothing further was put on air.'**
  String get mediaStalledTableFull;

  /// No description provided for @mediaStalledAirtime.
  ///
  /// In en, this message translates to:
  /// **'This hour\'s airtime budget refused the send, so it stopped. It can be tried again after the window rolls over.'**
  String get mediaStalledAirtime;

  /// No description provided for @voiceNotesSession.
  ///
  /// In en, this message translates to:
  /// **'Kept on this phone until the app closes. A note is not saved to history.'**
  String get voiceNotesSession;

  /// No description provided for @gridRangeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get gridRangeAuto;

  /// No description provided for @heatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chatter overheard here in the last hour.'**
  String get heatEmpty;

  /// No description provided for @elevationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody has reported an altitude yet. Ask a peer that carries a sensor, or wait for one to advertise.'**
  String get elevationEmpty;

  /// No description provided for @mapOverlaysTitle.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get mapOverlaysTitle;

  /// No description provided for @connectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a MeshCore radio'**
  String get connectTitle;

  /// Heading over the list of radios this phone has paired, on the connect screen.
  ///
  /// In en, this message translates to:
  /// **'Paired radios'**
  String get radioSwitchTitle;

  /// Marks the radio the app is paired with now, in place of a switch action.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get radioSwitchCurrent;

  /// Moves the one session to this radio.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get radioSwitchAction;

  /// Confirmation after the link was torn down and the new radio is connecting.
  ///
  /// In en, this message translates to:
  /// **'Switching to {name}.'**
  String radioSwitchDone(String name);

  /// The row was for the radio already paired, so nothing was touched.
  ///
  /// In en, this message translates to:
  /// **'That MeshCore radio is already the one in use.'**
  String get radioSwitchSame;

  /// The switch was refused because a send is unsettled. Names why waiting is the honest answer rather than a rule for its own sake.
  ///
  /// In en, this message translates to:
  /// **'Not switched. A message is still waiting for an answer, and that answer belongs to the MeshCore radio it was sent on.'**
  String get radioSwitchWaiting;

  /// No description provided for @mapKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Map key'**
  String get mapKeyTitle;

  /// No description provided for @mapKeyRepeater.
  ///
  /// In en, this message translates to:
  /// **'Repeater'**
  String get mapKeyRepeater;

  /// No description provided for @mapKeyClient.
  ///
  /// In en, this message translates to:
  /// **'Client radio'**
  String get mapKeyClient;

  /// No description provided for @mapKeyYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get mapKeyYou;

  /// No description provided for @mapKeyHeading.
  ///
  /// In en, this message translates to:
  /// **'Which way the phone points'**
  String get mapKeyHeading;

  /// No description provided for @mapKeyReach.
  ///
  /// In en, this message translates to:
  /// **'How far away we heard a peer'**
  String get mapKeyReach;

  /// No description provided for @mapKeyDensity.
  ///
  /// In en, this message translates to:
  /// **'Nodes per cell'**
  String get mapKeyDensity;

  /// No description provided for @mapKeyGeofence.
  ///
  /// In en, this message translates to:
  /// **'A fence you set'**
  String get mapKeyGeofence;

  /// No description provided for @mapKeyTrail.
  ///
  /// In en, this message translates to:
  /// **'Your own track'**
  String get mapKeyTrail;

  /// No description provided for @mapKeyMessage.
  ///
  /// In en, this message translates to:
  /// **'A node that just sent a message'**
  String get mapKeyMessage;

  /// Screen-reader label for the bubble drawn on the map at a node that has just sent a message; shown for one minute.
  ///
  /// In en, this message translates to:
  /// **'A message from {name} just arrived'**
  String mapMessageBubble(String name);

  /// No description provided for @mapDensityShow.
  ///
  /// In en, this message translates to:
  /// **'Node density per cell'**
  String get mapDensityShow;

  /// No description provided for @mapDensityCellTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 node in this cell} other{{count} nodes in this cell}}'**
  String mapDensityCellTitle(int count);

  /// No description provided for @mapDensityCellArea.
  ///
  /// In en, this message translates to:
  /// **'{size} across, so a cell is the same size on screen at every zoom.'**
  String mapDensityCellArea(String size);

  /// No description provided for @mapDensityCellOpen.
  ///
  /// In en, this message translates to:
  /// **'Open this node'**
  String get mapDensityCellOpen;

  /// No description provided for @bootFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Meshmore SNS could not start.'**
  String get bootFailedTitle;

  /// No description provided for @bootTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get bootTryAgain;

  /// No description provided for @notifGroupBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}} · {body}'**
  String notifGroupBody(int count, String body);

  /// The body of the one line standing for a queue of messages the app did not announce one by one.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread message} other{{count} unread messages}}'**
  String notifUnreadDigest(int count);

  /// No description provided for @mapDensityCellSize.
  ///
  /// In en, this message translates to:
  /// **'Cells: nodes per {size}'**
  String mapDensityCellSize(String size);

  /// No description provided for @actionReplyMention.
  ///
  /// In en, this message translates to:
  /// **'Reply to {name}'**
  String actionReplyMention(String name);

  /// No description provided for @actionQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote this message'**
  String get actionQuote;

  /// No description provided for @actionReact.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get actionReact;

  /// No description provided for @reactionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reactionSend;

  /// No description provided for @reactionAnyEmoji.
  ///
  /// In en, this message translates to:
  /// **'Any emoji'**
  String get reactionAnyEmoji;

  /// No description provided for @actionFriendlyAck.
  ///
  /// In en, this message translates to:
  /// **'Friendly ack'**
  String get actionFriendlyAck;

  /// No description provided for @actionReplyNoName.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get actionReplyNoName;

  /// No description provided for @chatActionsNoRadio.
  ///
  /// In en, this message translates to:
  /// **'No MeshCore radio: a reply or quote waits in the box until one is connected.'**
  String get chatActionsNoRadio;

  /// No description provided for @toolHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool history'**
  String get toolHistoryTitle;

  /// No description provided for @toolHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tool has finished a run yet. A run is kept when it ends, with the table it produced.'**
  String get toolHistoryEmpty;

  /// States both bounds of the stored history, so a reader knows what is kept and what is dropped.
  ///
  /// In en, this message translates to:
  /// **'The newest {runs} runs, and at most {size} of tables across them.'**
  String toolHistoryBounds(int runs, String size);

  /// No description provided for @toolHistoryTableDropped.
  ///
  /// In en, this message translates to:
  /// **'Table dropped to stay inside the size limit. The summary is kept.'**
  String get toolHistoryTableDropped;

  /// No description provided for @toolHistoryUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The stored history cannot be opened on this device, so it reads as empty. New runs are still kept.'**
  String get toolHistoryUnreadable;

  /// No description provided for @toolHistoryClear.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get toolHistoryClear;

  /// No description provided for @toolHistoryClearBody.
  ///
  /// In en, this message translates to:
  /// **'Every stored tool run goes, with its table. The tools themselves are unchanged.'**
  String get toolHistoryClearBody;

  /// The tool history store's own size, in the storage block. States both the run count and the table bytes, because the store bounds both.
  ///
  /// In en, this message translates to:
  /// **'Tool runs {n} of {cap}, {size} of tables'**
  String storageToolRuns(int n, int cap, String size);

  /// No description provided for @geofenceReshapeGone.
  ///
  /// In en, this message translates to:
  /// **'That fence has been deleted.'**
  String get geofenceReshapeGone;

  /// Names pictures that arrived in AEIC, MeshCore Open's neural codec, which this build does not ship. Without this line an arriving picture looks like nobody sending one.
  ///
  /// In en, this message translates to:
  /// **'{n} more arrived in a codec this build does not carry, so they cannot be shown here.'**
  String mediaReceivedForeign(int n);

  /// Diagnostics fact: commands that reached the ledger's timeout with no answer from the radio.
  ///
  /// In en, this message translates to:
  /// **'{n} commands were never answered'**
  String diagnosticsUnansweredLine(int n);

  /// Diagnostics fact: reaction lines that could not be attached to a message, so they were kept as ordinary lines.
  ///
  /// In en, this message translates to:
  /// **'{n} reactions named a message this window no longer holds'**
  String diagnosticsReactionsOrphanedLine(int n);

  /// Diagnostics fact: how many frames the app sent asking peers for readings, which is the airtime cost of the telemetry poller.
  ///
  /// In en, this message translates to:
  /// **'{n} telemetry requests sent this session'**
  String diagnosticsTelemetryAskedLine(int n);

  /// Under a downloading pack: the measured rate and the estimate for the rest of the pass.
  ///
  /// In en, this message translates to:
  /// **'{rate} tiles a second · {eta}'**
  String mapsPackRate(String rate, String eta);

  /// No description provided for @mapsEtaUnderMinute.
  ///
  /// In en, this message translates to:
  /// **'less than a minute left'**
  String get mapsEtaUnderMinute;

  /// No description provided for @mapsEtaMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {n} min left'**
  String mapsEtaMinutes(int n);

  /// No description provided for @mapsEtaUnknown.
  ///
  /// In en, this message translates to:
  /// **'estimating the time left'**
  String get mapsEtaUnknown;

  /// The feed's one line for a contact sync, which arrives as one frame per contact.
  ///
  /// In en, this message translates to:
  /// **'the MeshCore radio\'s contact table loaded · {count} contacts'**
  String eventContactBatch(int count);
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
