// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'Meshmore SNS';

  @override
  String get appSubtitle => 'ラジオでつながるメッシュ通信';

  @override
  String get tabDashboard => 'ダッシュボード';

  @override
  String get tabChat => 'チャット';

  @override
  String get tabNodes => 'ノード';

  @override
  String get tabMap => '地図';

  @override
  String get tabDocs => 'ドキュメント';

  @override
  String get tabSettings => '設定';

  @override
  String get tabAbout => 'アプリ情報';

  @override
  String get dashboardPeersInRange => '範囲内のノード';

  @override
  String get dashboardPeersInRangeStale => '付近のノード（既知の位置）';

  @override
  String dashboardKnownCount(int n) {
    return '$n件 既知';
  }

  @override
  String dashboardKnownAndContacts(int n, String contacts) {
    return '$n件 既知 · 連絡先 $contacts';
  }

  @override
  String dashboardMyPubkey(String hex) {
    return '自分の公開鍵 · $hex';
  }

  @override
  String get dashboardPubkeyAwaiting => '自分の公開鍵 · デバイス待機中';

  @override
  String get dashboardPubkeyHint => 'タップでコピー。相手が連絡先として追加する際に必要です。';

  @override
  String get botTitle => '自動応答ボット';

  @override
  String get botSubtitle => 'ここのメッセージに自動で返信します。既定はオフ。';

  @override
  String get botOnWire => '返信には [bot] を付けて送信し、相手が機械の発言だと分かるようにします。';

  @override
  String get botRefusedPublicSlot => 'パブリックでは使えません。';

  @override
  String get botRefusedPublicPsk =>
      'このチャンネルは公開の鍵のままなので、番号が違ってもパブリックです。先に非公開の鍵を設定してください。';

  @override
  String get botRefusedUnknownPsk => 'ラジオからこのチャンネルの鍵を待っています。';

  @override
  String get botMode => '返信モード';

  @override
  String get botModeDeterministic => '決定的';

  @override
  String get botModeRandom => 'ランダム';

  @override
  String get botModeDeterministicSub => '最初に一致した規則が必ず使われるので、2 回の実行を比べられます。';

  @override
  String get botModeRandomSub => '一致した規則から選択します。シードで再現可能。';

  @override
  String get botSeed => 'シード';

  @override
  String botBudget(int n) {
    return 'このウィンドウで残り $n 件';
  }

  @override
  String botCounters(int r, int p, int s) {
    return '受信 $r · 返信 $p · 抑制 $s';
  }

  @override
  String get botResetCounters => 'カウンタをリセット';

  @override
  String get botEditRules => '規則を編集';

  @override
  String get botRulesTitle => 'ルールパック';

  @override
  String get botRulesRestore => '既定に戻す';

  @override
  String botRulesErrors(int n) {
    return '$n 行を読み取れずスキップしました';
  }

  @override
  String get botRulesSave => '保存';

  @override
  String get botFromBot => 'ボット';

  @override
  String get dashboardRadio => 'ラジオ';

  @override
  String get dashForestCanopy => '樹冠';

  @override
  String get dashForestNoRoutes => 'まだ経路が学習されていません。無線機は誰への経路も知りません。';

  @override
  String get dashForestContacts => '連絡先';

  @override
  String get dashNervLink => 'リンク';

  @override
  String get dashNervNode => 'ノード';

  @override
  String get dashNervRegion => '地域';

  @override
  String get dashContacts => '連絡先';

  @override
  String get dashNervMesh => 'メッシュ';

  @override
  String get dashNervKnown => '既知';

  @override
  String get dashNervEvents => 'イベント';

  @override
  String get dashHyperEmpty => 'ノードを探索中…';

  @override
  String get dashPeers => 'ノード';

  @override
  String get dashAgHudSignal => 'シグナル';

  @override
  String get dashAgHudTraffic => 'ch トラフィック';

  @override
  String get dashDrPopLink => 'リンク';

  @override
  String get dashReconNoContacts => '範囲内に連絡先なし';

  @override
  String dashAgHudOfKnown(String count) {
    return '既知 $count 中';
  }

  @override
  String get dashboardLocation => '現在地';

  @override
  String get dashboardBattery => 'バッテリー';

  @override
  String get dashboardRecent => '最近のアクティビティ';

  @override
  String get dashboardNoActivity => 'まだ動きはありません';

  @override
  String get dashboardAwaitingDevice => '無線を待っています…';

  @override
  String get dashboardAwaitingDeviceLocation => '位置情報を待っています…';

  @override
  String get dashboardUnnamed => '(名前なし)';

  @override
  String get dashboardLocationNotSet => '位置情報なし';

  @override
  String get dashboardLocationConfigure => '設定';

  @override
  String get statusLinked => '接続済み';

  @override
  String get statusSyncing => '同期中…';

  @override
  String get statusHandshaking => '同期中…';

  @override
  String get statusReconnecting => '再接続中…';

  @override
  String get statusLinkLost => '接続切断';

  @override
  String get statusOffline => 'オフライン';

  @override
  String get statusConnecting => '接続中…';

  @override
  String get linkChipLinked => '接続済み';

  @override
  String get linkChipSync => '同期';

  @override
  String get linkChipRetry => '再試行';

  @override
  String get linkChipFail => '失敗';

  @override
  String get linkChipScan => '検索';

  @override
  String get linkChipOffline => 'オフライン';

  @override
  String get linkChipConnect => '無線機に接続';

  @override
  String linkChipSemantics(String state) {
    return 'ラジオ: $state';
  }

  @override
  String get actionConnect => '接続する';

  @override
  String get actionBlock => 'この相手をブロック';

  @override
  String get blockConfirmTitle => 'このキーをブロックしますか？';

  @override
  String get blockConfirmBody =>
      'この端末で、その相手からのメッセージ・通知・地点を表示しなくなります。無線機は今も受信・中継しており、メッシュ上の誰もブロックを知りません。';

  @override
  String get blockConfirmGo => 'ブロック';

  @override
  String get blockDone => 'ブロックしました。この端末はそのキーの送信を表示しません。';

  @override
  String get blockFull => 'ブロック一覧がいっぱいです。先に1件解除してください。';

  @override
  String get actionRetry => '再試行';

  @override
  String get actionRetrySend => '再送';

  @override
  String get dashboardDevice => 'デバイス';

  @override
  String get deviceMgrTitle => 'デバイス';

  @override
  String get deviceMgrNoPair => 'デバイス未ペアリング';

  @override
  String get deviceMgrStateConnected => '接続済み';

  @override
  String get deviceMgrStateConnecting => '接続中…';

  @override
  String get deviceMgrStateReconnecting => '再接続中…';

  @override
  String get deviceMgrStateDisconnected => '切断';

  @override
  String get deviceMgrStateFailed => '失敗';

  @override
  String get deviceMgrDisconnect => '切断';

  @override
  String get deviceMgrReconnect => '再接続';

  @override
  String get deviceMgrForget => 'ペアリング解除';

  @override
  String get deviceMgrPick => 'デバイスを選択';

  @override
  String get deviceMgrScan => 'スキャン';

  @override
  String get deviceMgrStopScan => '停止';

  @override
  String get deviceMgrScanHint =>
      '「スキャン」をタップして近くの MeshCore デバイスを探します。2 台以上ある場合はリストから選んでください。';

  @override
  String deviceMgrScanFailed(String message) {
    return 'スキャン失敗: $message';
  }

  @override
  String get deviceMgrRecent => '最近のペアリング';

  @override
  String get deviceMgrAgoNever => '未使用';

  @override
  String get deviceMgrAgoNow => 'たった今';

  @override
  String deviceMgrAgoMinutes(int n) {
    return '$n 分前';
  }

  @override
  String deviceMgrAgoHours(int n) {
    return '$n 時間前';
  }

  @override
  String deviceMgrAgoDays(int n) {
    return '$n 日前';
  }

  @override
  String get deviceMgrPairNew => '新しいラジオをペアリング';

  @override
  String get pairTitle => 'ラジオをペアリング';

  @override
  String pairStepOf(int step, int total) {
    return 'ステップ $step / $total';
  }

  @override
  String get pairPermissionTitle => 'Bluetooth の権限';

  @override
  String get pairPermissionBody =>
      'ラジオを見つけて通信するために「付近のデバイス」の権限が必要です。まだ何もペアリングされていません。';

  @override
  String get pairPermissionAllow => 'Bluetooth を許可';

  @override
  String get pairPermissionOpenSettings => 'OS 設定を開く';

  @override
  String get pairAdapterTitle => 'Bluetooth がオフです';

  @override
  String get pairAdapterBody =>
      'ラジオを探すには Bluetooth をオンにしてください。オンにするとこの画面は自動で次に進みます。';

  @override
  String get pairAdapterUnsupported =>
      'この端末には利用できる Bluetooth アダプターがないため、ここではペアリングできません。';

  @override
  String get pairRetry => '再試行';

  @override
  String get pairScanTitle => 'ラジオを検索中';

  @override
  String get pairScanBody =>
      'ラジオは MeshCore-<名前> としてアドバタイズします。電源を入れたまま、1〜2 m 以内に置いてください。';

  @override
  String get pairScanning => 'スキャン中…';

  @override
  String get pairStopScan => '停止';

  @override
  String get pairScanAgain => '再スキャン';

  @override
  String pairRssi(int rssi) {
    return 'RSSI $rssi';
  }

  @override
  String pairConnecting(String name) {
    return '$name に接続中…';
  }

  @override
  String get pairConnectingBody =>
      'ラジオに PIN が表示されたら、求められたときにスマートフォンへ入力してください。画面のないラジオは 123456 です。';

  @override
  String get pairConfirmTitle => 'ラジオに接続しました';

  @override
  String pairConfirmBody(String name) {
    return '$name が応答しました。リンクとプロトコルの両方が動作しています。このラジオがアプリの接続先になります。';
  }

  @override
  String get pairConfirmNode => 'ノード';

  @override
  String get pairConfirmFirmware => 'ファームウェア';

  @override
  String get pairConfirmUse => 'このラジオを使う';

  @override
  String get pairChooseAnother => '別のラジオを選ぶ';

  @override
  String get settingsHeading => 'アプリ設定';

  @override
  String get settingsBackgroundTitle => 'バックグラウンドで接続を維持';

  @override
  String get settingsBackgroundOn =>
      'アプリを閉じていてもメッセージが届きます。端末の再起動後はアプリを開いて再接続してください。';

  @override
  String get settingsBackgroundOff => 'アプリを開いたときにメッセージが届きます';

  @override
  String get settingsBackgroundFailed =>
      'バックグラウンドでの接続を維持できませんでした。アプリを開いて再接続してください。';

  @override
  String get settingsTelemetryPoll => 'ノードから気温と高度を取得';

  @override
  String get settingsTelemetryPollOn => '連絡先に気温と高度を問い合わせます。多少の空中時間を使います。';

  @override
  String get settingsTelemetryPollOff => '自動では問い合わせません。ノードを開けば1回だけ尋ねられます。';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsLanguageSystem => 'システム既定';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageJapanese => '日本語';

  @override
  String get settingsSpeech => '音声読み上げ';

  @override
  String get settingsSpeechOn => '音声読み上げ ON · チャネル別切替はチャット内';

  @override
  String get settingsSpeechOff => '音声読み上げ OFF (既定) · チャネルメッセージを読み上げ';

  @override
  String get settingsSpeechMuted => '読み上げはオンですが、通知音のミュートで消えています。';

  @override
  String get settingsPermissions => '権限';

  @override
  String get settingsPermissionsSubtitle => 'Bluetooth・通知・位置情報';

  @override
  String get termsTitle => '利用規約とプライバシー';

  @override
  String get termsLead => 'このアプリはメッシュ無線と通信します。アカウントもクラウドも解析もありません。';

  @override
  String get termsSectionLocal => 'この端末に残るもの';

  @override
  String get termsLocalBody =>
      'メッセージ、連絡先、チャンネル、設定はこの端末に保存されます。メッセージ履歴・地点・移動軌跡・ジオフェンスは、この端末が保持し書き出せない鍵で暗号化されます。受信範囲のセルと直近1日分のチャンネル活動も保存されるため、再起動後もマップと活動レポートは残ります。これらは暗号化されず、「すべて削除」で他と合わせて削除されます。クラウドバックアップと端末間の移行はすべて無効なので、新しい端末が知らないうちに引き継ぐことはありません。アプリを削除すると、そのデータも削除されます。';

  @override
  String get termsSectionLeaves => '端末の外に出るもの';

  @override
  String get termsLeavesBody =>
      'この端末から出るのは2つだけです。送信したもの（メッセージ・位置・リアクション）は接続中の無線から送られます。そして地図はタイルサーバーに地図の区画を要求するため、おおよそどこを見ているかがそのサーバーに伝わります。地図には取得元を表示します。オフライン地図パックは既定でオフで、有効にしたときだけ取得します。それ以外は出ません。書き出したファイルの保管先はあなたが決めます。';

  @override
  String get termsSectionPermissions => '権限とその理由';

  @override
  String get termsPermissionsBody =>
      'Bluetooth は無線に接続するために使います。位置情報は自分の現在地と、古い Android で Bluetooth スキャンを許可するために使います。通知はバックグラウンドで届いたメッセージを知らせるために使います。いずれを拒否しても、無線を使わない範囲でアプリは動作します。';

  @override
  String get termsSectionRetention => '保存される量';

  @override
  String termsRetentionBody(int cap) {
    return '会話ごとに新しい $cap 件を保持し、それより古いものは破棄します。場所はそれぞれの期限が切れると消えます。';
  }

  @override
  String get termsSectionChanges => '変更';

  @override
  String get termsChangesBody =>
      'この文章が重要な点で変わった場合は下の版番号が変わり、アプリを開く前にこのページが再表示されます。';

  @override
  String termsVersion(int version) {
    return '版 $version';
  }

  @override
  String get termsGateNote => 'アプリを使うには同意が必要です。';

  @override
  String get termsExit => '終了';

  @override
  String get termsAccept => '同意して続ける';

  @override
  String termsAcceptedVersion(int version) {
    return '版 $version に同意済みです。';
  }

  @override
  String get termsNotAccepted => '未同意です。';

  @override
  String get termsSettingsRow => '利用規約とプライバシー';

  @override
  String get termsSettingsSubtitle => '保存されるもの、端末外に出るもの、各権限が必要な理由';

  @override
  String get aboutCopyright => 'Copyright (c) 2026 IoTone, Inc.';

  @override
  String get aboutSubtitleEn => '(Socialrobot Network Service)';

  @override
  String get aboutSubtitleJa => '(ソーシャルロボット・ネットワークサービス)';

  @override
  String get aboutDescription => 'MeshCore コンパニオンクライアント。';

  @override
  String get aboutLicense => 'MIT (X11) ライセンスで提供。';

  @override
  String get aboutMadeWith => '福岡から ♥ をこめて';

  @override
  String aboutVersion(String version) {
    return 'v$version';
  }

  @override
  String get aboutReportProblem => '問題を報告';

  @override
  String get aboutReportProblemSub =>
      'アプリとラジオの情報を入れた状態で課題トラッカーを開きます。そこで送信するまで何も送られません。';

  @override
  String get aboutLicensesButton => 'オープンソースライセンスと権利表示';

  @override
  String get aboutAttributions =>
      'MeshCore ドキュメント（MIT）、OpenStreetMap 地図データ（ODbL）、Saira・JetBrains Mono フォント（OFL）を含みます。';

  @override
  String get personalizationThemePreset => 'テーマプリセット';

  @override
  String get personalizationType => '文字';

  @override
  String get personalizationFontSize => 'フォントサイズ';

  @override
  String get personalizationAccessibility => 'アクセシビリティ';

  @override
  String get personalizationHighContrast => 'ハイコントラスト';

  @override
  String get personalizationHighContrastSubtitle => 'ハイコントラストの配色を使う';

  @override
  String get personalizationHighContrastHint => 'ハイコントラストは選んだスキンより優先されます。';

  @override
  String get personalizationReduceMotion => 'モーションを減らす';

  @override
  String get personalizationVisualHapticOnly => '視覚 + 触覚のみ';

  @override
  String get personalizationVisualHapticOnlySubtitle => '通知は振動のみ';

  @override
  String get personalizationAudioAlerts => '音声アラート';

  @override
  String get personalizationAudioMaster => '音声アラート';

  @override
  String get personalizationAudioMasterDisabled => '「視覚 + 触覚のみ」により無効';

  @override
  String get personalizationAudioMasterEnabled => '既定で ON; 補助としてのみ';

  @override
  String get dashboardAudioMute => 'アラート音をミュート';

  @override
  String get dashboardAudioUnmute => 'アラート音のミュート解除';

  @override
  String get demoBanner => 'デモ';

  @override
  String get demoTooltip => 'デモモード — 無線なし。コンパニオンに接続せずにチャンネル・設定・ドキュメントを試せます。';

  @override
  String get demoModeRow => '無線なし';

  @override
  String get demoModeSubtitle => 'オフラインでアプリを試せます';

  @override
  String get firstRunHeader => 'MESHMORE · ようこそ';

  @override
  String get firstRunTitle => 'このアプリが求めるもの';

  @override
  String get firstRunBleTitle => 'Bluetooth';

  @override
  String get firstRunBleBody =>
      'MeshCore ラジオとペアリングし、ローカルメッシュ越しにメッセージを送受信します。OTA 通信に必須です。';

  @override
  String get firstRunNotificationsTitle => '通知';

  @override
  String get firstRunNotificationsBody => 'バックグラウンドで接続を維持する場合にだけ、後で確認します。';

  @override
  String get firstRunOfflineTitle => 'オフラインでも使えます';

  @override
  String get firstRunOfflineBody =>
      'Bluetooth を使わない場合、デモモードで起動します。履歴・チャネル・設定・ドキュメントは使えますが、無線の通信はありません。';

  @override
  String get firstRunGrant => 'Bluetooth を許可';

  @override
  String get firstRunSkip => 'デモモードで試す（無線なし）';

  @override
  String get firstRunDeniedTransient =>
      'このアプリでは Bluetooth がオフです。オフラインで続けるか、設定で許可してください。';

  @override
  String get firstRunDeniedPermanent =>
      'このアプリでは Bluetooth がブロックされています。設定で許可するか、オフラインのまま使ってください。';

  @override
  String get firstRunOpenSettings => 'OS 設定を開く';

  @override
  String dashboardPaired(String name) {
    return 'ペア済み: $name';
  }

  @override
  String get dashboardCharging => '充電中';

  @override
  String dashboardBatteryReadout(String volts, int percent) {
    return '${volts}V · 約$percent%';
  }

  @override
  String dashboardBatteryLeft(String time) {
    return '残り約$time';
  }

  @override
  String get nodesScanArea => '周辺をスキャン';

  @override
  String get nodesScanning => 'スキャン中…';

  @override
  String get nodesAdvertise => 'アドバート送信';

  @override
  String get nodesSyncContacts => 'コンタクト同期';

  @override
  String get nodesFloodAdvert => 'フラッドアドバート';

  @override
  String get nodesFloodAdvertBody => 'メッシュ全体 — 隣接 + リピーター。発見に最適。';

  @override
  String get nodesZeroHopAdvert => '直接アドバート';

  @override
  String get nodesZeroHopAdvertBody => '隣接のみ — 再ブロードキャストなし。混雑したメッシュ向け。';

  @override
  String get nodesFloodAdvertSent =>
      'フラッドアドバートを送信 — メッシュ全体に伝播します。相手側でも Advertise を実行するまで表示されません。';

  @override
  String get nodesZeroHopAdvertSent => '直接届く範囲のラジオにだけ送りました。';

  @override
  String get nodesSearchHint => '名前 / short ID / 公開鍵…';

  @override
  String get nodesFilterStarred => 'お気に入り';

  @override
  String get nodesFilterInRange => '範囲内';

  @override
  String get nodesFilterClear => 'クリア';

  @override
  String get nodesFiltersTitle => 'フィルター';

  @override
  String get nodesFilterLastSeenTitle => '最終受信';

  @override
  String get nodesFilterWithinTitle => '距離';

  @override
  String get nodesFiltersDone => '完了';

  @override
  String get nodesTagFilter => 'タグ';

  @override
  String get nodesAgeAny => '指定なし';

  @override
  String get nodesAgeHour => '1時間以内';

  @override
  String get nodesAge24h => '24時間以内';

  @override
  String get nodesAge7d => '7日以内';

  @override
  String get nodesDistAny => '指定なし';

  @override
  String get nodesDist100m => '100 m 以内';

  @override
  String get nodesDist500m => '500 m 以内';

  @override
  String get nodesDist5km => '5 km 以内';

  @override
  String get nodesDist25km => '25 km 以内';

  @override
  String nodesStatusReady(int shown, int total, int inRange, int favs) {
    return '$shown/$total件 表示 · $inRange件 範囲内 · $favs件 連絡先';
  }

  @override
  String get nodesStatusOffline => '未接続 — 「無線機に接続」を開いてください';

  @override
  String get nodesFarBadge => '遠距離';

  @override
  String get nodesEmptyFiltered => '条件に一致するノードがありません。';

  @override
  String get nodesEmptyReady => 'ノードはまだありません。ノードが自分を知らせると表示されます。';

  @override
  String get nodesEmptyOffline => 'ラジオを接続して周辺ノードを発見してください。';

  @override
  String get nodesFavTooltip => 'お気に入りに追加';

  @override
  String get nodesUnfavTooltip => 'お気に入りから削除';

  @override
  String get gridTitle => 'ハイパーローカルグリッド';

  @override
  String get gridShowLegend => '凡例を表示';

  @override
  String get gridHideLegend => '凡例を非表示';

  @override
  String get gridPlayTooltip => '再生 (一定間隔で更新)';

  @override
  String get gridPauseTooltip => '一時停止';

  @override
  String get gridIntervalTooltip => '更新間隔 (再生時)';

  @override
  String get gridRange => '範囲';

  @override
  String get gridRangeRoom => '部屋';

  @override
  String get gridRangeHome => '家';

  @override
  String get gridRangeBlock => 'ブロック';

  @override
  String get gridRangeNeighborhood => '近隣';

  @override
  String get gridRangeArea => 'エリア';

  @override
  String get gridRangeWide => '広域';

  @override
  String get gridRangeCity => '市';

  @override
  String get gridRangeRegion => '地域';

  @override
  String get gridLegend => '凡例';

  @override
  String gridLegendRings(String value) {
    return '輪は距離の帯です。両方に GPS があれば、外側の輪が上の範囲スケール（現在 約 $value）です。GPS がないときは電波の強さの帯（近・中・遠）です。';
  }

  @override
  String get gridLegendSelf => '中央 = 自分。十字 = 南北 / 東西の目安。';

  @override
  String get gridLegendNorth => '上が北です。円の上は端末の向きではなく真北を示します。';

  @override
  String get gridLegendDot => '点は受信したノードです。明るいほど新しく、1日かけて消えていきます。';

  @override
  String get gridLegendKnown => 'ゆっくり広がる輪は、直接やり取りしたことのあるノードです。';

  @override
  String get gridLegendFavourite => '別色での速い点滅 = お気に入りのノード。';

  @override
  String get gridLegendRipple => '中央からの波紋は、送信者が分からないチャンネルのメッセージです。';

  @override
  String get gridLegendTap => 'ノードをタップで詳細 + メッセージ / お気に入り。';

  @override
  String get gridViewRadial => 'レーダー';

  @override
  String get gridViewPicker => '表示';

  @override
  String get gridZoomWider => '広く（ズームアウト）';

  @override
  String get gridZoomTighter => '狭く（ズームイン）';

  @override
  String get gridNeedsFix => 'この表示には自分の位置が必要です。GPS 取得待ち（スマートフォンまたはデバイス）。';

  @override
  String get gridViewElevation => '高度';

  @override
  String get fujiLegendTitle => 'Fujiさん';

  @override
  String get fujiLegendDesc =>
      '標高測量。√スケール軸で有名な建造物と高さを比較。自分の標高はデバイスGPSテレメトリまたは電話の位置情報から取得。';

  @override
  String get fujiLegendMe => '破線 = あなた。標高が判明していればその位置に、未取得なら地面に「ALT?」表示。';

  @override
  String get fujiLegendRefs => 'シルエット = 実世界の基準（人 → 富士山）でスケール感を示す。';

  @override
  String get fujiLegendPeers => '点はノードです。問い合わせた標高に置かれます。';

  @override
  String get fujiLegendUnknown => '地面沿いの縞帯は、まだ標高が分からないノードです。';

  @override
  String get fujiLegendAutoQuery => '自動問い合わせは標高をゆっくり集めます。タップでやり直します。';

  @override
  String get elevationProfileTitle => 'MESHMORE :: Fujiさん';

  @override
  String get elevationProfileAltLabel => '高度';

  @override
  String get elevationProfileMeLabel => '現在地';

  @override
  String get elevationProfileUnknownLabel => '高度不明';

  @override
  String elevationProfilePeers(int n) {
    return '$n 個のノードを追跡中';
  }

  @override
  String get elevationRefPerson => '人間';

  @override
  String get elevationRefHouse => '家';

  @override
  String get elevationRefRedwood => 'セコイア';

  @override
  String get elevationRefEmpireState => 'エンパイア';

  @override
  String get elevationRefBurj => 'ブルジュ';

  @override
  String get elevationRefMtFuji => '富士山';

  @override
  String get streetMapRecenter => '現在地に戻す';

  @override
  String mapPackZoomOutside(int min, int max) {
    return 'このパックの範囲はズーム $min〜$max です。範囲外は粗いタイルで表示します。';
  }

  @override
  String deviceRegionLoadedOffline(String label) {
    return '$label を読み込みました — デバイス接続時に「適用」してください。';
  }

  @override
  String get mapFrozenBadge => '一時停止';

  @override
  String get voiceOfflineBadge => 'オフライン';

  @override
  String get dashboardLocationRefresh => 'デバイスから位置を更新';

  @override
  String dashboardLocationAltitude(int meters) {
    return '高度 $meters m';
  }

  @override
  String get deviceLocReportsAwaiting => 'デバイス報告値: (待機中)';

  @override
  String get deviceLocReportsNone => 'デバイス報告値: GPS 未取得 (0, 0)';

  @override
  String deviceLocReportsValue(String lat, String lon) {
    return 'デバイス報告値: $lat, $lon';
  }

  @override
  String get deviceLocUnsaved => '✱ 未保存';

  @override
  String get deviceGpsModule => 'オンボード GPS モジュール';

  @override
  String get deviceGpsEnable => 'オンボード GPS を有効化';

  @override
  String get deviceGpsEnabledHint =>
      'デバイスファームウェアが GPS チップを定期的に読み取り、位置を自動更新します。';

  @override
  String get deviceGpsDisabledHint => 'オフ。ラジオは GPS を読まず、最後に設定した位置を送り続けます。';

  @override
  String get deviceGpsUnknown => 'デバイス応答待ち…';

  @override
  String get deviceGpsInterval => 'GPS 更新間隔';

  @override
  String get deviceGpsIntervalOff => 'オフ';

  @override
  String deviceGpsIntervalSec(int n) {
    return '$n 秒ごと';
  }

  @override
  String deviceGpsIntervalMin(int n) {
    return '$n 分ごと';
  }

  @override
  String deviceGpsIntervalHour(int n) {
    return '$n 時間ごと';
  }

  @override
  String get deviceGpsIntervalFixedByFirmware => '無線側の設定です';

  @override
  String get locTitle => '位置の自動公開';

  @override
  String get locTileSubtitle => 'スマートフォンの位置をラジオに送ります';

  @override
  String get deviceGpsIntervalWhy =>
      'このファームウェアがセンサーの読み取り間隔を決めるため、アプリからは変更できません。';

  @override
  String get locMaster => '自動公開';

  @override
  String get locMasterOn => 'オン — 現在地をアドバートに載せて送ります';

  @override
  String get locMasterOff => 'オフ';

  @override
  String get locInterval => '定期間隔';

  @override
  String get locMovement => 'スマートブロードキャスト (移動検知)';

  @override
  String get locOff => 'オフ';

  @override
  String locIntervalMin(int n) {
    return '$n 分ごと';
  }

  @override
  String locIntervalHour(int n) {
    return '$n 時間ごと';
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
  String get locPublishNow => '今すぐ公開';

  @override
  String get locPublishNowSub => '現在地を一度だけ送ります。';

  @override
  String get locLastPublishedLabel => '最終送信';

  @override
  String get locBeacon => '定期位置ビーコン';

  @override
  String get locBeaconSub => '60秒ごとに現在地を範囲内のすべてのノードに知らせます。通信時間と電池を使います。';

  @override
  String get locBatteryHint => 'GPS を流し続けると反応は速くなりますが、電池を多く使います。';

  @override
  String get gridEmpty => 'まだ範囲内にノードがありません。\n\nノードが自分を知らせると表示されます。';

  @override
  String gridStatusCounts(int visible, int known, int favs) {
    String _temp0 = intl.Intl.pluralLogic(
      favs,
      locale: localeName,
      other: '$favs件 連絡先',
      zero: '0件 連絡先',
    );
    return '$visible件 表示 · $known件 既知 · $_temp0';
  }

  @override
  String get gridNotConnected => 'メッシュに未接続';

  @override
  String get voiceSettingsTitle => '読み上げ';

  @override
  String get voiceSettingsHint =>
      '「アプリ設定」で SPEECH を ON にするまで無効。レート / ピッチ / 音声は次の発話から適用されます。';

  @override
  String get voiceRate => '速さ';

  @override
  String get voicePitch => '高さ';

  @override
  String get voicePicker => '音声';

  @override
  String get voicePickerEmpty =>
      'プラットフォームエンジンから利用可能な音声が報告されていません — システム既定を使用します。';

  @override
  String get voicePickerOnlyMyLanguage => '現在の言語のみ表示';

  @override
  String voicePickerOnlyMyLanguageHint(String lang) {
    return 'スマートフォンの現在の言語（$lang）に一致する音声のみを表示します。オフにするとOSが報告する全音声を表示します。';
  }

  @override
  String voicePickerFilteredCount(int n, String lang) {
    return '$n 件 · $lang';
  }

  @override
  String voicePickerAllCount(int n) {
    return '$n 件 · すべて';
  }

  @override
  String voicePickerNoMatchForLanguage(String lang) {
    return '$lang の音声がインストールされていません。上のフィルターをオフにして他言語を表示するか、OS の設定から $lang の音声を追加してください。';
  }

  @override
  String get voicePickerSystem => 'システム既定';

  @override
  String get voicePreview => 'サンプル再生';

  @override
  String get voicePreviewPhrase => 'これは Meshmore SNS の音声プレビューです。';

  @override
  String get voicePreviewDisabledHint =>
      'プレビューを聴くには、アプリ設定で SPEECH を ON にしてください。';

  @override
  String get settingsHubDevice => 'デバイス設定';

  @override
  String get settingsGroupRadio => '無線';

  @override
  String get settingsGroupApp => 'アプリ';

  @override
  String get settingsGroupConnect => '接続';

  @override
  String get settingsGroupLocation => '位置情報';

  @override
  String get settingsHubLocation => '位置情報と共有';

  @override
  String get settingsGroupAbout => 'このアプリについて';

  @override
  String get settingsHubApp => 'アプリ設定';

  @override
  String get settingsHubProfile => '外観とアクセシビリティ';

  @override
  String get settingsHubChannels => 'チャンネル';

  @override
  String get settingsHubDiagnostics => '無線機の接続';

  @override
  String get bootStarting => '起動中';

  @override
  String get bootHeader => 'MESHMORE  /  同期中';

  @override
  String get bootConnecting => 'ラジオに接続中…';

  @override
  String get bootHandshaking => 'ハンドシェイク中…';

  @override
  String get bootReady => 'メッシュ オンライン';

  @override
  String get bootOffline => 'オフライン — 「無線機に接続」を開いてください';

  @override
  String get bootSkip => 'スキップ';

  @override
  String get bootSubtitle => '待機  /  WAIT';

  @override
  String eventAdvert(String name) {
    return 'アドバート · $name';
  }

  @override
  String eventChannelMsg(String channel, String text) {
    return 'ch$channel · 「$text」';
  }

  @override
  String eventDm(String text) {
    return 'DM · 「$text」';
  }

  @override
  String eventContact(String name) {
    return 'コンタクト · $name';
  }

  @override
  String eventBattery(String volts) {
    return 'バッテリー ${volts}V';
  }

  @override
  String eventDeviceError(String code) {
    return 'デバイスエラー (コード $code)';
  }

  @override
  String get eventDeviceClockSynced => 'デバイス時計 同期';

  @override
  String eventDeviceClockSkew(String seconds) {
    return 'デバイス時計 読取 (オフセット ${seconds}s)';
  }

  @override
  String get eventMsgSent => '送信 · 無線機が確認しました';

  @override
  String eventDeviceInfo(String version) {
    return 'デバイス $version';
  }

  @override
  String eventSelfInfo(String name) {
    return 'セルフ情報 · $name';
  }

  @override
  String get eventQueuedWaiting => 'キュー待機中';

  @override
  String eventQueuedWaitingN(String count) {
    return 'キュー待機中 ($count)';
  }

  @override
  String get chatManageChannels => 'チャンネル管理';

  @override
  String get chatTtsMuted => 'このチャンネルの TTS をミュート中';

  @override
  String get chatTtsActive => 'このチャンネルを TTS で読み上げ中';

  @override
  String chatRetentionDropped(int count, int cap) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '古いメッセージ$count件が削除済み',
      one: '古いメッセージ1件が削除済み',
    );
    return '$_temp0 — 各会話は最新の$cap件を保持します';
  }

  @override
  String get chatHistoryUnreadableTitle => 'この端末では履歴を開けません';

  @override
  String get chatHistoryUnreadableBody =>
      'メッセージはこの端末に残っていますが、この端末にもう無い鍵で封印されています。暗号化した書き出しから復元するまで読めません。';

  @override
  String get diagnosticsHistoryStore => '履歴ストア';

  @override
  String get diagnosticsHistoryStoreOk => '封印済みで読み取り可能';

  @override
  String get diagnosticsHistoryStoreKeyLost => '封印済みだが、鍵がこの端末にありません';

  @override
  String diagnosticsHistoryStoreWriteFailed(String code) {
    return '最後の書き込みがストアに届きませんでした（$code）';
  }

  @override
  String get chatHistoryRestoreAction => '書き出しから復元';

  @override
  String get chatRestoreMenu => '書き出しから復元…';

  @override
  String get chatRestoreNothing => '書き出しファイルをこのアプリで開くか、ここに共有してから、もう一度復元してください。';

  @override
  String get chatRestoreTitle => '会話を復元';

  @override
  String get chatRestorePassphrase => '書き出しのパスフレーズ';

  @override
  String get chatRestoreConfirm => '復元';

  @override
  String chatRestoreDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'メッセージ$count件を復元しました',
      one: 'メッセージ1件を復元しました',
    );
    return '$_temp0';
  }

  @override
  String get chatRestoreFailed => 'そのパスフレーズでは開けませんでした。書き出しファイルではない可能性があります。';

  @override
  String get diagnosticsPlaceStore => 'プレイスストア';

  @override
  String get diagnosticsPlaceStoreWriteFailed =>
      '最後の保存が届きませんでした — ピンは再起動後に残りません';

  @override
  String get diagnosticsPlaceStoreOk => '保存済み';

  @override
  String mediaReceiveDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '空きを作るため以前の転送$count件が破棄され、それらの写真は途中で止まりました',
      one: '空きを作るため以前の転送1件が破棄され、その写真は途中で止まりました',
    );
    return '$_temp0';
  }

  @override
  String get diagnosticsPlaceStoreCorruptKept => '前回のデータは読めなかったため、内容を別名で保存しました';

  @override
  String get chatEmpty => '— このチャンネルにメッセージはありません —';

  @override
  String chatJumpToNewest(int count) {
    return '新着 $count 件';
  }

  @override
  String chatComposerHint(String channel) {
    return '$channel へメッセージ';
  }

  @override
  String get chatSendNotSent => '送信できませんでした（無線機が未接続）。メッセージは入力欄に戻しました。';

  @override
  String get chatSend => '送信';

  @override
  String chatBudgetNear(int remaining) {
    return '上限が近いです:無線機は自分の名前もこのバイト数に含めます';
  }

  @override
  String chatBudgetTooLong(int over) {
    return '$over バイト超過 — 無線機は残りを通知せずに切り捨てます';
  }

  @override
  String get chatMessageActions => 'メッセージ操作';

  @override
  String get chatSinceNow => '今';

  @override
  String chatSinceMinutes(int m) {
    return '$m分';
  }

  @override
  String chatSinceHours(int h) {
    return '$h時間';
  }

  @override
  String chatSinceDays(int d) {
    return '$d日';
  }

  @override
  String dmTitle(String peer) {
    return '直接 · $peer';
  }

  @override
  String get nodeDetailSignature => 'メッセージ音';

  @override
  String get nodeDetailSignatureHint => 'この相手からのメッセージでは、通常の音の代わりに鳴ります。';

  @override
  String get nodeDetailSignatureNone => 'デフォルト';

  @override
  String nodeDetailSignatureSlot(int n) {
    return '音 $n';
  }

  @override
  String get nodeDetailSignatureMutedHint => '音声はミュート中です。振動は伝わりますが音は鳴りません。';

  @override
  String get dmEmpty => '— メッセージはまだありません —';

  @override
  String get dmOpenPeerDetail => '連絡先の詳細';

  @override
  String get dmSpeech => 'この会話を読み上げる';

  @override
  String get dmSpeechInherit => '全体の読み上げ設定に従う';

  @override
  String get dmSpeechAlways => '常に読み上げる';

  @override
  String get dmSpeechNever => '読み上げない';

  @override
  String get dmSpeechMutedByMaster => 'オーディオミュートにより消音中';

  @override
  String get dmPeerNotInFabric => 'この相手はまだメッシュで確認できていません。';

  @override
  String dmComposerHint(String peer) {
    return '$peer へメッセージ';
  }

  @override
  String get dmSend => 'DM 送信';

  @override
  String get actionCopy => 'コピー';

  @override
  String get actionDeleteLocal => 'ローカル削除';

  @override
  String get actionCopied => 'クリップボードにコピーしました';

  @override
  String get actionDeleteConfirmTitle => 'このメッセージをローカルから削除しますか?';

  @override
  String get actionDeleteConfirmBody =>
      'ローカル履歴からこの行を削除します。MeshCore に取り消しはなく、受信者側には残ります。';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionDelete => '削除';

  @override
  String get nodeDetailSelf => '自分のノードです。';

  @override
  String get nodeDetailShareTelemetryTitle => 'この連絡先と自分のテレメトリを共有';

  @override
  String get nodeDetailShareTelemetryHelp => 'テレメトリーが「連絡先」かつ Base がオンのときのみ。';

  @override
  String get nodeDetailRecentDms => '最近の DM';

  @override
  String get nodeDetailMessage => 'メッセージ';

  @override
  String get nodeIdentityTitle => '連絡先のキーが変更されました';

  @override
  String nodeIdentityBody(String name, int count) {
    return '「$name」は新しいキーで稼働中です — 相手の端末で削除・再追加された可能性があります。お気に入り・タグ・保存済みメッセージ $count 件を現在のキーに移動しますか？';
  }

  @override
  String nodeIdentityOldKey(String shortId) {
    return '旧キー …$shortId';
  }

  @override
  String get nodeIdentityAction => '現在のキーに移動';

  @override
  String nodeIdentityMoved(String name) {
    return 'データを「$name」の現在のキーに移動しました';
  }

  @override
  String get nodeIdentityLinkAction => '新しい鍵: この連絡先をリンク';

  @override
  String get nodeIdentityLinkTitle => '変更されたキーをリンク';

  @override
  String get nodeIdentityLinkHelp =>
      '同じ相手の新しい鍵です。ノードを選ぶか鍵を貼り付けると、お気に入り・タグ・メッセージが移ります。';

  @override
  String get nodeIdentityLinkEmpty =>
      'まだ他のノードがありません。新しい鍵のアドバートを待つか、鍵を貼り付けてください。';

  @override
  String get nodeIdentityLinkSearchHint => '名前で絞り込み、または公開鍵を貼り付け';

  @override
  String get nodeIdentityLinkNoMatch =>
      '一致するノードがありません — 検索をクリアするか、完全なキーを貼り付けて直接リンクしてください。';

  @override
  String get nodeIdentityLinkUseKey => 'このキーにリンク';

  @override
  String get nodeDetailNotDeviceContact => '無線機の連絡先にないため、DM が届かない場合があります。';

  @override
  String get nodeDetailAddDeviceContact => 'デバイスの連絡先に追加';

  @override
  String get nodeDetailAddDeviceContactDone => '追加しました。DM が届くようになります。';

  @override
  String get nodeDetailAddDeviceContactFailed =>
      '連絡先を追加できませんでした — リンクを確認して再試行してください。';

  @override
  String get nodeDetailRemoveDeviceContact => 'デバイスの連絡先から削除';

  @override
  String nodeDetailRemoveDeviceContactConfirm(String name) {
    return '「$name」をラジオの連絡先から削除しますか？後から追加し直せます。';
  }

  @override
  String get nodeDetailRemoveDeviceContactDone => '無線機の連絡先から削除しました。';

  @override
  String get deviceContactsTitle => '無線機の連絡先';

  @override
  String get deviceContactsRefresh => '更新';

  @override
  String get deviceContactsSyncing => '無線機から連絡先を同期中…';

  @override
  String get deviceContactsEmpty => '無線機に連絡先がありません。';

  @override
  String deviceContactsCount(int count, int max) {
    return '無線機の連絡先 $count / $max 件';
  }

  @override
  String deviceContactsCountOnly(int count) {
    return '無線機の連絡先 $count 件';
  }

  @override
  String get deviceContactsFullHelp => '連絡先がいっぱいです。下で削除すると追加できます。';

  @override
  String get deviceContactsChannelsNote => '連絡先はダイレクトメッセージ用です。';

  @override
  String get deviceContactsScrub => '連絡先を整理';

  @override
  String get deviceContactsRemoveOutOfRange => '圏外を削除';

  @override
  String get deviceContactsOutOfRangeIntro =>
      '遠い連絡先と、位置を共有していない連絡先を削除します。お気に入りと既知の連絡先は残ります。';

  @override
  String deviceContactsBeyondKm(int km) {
    return '$km km 以上（＋位置非公開）';
  }

  @override
  String get deviceContactsNeedLocation =>
      '現在地が未設定のため距離を測定できません。位置非公開の連絡先のみが対象です。位置を設定すると、遠方の GPS 連絡先も削除できます。';

  @override
  String deviceContactsRemoveOutOfRangeDone(int count) {
    return '圏外の連絡先を $count 件削除しました。';
  }

  @override
  String get deviceContactsRemoveStale => '最近未受信を削除';

  @override
  String get deviceContactsStaleIntro =>
      'しばらく受信していない連絡先を削除します。お気に入りと既知の連絡先は保持されます。';

  @override
  String deviceContactsNotHeardDays(int days) {
    return '$days 日間未受信';
  }

  @override
  String deviceContactsRemoveStaleDone(int count) {
    return '古い連絡先を $count 件削除しました。';
  }

  @override
  String get deviceContactsRemoveAll => 'すべて削除';

  @override
  String deviceContactsRemoveAllConfirm(int count) {
    return '連絡先 $count 件をすべて削除しますか？連絡先は直接メッセージを送るときだけ必要で、後から追加し直せます。';
  }

  @override
  String deviceContactsRemoveAllDone(int count) {
    return '無線機の連絡先を $count 件削除しました。';
  }

  @override
  String get deviceContactsFlood => 'フラッド';

  @override
  String get deviceContactsDirect => '直接';

  @override
  String deviceContactsHops(int n) {
    return '$n ホップ';
  }

  @override
  String nodeIdentityLinkConfirm(String from, String to) {
    return 'お気に入り・タグ・メッセージを「$from」から「$to」へ移動し、古いキーを廃止しますか？';
  }

  @override
  String get nodeDetailFavourite => 'お気に入り';

  @override
  String get nodeDetailContact => 'お気に入り済み';

  @override
  String get nodeDetailShowOnMap => '地図上に表示';

  @override
  String get nodeDetailShowOnMapFailed => 'マップアプリを開けませんでした。';

  @override
  String get nodeDetailCopyPubkey => '公開鍵をコピー';

  @override
  String get nodeDetailPubkeyCopied => '公開鍵をコピーしました';

  @override
  String get nodeDetailTags => 'タグ';

  @override
  String get nodeDetailAddTag => 'タグ';

  @override
  String get nodeDetailAddTagTitle => 'タグを追加';

  @override
  String get nodeDetailAddTagHint => '例: リピーター、職場、アマチュア無線クラブ';

  @override
  String get nodeDetailAddTagSuggestions => '最近使ったタグ';

  @override
  String get nodeDetailAddTagApply => '追加';

  @override
  String get nodeDetailInRange => '範囲内';

  @override
  String get nodeDetailKnown => '既知';

  @override
  String get nodeDetailContactBadge => 'お気に入り';

  @override
  String get nodeDetailShortIdKv => 'shortId';

  @override
  String get nodeDetailPubkeyKv => '公開鍵';

  @override
  String get nodeDetailSignalKv => '信号';

  @override
  String get nodeDetailLastHeardKv => '最終受信';

  @override
  String get nodeDetailDistanceKv => '距離';

  @override
  String get nodeDetailLatLonKv => '緯度 / 経度';

  @override
  String get gridViewTree => 'メッシュツリー';

  @override
  String get gridViewSnsCells => 'メッセージの熱';

  @override
  String get gridViewWeather => '気象';

  @override
  String get meshbookTitle => 'メッシュブック';

  @override
  String get meshbookLast24h => '直近24時間';

  @override
  String get meshbookEmpty => 'このチャンネルには直近24時間のメッセージがありません。';

  @override
  String get meshbookByHour => '時間帯別';

  @override
  String get meshbookTopVoices => 'トップ発言者';

  @override
  String get meshbookTopics => 'トピック';

  @override
  String get meshbookClear => 'クリア';

  @override
  String meshbookClearConfirm(String channel) {
    return 'CH$channel の直近24時間のメッシュブックデータをクリアしますか？新しいチャンネルメッセージが届くと再構築されます。';
  }

  @override
  String meshbookStats(int total, int replies, int pct, int voices) {
    return '$total 件 · 返信 $replies 件（$pct%）· $voices 人';
  }

  @override
  String get weatherSelf => 'このデバイス';

  @override
  String get weatherMeasuredHeader => '実測（センサー）';

  @override
  String get wxMicroclimateTitle => '微気候';

  @override
  String get wxMicroclimatesHeader => '微気候（場所別）';

  @override
  String get wxMicroclimateNearby => '近く';

  @override
  String get wxMeasured => '実測';

  @override
  String get wxAmbientEmpty =>
      'このチャンネルでは過去 24 時間に測定値のある天気報告はありません。数値と単位があるものだけを報告として扱います。';

  @override
  String wxMentionsShort(int count) {
    return '$count 件の言及';
  }

  @override
  String get wxLastHour => '1時間';

  @override
  String get wxLast24h => '24時間';

  @override
  String get wxCondClear => '晴れ';

  @override
  String get wxCondClouds => '曇り';

  @override
  String get wxCondFog => '霧';

  @override
  String get wxCondRain => '雨';

  @override
  String get wxCondSnow => '雪';

  @override
  String get wxCondWind => '風';

  @override
  String get wxCondStorm => '嵐';

  @override
  String get wxCondHeat => '暑い';

  @override
  String get wxCondCold => '寒い';

  @override
  String get weatherEmpty =>
      '環境データを報告しているノードはまだありません。\nセンサー搭載ノードが照会されると表示されます — アプリ設定で「ノードのテレメトリを収集」を有効にしてください。';

  @override
  String get weatherSelfNoTelemetry =>
      'このデバイスはまだテレメトリを返していません。接続を確認してから、この画面を開き直してください。';

  @override
  String weatherSelfNoEnv(String types) {
    return 'このデバイスのファームウェアは環境テレメトリに対応していません。\n報告内容: $types。\nセンサー（例: T1000-E の BME280）には MeshCore センサーファームウェアが必要です。標準ビルドはバッテリーと GPS のみを送信します。これはデバイス側の制限で、アプリの設定ではありません。';
  }

  @override
  String weatherReporting(int count) {
    return '$count 件が報告中';
  }

  @override
  String get docsHubSubtitle => 'プロトコル・ファームウェア・アプリ・実地メモをオフラインで。';

  @override
  String get docsHubFooter =>
      'ドキュメントはオフライン閲覧用に端末にキャッシュされます。項目を開いて ↻ で最新版を取得。出典: meshcore-dev/MeshCore。';

  @override
  String get docsProtocolTitle => 'プロトコル';

  @override
  String get docsProtocolSub => 'MeshCore コンパニオン無線プロトコル — フレーム、オペコード、フロー。';

  @override
  String get docsFirmwareTitle => 'ファームウェア';

  @override
  String get docsFirmwareSub => 'MeshCore ファームウェア概要（README）。';

  @override
  String docsFirmwareSubVersion(String version) {
    return 'MeshCore ファームウェア — $version に対応。';
  }

  @override
  String get docsAppTitle => 'アプリ';

  @override
  String get docsAppSub => 'Meshmore SNS の仕組みとメッシュの活用方法。';

  @override
  String get docsDevicesTitle => 'デバイス';

  @override
  String get docsDevicesSub =>
      '運用中の無線機（T1000-E、Wio Tracker L1 Pro、Heltec V3）の実地メモと注意点。';

  @override
  String get docsRefresh => 'GitHub から更新';

  @override
  String get docsUpdated => '最新版に更新しました';

  @override
  String get docsUpToDate => 'すでに最新です';

  @override
  String get docsOriginBundled => 'アプリに同梱';

  @override
  String docsOriginUpdated(String when) {
    return '更新: $when';
  }

  @override
  String docsFirmwareForVersion(String version) {
    return 'デバイス $version';
  }

  @override
  String get docsFirmwareNoDevice => 'デバイス未接続';

  @override
  String get docsAgoJustNow => 'たった今';

  @override
  String docsAgoMinutes(int n) {
    return '$n分前';
  }

  @override
  String docsAgoHours(int n) {
    return '$n時間前';
  }

  @override
  String docsAgoDays(int n) {
    return '$n日前';
  }

  @override
  String get weatherMin => '最低';

  @override
  String get weatherAvg => '平均';

  @override
  String get weatherMax => '最高';

  @override
  String weatherAgoSeconds(int s) {
    return '$s秒前';
  }

  @override
  String weatherAgoMinutes(int m) {
    return '$m分前';
  }

  @override
  String weatherAgoHours(int h) {
    return '$h時間前';
  }

  @override
  String get snsCellsClear => 'クリア';

  @override
  String snsCellsStatus(int active, int hot) {
    String _temp0 = intl.Intl.pluralLogic(
      active,
      locale: localeName,
      other: '$active セル',
      one: '1 セル',
    );
    String _temp1 = intl.Intl.pluralLogic(
      hot,
      locale: localeName,
      other: '$hot ホット',
      one: '1 ホット',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get snsFrameMetro => 'メトロ · 約20 km';

  @override
  String get snsFrameRegion => '地域 · 約300 km';

  @override
  String get snsFrameMesh => 'メッシュ · 全体';

  @override
  String get snsCellsLegendTitle => 'SNS セル';

  @override
  String get snsCellsLegendDesc =>
      'ライブのソーシャル活動ヒートマップ。観測したメッセージごとにセルが温まり、1時間の地平で冷えていきます。';

  @override
  String get snsCellsLegendHot => '明るい赤 = 活発（直近1分で約5件以上）。';

  @override
  String get snsCellsLegendCool => '白へ退色 = 沈静化。約1時間無活動で消滅。';

  @override
  String get snsCellsLegendToast => '新着メッセージは発信元付近にトーストで点滅し、消えます。';

  @override
  String get snsCellsLegendChannel =>
      'チャンネルメッセージは送信者名を含みます。送信者の位置が分かればそのセルを、分からなければ自分のセルを温めます。';

  @override
  String get snsCellsLegendDecay => '直近1時間のみ追跡。保存はされません。';

  @override
  String get meshTreeEmpty => 'コンタクト同期を待機中 — ツリーは各コンタクトの outPath から構築されます。';

  @override
  String meshTreeFilteredEmptyFor(String stop, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$stop に経路が分かっている相手はいません。経路不明の相手が $count 台います。「Flood / All」で表示されます。',
      one: '$stop に経路が分かっている相手はいません。経路不明の相手が 1 台います。「Flood / All」で表示されます。',
    );
    return '$_temp0';
  }

  @override
  String get meshTreeKey => '■ 中継機   ● クライアント   ◆ ルーム   ○ アナウンスのみ';

  @override
  String get meshTreeLearnRoutes => '無線機に経路を問い合わせる';

  @override
  String get meshTreeLearning => '無線機に問い合わせ中…';

  @override
  String get meshTreeNoRoutes =>
      'この無線機はまだ経路を学習していないため、すべての相手を表示しています。学習すると停止位置が使えるようになります。';

  @override
  String get meshTreeHopsDirect => '直接';

  @override
  String get meshTreeHopsFlood => 'フラッド / 全て';

  @override
  String meshTreeHopsN(int n) {
    return '≤$n ホップ';
  }

  @override
  String meshTreeHopsRouted(int count) {
    return '経路あり $count 件';
  }

  @override
  String get meshTreeHopsNoRoutes => '経路なし';

  @override
  String get meshTreeRecenter => '中央に戻す';

  @override
  String get meshTreeLegendTitle => 'メッシュツリー';

  @override
  String get meshTreeLegendDesc =>
      '無線がどの経路で各コンタクトに到達するかの有向グラフ。各エッジは、実際に送信に使う経路上のリピーターです。';

  @override
  String get meshTreeLegendSelf => 'あなた — 中央に固定。';

  @override
  String get meshTreeLegendRepeater => '四角はリピーターです。他のラジオのメッセージを中継します。';

  @override
  String get meshTreeLegendRoom => 'ひし形はルームサーバです。名前付きのルームを提供するラジオです。';

  @override
  String get meshTreeLegendChat => '円は、直接メッセージできるノードです。';

  @override
  String get meshTreeLegendSensor => '小さく暗い円はセンサーです。計測値だけを送ります。';

  @override
  String get meshTreeLegendFlood =>
      '破線で自分とつながる = フラッドルーティングのコンタクト。到達可能だが固定経路なし。';

  @override
  String get meshTreeLegendFloat => '浮遊（エッジなし）— advert のみで受信、経路不明。';

  @override
  String get meshTreeLegendArrow => '矢印は自分から目的ピアへ向かう。';

  @override
  String get meshTreeLegendInteract => 'ノードをタップで詳細、「中央に戻す」で表示を戻します。';

  @override
  String get nodeDetailHopsKv => 'ホップ数';

  @override
  String get nodeDetailHopsDirect => '直接';

  @override
  String nodeDetailHopsViaRepeaters(int n) {
    return '$n';
  }

  @override
  String get nodeDetailHopsUnknown => '不明';

  @override
  String get nodeDetailHopsFlood => 'フラッド';

  @override
  String get nodeDetailAltitudeKv => '標高';

  @override
  String nodeDetailAltitudeMeters(String m) {
    return '$m m';
  }

  @override
  String get nodeDetailTempKv => '温度';

  @override
  String nodeDetailTempValue(String c) {
    return '$c °C';
  }

  @override
  String get nodeDetailHumidityKv => '湿度';

  @override
  String nodeDetailHumidityValue(String p) {
    return '$p%';
  }

  @override
  String get nodeDetailPressureKv => '気圧';

  @override
  String nodeDetailPressureValue(String hpa) {
    return '$hpa hPa';
  }

  @override
  String get nodeDetailLuminosityKv => '照度';

  @override
  String get nodeDetailQueryTelemetry => 'テレメトリを取得';

  @override
  String get nodeDetailRefreshTelemetry => 'テレメトリを更新';

  @override
  String get nodeDetailTelemetryQuerying => 'ラジオに計測値を問い合わせ中…';

  @override
  String get nodeDetailTelemetryNotContact => 'デバイスの連絡先ではないため、テレメトリは取得できません。';

  @override
  String nodeDetailTelemetryAge(String age) {
    return '$age前のテレメトリ';
  }

  @override
  String nodeDetailAgoSeconds(int n) {
    return '$n秒前';
  }

  @override
  String nodeDetailAgoMinutes(int n) {
    return '$n分前';
  }

  @override
  String nodeDetailAgoHours(int n) {
    return '$n時間前';
  }

  @override
  String nodeDetailAgoDays(int n) {
    return '$n日前';
  }

  @override
  String get channelsTitle => 'チャンネル';

  @override
  String get channelsHelp =>
      'チャンネル 0 は共有のパブリックです。非公開にするには、どのラジオでも同じ番号・名前・鍵にします。';

  @override
  String get channelsOfflineHint => 'チャンネルを編集するにはラジオを接続 (診断)。';

  @override
  String get channelCreateCreated => 'チャンネルを作成しました。';

  @override
  String get channelCreateTitle => '新しいチャンネル';

  @override
  String get channelCreateIntro => '名前を決めて、誰が読めるかを選びます。';

  @override
  String get channelCreateNameHint => '例: basecamp';

  @override
  String get channelCreateNameKeyedTitle => '名前を知っている人';

  @override
  String get channelCreateNameKeyedBody =>
      '名前から鍵を作るので、同じ名前を入力した無線機だけが参加できます。それ以外は読めません。';

  @override
  String get channelCreatePublicTitle => 'パブリックチャンネル';

  @override
  String get channelCreatePublicBody =>
      '電波の届く範囲でパブリックチャンネルを使う全員が読めます。公開前提のときだけ選んでください。';

  @override
  String channelCreateSlotNote(Object slot) {
    return 'スロット $slot（空いている最初の枠）に作成します。';
  }

  @override
  String get channelCreateNoSlot => 'この無線機のチャンネル枠はすべて使用中です。先にチャンネル画面で空けてください。';

  @override
  String channelCreateExists(String name) {
    return '$name というチャンネルはすでにあります。';
  }

  @override
  String get channelCreateAction => '作成';

  @override
  String get channelsEmpty => '— 未設定 —';

  @override
  String channelsSlotLabel(int idx) {
    return 'チャンネル $idx';
  }

  @override
  String channelsSlotActive(int idx) {
    return 'チャンネル $idx · 有効';
  }

  @override
  String get channelsEdit => '編集';

  @override
  String get channelsSet => '設定';

  @override
  String channelsSetSnack(int idx) {
    return 'スロット $idx を保存しました';
  }

  @override
  String channelsDialogTitle(int idx) {
    return 'チャンネル $idx';
  }

  @override
  String get channelsName => 'チャンネル名';

  @override
  String get channelsInferPlaces => 'メッセージから地名を探す';

  @override
  String get channelsInferPlacesSub =>
      'このチャンネルのメッセージから地名を探し、メッセージの下に候補として表示します。そこから報告できます。';

  @override
  String notifTitleChannel(String name) {
    return '$name のメッセージ';
  }

  @override
  String notifTitleDirect(String name) {
    return '$name からのダイレクトメッセージ';
  }

  @override
  String get notifTitleSos => '緊急アラート';

  @override
  String get notifBodySos => '位置はアプリで確認してください。警報には座標が含まれますが、ロック画面には表示しません。';

  @override
  String get notifAlarmRunningBody => '警報を繰り返し送信中です。アプリを開いて停止してください。';

  @override
  String get notifSectionTitle => '通知';

  @override
  String get notifMutedNoticeHere => '通知は停止中です。再び有効にすると下のスイッチが効きます。';

  @override
  String get notifMuted => 'このチャンネルを通知停止';

  @override
  String get settingsSilencePerChannel => 'チャンネルの通知を止める';

  @override
  String get notifMutedSub => 'メッセージは保存し、通知・読み上げ・バッジだけ止めます。';

  @override
  String get notifOs => '通知を表示';

  @override
  String get notifAudio => '音を鳴らす';

  @override
  String get notifHaptic => '振動';

  @override
  String get notifTts => '読み上げ';

  @override
  String get notifMentionsOnly => '自分の名前が出たときだけ';

  @override
  String get notifMentionsOnlySub => '単語全体か @名前。オフなら全メッセージで通知します。';

  @override
  String get notifKeySuffix => 'ID の末尾 4 文字にも一致させる';

  @override
  String get notifKeySuffixSub => '4 文字は誰でも選べるので、送信者が確かなとき以外はオフにしてください。';

  @override
  String get notifDeniedBanner => 'このアプリの通知がオフのため、メッセージはロック画面に表示されません。';

  @override
  String get notifQuietBanner =>
      'このアプリの通知が Android 設定でサイレントになっているため、警告音は鳴りません。';

  @override
  String get notifMissingChannelBanner =>
      'このアプリの通知チャンネルが削除されていたため、一部の通知を表示できませんでした。再作成しました。';

  @override
  String get channelsKeyPublic => 'Public';

  @override
  String get channelsKeyHashtag => '#タグ';

  @override
  String get channelsKeyHex => 'Hex';

  @override
  String get channelsKeyPublicBody => '公開チャンネル既定鍵を使用。';

  @override
  String get channelsKeyHashtagHint => '例: #mygroup';

  @override
  String get channelsKeyHashtagHelper => 'sha256(\"#タグ\") から鍵を導出 — # も鍵の一部です';

  @override
  String get channelsKeyHexHint => '16 進 32 文字 (16 バイト)';

  @override
  String get channelsErrorTag => '#ハッシュタグを入力してください';

  @override
  String get channelsErrorHex => '鍵は 0〜9 か A〜F の 32 文字です';

  @override
  String get channelsErrorName => 'チャンネル名を入力してください';

  @override
  String get channelsCancel => 'キャンセル';

  @override
  String get channelsSave => '保存';

  @override
  String get channelsHelpEncryption => 'チャンネル 0 の鍵は公開です。他のチャンネルは設定した鍵を使います。';

  @override
  String get channelsHexGenerate => 'ランダムな鍵を作る';

  @override
  String get channelsHexCopy => 'コピー';

  @override
  String get channelsHexCopied => '鍵をコピーしました';

  @override
  String get channelsTagWeakShort => '短いタグは推測されやすい。12 文字以上または独自の表現を使用してください。';

  @override
  String get channelsTagWeakCommon =>
      '一般的な単語は推測されやすい — 攻撃者にタグ総当りを許します。独自の表現を使用してください。';

  @override
  String get channelsSlot0WarnTitle => 'Public チャンネルを上書きしますか?';

  @override
  String get channelsSlot0WarnBody =>
      'チャンネル 0 は共有のパブリックです。ここに非公開の鍵を入れると、同じ鍵のラジオとしか通信できず、パブリックを失います。続行しますか？';

  @override
  String get channelsSlot0WarnContinue => 'チャンネル 0 を上書き';

  @override
  String get channelsSlot0WarnCancel => 'キャンセル';

  @override
  String get channelsCurrentKey => '現在の鍵';

  @override
  String get channelsRevealKey => '表示';

  @override
  String get channelsHideKey => '隠す';

  @override
  String get channelsClear => 'チャンネルをリセット';

  @override
  String channelsClearConfirmTitle(int idx) {
    return 'チャンネル $idx をリセットしますか？';
  }

  @override
  String get channelsClearConfirmBody =>
      'ラジオに空のチャンネルはないので、このチャンネルは公開の名前と鍵に戻ります。他のラジオも同じにしないと、ここで通信できません。';

  @override
  String get channelsClearConfirmAction => 'クリア';

  @override
  String channelsClearSnack(int idx) {
    return 'チャンネル $idx を公開の既定値に戻しました';
  }

  @override
  String get channelsDefaultBadge => '既定';

  @override
  String get channelsSetDefaultTooltip => '起動時の既定チャンネルに設定';

  @override
  String get channelsClearDefaultTooltip => '既定チャンネル設定を解除';

  @override
  String channelsSetDefaultSnack(int idx) {
    return 'チャンネル $idx を起動時に開くよう設定しました';
  }

  @override
  String get channelsClearedDefaultSnack => '起動時の既定を解除しました';

  @override
  String get channelsKeyShake => '振る';

  @override
  String get channelsShakeTitle => 'シェイクでダイスロール';

  @override
  String get channelsShakeBody =>
      'スマートフォンを振ってください — 検出された動きサンプルがハッシュに加算されます。リングが満たされたら停止。';

  @override
  String channelsShakeProgress(int accepted, int target, int pct) {
    return '$accepted / $target サンプル · $pct%';
  }

  @override
  String get channelsShakeReroll => '再ロール';

  @override
  String get channelsShakeTapFallback =>
      'タップでロール (reduceMotion 有効 — Random.secure を使用)';

  @override
  String get channelsShareQr => 'QR で共有';

  @override
  String channelsQrTitle(int idx) {
    return 'チャンネル $idx を共有';
  }

  @override
  String get channelsQrBody =>
      'Meshmore の端末や QR リーダーでスキャンします。このコードを持つ人はチャンネルに参加できるので、信頼できる相手にだけ見せてください。';

  @override
  String get channelsQrPayload => 'チャンネルコード（コピーできます）';

  @override
  String get channelsQrClose => '閉じる';

  @override
  String get deviceConfigTitle => 'デバイス設定';

  @override
  String get deviceRegionBand => 'バンドプリセット';

  @override
  String get deviceRegionWhy => '理由';

  @override
  String get deviceRegionCaveatTitle => '地域の注意';

  @override
  String get deviceRegionCaveatClose => '閉じる';

  @override
  String get deviceRegionCurrent => '現在の設定';

  @override
  String get deviceRegionUnknown => 'デバイス応答待ち…';

  @override
  String get deviceRegionCustom => 'カスタム';

  @override
  String get deviceRegionSuggestFromLocation => '現在地から自動選択';

  @override
  String get deviceRegionFamilyAmericas => 'アメリカ';

  @override
  String get deviceRegionFamilyEurope => 'ヨーロッパ';

  @override
  String get deviceRegionFamilyAsiaPacific => 'アジア太平洋';

  @override
  String get deviceRegionFamilyOther => 'その他';

  @override
  String get deviceRegionSuggestTitle => '現在地のプリセットを使いますか？';

  @override
  String deviceRegionSuggestBody(String lat, String lon, String label) {
    return 'スマートフォンの GPS（$lat, $lon）に該当するプリセットは「$label」です。適用前に、現地の法令に適合するか確認してください。';
  }

  @override
  String get deviceRegionSuggestApply => '使う';

  @override
  String get deviceRegionSuggestNoFix =>
      'まだ GPS を取得できません。屋外で位置情報をオンにして試してください。';

  @override
  String get deviceRegionSuggestNoMatch => '現在地が出荷時プリセットの対象外です — 手動で選択してください。';

  @override
  String get deviceRegionDisclaimerShort => '利用者どうしの値で、規制当局の確認はありません。';

  @override
  String get deviceRegionDisclaimer =>
      'プリセットは利用者どうしで共有されている値で、規制当局の確認を受けたものではありません。利用地で合法なものを選び、どのラジオでも同じ設定にしてください。日本では無線機自体が技適を取得している必要があり、輸入したボードの多くは未取得です。設定にかかわらず、未取得機の使用は電波法違反になります。日本（ARIB STD-T108）のプリセットはコミュニティ提案で、広く検証されたものではありません。';

  @override
  String get presetUsCanada => '米国 / カナダ';

  @override
  String get presetUsArizona => '米国 — アリゾナ';

  @override
  String get presetJpAribT108 => '日本（ARIB STD-T108）';

  @override
  String get presetJpMeshcore => '日本（MeshCore-JP）';

  @override
  String get presetEuUkLong => 'EU / UK（長距離）';

  @override
  String get presetEuUkMedium => 'EU / UK（中距離）';

  @override
  String get presetEuUkNarrow => 'EU / UK（狭帯域）';

  @override
  String get presetCh => 'スイス';

  @override
  String get presetCz => 'チェコ';

  @override
  String get presetPt869 => 'ポルトガル（869 MHz）';

  @override
  String get presetAu => 'オーストラリア';

  @override
  String get presetAuNarrow => 'オーストラリア（狭帯域）';

  @override
  String get presetAuSaWaQld => 'オーストラリア（SA / WA / QLD）';

  @override
  String get presetNz => 'ニュージーランド';

  @override
  String get presetVn => 'ベトナム';

  @override
  String get cancel => 'キャンセル';

  @override
  String get closeSheet => '閉じる';

  @override
  String get deviceRadioParams => '無線';

  @override
  String get deviceIdentityAdvert => '識別とアドバート';

  @override
  String get deviceChannelsSection => 'チャンネル';

  @override
  String get deviceOtherParamsSection => '詳細設定';

  @override
  String get deviceDeviceSection => 'デバイス';

  @override
  String get deviceFrequency => '周波数 (MHz)';

  @override
  String get deviceBandwidth => '帯域幅 (kHz)';

  @override
  String get deviceSpreadingFactor => '拡散率 (5–12)';

  @override
  String get deviceCodingRate => '符号化率 (5–8)';

  @override
  String get deviceTxPower => '送信電力 (dBm)';

  @override
  String get devicePathHashSize => 'パスハッシュ長';

  @override
  String get devicePathHashSizeHelp =>
      'このラジオが送信するパケットに付けるハッシュ長です。中継は各パケット自身の長さに従うため、ノード間で揃える必要はありません。長いほど中継を区別しやすい一方、ペイロード容量が減ります。';

  @override
  String get devicePathHashUnread => '無線機はまだハッシュ長を伝えていません。';

  @override
  String devicePathHashMismatch(String device, String form) {
    return '無線: $device。この画面: $form。適用を押すと画面の値が送られます。';
  }

  @override
  String get deviceRadioApplied => '無線機が変更を確認しました。';

  @override
  String deviceRadioRefused(String param, String code) {
    return '無線機が $param を拒否しました(エラー $code)。以降の書き込みは送信していません。';
  }

  @override
  String deviceRadioSilent(String param) {
    return '$param の応答が5秒以内にありません。書き込みが反映されていない可能性があります。';
  }

  @override
  String deviceRadioUnsupported(String param) {
    return '$param はこのファームウェアにありません。';
  }

  @override
  String get deviceRadioUnknownState =>
      '無線設定を変更できません: この無線機はパスハッシュ長をまだ報告していないため、戻す値がありません。';

  @override
  String get deviceRadioRevert => '無線設定を元に戻す';

  @override
  String get deviceRadioReverted => '以前の設定に戻しました。';

  @override
  String get deviceRadioRevertUnavailable => '元に戻せるのは一度だけです。';

  @override
  String get deviceRadioRevertFailed => '元に戻せませんでした — 無線機は直前の値のままです。';

  @override
  String get radioHealthTitle => '無線の状態';

  @override
  String get radioHealthRead => '取得';

  @override
  String get radioHealthReading => '取得中…';

  @override
  String get radioHealthUnread => 'まだ読み取っていません。';

  @override
  String radioHealthNoise(String dbm) {
    return 'ノイズ $dbm dBm';
  }

  @override
  String radioHealthLast(String rssi, String snr) {
    return '直近 $rssi dBm · SNR $snr dB';
  }

  @override
  String radioHealthBattery(String volts) {
    return '電池 $volts V';
  }

  @override
  String get radioHealthNotReported => '未報告';

  @override
  String radioHealthUptime(String uptime) {
    return '稼働 $uptime';
  }

  @override
  String get radioHealthSource => '無線の値です';

  @override
  String radioHealthAckTrip(int ms) {
    return '最後の確認応答: 往復 $ms ms（無線機の計測値）';
  }

  @override
  String get deviceLoadFromDevice => 'デバイスから読込';

  @override
  String get deviceApplyRadio => 'ラジオパラメータを適用';

  @override
  String get deviceConnectFirst => 'まずラジオに接続してください (診断 & 接続)。';

  @override
  String get deviceAdvertName => 'アドバート名';

  @override
  String get deviceSetName => '名前を設定';

  @override
  String get deviceAdvertLatitude => 'アドバート緯度 (°)';

  @override
  String get deviceAdvertLongitude => 'アドバート経度 (°)';

  @override
  String get deviceUsePhoneLocation => 'スマートフォンの位置を使用';

  @override
  String get deviceReadDeviceLocation => 'デバイスの位置を読込';

  @override
  String get deviceSetAdvertLocation => 'アドバート位置を設定';

  @override
  String get deviceAdvertSource => 'アドバート位置ソース';

  @override
  String get deviceAdvertSourceNone => 'なし';

  @override
  String get deviceAdvertSourcePinned => 'ピン留め';

  @override
  String get deviceAdvertSourceGps => 'デバイス GPS';

  @override
  String get deviceToastNameEmpty => 'ノード名を入力してください';

  @override
  String get deviceToastNameSet => '名前を更新 — 隣接ノードへ再アドバート中';

  @override
  String deviceToastSendFailed(String error) {
    return '送信失敗: $error';
  }

  @override
  String get deviceToastNoDeviceYet => 'デバイス未応答 — 接続後に再試行';

  @override
  String get deviceToastNoGpsYet => 'デバイスにまだ位置情報がありません (GPS 未取得)';

  @override
  String get deviceToastLoadedDeviceLoc =>
      'デバイス位置を読込 · ブロードキャストするには「アドバート位置を設定」をタップ';

  @override
  String get deviceToastGettingPhoneFix => 'スマートフォン GPS を取得中…';

  @override
  String get deviceToastPhoneFixFailed => 'スマートフォン GPS の取得失敗 (サービス無効またはタイムアウト)';

  @override
  String get deviceToastNoFixReturned => '位置情報が返されませんでした';

  @override
  String get deviceToastGotPhoneLoc =>
      'スマートフォン位置を取得 · ブロードキャストするには「アドバート位置を設定」をタップ';

  @override
  String get deviceToastInvalidLatLon => '有効な緯度 (−90..90) と経度 (−180..180) を入力';

  @override
  String get deviceToastAdvertLocSet => 'アドバート位置を設定しました';

  @override
  String get deviceToastInvalidRadio => 'freq/BW/SF/CR に有効な数値を入力';

  @override
  String get deviceLocPermDenied => 'スマートフォン GPS 取得には位置情報の許可が必要です。';

  @override
  String get deviceLocPermDeniedPerm => '位置情報が永続的に拒否されました — OS 設定で許可してください。';

  @override
  String get deviceOpenSettings => '設定を開く';

  @override
  String get connectionDiagnosticsRow => '診断とツール';

  @override
  String get connectionDiagnosticsExplainer => '生フレーム、フィクスチャ、テストコマンド。';

  @override
  String get diagnosticsTitle => '無線機の診断';

  @override
  String get diagnosticsRawFrameLog => 'RAW フレームログ (新しい順)';

  @override
  String get diagnosticsDisconnect => '切断';

  @override
  String get diagnosticsCopyLog => 'ログをコピー';

  @override
  String get otherManualAddTitle => 'コンタクトを手動追加';

  @override
  String get otherManualAddSubOn => '受信したノードは必要時に手動でコンタクトに追加します。';

  @override
  String get otherManualAddSubOff => '受信したノードは連絡先として保存されます。';

  @override
  String get otherTelemetryModeTitle => 'テレメトリを読める相手';

  @override
  String get otherTelemetryBase => '基本';

  @override
  String get otherTelemetryLoc => '位置';

  @override
  String get otherTelemetryEnv => '環境';

  @override
  String get otherTelemetryDeny => 'オフ';

  @override
  String get otherTelemetryFlags => '連絡先';

  @override
  String get otherTelemetryAll => '全員';

  @override
  String get otherTelemetryModeHelp => 'この端末からバッテリー・GPS・環境データを要求できる相手を設定します。';

  @override
  String get otherMultiAcksLabel => '追加の確認 (0–3)';

  @override
  String get otherMultiAcksHelper =>
      '0 が既定です。大きくすると、その数だけ多くのラジオの確認を待ってから送信済みとみなします。';

  @override
  String get otherSentSnack => 'OTHER PARAMS を送信 — デバイス側の書込に時間がかかる場合があります。';

  @override
  String get otherAwaitingDevice => '— デバイス待機中 —';

  @override
  String get batteryTitle => 'バッテリー';

  @override
  String get batteryConfigSubtitle => '充電量・消費レート・残り時間の推定';

  @override
  String get batteryAwaiting => 'デバイスからのバッテリー値を待機中…';

  @override
  String get batteryReset => '履歴をリセット';

  @override
  String get batteryResetConfirm =>
      '保存済みのバッテリー履歴をすべて消去しますか？新しい値が届くと推定は再構築されます。';

  @override
  String get batteryVoltageLabel => '電圧';

  @override
  String get batteryCharging => '充電中';

  @override
  String get batteryChargingNote => '充電中 — 残り時間の推定は一時停止しています。';

  @override
  String get batteryTimeToEmpty => '残り時間';

  @override
  String get batteryEstimating => '消費データを収集中 — 数分間の放電後に推定値が表示されます。';

  @override
  String get batteryDrainRate => '消費レート';

  @override
  String get batteryBasis => '根拠';

  @override
  String batteryBasisObserved(String span) {
    return '$span の放電実測に基づく';
  }

  @override
  String get batteryBasisRated => '定格 (容量 ÷ 標準消費電流)';

  @override
  String get batteryConfidence => '信頼度';

  @override
  String get batteryConfHigh => '高';

  @override
  String get batteryConfMedium => '中';

  @override
  String get batteryConfLow => '低';

  @override
  String get batteryMethodObserved => '放電実測';

  @override
  String get batteryMethodRated => '定格推定';

  @override
  String get batteryMethodNone => 'データ収集中';

  @override
  String get batterySpecTitle => 'デバイスモデル';

  @override
  String get batterySpecGeneric =>
      '不明なハードウェア — 汎用の単セル Li-ion モデルを使用します。定格容量での照合ができないため、推定は実測消費に依存します。';

  @override
  String batterySpecCapacity(int mah) {
    return '容量: $mah mAh';
  }

  @override
  String get batterySpecCapacityUnknown => '容量: ユーザー供給 (不明)';

  @override
  String batterySpecDraw(int ma) {
    return '標準消費: 約 $ma mA (受信時)';
  }

  @override
  String get batteryHistoryTitle => '電圧履歴';

  @override
  String batteryHistorySpan(String span, int count) {
    return '$span · $count サンプル';
  }

  @override
  String batteryDurDH(int days, int hours) {
    return '$days日 $hours時間';
  }

  @override
  String batteryDurHM(int hours, int mins) {
    return '$hours時間 $mins分';
  }

  @override
  String batteryDurM(int mins) {
    return '$mins分';
  }

  @override
  String get deliverySending => '送信中…';

  @override
  String get deliverySent => 'メッシュへ送信済み';

  @override
  String get deliveryDelivered => '配信完了 (受信側が確認)';

  @override
  String get deliveryFailed => '未配信 — 確認応答なし、または送信失敗';

  @override
  String get deliveryUnknown => 'アプリ終了中に送信 — 無線機が送信したかは不明です';

  @override
  String get settingsHubTools => 'ツール';

  @override
  String get toolsTitle => 'ツール';

  @override
  String get toolsOffline => '未接続 — ツールには無線機が必要です。「無線機に接続」を開いてください';

  @override
  String get toolsRunning => '実行中';

  @override
  String get toolsStart => '開始';

  @override
  String get toolsStop => '停止';

  @override
  String get toolsCopyReport => '結果をコピー';

  @override
  String get toolsCopied => 'クリップボードにコピーしました';

  @override
  String get toolsCount => '回数';

  @override
  String get toolsInterval => '間隔';

  @override
  String toolsSeconds(int n) {
    return '$n 秒';
  }

  @override
  String toolsMinutes(int n) {
    return '$n 分';
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
  String get toolsChoose => '選択…';

  @override
  String get toolStatsName => '無線統計';

  @override
  String get toolStatsSub => 'ノイズフロア・エアタイム・パケット数';

  @override
  String get toolPingName => 'Ping';

  @override
  String get toolPingSub => 'コンタクトへの往復: 損失と RTT';

  @override
  String get toolTraceName => 'パストレース';

  @override
  String get toolTraceSub => 'リピーター経路のホップごとの SNR';

  @override
  String get toolDiscoverName => '近隣探索';

  @override
  String get toolDiscoverSub => 'こちらが聞こえるリピーターと双方向の SNR';

  @override
  String get toolSoakName => 'ソークテスト';

  @override
  String get toolSoakSub => '連番メッセージを計数 — ボットと組み合わせ';

  @override
  String get toolRangeName => 'レンジテスト';

  @override
  String get toolRangeSub => 'ビーコン送信または受信記録 (SNR・距離付き)';

  @override
  String get toolFailNotConnected => '無線機に接続されていません。';

  @override
  String get toolFailBusy => '別のツールが無線機を使用中です。先に停止してください。';

  @override
  String get toolFailUnsupported => 'この無線機のファームウェアは未対応です。';

  @override
  String get toolFailNotFound => '無線機にこのコンタクトがありません。';

  @override
  String get toolFailTableFull => '無線機がビジーです (送信テーブル満杯)。少し待って再試行してください。';

  @override
  String get toolFailRejected => '無線機が要求を拒否しました。';

  @override
  String get toolFailNoConfirm => '無線機が送信を確認しませんでした。';

  @override
  String get toolFailPublic =>
      'Public は使用できません: 全ての無線機に届きます。プライベートチャンネルか DM を使ってください。';

  @override
  String get toolFailUnknownChannel => 'このチャンネルの鍵をまだ無線機から読み込んでいません。';

  @override
  String get toolFailNoTarget => '先に対象を選んでください。';

  @override
  String get statsRefresh => '更新';

  @override
  String get statsAuto => '自動 (5 秒ごと)';

  @override
  String get statsSectionRadio => '無線';

  @override
  String get statsSectionPackets => 'パケット';

  @override
  String get statsSectionCore => 'コア';

  @override
  String get statsNoise => 'ノイズフロア';

  @override
  String get statsLastRssi => '直近 RSSI';

  @override
  String get statsLastSnr => '直近 SNR';

  @override
  String get statsTxAir => '送信エアタイム';

  @override
  String get statsRxAir => '受信エアタイム';

  @override
  String get statsDuty => 'デューティ比 (送信)';

  @override
  String get statsReceived => '受信';

  @override
  String get statsSent => '送信';

  @override
  String statsSplit(int flood, int direct) {
    return 'フラッド $flood · 直接 $direct';
  }

  @override
  String get statsRxErrors => '受信エラー';

  @override
  String get statsUptime => '稼働時間';

  @override
  String get statsQueue => '送信キュー';

  @override
  String get statsErrFlags => 'エラーフラグ';

  @override
  String get statsBattery => 'バッテリー';

  @override
  String get statsNotFetched => 'まだ取得していません。';

  @override
  String get pingTarget => '対象';

  @override
  String get pingMethodStatus => 'ステータス要求 — リピーター・ルーム・センサーが応答します。';

  @override
  String get pingMethodTelemetry => '計測値を求めます。相手のラジオが共有している場合だけ応答します。';

  @override
  String pingSummary(int sent, int replied, int lost) {
    return '送信 $sent · 応答 $replied · 損失 $lost';
  }

  @override
  String pingRtt(int min, int avg, int max) {
    return 'RTT 最小 $min · 平均 $avg · 最大 $max ms';
  }

  @override
  String get pingLost => '損失';

  @override
  String get pingWaiting => '待機中…';

  @override
  String get pingNoContacts => '同期済みコンタクトがありません — Ping できるのはコンタクトのみです。';

  @override
  String get pingLastStatus => '直近のステータス';

  @override
  String get traceToNode => 'ノードへ';

  @override
  String get traceManual => '手動';

  @override
  String get traceRoundTrip => '往復 (こちらに戻す)';

  @override
  String get traceNoRoute => '経路なし — 先にメッセージを送ってください';

  @override
  String tracePath(String path) {
    return '経路 $path';
  }

  @override
  String get traceManualHint => 'ハッシュ (例: a1,7f,a1)';

  @override
  String get traceInvalid => '16 進バイトを 1 つ以上入力してください。';

  @override
  String get traceRun => 'トレース';

  @override
  String get traceNoAnswer => '応答なし';

  @override
  String get traceToUs => '→ 自分';

  @override
  String traceWeakest(String hop, String snr) {
    return '最弱: $hop, $snr dB';
  }

  @override
  String get traceReset => '経路をリセット';

  @override
  String get traceResetDone => '経路をリセットしました — 次のメッセージはフラッドします。';

  @override
  String get traceNoRepeaters =>
      'トレースには経路上のリピーターが必要です: リピーターか、リピーター経由のコンタクトを選んでください。';

  @override
  String get discoverStart => '探索';

  @override
  String discoverListening(int s) {
    return '受信待ち… $s 秒';
  }

  @override
  String get discoverNone => '応答したリピーターはありません。';

  @override
  String discoverTheyHearUs(String snr) {
    return '相手→自分 $snr dB';
  }

  @override
  String discoverWeHearThem(String snr, int rssi) {
    return '自分→相手 $snr dB / $rssi dBm';
  }

  @override
  String get discoverAsymmetric => '非対称リンク';

  @override
  String get soakScope => '会話';

  @override
  String get soakPairHint => '相手側の R59 ボットと組み合わせると、エコーで欠落・重複・順序入れ替わりがわかります。';

  @override
  String soakSummary(int sent, int delivered, int failed) {
    return '送信 $sent · 配達 $delivered · 失敗 $failed';
  }

  @override
  String soakEchoes(int echoed, int dup, int reordered) {
    return 'エコー $echoed · 重複 $dup · 順序違い $reordered';
  }

  @override
  String get soakListening => '送信完了 — 遅れたエコーを待っています…';

  @override
  String soakRun(String id) {
    return '実行 $id';
  }

  @override
  String soakEcho(int ms) {
    return 'エコー $ms ms';
  }

  @override
  String soakDm(String name) {
    return 'DM · $name';
  }

  @override
  String get rangeSender => '送信側';

  @override
  String get rangeReceiver => '受信側';

  @override
  String get rangeChannel => 'チャンネル';

  @override
  String get rangeHint => '両方の無線機を同じプライベートチャンネルに。送信側がビーコン、受信側が移動しながら記録します。';

  @override
  String rangeBeacons(int n) {
    return 'ビーコン $n 件送信';
  }

  @override
  String rangeSummary(int heard, int missing) {
    return '受信 $heard · 欠落 $missing';
  }

  @override
  String rangeBest(String snr) {
    return '最良 SNR $snr dB';
  }

  @override
  String rangeFarthest(String d) {
    return '最遠 $d';
  }

  @override
  String get rangeCopyCsv => 'CSV をコピー';

  @override
  String get rangeFlood => 'フラッド';

  @override
  String get settingsHubInfo => 'このアプリについて';

  @override
  String get settingsNotifDeniedPermanent =>
      '通知が永続的に拒否されました。バックグラウンドサービスには常駐通知が必要です。';

  @override
  String get settingsNotifDeniedTransient =>
      'バックグラウンド接続には通知の許可が必要です。設定で許可してください。';

  @override
  String get deviceAdvertPropagatesHint => 'ラジオが次に自分の名前を知らせたときに反映されます。';

  @override
  String get settingsHubMaps => 'オフライン地図';

  @override
  String get mapsTitle => 'オフライン地図';

  @override
  String get mapsOffline => 'ネットワークがありません。ダウンロードは自動で再開します。';

  @override
  String get mapsStorage => 'ストレージ';

  @override
  String mapsUsed(String used, String budget) {
    return '$budget 中 $used 使用';
  }

  @override
  String mapsBreakdown(String packs, String layers, String view) {
    return '地域 $packs・イベント地図 $layers・保存済みタイル $view';
  }

  @override
  String get mapsBudget => '上限';

  @override
  String get mapsViewKeep => '閲覧分の保持';

  @override
  String get mapsClearView => '閲覧済みタイルを消去';

  @override
  String get mapsPacks => '地域ダウンロード';

  @override
  String get mapsAddPack => '地域をダウンロード';

  @override
  String get mapsNoPacks => '地域はまだありません。';

  @override
  String get mapsArchives => '地域ファイル';

  @override
  String get mapsNoArchives => '地域ファイルはまだありません。';

  @override
  String get mapsAddArchive => '地域ファイルを追加';

  @override
  String get archiveUrl => 'リンク (https)';

  @override
  String get archiveSize => 'サイズ (MB・任意)';

  @override
  String get archiveSha => 'SHA-256 (任意)';

  @override
  String get archiveStateFailed => '拒否';

  @override
  String get archiveFailBadHash => 'チェックサムが一致しません。';

  @override
  String get archiveFailBadSize => 'サイズが一致しません。';

  @override
  String get archiveFailNotPm => 'PMTiles ファイルではありません。';

  @override
  String get archiveFailSchema => '地図のレイヤー構成が違います。このファイルは互換性のない地図です。';

  @override
  String get archiveFailNotFound => 'リンクが見つかりません。';

  @override
  String get archiveFailStorage => '端末の空き容量に書き込めませんでした。空きを作ってから再度お試しください。';

  @override
  String get archiveRefusalDuplicate => '追加済みです。';

  @override
  String get archiveStateWaitingWifi => 'Wi-Fi 待ち';

  @override
  String get archiveRefusalNoSpace => '空き容量が足りません。空けてからやり直してください。';

  @override
  String get mapsPacksPublished => 'ダウンロード可能なパック';

  @override
  String get mapsPacksEmpty => '公開パックはありません。リンクから追加できます。';

  @override
  String mapsPacksFrom(String source) {
    return 'リスト提供: $source';
  }

  @override
  String get mapsPacksBundle => '同梱リスト';

  @override
  String get mapsPacksUnreadable => '公開リストを読めませんでした。内蔵リストを表示しています。';

  @override
  String get mapsPackInstall => 'ダウンロード';

  @override
  String mapsPackLicence(String licence, String attribution) {
    return '$licence · $attribution';
  }

  @override
  String get mapsWifiOnly => 'Wi-Fi のみでダウンロード';

  @override
  String get mapsWifiOnlyHint => 'パックは数百 MB になることがあります。';

  @override
  String get mapsOutsidePacks => 'オフライン地図の範囲外では、地図に接続が必要です。';

  @override
  String get mapsLayers => 'イベント地図';

  @override
  String get mapsNoLayersShort => 'イベントマップ未登録';

  @override
  String get mapsAddLayer => 'イベント地図を追加';

  @override
  String get mapsNoLayers => 'イベントマップはまだありません。';

  @override
  String get mapsSources => '地図ソース';

  @override
  String get mapsAddSource => 'タイルサーバーを追加';

  @override
  String get mapsSourcePacks => 'オフラインダウンロード可';

  @override
  String get mapsSourcePacksUs => 'オフラインダウンロード可(米国のみ)';

  @override
  String get mapsSourceViewOnly => '閲覧したタイルのみ保存(サーバーが一括取得を禁止)';

  @override
  String get mapsSourcePick => 'ベースマップ';

  @override
  String get packStateDownloading => 'ダウンロード中';

  @override
  String get packStateUpdating => '更新中';

  @override
  String get packStateWaiting => 'ネットワーク待ち';

  @override
  String get packStateOverBudget => '停止:容量上限超過';

  @override
  String get packStatePaused => '一時停止';

  @override
  String get packStateComplete => '完了';

  @override
  String mapsPackLine(String source, int minZ, int maxZ) {
    return '$source・ズーム $minZ–$maxZ';
  }

  @override
  String mapsProgress(int done, int total) {
    return '$done / $total タイル';
  }

  @override
  String mapsMissing(int n) {
    return 'サーバーに無し $n';
  }

  @override
  String mapsExpiresIn(int days) {
    return '$days 日後に削除';
  }

  @override
  String get mapsKeepForever => '削除するまで保持';

  @override
  String get mapsPause => '一時停止';

  @override
  String get mapsResume => '再開';

  @override
  String get mapsUpdate => '更新';

  @override
  String get mapsRedownload => '再ダウンロード';

  @override
  String get mapsKeepFor => '自動削除…';

  @override
  String get mapsDelete => '削除';

  @override
  String mapsDeleteConfirm(String name) {
    return '$name を削除しますか?';
  }

  @override
  String get mapsKeepNever => 'しない';

  @override
  String mapsKeepDays(int days) {
    return '$days 日';
  }

  @override
  String mapsLayerFeatures(int n) {
    return '$n 件';
  }

  @override
  String get mapsLayerName => '名前';

  @override
  String get mapsLayerUrl => 'GeoJSON の URL(https)';

  @override
  String get mapsLayerTerms => 'データの利用条件は提供元に従います。';

  @override
  String get mapsSourceName => '名前';

  @override
  String get mapsSourceUrl => 'タイル URL テンプレート';

  @override
  String get mapsSourceAttr => 'クレジット表記';

  @override
  String get mapsSourceAllowsPacks => 'このサーバーはオフラインダウンロードを許可している';

  @override
  String get mapsSourceBad => '名前と、z・x・y を含む https テンプレートが必要です。';

  @override
  String get mapsAdd => '追加';

  @override
  String get mapsWorking => '処理中…';

  @override
  String get newPackName => '名前';

  @override
  String get newPackSource => 'ソース';

  @override
  String get newPackCenter => '中心';

  @override
  String get newPackMyLocation => '現在地';

  @override
  String get newPackNoLocation => '位置が未取得です。緯度, 経度を入力';

  @override
  String get newPackLatLon => '緯度, 経度';

  @override
  String get newPackRadius => '半径';

  @override
  String get newPackZoomFrom => '最小ズーム';

  @override
  String get newPackZoomTo => '最大ズーム';

  @override
  String get newPackKeep => '自動削除';

  @override
  String newPackEstimate(int tiles, String size) {
    return '$tiles タイル・約 $size';
  }

  @override
  String get newPackCreate => 'ダウンロード';

  @override
  String get newPackNoSource =>
      'オフラインダウンロード可能なソースがありません。「地図ソース」で許可されたタイルサーバーを追加してください。';

  @override
  String get packRefusalNoName => '名前を付けてください。';

  @override
  String get packRefusalOffline => 'サーバーに接続できません。オンライン時に設定してください。';

  @override
  String get packRefusalViewOnly => 'このサーバーはオフラインダウンロードを許可していません。';

  @override
  String get packRefusalCoverage => 'このソースはその地域のデータを持っていません。';

  @override
  String get packRefusalTooMany => 'タイルが多すぎます。範囲を狭めるか最大ズームを下げてください。';

  @override
  String get packRefusalBudget => '容量上限に収まりません。';

  @override
  String get layerRefusalBadUrl => 'https の URL が必要です。';

  @override
  String mapsLayerDense(int max) {
    return '高密度レイヤー: 地図は最初の $max 件だけを描きます。';
  }

  @override
  String get mapsLayerFileMissing => 'このファイルを開けません。更新するか削除してください。';

  @override
  String get layerRefusalEmpty => '有効な GeoJSON ですが、描くものがありません。';

  @override
  String get layerRefusalNotGeoJson => 'その URL は GeoJSON を返しませんでした。';

  @override
  String get layerRefusalTooLarge => '10 MB を超えています。重ね表示には大きすぎます。';

  @override
  String get mapsSelfTest => 'セルフテスト';

  @override
  String get selfTestIntro =>
      '地図のダウンロードを一通り検証します（実際のサーバー、保存、中断と再開、期限切れ）。サンドボックスで実行し後で削除するため、あなたの地図には影響しません。約 1 分、1 MB 未満です。';

  @override
  String get selfTestRun => 'セルフテストを実行';

  @override
  String get selfTestRunning => '実行中…';

  @override
  String get selfTestPass => 'すべて合格';

  @override
  String selfTestFail(int n) {
    return '$n 件不合格';
  }

  @override
  String get selfTestCopy => '結果をコピー';

  @override
  String get selfTestCopied => '結果をコピーしました';

  @override
  String get selfCheckReach => '地図サーバーに接続';

  @override
  String get selfCheckViewCache => '閲覧タイルの保存';

  @override
  String get selfCheckRevalidate => '古いタイルの条件付き再確認';

  @override
  String get selfCheckPack => '地域ダウンロード';

  @override
  String get selfCheckUpdate => '地域の更新';

  @override
  String get selfCheckEventLayer => 'イベント地図(GeoJSON)';

  @override
  String get selfCheckOffline => 'オフライン時の動作';

  @override
  String get selfCheckResume => '通信断での中断と再開';

  @override
  String get selfCheckGuards => '拒否条件(サイズ・容量・規約・範囲)';

  @override
  String get selfCheckExpiry => '期限切れ自動削除';

  @override
  String get selfCheckDisk => '保存量と記録の一致';

  @override
  String get locGroupAutoPublish => '公開';

  @override
  String get locGroupBeacon => 'ビーコン';

  @override
  String get locGroupManual => '手動';

  @override
  String get deviceManageChannels => 'チャンネルを管理';

  @override
  String deviceActiveChannelSub(String name) {
    return '使用中: $name · チャンネルとキー';
  }

  @override
  String get locationSourceDevice => 'デバイス';

  @override
  String get locationSourcePhone => 'スマートフォン GPS';

  @override
  String get locationSourceNone => 'なし';

  @override
  String get batteryChargingShort => '充電中';

  @override
  String get elevationSelfTelemetry => '自機テレメトリ';

  @override
  String elevationSelfAlt(String m) {
    return '高度: $m m';
  }

  @override
  String get elevationSelfAltUnknown => '高度: —';

  @override
  String elevationSelfTemp(String c) {
    return '気温: $c °C';
  }

  @override
  String get elevationPolling => '取得中…';

  @override
  String get elevationTapToUpdate => 'タップで更新';

  @override
  String get diagnosticsSectionConnection => '接続';

  @override
  String diagnosticsStateLine(String state) {
    return '状態: $state';
  }

  @override
  String get diagnosticsStateDisconnected => '切断';

  @override
  String get diagnosticsStateHandshaking => 'ハンドシェイク中';

  @override
  String get diagnosticsStateReady => '接続済み';

  @override
  String get diagnosticsStateReconnecting => '再接続中';

  @override
  String get diagnosticsStateFailed => '失敗';

  @override
  String get diagnosticsConnectingSuffix => ' · 接続中…';

  @override
  String diagnosticsDeviceLine(String name, String freq, String sf) {
    return 'デバイス: $name · ${freq}MHz SF$sf';
  }

  @override
  String diagnosticsBatteryLine(String volts, String pct) {
    return 'バッテリー: ${volts}V (約 $pct%)';
  }

  @override
  String get diagnosticsChargingSuffix => ' ⚡ 充電中';

  @override
  String diagnosticsReconnectLine(String n) {
    return '再接続の試行 $n 回目';
  }

  @override
  String get diagnosticsGaveUpSuffix => '(断念)';

  @override
  String diagnosticsErrorLine(String error) {
    return 'エラー: $error';
  }

  @override
  String diagnosticsMtuLine(String mtu, String need) {
    return 'リンク $mtu バイト（1 フレームに $need 必要）';
  }

  @override
  String diagnosticsMtuRefusedLine(String mtu, String need) {
    return 'このリンクは $mtu バイトで、1 フレームには $need 必要です。再接続して試してください。リンクを広げられないラジオはすべてのフレームを運べません。';
  }

  @override
  String diagnosticsDatagramLine(String ch, String via, String type) {
    return 'データグラム: チャンネル $ch、経由 $via、種別 $type';
  }

  @override
  String get rxViaPrimary => 'プライマリ無線';

  @override
  String get rxViaSecondary => '無線 2';

  @override
  String get rxViaUnknown => '無線の報告なし';

  @override
  String diagnosticsFramesDroppedLine(int count) {
    return '$count 件のフレームが一部だけ処理されました。内容が不完全な可能性があります';
  }

  @override
  String diagnosticsFramingLine(
      String truncated, String trailing, Object empty) {
    return '不完全なフレーム: 途中で切れた $truncated 件、余りのバイトがある $trailing 件、空の $empty 件';
  }

  @override
  String get diagnosticsForgetShort => '解除';

  @override
  String diagnosticsPairedLine(String name) {
    return 'ペアリング済み: $name — 起動時に自動再接続します';
  }

  @override
  String get diagnosticsSectionDeveloper => '開発者向け';

  @override
  String get diagnosticsPairRadio => '無線をペアリング';

  @override
  String get diagnosticsForgetConfirmTitle => 'この無線のペアリングを解除しますか？';

  @override
  String get diagnosticsForgetConfirmBody =>
      '再度ペアリングが必要になり、ボンドも削除されます。無線が手の届かない場所にあるときは行わないでください。';

  @override
  String get diagnosticsSectionSend => '送信';

  @override
  String get diagnosticsSendSelfAdvert => '自己アドバートを送信';

  @override
  String get diagnosticsReadClock => '無線の時計を読む';

  @override
  String get diagnosticsPullMessage => '次のメッセージを取り込む';

  @override
  String get diagnosticsTestMessage => '公開チャンネルのテストメッセージ';

  @override
  String get diagnosticsSend => '送信';

  @override
  String diagnosticsSentWhat(String what) {
    return '$what を送信しました';
  }

  @override
  String diagnosticsSendFailed(String error) {
    return '送信に失敗しました: $error';
  }

  @override
  String get diagnosticsSectionErrors => 'アプリ自体の失敗';

  @override
  String diagnosticsErrorsCurrent(int count) {
    return '今回の実行で $count 件';
  }

  @override
  String diagnosticsErrorsPrevious(int count) {
    return '前回の実行で $count 件';
  }

  @override
  String get diagnosticsErrorsNone => '記録はありません。';

  @override
  String get diagnosticsSectionM6 => 'チャンネル末尾の証跡';

  @override
  String get diagnosticsResolveTail => 'チャンネル末尾を解決';

  @override
  String get diagnosticsExportFixture => 'フィクスチャを書き出す';

  @override
  String get diagnosticsCopyFixture => 'フィクスチャ JSON をコピー';

  @override
  String get diagnosticsFixtureCopied => 'コピーしました。プロトコルパッケージの取得済みベクタに保存してください。';

  @override
  String get diagnosticsNoRfLog => 'RF ログのフレームがまだありません';

  @override
  String get diagnosticsNotRfLog => '最後の RF ログフレームをデコードできませんでした';

  @override
  String get diagnosticsNotGrpTxt =>
      'このパケットはグループテキストではありません。公開チャンネルで送信して再試行してください。';

  @override
  String get diagnosticsExportNeedsCapture => '先に RF ログのフレームを取得してください';

  @override
  String get diagnosticsNoFrames => 'フレームはまだありません';

  @override
  String diagnosticsFramesCopied(String count) {
    return '$count 件のフレームをコピーしました';
  }

  @override
  String get diagnosticsSectionSoak => 'ソーク';

  @override
  String get diagnosticsSoakEmpty => 'スコープが未設定です';

  @override
  String get diagnosticsCopySoak => 'ソーク結果をコピー';

  @override
  String get diagnosticsSoakCopied => 'ソーク結果をコピーしました';

  @override
  String get nodesClearSearch => '検索をクリア';

  @override
  String get networksTitle => 'ネットワーク';

  @override
  String get networksEmpty => 'ネットワークはまだありません。ネットワークとは、無線機同士で合わせる無線設定のことです。';

  @override
  String get networksNew => '新しいネットワーク';

  @override
  String get networksName => '名前';

  @override
  String get networksNameRequired => 'ネットワーク名を入力してください。';

  @override
  String get networksPreset => '無線設定の元';

  @override
  String get networksPathHash => 'パスハッシュ長';

  @override
  String get networksPrivateSwitch => '専用周波数';

  @override
  String get networksPrivateHelp =>
      '公開プリセットが使わない周波数を使います。この周波数の無線機は公開メッシュを聞けず、公開メッシュからも聞こえません。';

  @override
  String get networksFrequency => '周波数 (MHz)';

  @override
  String get networksFrequencyInvalid => '150〜2500 MHz の周波数を入力してください。';

  @override
  String networksFrequencyPublic(String preset) {
    return 'この周波数・帯域幅・拡散率は公開プリセット $preset のものです。別の周波数を選んでください。';
  }

  @override
  String get networksSave => '保存';

  @override
  String get networksCancel => 'キャンセル';

  @override
  String networksShared(String preset) {
    return '公開 $preset メッシュと同じ電波を使います。周波数・帯域幅・拡散率が同じなら、鍵や名前では無線機を分けられません。';
  }

  @override
  String get networksIsolated => '公開メッシュとは別です。この周波数に設定していない無線機には聞こえません。';

  @override
  String networksSummary(
      String freq, String bw, String sf, String cr, String ph) {
    return '$freq MHz · $bw kHz · SF$sf · CR$cr · パスハッシュ $ph';
  }

  @override
  String networksMembers(int count) {
    return 'メンバー ($count)';
  }

  @override
  String get networksNoMembers => 'メンバーはまだいません。';

  @override
  String get networksAddMember => 'メンバーを追加';

  @override
  String get networksNoContacts => '追加できる既知のコンタクトがありません。';

  @override
  String get networksRemoveMember => '外す';

  @override
  String get networksApply => 'この無線機に適用';

  @override
  String get networksApplyNeedsRadio => '適用するには無線機を接続してください。';

  @override
  String networksApplyTitle(String name) {
    return '$name を適用しますか?';
  }

  @override
  String networksApplyBodyShared(String summary) {
    return 'この無線機を $summary に切り替えます。';
  }

  @override
  String networksApplyBodyIsolated(String summary) {
    return 'この無線機を $summary に切り替えます。元に戻すまで公開メッシュは聞こえなくなります。';
  }

  @override
  String get networksApplyConfirm => '適用';

  @override
  String get networksApplied => '適用しました。';

  @override
  String networksApplyFailed(String error) {
    return '適用できません: $error';
  }

  @override
  String get networksCurrent => 'この無線機はこのネットワークです';

  @override
  String get networksDelete => 'ネットワークを削除';

  @override
  String networksDeleteTitle(String name) {
    return '$name を削除しますか?';
  }

  @override
  String get networksDeleteBody => '保存した設定だけが消えます。無線機の設定はそのままです。';

  @override
  String get networksDeleteConfirm => '削除';

  @override
  String get placeCreateTitle => '場所を立てる';

  @override
  String get placeCreateAction => 'タグ付け';

  @override
  String get placeLabelField => 'ここは何ですか?';

  @override
  String get placeLabelHint => '短い言葉で。60文字まで';

  @override
  String get placeTypeTitle => '種類';

  @override
  String get placeTtlTitle => 'いつまで有効ですか?';

  @override
  String get placePrecisionTitle => '精度';

  @override
  String get placePrecisionExact => '正確';

  @override
  String get placePrecision100 => '約100 m';

  @override
  String get placePrecision1000 => '約1 km';

  @override
  String get placeSent => 'タグ付けしました。期限が来ると自動で消えます。';

  @override
  String placeBudgetRefused(int n, String time) {
    return '直近1時間に $n 件送信しました。次は $time に送れます。';
  }

  @override
  String get placeNoIdentity => '先に無線機に接続してください。場所はあなたの名前でタグ付けされます。';

  @override
  String get placeLabelEmpty => '場所には短い言葉が必要です。';

  @override
  String get placeLabelTooLong => 'ラベルは60文字までです。';

  @override
  String get placeLabelCarriesTtl => 'ラベルにTTLトークンは入れられません。';

  @override
  String placeExpiresIn(String value) {
    return '残り $value';
  }

  @override
  String get placeExpired => '期限切れ';

  @override
  String placeReportedBy(String name, String time) {
    return '$name が $time にタグ付け';
  }

  @override
  String get placeTimeUnknown => '時刻不明';

  @override
  String get placeSourceGps => '送信者のGPSから';

  @override
  String get placeSourcePhone => '送信者の電話から';

  @override
  String get placeSourcePinned => '手で置いた場所';

  @override
  String get placeSourceReceived => 'メッシュ経由で受信';

  @override
  String get placeSourceInferred => '推定';

  @override
  String get placeUnkeyedIdentity => 'この身元はチャンネル上の名前であり、鍵ではありません。';

  @override
  String placeUnknownType(String token) {
    return '$token として送信';
  }

  @override
  String get placeConfirmAction => 'まだある';

  @override
  String get placeRefuteAction => 'もう無い';

  @override
  String placeConfirmations(int n) {
    return '$n 件の確認';
  }

  @override
  String placeConfirmationsMore(int n) {
    return '他 $n 件';
  }

  @override
  String placeClaimedConfirmations(int n) {
    return '$n 件は名前のみ';
  }

  @override
  String get placeHiddenByRefutation => '既知の鍵からの否定によりここでは非表示';

  @override
  String get placeFenceThis => 'この場所を囲む';

  @override
  String placeFenceMade(Object n) {
    return '作成しました。一覧に $n 件あります。';
  }

  @override
  String get placeDirections => '経路';

  @override
  String get placeDirectionsCopied => '座標をコピーしました';

  @override
  String get placeShareAddress => '住所を共有';

  @override
  String get placeShareSubject => 'メッシュ上の地点';

  @override
  String get placeShareFailed => '住所を引き受けるアプリがありません。';

  @override
  String get placeHistoryTitle => '保存した場所';

  @override
  String get placeHistoryEmpty => 'まだ場所はありません。地図を長押しするとタグ付けできます。';

  @override
  String get placeStateLive => '有効';

  @override
  String get placeStateExpired => '期限切れ';

  @override
  String get placeSearchHint => 'ラベルまたはタグ付けした人で検索';

  @override
  String get placeWithinAny => '残り時間の指定なし';

  @override
  String get placeWithinHour => '1時間以内に期限';

  @override
  String get placeWithinDay => '24時間以内に期限';

  @override
  String get placeKeyedOnly => '鍵のある場所のみ';

  @override
  String get placeCoordinatesRefused => 'この座標は送信できません。';

  @override
  String placeEchoLine(String label, String type, String expiry) {
    return '$label · $type · $expiry';
  }

  @override
  String get placeTypeHazard => '危険';

  @override
  String get placeTypeWater => '水';

  @override
  String get placeTypeFuel => '燃料';

  @override
  String get placeTypeMed => '医療';

  @override
  String get placeTypeRally => '集会';

  @override
  String get placeTypeView => '眺め';

  @override
  String get placeTypeCamp => '野営';

  @override
  String get placeTypeLook => '目印';

  @override
  String get placeTypeOther => 'その他';

  @override
  String get failureUnsupportedCommand =>
      'ラジオはこのコマンドに対応していません。ファームウェアがこのアプリの想定より古い可能性があります。ラジオを更新するか、対応しているコマンドを使ってください。';

  @override
  String get failureNotFound =>
      'ラジオはその要求の対象（チャンネル・連絡先・メッセージ）を見つけられませんでした。連絡先を更新してから再試行してください。';

  @override
  String get failureTableFull =>
      'ラジオのキューまたはテーブルが満杯のため、要求を拒否しました。空くのを待ってから再試行してください。失われたものはありません。';

  @override
  String get failureBadState =>
      'ラジオは別の操作の実行中で、これを開始できません。現在の操作が終わってから再試行してください。';

  @override
  String get failureFileIoError =>
      'ラジオのストレージが書き込みを拒否しました。詳細はラジオ側のログにあります。一度再試行し、繰り返す場合はラジオのファイルシステムを確認してください。';

  @override
  String get failureIllegalArgument =>
      'ラジオは値または長さを不正として拒否しました。変更した項目を確認してください。このファームウェアが受け付けない値が 1 つあります。';

  @override
  String get failureUnknownDeviceError =>
      'ラジオはこのアプリが知らない理由で要求を拒否しました。診断ページに生のフレームが表示されます。';

  @override
  String get failureBlePermissions =>
      'Bluetooth の権限が拒否されたため、ラジオに接続できません。Android の設定でこのアプリに「付近のデバイス」を許可し、再接続してください。';

  @override
  String get failureBluetoothOff => 'Bluetooth がオフです。オンにしてから再接続してください。';

  @override
  String get failureNoRadioFound =>
      'スキャンに応答したラジオがありません。ラジオの電源・距離・他のスマートフォンへの接続を確認してください。';

  @override
  String get failurePairingFailed =>
      'ペアリングが完了しませんでした。ラジオの画面に表示された PIN を入力し（画面のないラジオは 123456）、再試行してください。';

  @override
  String get failureStalePairing =>
      'ラジオはこのペアリングを保持していません。Android の Bluetooth 設定で削除し、ラジオの電源を入れ直してから再ペアリングしてください。';

  @override
  String get failurePairingNotKept =>
      'ラジオはペアリングできましたが、次の接続で暗号化できず、ペアリングが保存されていません。電源を入れ直して再ペアリングしてください。繰り返す場合はラジオ側の問題です。';

  @override
  String get failureServiceMissing =>
      'このデバイスは MeshCore サービスを公開していないため、MeshCore ラジオではない可能性があります。';

  @override
  String get failureCharacteristicMissing =>
      'ラジオのリンクに、アプリが必要とするキャラクタリスティックがありません。ファームウェアがこのアプリの想定より古い可能性があります。';

  @override
  String failureMtuTooSmall(String mtu, String need) {
    return 'この無線機のリンクは $mtu バイトで、1フレームには $need バイト必要です。小さい値を要求するファームウェアもあるため、この無線機は最大サイズのフレームを運べません。ファームウェアを新しくするか、再接続してください。';
  }

  @override
  String get failureFrameTruncated => 'メッセージの一部が届きませんでした。件数は診断ページにあります。';

  @override
  String get failureFrameTrailingBytes =>
      'メッセージの末尾に余分なバイトがあり、破棄しました。件数は診断ページにあります。';

  @override
  String get failureStorageFull =>
      'ストレージが満杯のため書き込みを拒否しました。無言で削除はしていません。空き容量を確保してください。履歴はそのまま残ります。';

  @override
  String get failureRadioSilent =>
      'ラジオは要求を受け取りましたが、時間内に応答しませんでした。実行済みの可能性があります。再試行の前にラジオを確認してください。';

  @override
  String diagnosticsRadioChangedLine(String previous, String current) {
    return 'この無線機は前回まで使っていたものではありません(前回 $previous、今回 $current)。履歴・タグ・お気に入り・ブロックはアプリ側のものなので残ります。連絡先・チャンネル・無線設定は無線機側のものなので、この無線機の内容になります。';
  }

  @override
  String get diagnosticsRadioChangedAccept => 'この無線機を使う';

  @override
  String get failureAirtimeBudget =>
      'この1時間でアプリの送信時間の上限に達したため、送信していません。時間の経過とともにまた送信できます。';

  @override
  String get failureLinkTimeout => '無線リンクを時間内に開けませんでした。送信はしていません。もう一度お試しください。';

  @override
  String diagnosticsHandshakeLine(String started, String timedOut) {
    return 'リンクのハンドシェイク: $started 回開始、$timedOut 回応答なし';
  }

  @override
  String diagnosticsLinkCloseLine(String count) {
    return '完了しなかったリンク切断: $count 回';
  }

  @override
  String airtimeSpentLine(String spent, String budget) {
    return 'この1時間の送信時間: $spent / $budget';
  }

  @override
  String airtimeSpentLineUnlimited(String spent) {
    return 'この1時間の送信時間: $spent(上限なし)';
  }

  @override
  String airtimeRefusedCount(int count) {
    return '$count 件が上限で拒否されました';
  }

  @override
  String get settingsAirtimeTitle => '送信時間の上限';

  @override
  String get settingsAirtimeHelp =>
      'このアプリが送信したフレームはすべて記録されます。上限に達すると、1時間が経過するまで送信を止めます。無線側の法的な上限は別に働きます。';

  @override
  String get airtimePolicyOnePercent => '1 % デューティ比';

  @override
  String get airtimePolicyOnePercentSub => '1時間あたり36秒の送信。EU・英国の法定上限です。';

  @override
  String get airtimePolicyOwned => '上限なし';

  @override
  String get airtimePolicyOwnedSub => '自分が使う周波数で、他に利用者がいない場合。';

  @override
  String get clockUnknown => '時刻不明';

  @override
  String get clockJustNow => 'たった今';

  @override
  String clockMinutesAgo(String count) {
    return '$count 分前';
  }

  @override
  String clockHoursAgo(String count) {
    return '$count 時間前';
  }

  @override
  String clockDaysAgo(String count) {
    return '$count 日前';
  }

  @override
  String clockAhead(String count) {
    return '送信側の時計が $count 分進んでいます';
  }

  @override
  String get degradedStorageFull =>
      'ストレージが満杯のため、この端末は書き込みを拒否しました。容量を空けるために削除はしていません。空き容量を確保すれば履歴は継続します。';

  @override
  String get degradedClockUnset =>
      'ラジオの時計が一度も設定されていないため、ラジオが報告する時刻は「時刻不明」と表示されます。';

  @override
  String get degradedBatteryCritical =>
      'ラジオの電池残量が少なく、送信が途中で切れる可能性があります。長い送信の前に充電してください。';

  @override
  String get degradedRadioAbsent =>
      'ラジオが接続されていません。受信済みの内容は読めます。送信・テレメトリ・プレイスはラジオが接続するまで待機します。';

  @override
  String get degradedRadioSilent =>
      'ラジオはペアリングされていますが応答しません。直前の要求は実行済みの可能性があります。再試行の前にラジオを確認してください。';

  @override
  String get degradedNoLocation =>
      '位置情報が無効のため、距離・方位・場所のタグの基準がありません。それ以外は動作します。';

  @override
  String get degradedMapOffline => '地図タイルを取得できません。同梱のベースマップと保存済みのタイルは表示されます。';

  @override
  String get sosTitle => '緊急';

  @override
  String get sosEntryTooltip => '緊急警報とチェックイン';

  @override
  String sosGoesToChannel(String name) {
    return 'チャンネル $name';
  }

  @override
  String sosGoesToContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '連絡先 $count 件へ直接送信',
      zero: '直接送信なし',
    );
    return '$_temp0';
  }

  @override
  String get sosInRange => '電波の届く範囲にいる人以外には通知されません。';

  @override
  String get sosHoldToArm => '長押しで警報を発します';

  @override
  String sosHoldRemaining(int seconds) {
    return 'そのまま長押し · $seconds秒';
  }

  @override
  String get sosHoldReleased => '早く離したため、何も送信していません。';

  @override
  String get sosNoIdentity => 'ラジオがまだ名前を知らせていないため、警報に名前を載せられません。';

  @override
  String get sosWords => '何が起きていますか';

  @override
  String get sosWordsHint => '繰り返しごとに送信されます（最大96バイト）';

  @override
  String get sosDestination => '送信先';

  @override
  String get sosEmergencyPublicKey =>
      '#emergency の鍵は名前から計算できるため、名前を知る人は誰でもこの内容を読めます。';

  @override
  String get sosEmergencyRepeat =>
      'ラジオは約 2 分後に各メッセージを一度だけ再送します。アプリを閉じると、残りは止まります。';

  @override
  String get sosContactsNone => '連絡先への直接送信がないため、チャンネルの応答ではこの警報を止められません。';

  @override
  String get sosActive => '警報送信中';

  @override
  String sosNextSend(int seconds) {
    return '次は $seconds秒後';
  }

  @override
  String sosElapsed(int minutes) {
    return '$minutes分経過';
  }

  @override
  String sosRemaining(int count, int total) {
    return '残り $count/$total';
  }

  @override
  String get sosImSafe => '無事です';

  @override
  String get sosImSafeHint => '[SAFE] を1通送って繰り返しを止めます。';

  @override
  String get sosStopRepeats => '繰り返しを停止';

  @override
  String get sosStopHint => 'この端末での繰り返しを止めます。送信しないため、誰にも伝わりません。';

  @override
  String sosMissedSends(int count) {
    return 'アプリのスリープ中に送信できなかった回数: $count';
  }

  @override
  String get sosSafeSent => '安全メッセージを送信しました。';

  @override
  String get sosSafeNotSent =>
      '安全メッセージはこの端末から送信されませんでした。繰り返しは停止しましたが、安全であることは誰にも伝わっていません。';

  @override
  String get sosResumed =>
      'この警報は前回アプリを閉じたときに実行中でした。残り時間の分は継続します。アプリが閉じている間に逃した繰り返しは送信されていません。';

  @override
  String get sosBestEffort =>
      '端末がスリープしている間の繰り返しはベストエフォートです。遅れた分は直近の1回だけを送り、まとめて送信はしません。';

  @override
  String get sosSendFailed => '無線が繰り返し送信を拒否しました。スケジュールは継続します。';

  @override
  String get sosDefaultWords => '助けが必要です';

  @override
  String sosClaimedBy(String name) {
    return '$name が受信したと主張しています（チャンネル）。警報は継続します。';
  }

  @override
  String sosSeenBy(String name) {
    return '$name が受信しました（直接メッセージ）。';
  }

  @override
  String get sosExpired => '警報の繰り返しは終了しました。解決したわけではありません。';

  @override
  String get sosCancelled => '警報は停止しました。';

  @override
  String get sosAcknowledgedHeading => '受信済み';

  @override
  String get sosDismiss => '閉じる';

  @override
  String get sosRefusedAlreadyActive => 'すでに警報が動作中です。';

  @override
  String get sosRefusedNoDestination => '先に送信先を選んでください。';

  @override
  String get sosRefusedNoWords => '先に状況を入力してください。';

  @override
  String get sosRefusedTooLong => '名前と位置を含めると長すぎます。短くしてください。';

  @override
  String get sosRefusedHold => '長押しが完了していません。';

  @override
  String get checkinTitle => 'チェックイン';

  @override
  String get checkinIntro => '期限付きの1通のみ。期限切れはこのアプリが判断します。無線側にタイマーはありません。';

  @override
  String get checkinDeadline => '期限';

  @override
  String checkinMinutes(int minutes) {
    return '$minutes 分';
  }

  @override
  String get checkinSend => 'チェックインを送信';

  @override
  String get checkinOneMessage => 'チェックインは1通のみで、繰り返しません。';

  @override
  String checkinUntil(String time) {
    return '期限 $time';
  }

  @override
  String get checkinWatching => '応答待ち';

  @override
  String get checkinOverdue => '期限切れ — 期限を過ぎ、応答はありませんでした。';

  @override
  String get checkinAnsweredDirect => '応答あり（直接メッセージ）。';

  @override
  String get checkinAnsweredChannel => 'チャンネルで応答がありました（名前だけで、鍵による確認はありません）。';

  @override
  String get checkinSent => 'チェックインを送信しました。繰り返しはしません。';

  @override
  String get checkinNeedsRadio => 'チェックインには無線の接続と無線の名前が必要です。';

  @override
  String get mediaComposerTitle => '写真を送る';

  @override
  String get mediaSourceUnavailable => 'このビルドは端末から写真を読み取れないため、ここからは送信できません。';

  @override
  String get mediaSourceFailed => '写真を読み取れませんでした。別の写真をお試しください。';

  @override
  String get mediaPickCamera => '写真を撮る';

  @override
  String get mediaPickGallery => '写真を選ぶ';

  @override
  String get mediaSourceUnsupportedFormat =>
      'このビルドで読み取れない形式です。HEIC と AV1 には対応していません。JPEG か PNG の写真を選んでください。';

  @override
  String get mediaEncoding => '写真をメッシュ用に調整しています…';

  @override
  String mediaCostLine(int chunks, String airtime) {
    return '$chunks パケット · 送信時間は約 $airtime';
  }

  @override
  String get mediaOverBudget => 'この写真は最低品質でもメッシュの上限に収まりません。送信はできますが途中で切れます。';

  @override
  String get mediaInterruptedEarlier => '前回の写真は送信が完了しませんでした。';

  @override
  String get mediaInterruptedDismiss => '閉じる';

  @override
  String mediaSendingProgress(int sent, int total) {
    return '$total 中 $sent パケット送信済み';
  }

  @override
  String mediaReceiptLine(int chunks, int resends) {
    return '$chunks パケット送信、うち $resends は再送';
  }

  @override
  String get mediaAcceptedNotDelivered =>
      'ラジオはこれらのパケットを受け取りました。同報に配達の保証はありません。';

  @override
  String mediaSendFailed(int count) {
    return 'ラジオが $count パケットを拒否したため、この写真は完了しませんでした。';
  }

  @override
  String get mediaSend => '送信';

  @override
  String get mediaRetrySend => '再試行';

  @override
  String get mediaClose => '閉じる';

  @override
  String get mediaOffOnPublic =>
      'パブリックチャンネルではメディアは送信できません。プライベートなチャンネルで送ってください。';

  @override
  String get mediaPayloadUnusable => '送信する内容がありません。';

  @override
  String get mediaChannelUnknown => 'チャンネルが選択されていないため、送信先がありません。';

  @override
  String mediaReceiveWaiting(int received, int total, int missing) {
    return '$total 中 $received パケット · 残り $missing を待機中';
  }

  @override
  String get mediaReceiveAsk => '不足パケットを要求する';

  @override
  String mediaReceiveRequested(int count) {
    return '送信者に $count パケットを要求しました。';
  }

  @override
  String get mediaReceivedTitle => '受信した写真';

  @override
  String mediaReceivedKept(int count) {
    return '$count 枚（アプリを閉じるまで保持）';
  }

  @override
  String get mediaReceiveComplete => '写真を受信しました。';

  @override
  String get mediaDecodeFailed => '写真は届きましたが読み取れません。';

  @override
  String get mediaPhotoSemantics => 'メッシュで受信した写真';

  @override
  String get placePhotoNotFetched => '写真は未取得です。項目自体は完全で、写真は任意であり届かないこともあります。';

  @override
  String get placePhotoMayNotArrive => '写真は届かないことがあります。テキストは届きます。';

  @override
  String get placePhotoFetch => '写真を取得';

  @override
  String get placePhotoFetching => 'メッシュに写真を問い合わせています…';

  @override
  String get geofenceCreateTitle => 'ここにフェンスを描く';

  @override
  String get geofenceNameLabel => '名前';

  @override
  String get actionSave => '保存';

  @override
  String get geofenceEditTitle => 'このフェンスを変更';

  @override
  String get geofenceEdit => 'フェンスを編集';

  @override
  String get geofenceSearchHint => 'フェンスを検索';

  @override
  String get geofenceNoMatches => 'その名前のフェンスはありません。';

  @override
  String get geofenceShowAll => 'すべて地図で表示';

  @override
  String get geofenceFocused => '地図から開きました';

  @override
  String geofenceCornerHandle(int n) {
    return '角 $n、ドラッグで移動';
  }

  @override
  String geofenceCorners(int n) {
    return '$n 角';
  }

  @override
  String get geofenceCanvasTitle => 'このフェンスを保存';

  @override
  String get geofencePolygonNote =>
      '描いた形のまま保存されます。ここでは名前を変えられますが、形の変更はまだできません。';

  @override
  String get geofenceDrawTitle => 'フェンスを描く';

  @override
  String get geofenceDrawHint => '地図をタップして角を追加します。角はドラッグで移動できます。';

  @override
  String get geofenceDrawDone => '完了';

  @override
  String get geofenceDrawCancel => 'キャンセル';

  @override
  String get geofenceDrawNeedThree => 'フェンスには3つ以上の角が必要です。';

  @override
  String get geofenceDrawStarted => 'フェンスを描いています。';

  @override
  String get geofenceTitle => 'ジオフェンス';

  @override
  String get geofenceExplainer =>
      'フェンスは見張る範囲です。入ったときと出たときに一度ずつ知らせるので、境界を歩いても通知が連続しません。';

  @override
  String get geofenceAddSection => 'フェンスを追加';

  @override
  String geofenceRadius(int meters) {
    return '$meters m';
  }

  @override
  String get geofenceNeedsFix => 'フェンスには現在地が必要です。先に無線を接続するか位置情報を許可してください。';

  @override
  String get geofenceAddHere => 'ここにフェンスを追加';

  @override
  String get geofenceListSection => 'フェンス';

  @override
  String get geofenceEmpty => 'フェンスはまだありません。';

  @override
  String get geofenceInsideNow => '内側にいます';

  @override
  String get geofenceOutsideNow => '外側にいます';

  @override
  String get geofenceDelete => 'フェンスを削除';

  @override
  String get geofenceSaveAsPlace => '場所として保存';

  @override
  String get geofenceClearLog => '履歴を消去';

  @override
  String get geofenceEventsSection => '最近の出入り';

  @override
  String geofenceEntered(String label) {
    return '$label に入りました';
  }

  @override
  String geofenceLeft(String label) {
    return '$label を出ました';
  }

  @override
  String geofenceDefaultName(int number) {
    return 'フェンス $number';
  }

  @override
  String nodeClosing(String name, String distance) {
    return '$name は $distance 先で近づいています';
  }

  @override
  String nodeOpening(String name, String distance) {
    return '$name は $distance 先で遠ざかっています';
  }

  @override
  String get geofenceExplainerShort => '到着・出発を知らせる範囲';

  @override
  String get coverageTitle => 'カバレッジ';

  @override
  String get coverageCountsTitle => 'カバレッジ';

  @override
  String get coverageBeforeStart =>
      '現在地と、応答した相手を記録します。端末内にのみ保存され、アプリを閉じると記録は終わります。';

  @override
  String get coverageStart => '記録を開始';

  @override
  String get coverageStop => '記録を停止';

  @override
  String coverageCounts(int answered, int tried) {
    return '$tried 回中 $answered 回応答あり';
  }

  @override
  String coverageUnmatched(int count) {
    return '識別できなかった応答が $count 件あります';
  }

  @override
  String get coverageRefusedTooSoon => 'このアプリは自ら間隔を守ります。30秒に1回までなので、今回は待ちます。';

  @override
  String get coverageRefusedCellFresh =>
      'この場所は1時間以内に ping 済みです。同じ場所に留まれば1時間に1回です。';

  @override
  String get coverageRefusedManualUsed => 'この1時間の手動 ping は使用済みです。';

  @override
  String get coveragePacingNote => 'このアプリは自ら間隔を守りますが、他の端末が守ることは保証できません。';

  @override
  String get coveragePingNow => '今すぐ ping（1時間に1回）';

  @override
  String get coverageCellsSection => 'ping した場所';

  @override
  String get coverageNoSamples => 'まだ記録はありません。';

  @override
  String coverageCellLine(String cell, int percent, int samples) {
    return '$cell · $percent% · $samples 件';
  }

  @override
  String coverageHidden(int count) {
    return '$count 件非表示';
  }

  @override
  String coverageEdges(int count) {
    return '描画された応答 $count 件 — 応答のみで、推定したリンクはありません';
  }

  @override
  String get coverageNotAMap => 'これは ping が応答された場所であり、メッシュが届く範囲ではありません。';

  @override
  String get coverageExplainerShort => 'ここで応答があった ping';

  @override
  String get fieldExportSection => '現地記録';

  @override
  String get fieldExportExplainer =>
      '軌跡・プレイス・応答のあった ping・チェックインを1つのファイルにまとめます。暗号化されない JSON なので、そのまま渡せます。';

  @override
  String get fieldExportAction => 'このセッションを書き出す';

  @override
  String get fieldExportShared => '現地記録を共有できます。';

  @override
  String fieldExportDone(String path) {
    return '現地記録を書き出しました。パスはクリップボードにあります: $path';
  }

  @override
  String get gpxExportExplainer =>
      '軌跡を GPX として書き出します。地図アプリならどれでも読めます。メッセージと違い、暗号化されない平文です。';

  @override
  String get gpxExportAction => '軌跡を GPX で共有';

  @override
  String get gpxExportTrackName => 'MeshMore の軌跡';

  @override
  String get gpxExportEmpty => 'まだ軌跡がありません。位置はアプリの動作中に記録されるため、書き出せるものがありません。';

  @override
  String get gpxExportShared => '軌跡を共有できます。';

  @override
  String gpxExportDone(String path) {
    return '軌跡を書き出しました。パスはクリップボードにあります: $path';
  }

  @override
  String get chatSearchAction => 'メッセージを検索';

  @override
  String get settingsHistoryExportRow => 'すべての履歴を書き出す';

  @override
  String get settingsHistoryExportSubtitle =>
      'すべての会話をまとめた暗号化ファイルを1つ作成します。保存先はあなたが選びます。';

  @override
  String get settingsHistoryExportTitle => 'バックアップのパスフレーズ';

  @override
  String get settingsHistoryExportConfirm => '書き出す';

  @override
  String get settingsHistoryExportShared => '履歴を共有できます。';

  @override
  String settingsHistoryExportDone(String path) {
    return '履歴を $path に保存しました';
  }

  @override
  String get settingsHistoryExportEmpty => '書き出せる履歴がまだありません。';

  @override
  String get chatExportAction => 'この会話を書き出す';

  @override
  String get chatExportTitle => '書き出すファイルのパスフレーズ';

  @override
  String get chatExportPassphrase => 'パスフレーズ';

  @override
  String get chatExportConfirm => '書き出す';

  @override
  String get chatExportShared => '会話を共有できます。';

  @override
  String chatExportDone(String path) {
    return '会話を保存しました: $path';
  }

  @override
  String get chatExportFailed => '会話を書き出せませんでした。何も書き出していません。';

  @override
  String get chatSearchHint => '保存済みの履歴を検索';

  @override
  String get chatSearchPrompt => '入力すると、この端末に保存されたメッセージを検索します。';

  @override
  String chatSearchNoResults(String query) {
    return '「$query」に一致するメッセージはありません。';
  }

  @override
  String chatSearchHidden(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ブロックにより$count件の一致を非表示',
    );
    return '$_temp0';
  }

  @override
  String chatSearchTruncated(int count) {
    return '最新の$count件を表示しています。絞り込むと残りを確認できます。';
  }

  @override
  String chatSearchRetention(int cap) {
    return 'この端末は最新の$cap件を保持するため、それより古いメッセージは検索されません。';
  }

  @override
  String get chatSearchDm => 'ダイレクトメッセージ';

  @override
  String chatUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '未読$count件',
    );
    return '$_temp0';
  }

  @override
  String get blockedKeysTitle => 'ブロックした相手';

  @override
  String blockedKeysSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の鍵をブロック中',
      zero: 'ブロックした鍵はありません',
    );
    return '$_temp0';
  }

  @override
  String get blockedKeysEmpty =>
      'ブロックした鍵はありません。鍵をブロックすると、その相手からのメッセージ・通知・プレイスがこの端末で非表示になります。';

  @override
  String get blockedKeysCannotStopShort => 'このアプリ内のみ';

  @override
  String get blockedKeysCannotStop =>
      'ブロックはこのアプリ内だけの設定です。無線は今もパケットを受信・中継します。止まるのはこのアプリの表示だけです。';

  @override
  String get blockedKeysUnblock => 'ブロック解除';

  @override
  String blockedKeysSince(String when) {
    return '$whenにブロック';
  }

  @override
  String get blockedKeysUnknownName => '名前は不明';

  @override
  String blockedKeysCapacity(int cap) {
    return 'リストが上限（$cap件）です。追加する前に1件解除してください。';
  }

  @override
  String blockedKeysUnblocked(String name) {
    return '$nameのブロックを解除しました。メッセージが再び表示されます。';
  }

  @override
  String get blockedKeysUnblockedUnnamed => 'ブロックを解除しました。メッセージが再び表示されます。';

  @override
  String get reportAction => '書き出し…';

  @override
  String get reportSheetTitle => 'このメッセージを書き出す';

  @override
  String get reportObservationLabel => '何を見ましたか？（任意）';

  @override
  String get reportNothingSent =>
      '何も送信していません。アプリはこの端末にファイルを作成しただけです。送り先はあなたが決めます。';

  @override
  String reportBundleWritten(String path) {
    return '$path に保存しました';
  }

  @override
  String get reportShareBundle => 'ファイルを共有';

  @override
  String get reportCopyBundle => 'ファイルをコピー';

  @override
  String get reportCopied => 'コピーしました。';

  @override
  String get blockedKeysNotPersisted =>
      'この一覧を端末に保存できませんでした。今は機能しますが、再起動後は空になります。';

  @override
  String get blockedKeysUnreadable =>
      '保存された一覧を読み取れなかったため、現在は何もブロックしていません。壊れたファイルのコピーは保存され、新しいブロックは通常どおり保存されます。';

  @override
  String sosDestinationContactsLimit(int count) {
    return '$count 件まで';
  }

  @override
  String get sosDestinationChange => '変更';

  @override
  String get sosDestinationPickerTitle => '警報の送信先';

  @override
  String get sosDestinationChannelHeader => 'チャンネル';

  @override
  String get sosDestinationContactsHeader => '直接送信';

  @override
  String get sosDestinationContactsHelp =>
      'これらの鍵への直接送信だけが警報を止められます。チャンネルの応答では止まりません。';

  @override
  String get sosDestinationMissing => 'この警報の送信先チャンネルはなくなりました。選び直してください。';

  @override
  String get sosDestinationNoContacts => '連絡先がまだありません';

  @override
  String get sosDestinationNotAContact => '連絡先にありません';

  @override
  String get sosDestinationDone => '完了';

  @override
  String get sosEmergencyShort => '公開チャンネル。アプリを閉じた場合も1回だけ再送されます';

  @override
  String get sosAboutTitle => 'この送信先について';

  @override
  String get sosRepeatsShort => '最大1時間くり返します';

  @override
  String placeTtlMinutes(int count) {
    return '$count分';
  }

  @override
  String placeTtlHours(int count) {
    return '$count時間';
  }

  @override
  String placeTtlDays(int count) {
    return '$count日';
  }

  @override
  String get mapReportPlace => 'ここに場所を保存';

  @override
  String get settingsAppGroupRadio => '接続とバックグラウンド';

  @override
  String get settingsAppGroupReading => '単位と時刻';

  @override
  String get settingsUnits => '距離の単位';

  @override
  String get settingsUnitsMetric => 'メートル・キロメートル';

  @override
  String get settingsUnitsMetricHint => 'MeshCore のツールが報告する距離そのままです。';

  @override
  String get settingsUnitsImperial => 'フィート・マイル';

  @override
  String get settingsUnitsImperialHint => '無線機が報告するメートルから換算します。';

  @override
  String get settingsClock24 => '24時間表示';

  @override
  String get settingsClock24On => '14:32';

  @override
  String get settingsClock12On => '午後2:32';

  @override
  String get settingsCelsius => '摂氏';

  @override
  String get settingsCelsiusOn => '21 °C';

  @override
  String get settingsFahrenheitOn => '70 °F';

  @override
  String get settingsAppGroupSound => '表示と音';

  @override
  String get settingsAppGroupData => 'データ';

  @override
  String get settingsAppGroupSystem => 'システム';

  @override
  String get aboutReplayIntro => '初回画面をもう一度表示';

  @override
  String get toolsGroupDiagnostics => '無線の診断';

  @override
  String nodeMarkerSemantics(String name) {
    return '$name — 詳細はタップ';
  }

  @override
  String placePinSemantics(String label, String expiry) {
    return '$label、$expiry';
  }

  @override
  String placePinSemanticsUnkeyed(String label, String expiry) {
    return '$label、$expiry。チャンネル名から送られたため、そのチャンネルを知る誰でも書けます。';
  }

  @override
  String get placeUnkeyedShort => '名前のみ';

  @override
  String placeClusterSemantics(int count) {
    return 'ここに $count 件の場所';
  }

  @override
  String get mapCanvasSemantics => 'マップ上のマーカーをタップすると開きます';

  @override
  String get gridLegendSignalOnly => '中抜き · 位置なし';

  @override
  String get gridLegendMore => '凡例の全文';

  @override
  String get gridLegendRingsShort => '同心円 · 距離';

  @override
  String get gridLegendSelfShort => '中心 · 自分';

  @override
  String get gridLegendDotShort => '点 · 受信したノード';

  @override
  String get gridLegendKnownShort => '脈動 · 既知';

  @override
  String get gridLegendFavShort => '点滅 · お気に入り';

  @override
  String get gridLegendRippleShort => '波紋 · チャンネル受信';

  @override
  String get gridLegendTapShort => 'タップ · 詳細';

  @override
  String get treeSelfShort => '中心 · 自分';

  @override
  String get treeRepeaterShort => '四角 · リピーター';

  @override
  String get treeRoomShort => '菱形 · ルーム';

  @override
  String get treeChatShort => '円 · チャット';

  @override
  String get treeSensorShort => '波形 · センサー';

  @override
  String get treeFloodShort => '点 · フラッド経由';

  @override
  String get treeArrowShort => '矢印 · 経路';

  @override
  String get snsHotShort => '赤 · 現在混雑';

  @override
  String get snsCoolShort => '色落ち · 沈静化';

  @override
  String get snsToastShort => '点滅 · 新着';

  @override
  String get snsDecayShort => '直近1時間のみ';

  @override
  String get fujiMeShort => '破線 · 自分';

  @override
  String get fujiRefsShort => 'シルエット · 縮尺';

  @override
  String get fujiPeersShort => '点 · ピア';

  @override
  String get fujiUnknownShort => '縞 · 標高なし';

  @override
  String get chatSpeechOffAction => '読み上げはアプリ設定でオフです';

  @override
  String get nodeDetailAltitudeNotReported => '報告されません';

  @override
  String get gridCompassCalibrating => '較正のため、端末を一度ぐるりと回してください。';

  @override
  String get gridCompassLowAccuracy => '端末の方位精度が低い状態です。一度ぐるりと回してください。';

  @override
  String get gridCompassDisturbed =>
      '方位が取れません — ここは磁場が強すぎます。磁石から離し、平らに置いて一度ぐるりと回してください。';

  @override
  String get gridPurposeRadial => '各ノードまでの距離と、最後に聞こえた時刻。';

  @override
  String get gridPurposeWeather => '温度・湿度・気圧（報告するノードのみ）。';

  @override
  String get gridPurposeTree => 'ノード同士の経路（広告されたルートより）。';

  @override
  String get gridPurposeSnsCells => 'メッセージの発信元を直近1時間で。';

  @override
  String get gridPurposeElevation => '各ノードの高度を地形と比較して。';

  @override
  String get mapNoPositionYet => '現在地がまだ分かりません。';

  @override
  String get mapNoPositionFind => '現在地を取得';

  @override
  String get mapNoPositionAsking => '取得中...';

  @override
  String get mapLocationOffApp => 'このアプリの位置情報がオフです。';

  @override
  String get mapLocationAllow => '位置情報を許可';

  @override
  String get mapLocationBlockedApp => 'このアプリの位置情報がブロックされています。';

  @override
  String get mapLocationOpenSettings => '設定を開く';

  @override
  String get mapLocationOffDevice => 'この端末の位置情報がオフです。';

  @override
  String get weatherOpenTelemetrySettings => 'ノードのテレメトリを有効にする';

  @override
  String get chatNoRadio => '無線機が接続されていません';

  @override
  String get chatConnectRadio => '無線機を接続';

  @override
  String get chatConnecting => '接続中…';

  @override
  String chatBudgetEstimateNear(int remaining) {
    return '残り約 $remaining';
  }

  @override
  String get chatMetaFlood => 'フラッド経由';

  @override
  String chatMetaSnr(String snr) {
    return 'SNR $snr dB';
  }

  @override
  String get chatMoreActions => 'その他';

  @override
  String get dmKeyCopied => '相手の鍵をコピーしました';

  @override
  String get channelsInfoTooltip => 'チャンネルの仕組み';

  @override
  String get channelsOptionsTooltip => '通知と動作';

  @override
  String get sosSafeUnconfirmed => '確認できません。送信中に接続が切れたため、届いたかどうかは不明です。';

  @override
  String sosSendUnconfirmed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 回の送信は確認できません。スケジュールは継続します。',
    );
    return '$_temp0';
  }

  @override
  String get rawRecordTitle => '生データを送信';

  @override
  String get rawRecordHelp =>
      '1件のレコードを、経路のある連絡先1件へ送ります。無線が OK か ERR を返し、相手からは何も返りません。';

  @override
  String get rawRecordNoContact =>
      '直接経路のある連絡先がまだありません。生データは宛先指定のみで、フラッド送信はできません。';

  @override
  String get rawRecordBytes => 'バイト列（16進）';

  @override
  String get rawRecordEmpty => '送るバイト列を入力してください。';

  @override
  String get rawRecordNotHex =>
      '16進ではありません。01 02 ab のような2桁区切り、または 0102ab のように続けて入力してください。';

  @override
  String rawRecordTooShort(String min) {
    return '$min バイト以上必要です。それ未満はファームウェアが破棄します。';
  }

  @override
  String rawRecordTooLong(String max) {
    return 'この連絡先の上限 $max バイトを超えています。';
  }

  @override
  String rawRecordBudget(String frame, String max, String typed) {
    return 'フレーム上限 $frame バイト · この経路で記録に使えるのは $max バイト · 入力 $typed バイト';
  }

  @override
  String get rawRecordNotReady => '無線が接続されていません。';

  @override
  String get rawRecordSending => '送信中…';

  @override
  String get rawRecordConfirmTitle => 'このバイト列を送信しますか？';

  @override
  String rawRecordConfirmBody(String name, String count) {
    return 'アプリはこのバイト列の内容を検証できません。$name に $count バイトを1件のレコードとして送り、無線が OK か ERR を返します。';
  }

  @override
  String get rawRecordSent => '無線が受け付けました。配達の証明ではありません。生データには相手からの受領通知がありません。';

  @override
  String rawRecordRefused(String reason, String code) {
    return '無線が拒否しました: $reason（コード $code）。';
  }

  @override
  String rawRecordNoAnswer(String seconds) {
    return '$seconds 秒以内に応答がありません。送信された可能性があります。';
  }

  @override
  String rawRecordNoRoute(String name) {
    return '$name への直接経路がなくなりました。生データはフラッド送信できません。';
  }

  @override
  String placeSuggestLooksLike(String name) {
    return '場所の候補: $name';
  }

  @override
  String get placeSuggestReport => '場所をタグ付け';

  @override
  String get placeSuggestDismiss => '閉じる';

  @override
  String get placeSuggestNeedsLocation => '場所をタグ付けするには位置情報をオンにしてください。';

  @override
  String get mapCompassLegend => '矢印はこの端末の方位磁針です。';

  @override
  String get diagnosticsPosition => 'アプリが見ている位置';

  @override
  String diagnosticsPositionRadio(Object lat, Object lon) {
    return '無線機 $lat, $lon';
  }

  @override
  String diagnosticsPositionPolicy(Object policy) {
    return '位置広告の方針 $policy';
  }

  @override
  String diagnosticsPositionPhone(Object source) {
    return 'スマートフォンの測位 $source';
  }

  @override
  String get diagnosticsPositionNone => 'なし';

  @override
  String get sosWordsOptional => '任意 — 空にすると既定の文言で送信します。';

  @override
  String sosHoldSummary(Object channel) {
    return '長押しで、上の文言を名前と位置とともに $channel へ送信します。';
  }

  @override
  String get sosUseDefaults => '既定に戻す';

  @override
  String wxMicroclimateFromChat(Object ago) {
    return 'このチャンネルのメッセージから読み取り。最新 $ago。';
  }

  @override
  String get wxMicroclimateFromChatNoMessages =>
      'まだ測定値はありません。このチャンネルに書かれた報告のうち、数値と単位があるものだけを読み取ります。';

  @override
  String get elevationAskNodes => '各ノードに高度を問い合わせる';

  @override
  String get elevationAsking => '問い合わせ中…';

  @override
  String get elevationNotADistance => '点は横並びで、距離の順ではありません。';

  @override
  String get meshbookEmptyDetail => 'このチャンネルの発言が記録されます。対象は直近24時間です。';

  @override
  String get locTriggerManual => '手動';

  @override
  String get locTriggerPeriodic => 'タイマー';

  @override
  String get locTriggerMovement => '移動';

  @override
  String get pingLostMeaning =>
      '「応答なし」は、無線機が見積もった応答時間内に返事がなかったという意味です。要求を無視するノードも、休眠中のノードも同じに見えます。';

  @override
  String get contactFilterHint => '名前または鍵の先頭';

  @override
  String get contactFilterNone => '一致する連絡先はありません。';

  @override
  String get actionClear => 'クリア';

  @override
  String get storageTitle => 'ストレージ';

  @override
  String storageMaps(String used, String budget) {
    return '地図データ $used MB / $budget MB';
  }

  @override
  String storageMapsSplit(String view, String packs) {
    return 'キャッシュしたタイル $view MB · ダウンロード済み地域 $packs MB';
  }

  @override
  String get storageMapsUnknown => 'このセッションでは地図データを開いていません';

  @override
  String get storageClearCache => 'キャッシュしたタイルを削除';

  @override
  String get storageCacheCleared => 'キャッシュしたタイルを削除しました。ダウンロード済みの地域は残ります。';

  @override
  String storageHistory(String kb) {
    return 'メッセージ履歴 $kb KB（密封）';
  }

  @override
  String storagePlaces(int n, int cap) {
    return '場所 $n / $cap 件';
  }

  @override
  String storageTrail(int n, int cap) {
    return '軌跡 $n 点 / $cap 点、7日間';
  }

  @override
  String storageMedia(int n) {
    return '未完了のメディア送信 $n 件';
  }

  @override
  String get storageClearAll => 'アプリが保持したデータをすべて削除';

  @override
  String get storageClearAllTitle => 'すべて削除しますか？';

  @override
  String get storageClearAllGoes =>
      'このアプリが保持していたメッセージ履歴、場所、移動の軌跡、未完了のメディア記録、キャッシュした地図タイルを削除します。';

  @override
  String get storageClearAllStays =>
      '無線機には影響しません。無線機自身の連絡先・チャンネル・設定は残り、送信済みのメッセージは取り消されません。アプリの設定とダウンロード済みの地図地域も残ります。';

  @override
  String storageClearAllTypeWord(String word) {
    return '確認のため $word と入力';
  }

  @override
  String get storageClearAllConfirm => '削除';

  @override
  String get storageClearAllDone => '削除しました。無線機と設定はそのままです。';

  @override
  String storageClearAllPartly(int unfinished, int total) {
    return '$total 件中 $unfinished 件を削除できませんでした。残っているものはここに表示されます。無線機と設定はそのままです。';
  }

  @override
  String get chatMediaPrivateOnly => '写真と音声はダイレクトメッセージとプライベートチャンネルのみです。';

  @override
  String mediaReachScope(String scope) {
    return '地域スコープ $scope。';
  }

  @override
  String get mediaReachNoScope => '地域スコープ未設定: 届く全員に送られます。';

  @override
  String get mediaReachUnknown => '到達範囲は無線機のスコープ次第で、まだ報告されていません。写真は受信確認されません。';

  @override
  String get deviceContactsSection => '連絡先テーブル';

  @override
  String get autoAddIntro => 'どのノードを保持するかは無線機が決めます。これはアプリではなく無線機の設定です。';

  @override
  String get autoAddOverwriteOldest => '満杯なら最も古いものを置き換える';

  @override
  String get autoAddOverwriteOldestHint => 'お気に入りは置き換えられません。';

  @override
  String get autoAddChat => 'チャットノード';

  @override
  String get autoAddRepeater => 'リピーター';

  @override
  String get autoAddRoomServer => 'ルームサーバー';

  @override
  String get autoAddSensor => 'センサー';

  @override
  String get autoAddMaxHops => 'ホップ上限';

  @override
  String get autoAddMaxHopsHint => '0 = 無制限 · 1 = 直接のみ · N = N−1 ホップまで';

  @override
  String get autoAddUnknown => '無線機の設定を読み取り中…';

  @override
  String get autoAddManage => 'テーブルを管理';

  @override
  String get nodeAdvertPath => '最後のアドバートの経路';

  @override
  String get nodeAdvertPathNone => 'このノードのアドバート経路は無線機にありません。';

  @override
  String get nodeAdvertPathReading => '経路を読み取り中…';

  @override
  String get retryPathReset => '経路をクリアしたため、この再送はフラッドで送信されます。';

  @override
  String get nodeFindRoute => '経路を探す';

  @override
  String get nodeFindRouteHint => '通信時間を使います。';

  @override
  String get nodeFindRouteNone => '経路は返ってきませんでした。';

  @override
  String get nodeFindRouteDirect => '直接 — 範囲内の隣接ノードです。';

  @override
  String nodeFindRouteTwoWay(Object back) {
    return '復路: $back';
  }

  @override
  String eventOneKeyRejected(Object key) {
    return '無線機が $key からのメッセージを拒否しました';
  }

  @override
  String get eventRadioRefused => '無線機がそのコマンドを拒否しました';

  @override
  String get failureCommandDisabled =>
      'この無線機ではそのコマンドが無効になっているため拒否されました。通信自体に問題はありません。';

  @override
  String get nodeShareContact => 'この連絡先を共有';

  @override
  String get nodeShareContactHint => 'リンクをコピーします。';

  @override
  String get nodeShareContactFailed => '無線機が連絡先を返しませんでした。';

  @override
  String get shareLinkSheetTitle => '連絡先リンク';

  @override
  String get shareLinkCopied => 'コピーしました。';

  @override
  String get deviceContactsImport => 'リンクを取り込む';

  @override
  String get deviceContactsImportHint => 'meshcore:// リンクを貼り付け';

  @override
  String get deviceContactsImportBad => '連絡先リンクではありません。';

  @override
  String get deviceContactsImportDone => '無線機に送信しました。無線機が確認すると一覧に表示されます。';

  @override
  String get diagnosticsRestartRadio => '無線機を再起動';

  @override
  String get diagnosticsRestartConfirm =>
      'この無線機を今すぐ再起動しますか？起動の間リンクは数秒切れ、無線機に溜まっていたものは失われます。';

  @override
  String get diagnosticsRestartSent => '再起動を送信しました。リンクは切れ、自動的に戻ります。';

  @override
  String get diagnosticsRestartNoReply => '再起動に応答はありません。確認ではなく送信のみです。';

  @override
  String get settingsSecuritySection => '無線機へのアクセス';

  @override
  String get settingsPinIntro =>
      'ペアリングPINは、この無線機への新しいBluetoothペアリングを制限します。接続済み端末の一覧は無線機側が保持します。';

  @override
  String get settingsPinCurrent => 'ペアリングPIN';

  @override
  String get settingsPinNone => 'PIN は未設定です';

  @override
  String get settingsPinSet => '新しいPINを設定';

  @override
  String get settingsPinRemove => 'PIN を削除';

  @override
  String get settingsPinHint => '6桁';

  @override
  String get settingsPinBad => 'PIN は6桁ちょうどです。';

  @override
  String get settingsPinDone => 'PIN を設定しました。次回のペアリングには必要です。';

  @override
  String get settingsPinRemoved => 'PIN を削除しました。ペアリング時に要求されません。';

  @override
  String get settingsPinConfirmRemove =>
      'ペアリングPINを削除しますか？範囲内の誰でもペアリングを申し出られるようになります（接続済み端末の一覧は無線機側に残ります）。';

  @override
  String get repeaterSession => 'リピーターセッション';

  @override
  String get repeaterSessionIntro =>
      'パスワードでこのリピーターのセッションを開きます。合言葉はリピーターとあなたの間のもので、アプリは保存しません。';

  @override
  String get repeaterSignIn => 'サインイン';

  @override
  String get repeaterSignOut => 'サインアウト';

  @override
  String get repeaterPasswordHint => 'リピーターのパスワード';

  @override
  String repeaterSignedIn(Object perm) {
    return 'サインインしました（権限 0x$perm）';
  }

  @override
  String get repeaterRefused => 'リピーターがそのパスワードを拒否しました。';

  @override
  String get repeaterNoAnswer => '応答がありません。リピーターが届かない可能性があります。';

  @override
  String get repeaterSignOutDone => 'サインアウトしました。';

  @override
  String get actionForward => '転送';

  @override
  String get forwardNoTarget => '転送先がありません。チャンネルも連絡先もありません。';

  @override
  String get forwardDone => 'その会話の入力欄に入れました。送信前に編集できます。';

  @override
  String get forwardFailed => '下書きを書けませんでした。この端末では暗号化ストアを開けません。';

  @override
  String get placeConfirmToSender => '送信者に確認を送る';

  @override
  String get placeRefuteToSender => '送信者に否定を送る';

  @override
  String get placeSentDirect => '送信者にダイレクトメッセージで送りました。';

  @override
  String get placeNoSenderKey => 'この場所には鍵が付いていないため、直接宛先にできません。';

  @override
  String get dmWaiting =>
      '上のメッセージの結果を待っています。連絡先ごとに1通ずつにすることで、無線機がどのメッセージに応答があったかを示せます。';

  @override
  String get settingsHubFirmware => 'ファームウェア';

  @override
  String get firmwareTitle => 'ファームウェア';

  @override
  String get firmwareIntro =>
      'この無線機が動かしているものと、アプリがそれに対して行うこと。この画面から何かをインストールすることはありません。';

  @override
  String get firmwareRadioLabel => '無線機のファームウェア';

  @override
  String get firmwareAppLabel => 'このアプリ';

  @override
  String get firmwareOtaSupported => '無線更新に対応してビルドされています';

  @override
  String get firmwareOtaAbsent => 'このビルドには無線更新がありません';

  @override
  String get firmwareOtaUnknown => '未確認: 無線機が最初の接続時に応答します';

  @override
  String get firmwareNoInstallWhy =>
      'アプリからのインストールは提供していません。インストールは無線機の送信待ちメッセージを数フレームまで消費し、捨てられるメッセージを再同期する手段がアプリにありません。Diagnostics からの再起動が唯一の操作で、これはインストールではありません。';

  @override
  String get firmwareOtaLabel => '無線更新';

  @override
  String deviceRadio2Seen(String when) {
    return '第2プロファイル: $when受信';
  }

  @override
  String get deviceRadio2Never => '第2プロファイル: 今回は受信なし';

  @override
  String get deviceRadio2Note =>
      '第2プロファイルは無線機の送信時間の96〜99%を使うため、切り替えは無線機側で行い、このアプリでは変更しません。両方のフレームは受信しますが、第2プロファイル自体のパラメータは表示しません。';

  @override
  String get deviceReadoutQuerying => '無線機に問い合わせ中…';

  @override
  String deviceReadoutFirmware(String value) {
    return 'ファームウェア: $value';
  }

  @override
  String deviceReadoutBuild(String value) {
    return 'ビルド: $value';
  }

  @override
  String deviceReadoutManufacturer(String value) {
    return '製造元: $value';
  }

  @override
  String deviceReadoutContacts(int maxContacts, int channels) {
    return '最大コンタクト数: $maxContacts · チャンネル: $channels';
  }

  @override
  String deviceReadoutBlePin(int value) {
    return 'BLE PIN: $value';
  }

  @override
  String deviceReadoutPathHash(int bytes) {
    return 'パスハッシュ: $bytes バイト';
  }

  @override
  String deviceReadoutBattery(String value) {
    return 'バッテリー: $value';
  }

  @override
  String deviceBatteryValue(String volts, int percent) {
    return '${volts}V（約$percent%）';
  }

  @override
  String deviceAirtimeLimit(int share, String af) {
    return '送信時間上限: $share%（af $af）';
  }

  @override
  String get deviceAirtimeLimitUnknown => '送信時間上限: —';

  @override
  String deviceRepeatRanges(String ranges) {
    return '中継: $ranges MHz';
  }

  @override
  String get deviceRepeatNone => '中継: 報告なし';

  @override
  String get deviceRepeatUnknown => '中継: —';

  @override
  String get diagnosticsSectionRadioAlerts => '無線機のアラート';

  @override
  String get diagnosticsRadioAlertsWhy =>
      '無線機自身のブザーと振動で、無線機のルールに従って鳴ります。このアプリからは鳴らしません。スマートフォンが離れていても無線機側で動きます。';

  @override
  String get diagnosticsBuzzer => 'ブザー';

  @override
  String get diagnosticsVibration => '振動';

  @override
  String get diagnosticsAlertNotRead => '未取得';

  @override
  String get diagnosticsAlertReading => '無線機に問い合わせ中';

  @override
  String get diagnosticsAlertRead => '無線機に問い合わせる';

  @override
  String get diagnosticsAlertOn => 'オン';

  @override
  String get diagnosticsAlertOff => 'オフ';

  @override
  String get diagnosticsAlertDone => '無線機が受け付けました。';

  @override
  String diagnosticsAlertSaid(String text) {
    return '無線機の応答: $text';
  }

  @override
  String diagnosticsAlertRefused(String cause) {
    return '無線機が拒否しました: $cause';
  }

  @override
  String diagnosticsAlertRefusedSaid(String cause, String text) {
    return '無線機が拒否しました: $cause。応答: $text';
  }

  @override
  String get diagnosticsAlertSilent => '6秒以内に応答がありません。無線機が実行した可能性はあります。';

  @override
  String diagnosticsAlertSilentPartial(String text) {
    return '6秒以内に応答がありません。応答: $text';
  }

  @override
  String get diagnosticsAlertBusy => '別のコマンドがまだ応答待ちです。';

  @override
  String get diagnosticsAlertUnavailable => '接続がないため、何も送信していません。';

  @override
  String get voiceTitle => 'ボイスメモ';

  @override
  String get voiceLimit => '20秒で自動的に停止します。';

  @override
  String get voiceRecord => '録音';

  @override
  String get voiceStop => '停止';

  @override
  String get voiceDiscard => '破棄';

  @override
  String get voiceStoppedAtLimit => '20秒で停止しました。';

  @override
  String get voiceNoMicrophone => 'マイクを利用できないため録音できません。';

  @override
  String get voiceNoCodec => 'このビルドには音声コーデックがありません。';

  @override
  String voiceCost(int datagrams, int seconds, String mode) {
    return '$datagrams パケット、$mode で約 $seconds 秒の送信時間。';
  }

  @override
  String voiceRecording(int seconds, int bytes, int datagrams) {
    return '録音中 $seconds 秒、$bytes バイト、約 $datagrams パケット。';
  }

  @override
  String get voiceNoteSend => '音声を送信';

  @override
  String get voiceNotePreview => '試聴';

  @override
  String get voiceNotePlaying => '再生中';

  @override
  String get voiceModeTitle => '音声モード';

  @override
  String get voiceModeNarrow => 'ナロー';

  @override
  String get voiceModeStandard => 'スタンダード';

  @override
  String get voiceNotesTitle => 'ボイスメモ';

  @override
  String get voiceNotesEmpty => 'ボイスメモはまだありません。録音してから送信してください。';

  @override
  String voiceNotesCount(int count) {
    return 'ボイスメモ ($count)';
  }

  @override
  String get voiceNoteDecodeFailed => 'このボイスメモは復号できません。';

  @override
  String get voiceNoteTooShort => '短すぎて復号できません。';

  @override
  String get mediaStalledTableFull =>
      '無線機のパケット表が満杯のままになったため、送信を中止しました。以降は何も送信していません。';

  @override
  String get mediaStalledAirtime =>
      'この1時間の送信時間の上限に達したため、送信を中止しました。時間枠が戻れば再試行できます。';

  @override
  String get voiceNotesSession => 'アプリを閉じるまでこの端末に保持されます。履歴には保存されません。';

  @override
  String get gridRangeAuto => '自動';

  @override
  String get heatEmpty => 'この1時間、この範囲で交信は聞こえていません。';

  @override
  String get elevationEmpty => 'まだ誰も高度を報告していません。センサーを持つ相手に問い合わせるか、広告を待ってください。';

  @override
  String get mapOverlaysTitle => 'マップに表示するもの';

  @override
  String get connectTitle => '無線機に接続';

  @override
  String get mapKeyTitle => '地図の凡例';

  @override
  String get mapKeyRepeater => '中継機';

  @override
  String get mapKeyClient => 'クライアント無線機';

  @override
  String get mapKeyYou => '自分';

  @override
  String get mapKeyHeading => '端末が向いている方向';

  @override
  String get mapKeyReach => '相手の推定到達距離';

  @override
  String get mapKeyDensity => 'セルあたりのノード数';

  @override
  String get mapKeyGeofence => '設定したフェンス';

  @override
  String get mapKeyTrail => '自分の軌跡';

  @override
  String get mapKeyMessage => '直前にメッセージを送ったノード';

  @override
  String mapMessageBubble(String name) {
    return '$name からメッセージが届きました';
  }

  @override
  String get mapDensityShow => 'セルごとのノード密度';

  @override
  String mapDensityCellTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'このセルに $count ノード',
      one: 'このセルに 1 ノード',
    );
    return '$_temp0';
  }

  @override
  String mapDensityCellArea(String size) {
    return '$size ごと。どのズームでも画面上の大きさは同じです。';
  }

  @override
  String get mapDensityCellOpen => 'このノードを開く';

  @override
  String get bootFailedTitle => 'Meshmore SNS を起動できませんでした。';

  @override
  String get bootTryAgain => '再試行';

  @override
  String notifGroupBody(int count, String body) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件',
    );
    return '$_temp0 · $body';
  }

  @override
  String notifUnreadDigest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '未読メッセージ $count 件',
      one: '未読メッセージ 1 件',
    );
    return '$_temp0';
  }

  @override
  String mapDensityCellSize(String size) {
    return 'セル: $size あたりのノード数';
  }

  @override
  String actionReplyMention(String name) {
    return '$name に返信';
  }

  @override
  String get actionQuote => 'このメッセージを引用';

  @override
  String get actionReplyNoName => '返信';

  @override
  String get chatActionsNoRadio => '無線が未接続です。返信や引用は入力欄に保持され、接続後に使えます。';
}
