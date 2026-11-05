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
  String get appSubtitle => 'ソーシャルロボット・ネットワークサービス';

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
  String get dashboardPeersInRange => '範囲内のピア';

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
  String get botRefusedPublicSlot => 'パブリックでは使用できません。スロット0は公開チャンネルです。';

  @override
  String get botRefusedPublicPsk =>
      'このスロットは公開鍵のままなので、実質パブリックです。先に専用の鍵を設定してください。';

  @override
  String get botRefusedUnknownPsk => '無線機からこのスロットの鍵を取得中です。';

  @override
  String get botMode => '返信モード';

  @override
  String get botModeDeterministic => '決定的';

  @override
  String get botModeRandom => 'ランダム';

  @override
  String get botModeDeterministicSub => '常に最初に一致した規則を使うため、記録を差分比較できます。';

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
  String get dashPeers => 'ピア';

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
  String get statusLinked => '接続中';

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
  String get linkChipLinked => '接続';

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
  String linkChipSemantics(String state) {
    return 'ラジオ: $state';
  }

  @override
  String get actionConnect => '接続';

  @override
  String get actionRetry => '再送';

  @override
  String get dashboardDevice => 'デバイス';

  @override
  String get deviceMgrTitle => 'デバイス';

  @override
  String get deviceMgrNoPair => 'デバイス未ペアリング';

  @override
  String get deviceMgrStateConnected => '接続中';

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
  String get pairNothingFound =>
      '応答したラジオがありません。電源・距離・他のスマートフォンへの接続を確認して、もう一度スキャンしてください。';

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
      'Android: 常駐通知でラジオ接続を維持し、バックグラウンド中もメッセージを受信';

  @override
  String get settingsBackgroundOff =>
      'アプリ再表示時にメッセージ受信 (ラジオがバッファ); バックグラウンド通知なし';

  @override
  String get settingsTelemetryPoll => 'ノードのテレメトリを収集';

  @override
  String get settingsTelemetryPollOn => 'コンタクトに温度・標高を控えめに問い合わせ (少量の電波使用)';

  @override
  String get settingsTelemetryPollOff => 'テレメトリ要求は送信しません; 各ノードの詳細から手動で取得';

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
  String get settingsSpeechMuted => '読み上げは ON ですが、オーディオミュートにより消音されています';

  @override
  String get settingsPermissions => '権限';

  @override
  String get settingsPermissionsSubtitle =>
      'このアプリの OS 設定画面を開く — Bluetooth / 通知をオン・オフできます。';

  @override
  String get settingsShowIntro => '次回起動時に紹介を再表示';

  @override
  String get settingsShowIntroEnabled => '初回フラグを消去し権限紹介を再表示 — フロー検証時に便利';

  @override
  String get settingsShowIntroDisabled => '紹介は次回起動時に表示予定';

  @override
  String get termsTitle => '利用規約とプライバシー';

  @override
  String get termsLead => 'このアプリはメッシュ無線と通信します。アカウントもクラウドも解析もありません。';

  @override
  String get termsSectionLocal => 'この端末に残るもの';

  @override
  String get termsLocalBody =>
      'メッセージ、連絡先、チャンネル、設定、記録した軌跡はこの端末に保存されます。アプリ自身のデータはクラウドバックアップと端末間転送の対象外なので、新しい端末が黙って引き継ぐことはありません。アプリを削除すると、そのデータも削除されます。';

  @override
  String get termsSectionLeaves => '端末の外に出るもの';

  @override
  String get termsLeavesBody =>
      '送信したもの以外は出ません。メッセージと位置は接続中の無線から送られます。オンライン地図パックは既定でオフで、有効にしたときだけ取得し、取得元を画面に表示します。書き出したファイルの保管先はあなたが決めます。';

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
      'MeshCore ドキュメント（MIT）、GeoNames 都市データ（CC-BY 4.0）、Natural Earth（パブリックドメイン）、OpenStreetMap 地図データ（ODbL）、Saira・JetBrains Mono フォント（OFL）を含みます。';

  @override
  String get personalizationHeading => 'プロフィール & パーソナライズ';

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
  String get personalizationHighContrastSubtitle => 'SEELE ハイコントラストパレットを強制適用';

  @override
  String get personalizationHighContrastHint =>
      'ハイコントラストが ON のため、プリセットの選択に関わらず SEELE ハイコントラストパレットが強制されます。別テーマを使うには下の「ハイコントラスト」を OFF にしてください。';

  @override
  String get personalizationReduceMotion => 'モーションを減らす';

  @override
  String get personalizationVisualHapticOnly => '視覚 + 触覚のみ';

  @override
  String get personalizationVisualHapticOnlySubtitle => '音による情報提示なし; 音声をオフ';

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
  String get demoModeRow => 'デモモード（無線なし）';

  @override
  String get demoModeOn => 'オン — 起動時に無線へ接続しません';

  @override
  String get demoModeOff => 'オフ — 起動時にペアリング済みの無線へ接続します';

  @override
  String get firstRunHeader => 'MESHMORE · ようこそ';

  @override
  String get firstRunTitle => 'アプリが必要とする権限について';

  @override
  String get firstRunBleTitle => 'Bluetooth';

  @override
  String get firstRunBleBody =>
      'MeshCore ラジオとペアリングし、ローカルメッシュ越しにメッセージを送受信します。OTA 通信に必須です。';

  @override
  String get firstRunNotificationsTitle => '通知';

  @override
  String get firstRunNotificationsBody =>
      '後でアプリ設定の「バックグラウンドで接続を維持」を ON にした場合のみ求めます。今回はスキップし二度確認しません。';

  @override
  String get firstRunOfflineTitle => 'オフラインでも使えます';

  @override
  String get firstRunOfflineBody =>
      'Bluetooth をスキップするとデモモードで起動します。メッセージ履歴の閲覧、チャネル設定、診断、ドキュメントが使えます。無線を接続するまでライブのメッシュ通信はありません。';

  @override
  String get firstRunGrant => 'Bluetooth を許可して続行';

  @override
  String get firstRunSkip => 'デモモードで試す（無線なし）';

  @override
  String get firstRunDeniedTransient =>
      'Bluetooth が許可されませんでした — オフラインで続行するか、OS 設定で許可を変更できます。';

  @override
  String get firstRunDeniedPermanent =>
      'Bluetooth が永続的に拒否されました — OS 設定で許可してください。オフラインでも引き続き利用可能です。';

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
  String get nodesZeroHopAdvert => 'ゼロホップアドバート';

  @override
  String get nodesZeroHopAdvertBody => '隣接のみ — 再ブロードキャストなし。混雑したメッシュ向け。';

  @override
  String get nodesFloodAdvertSent =>
      'フラッドアドバートを送信 — メッシュ全体に伝播 (隣接 + リピーター)。相手側でも Advertise を実行するまで表示されません。';

  @override
  String get nodesZeroHopAdvertSent =>
      'ゼロホップアドバートを送信 — 隣接のみ、リピーターは再ブロードキャストしません。';

  @override
  String get nodesSearchHint => '名前 / shortId / 公開鍵で検索…';

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
    return '$shown/$total件 表示 · $inRange件 範囲内 · $favs件 コンタクト';
  }

  @override
  String get nodesStatusOffline => '未接続 — 設定 → 診断で接続';

  @override
  String get nodesFarBadge => '遠距離';

  @override
  String get nodesEmptyFiltered =>
      '条件に一致するノードがありません。\n\n上の「クリア」で絞り込みを解除するか、各チップで条件を変更してください。';

  @override
  String get nodesEmptyReady => 'ノードはまだありません。アドバートを受信すると表示されます。';

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
    return '同心円 3 本 = 距離帯。両端に GPS がある場合、外側のリングは上の「範囲」スケール (現在 ~$value)。GPS がない場合は RSSI 帯 (近 / 中 / 遠)。';
  }

  @override
  String get gridLegendSelf => '中央 = 自分。十字 = 南北 / 東西の目安。';

  @override
  String get gridLegendDot =>
      'ドット = 受信したファブリックノード。明るさ = 新しさ (受信直後 = 最大、24時間で 0 に減衰し消滅)。';

  @override
  String get gridLegendKnown => 'パルス (緩やかに広がる輪) = 既知ノード — 直接やり取り (DM) があったノード。';

  @override
  String get gridLegendFavourite => '別色での速い点滅 = お気に入りのノード。';

  @override
  String get gridLegendRipple => '中央からの波紋 = 匿名のチャネルメッセージ (プロトコル上、送信者を特定できません)。';

  @override
  String get gridLegendTap => 'ノードをタップで詳細 + メッセージ / お気に入り。';

  @override
  String get gridLegendHeading =>
      '方位ウェッジ・HDG 表示 = スマートフォン上端が**磁北**を基準に向いている方向（真北でも GPS 進行方向でもなく、スマートフォンの方位センサーが示す方位）。';

  @override
  String get gridLegendCalibration =>
      'キャリブレーション: 矢印がずれている場合、スマートフォンを水平に持って数回 8 の字に動かしてください。コンパスのキャリブレーションは OS が行い、アプリは精度のみ表示します（精度が悪いと「Calibrate」ヒントが出ます）。';

  @override
  String get gridViewRadial => 'ラジアル';

  @override
  String get gridViewGlobe => 'グローブ';

  @override
  String get gridViewEqualGrid => '等分グリッド';

  @override
  String get gridViewStreetMap => 'ストリートマップ';

  @override
  String get gridViewPicker => 'マップ表示を切替';

  @override
  String get gridViewFabric => 'ファブリック調査';

  @override
  String get gridViewElevation => 'Fujiさん';

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
  String get fujiLegendPeers => '点 = ピア。問い合わせ後にテレメトリ標高でプロット。';

  @override
  String get fujiLegendUnknown => '地面沿いの縞帯 = まだ標高不明のピア。';

  @override
  String get fujiLegendAutoQuery => 'AUTO-QUERY ボックスがピア標高を順次取得。タップで再起動。';

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
    return '$n 個のノード';
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
  String fabricCoverageCount(int n) {
    return 'メッシュ調査 · $n セル';
  }

  @override
  String get fabricResetTooltip => '調査結果をリセット';

  @override
  String get fabricResetTitle => 'メッシュ調査結果をリセットしますか？';

  @override
  String get fabricResetBody =>
      '記録済みのセルをすべて削除します。移動と近隣ノードの観測に応じて新しい記録が再び埋まっていきます。';

  @override
  String get fabricResetApply => 'リセット';

  @override
  String get streetMapRecenter => '現在地に戻す';

  @override
  String get mapNoFixBanner => '位置情報がまだ取得できていません。表示は世界地図で、現在地には合わせていません。';

  @override
  String get mapHideTiles => '地図タイルを非表示';

  @override
  String get mapShowTiles => '地図タイルを表示';

  @override
  String deviceRegionLoadedOffline(String label) {
    return '$label を読み込みました — デバイス接続時に「適用」してください。';
  }

  @override
  String get equalGridAwaitingFix =>
      '等分グリッド表示には自分の位置が必要です — GPS 取得待ち（スマートフォンまたはデバイス）。';

  @override
  String equalGridCellSize(String size) {
    return 'セル $size';
  }

  @override
  String get equalGridZoomIn => 'ズームイン（セルを狭く）';

  @override
  String get equalGridZoomOut => 'ズームアウト（セルを広く）';

  @override
  String get equalGridShowStats => 'ターゲティングパネルを表示';

  @override
  String get equalGridHideStats => 'ターゲティングパネルを非表示';

  @override
  String globeFooter(int n) {
    return '位置情報のある $n 件のピアを表示';
  }

  @override
  String get globeOverlayArcs => 'アーク';

  @override
  String get globeOverlayRegion => '地域';

  @override
  String get globeOverlayLabels => 'ラベル';

  @override
  String get globeAltitude => '高度';

  @override
  String get globePaused => '一時停止';

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
  String get deviceGpsDisabledHint =>
      'オフ — デバイスは GPS を一切読み取らず、配信される位置は最後に書き込まれた値のままです。';

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
  String get deviceGpsIntervalFixedByFirmware =>
      'このファームウェアビルドでは GPS 更新間隔がハードコードされており、変更できません（sensors モジュールが `gps_interval` を公開していないため）。';

  @override
  String get locTitle => '位置の自動公開';

  @override
  String get locTileSubtitle => '定期 + 移動検知でスマートフォン GPS をデバイスに反映';

  @override
  String get locHelp => '無線機の GPS が古いとき、スマートフォンの位置を書き込みます。';

  @override
  String get locMaster => '自動公開';

  @override
  String get locMasterOn => 'オン — スマートフォン GPS 使用中';

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
  String get locPublishNowSub => 'ループ動作の確認用に手動で 1 回送信。';

  @override
  String locLastPublished(String lat, String lon, String time, String trigger) {
    return '最終: $lat, $lon  ·  $time  ·  $trigger';
  }

  @override
  String get locBeacon => '定期位置ビーコン';

  @override
  String get locBeaconSub => '60 秒ごとに位置をアドバートします（ゼロホップ）。通信時間と電池を使います。';

  @override
  String get locBatteryHint =>
      'スマートブロードキャストは GPS を継続使用 (約 10 mA)。定期のみは省電力。両方有効で応答性最大、バッテリー優先ならスマートブロードキャストのみ推奨。';

  @override
  String get gridEmpty => 'まだ範囲内にノードがありません。\n\nアドバートを受信すると表示されます。';

  @override
  String get gridStatusOffline => '未接続 — 設定 → 診断で接続';

  @override
  String get gridSwipeModeTooltip => 'スワイプモード:左右にスワイプで他の画面へ。タップでこのマップを移動・ズーム';

  @override
  String get gridPanModeTooltip => '移動・ズームモード:ドラッグでマップを移動。タップで画面スワイプに戻る';

  @override
  String get gridSwipeHint => '← → スワイプで他の画面 · ✋ をタップで移動・ズーム';

  @override
  String get gridPanHint => '移動・ズーム中 · ⇆ をタップで画面スワイプ';

  @override
  String gridStatusCounts(int visible, int known, int favs) {
    String _temp0 = intl.Intl.pluralLogic(
      favs,
      locale: localeName,
      other: '$favs件 コンタクト',
      zero: '0件 コンタクト',
    );
    return '$visible件 ファブリック · $known件 既知 · $_temp0';
  }

  @override
  String get gridGroupPeers => 'ピア';

  @override
  String get gridGroupSurvey => '調査';

  @override
  String get gridGroupReports => 'レポート';

  @override
  String get gridNotConnected => 'メッシュに未接続';

  @override
  String get gridHeadingCalibrate => 'コンパス要校正 — スマートフォンを 8 の字に振ってください。';

  @override
  String get gridOrientNorthUp => '北を上';

  @override
  String get gridOrientHeadingUp => '進行方向を上';

  @override
  String get gridHeadingHud => '方位';

  @override
  String get voiceSettingsTitle => '音声 (TTS 品質)';

  @override
  String get voiceSettingsHint =>
      '「アプリ設定」で SPEECH を ON にするまで無効。レート / ピッチ / 音声は次の発話から適用されます。';

  @override
  String get voiceRate => '速度';

  @override
  String get voicePitch => 'ピッチ';

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
  String get settingsGroupAbout => 'このアプリについて';

  @override
  String get settingsHubApp => 'アプリ設定';

  @override
  String get settingsHubProfile => 'プロフィール & パーソナライズ';

  @override
  String get settingsHubChannels => 'チャンネル';

  @override
  String get settingsHubDiagnostics => '診断 & 接続';

  @override
  String get bootHeader => 'MESHMORE  /  同期中';

  @override
  String get bootConnecting => 'ラジオに接続中…';

  @override
  String get bootHandshaking => 'ハンドシェイク中…';

  @override
  String get bootReady => 'メッシュ オンライン';

  @override
  String get bootOffline => 'オフライン — 設定 → 診断 & 接続';

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
  String eventMsgSent(String ack) {
    return 'メッセージ送信 (ack $ack)';
  }

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
  String get chatComposerOffline => '送信するにはラジオに接続';

  @override
  String get chatSend => '送信';

  @override
  String chatBudgetRemaining(int remaining, int max) {
    return '残り $remaining / $max バイト';
  }

  @override
  String chatBudgetEstimate(int remaining, int max) {
    return '残り約 $remaining / $max バイト — 無線機の名前はまだ不明です';
  }

  @override
  String get chatBudgetNear => '上限が近いです:無線機は自分の名前もこのバイト数に含めます';

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
    return 'DM · $peer';
  }

  @override
  String dmPubkeyLabel(String hex) {
    return '公開鍵 · $hex';
  }

  @override
  String get nodeDetailSignature => '着信シグネチャ';

  @override
  String get nodeDetailSignatureHint => 'この相手専用の通知音（DM の通知の代わり）。';

  @override
  String get nodeDetailSignatureNone => 'デフォルト';

  @override
  String nodeDetailSignatureSlot(int n) {
    return 'シグネチャ $n';
  }

  @override
  String get nodeDetailSignatureMutedHint => '音声はミュート中です。振動は伝わりますが音は鳴りません。';

  @override
  String get dmEmpty => '— メッセージはまだありません —';

  @override
  String get dmOpenPeerDetail => '相手の詳細';

  @override
  String get dmSpeech => 'この相手を読み上げる';

  @override
  String get dmSpeechInherit => '全体の読み上げ設定に従う';

  @override
  String get dmSpeechAlways => '常に読み上げる';

  @override
  String get dmSpeechNever => '読み上げない';

  @override
  String get dmSpeechMutedByMaster => 'オーディオミュートにより消音中';

  @override
  String get dmPeerNotInFabric => 'この相手はまだメッシュ上で確認されていません（アドバート未受信）。';

  @override
  String dmComposerHint(String peer) {
    return '$peer へメッセージ';
  }

  @override
  String get dmSend => 'DM 送信';

  @override
  String get actionRetrySub => 'このメッセージをもう一度送信';

  @override
  String get actionReply => '返信';

  @override
  String get actionReplySub => 'このメッセージを引用して返信';

  @override
  String get actionCopy => 'コピー';

  @override
  String get actionCopySub => 'メッセージ本文をクリップボードにコピー';

  @override
  String get actionDeleteLocal => 'ローカル削除';

  @override
  String get actionDeleteLocalSub => '履歴からこの行のみ削除 — OTA 送信済みのメッセージは取り消せません。';

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
  String get nodeDetailSelf => 'これはあなた自身のノードです — メッセージ / お気に入りは利用不可。';

  @override
  String get nodeDetailShareTelemetryTitle => 'この連絡先と自分のテレメトリを共有';

  @override
  String get nodeDetailShareTelemetryHelp => 'テレメトリモードが「連絡先」で、基本がオンのときのみ有効です。';

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
  String get nodeIdentityLinkAction => 'キーが変わった？ 別のノードにリンク';

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
  String get nodeDetailNotDeviceContact =>
      '無線機の連絡先にないため、DM が届かない場合があります。チャンネルは利用できます。';

  @override
  String get nodeDetailAddDeviceContact => 'デバイスの連絡先に追加';

  @override
  String get nodeDetailAddDeviceContactDone =>
      '追加しました。DM が届くようになります。届かない場合、連絡先がいっぱいかもしれません。';

  @override
  String get nodeDetailAddDeviceContactFailed =>
      '連絡先を追加できませんでした — リンクを確認して再試行してください。';

  @override
  String get nodeDetailRemoveDeviceContact => 'デバイスの連絡先から削除';

  @override
  String nodeDetailRemoveDeviceContactConfirm(String name) {
    return '「$name」を無線機の連絡先から削除しますか？空きができます。後で再追加できます。';
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
  String get deviceContactsChannelsNote =>
      '連絡先が必要なのはダイレクトメッセージを送るときだけです。チャンネルのメッセージは連絡先がなくても機能し、全員がチャンネルに表示されます。';

  @override
  String get deviceContactsScrub => '連絡先を整理';

  @override
  String get deviceContactsRemoveOutOfRange => '圏外を削除';

  @override
  String get deviceContactsOutOfRangeIntro =>
      '現在地から遠い連絡先、または位置を隠している（GPS なし）連絡先を削除します（圏外として扱います）。お気に入りと既知の連絡先は保持されます。';

  @override
  String deviceContactsBeyondKm(int km) {
    return '$km km 以上（＋位置非公開）';
  }

  @override
  String get deviceContactsNeedLocation =>
      '現在地が未設定のため距離を測定できません。位置非公開の連絡先のみが対象です。GPS または手動ピンで位置を設定すると、遠方の GPS 連絡先も削除できます。';

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
    return '無線機の連絡先 $count 件をすべて削除しますか？チャンネルには連絡先は不要で、DM のときだけ必要です。後でメッセージしたい相手を再追加できます。';
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
  String get gridViewSnsCells => 'SNS セル（ヒート）';

  @override
  String get gridViewWeather => '気象（環境）';

  @override
  String get gridViewMeshbook => 'メッシュブック（チャンネル活動）';

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
    return 'CH$channel の直近24時間のメッシュブックデータをクリアしますか？新しいチャンネルメッセージが届くと再構築されます。（チャンネルごとに別々に保存されます。）';
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
  String get wxAmbientEmpty => 'このチャンネルにはまだ天気の話題がありません。';

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
    return 'このデバイスのファームウェアは環境テレメトリに対応していません。\n報告内容: $types。\nセンサー（例: T1000-E の BME280）には MeshCore センサーファームウェアが必要です。標準ビルドはバッテリー／GPS のみを送信し、環境モードを設定してもデバイス側でオフに戻されます。これはアプリの設定ではなくデバイス側の制限です。';
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
  String get docsOriginBundled => '同梱スナップショット';

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
  String get snsCellsAwaitingFix => '位置情報を待機中 — ヒートマップは自分を中心に表示されます。';

  @override
  String get snsCellsClear => 'クリア';

  @override
  String snsCellsStatus(int active, int hot) {
    return '$active セル · $hot ホット';
  }

  @override
  String snsPlacesButton(int count) {
    return '場所 ($count)';
  }

  @override
  String get snsPlacesTitle => '推定された場所（過去1時間）';

  @override
  String get snsPlacesEmpty => '現在、推定された場所はありません。';

  @override
  String get snsPlacesDismiss => '場所ではない — 削除';

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
      'チャンネルメッセージは送信者名を含みます — 送信者の位置が分かればそのセルを、分からなければ自分のセル（受信地点）を温めます。';

  @override
  String get snsCellsLegendInferred =>
      '破線の ◇ マーカーは会話（「〜から」など）から推定した場所で、おおよその位置に表示されます。チャンネルごとに設定で切替できます。';

  @override
  String get snsCellsLegendDecay => '直近1時間のみ追跡。保存はされません。';

  @override
  String get meshTreeEmpty => 'コンタクト同期を待機中 — ツリーは各コンタクトの outPath から構築されます。';

  @override
  String get meshTreeHopsDirect => '直接';

  @override
  String get meshTreeHopsFlood => 'フラッド / 全て';

  @override
  String meshTreeHopsN(int n) {
    return '≤$n ホップ';
  }

  @override
  String get meshTreeRecenter => '中央に戻す';

  @override
  String get meshTreeLegendTitle => 'メッシュツリー';

  @override
  String get meshTreeLegendDesc =>
      '無線がどの経路で各コンタクトに到達するかの有向グラフ。エッジは Contact.outPath — デバイスが送信に使う正確なリピーター連鎖。';

  @override
  String get meshTreeLegendSelf => 'あなた — 中央に固定。';

  @override
  String get meshTreeLegendRepeater =>
      '四角 = リピーター。マスト設置インフラ、ハブ色。ピアはこれらを経由して広がる。';

  @override
  String get meshTreeLegendRoom => 'ひし形 = ルームサーバ。名前付きルームをホストするサーバ級ノード。';

  @override
  String get meshTreeLegendChat => '円 = チャットノード。DM 可能なピア。';

  @override
  String get meshTreeLegendSensor => '小さい円（暗）= センサー。特定用途のノード。';

  @override
  String get meshTreeLegendFlood =>
      '破線で自分とつながる = フラッドルーティングのコンタクト。到達可能だが固定経路なし。';

  @override
  String get meshTreeLegendFloat => '浮遊（エッジなし）— advert のみで受信、経路不明。';

  @override
  String get meshTreeLegendArrow => '矢印は自分から目的ピアへ向かう。';

  @override
  String get meshTreeLegendInteract =>
      'ピンチで拡大縮小、ドラッグで移動、ノードをタップで詳細。「中央に戻す」でリセット。';

  @override
  String get fabricLegendTitle => 'ファブリックサーベイ';

  @override
  String get fabricLegendDesc =>
      'メッシュが観測された場所の永続的な記録。各長方形は小さな地理セル（約 220 m × 220 m）で、デバイスがこの位置と接続したときにログ。';

  @override
  String get fabricLegendCell => '塗りつぶしセル — ここで一度はメッシュが届いた。';

  @override
  String get fabricLegendRecency =>
      '明るい塗り = より新しい。階層 — 1時間以内、24時間以内、7日以内、それ以上。';

  @override
  String get fabricLegendMarker => '第三色のピンは現在のセット内のピア。タップで詳細。';

  @override
  String get fabricLegendSelf => '原色のピンはあなた。';

  @override
  String get fabricLegendReset => '新しい地域に移動するときは、オーバーフローメニューからサーベイをリセット。';

  @override
  String get nodeDetailHopsKv => 'ホップ数';

  @override
  String get nodeDetailHopsDirect => '直接 (0 ホップ)';

  @override
  String nodeDetailHopsViaRepeaters(int n) {
    return '$n 経由リピーター';
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
  String get nodeDetailTelemetryQuerying => '電波経由でピアに問い合わせ中…';

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
  String get channelsHelp => 'スロット 0 は共有のパブリック。プライベートは全ノードで同じスロット・名前・PSK にします。';

  @override
  String get channelsOfflineHint => 'チャンネルを編集するにはラジオを接続 (診断)。';

  @override
  String get channelsEmpty => '— 未設定 —';

  @override
  String channelsSlotLabel(int idx) {
    return 'スロット $idx';
  }

  @override
  String channelsSlotActive(int idx) {
    return 'スロット $idx · 有効';
  }

  @override
  String get channelsEdit => '編集';

  @override
  String get channelsSet => '設定';

  @override
  String channelsSetSnack(int idx, String name) {
    return 'チャンネル $idx を「$name」に設定 — 全ノードで同じ名前 & PSK が必要';
  }

  @override
  String channelsDialogTitle(int idx) {
    return 'チャンネルスロット $idx';
  }

  @override
  String get channelsName => 'チャンネル名';

  @override
  String get channelsInferPlaces => 'メッセージから場所を推定';

  @override
  String get channelsInferPlacesSub => 'このチャンネルの会話から地名を抽出し、SNS グリッドに表示します。';

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
  String get notifSectionTitle => '通知';

  @override
  String get notifOs => 'ロック画面に通知';

  @override
  String get notifAudio => '効果音を鳴らす';

  @override
  String get notifHaptic => '振動';

  @override
  String get notifTts => '読み上げ';

  @override
  String get notifMentionsOnly => '名前を呼ばれた時だけ';

  @override
  String get notifMentionsOnlySub => '単語全体か @名前。オフなら全メッセージで通知します。';

  @override
  String get notifKeySuffix => '鍵の末尾にも一致させる';

  @override
  String get notifKeySuffixSub => '16進4文字は識別子ではありません。送信者を確実に知っている場合のみ。';

  @override
  String get notifDeniedBanner => 'このアプリの通知がオフのため、メッセージはロック画面に表示されません。';

  @override
  String get channelsKeySource => '鍵ソース';

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
  String get channelsErrorHex => 'PSK は 16 進 32 文字 (16 バイト) で入力してください';

  @override
  String get channelsErrorName => 'チャンネル名を入力してください';

  @override
  String get channelsCancel => 'キャンセル';

  @override
  String get channelsSave => '保存';

  @override
  String get channelsHelpEncryption =>
      'スロット 0 の鍵は公開。他のスロットは設定した PSK による AES-128 です。';

  @override
  String get channelsHexGenerate => 'PSK をランダム生成';

  @override
  String get channelsHexCopy => 'コピー';

  @override
  String get channelsHexCopied => 'PSK をクリップボードにコピー';

  @override
  String get channelsTagWeakShort => '短いタグは推測されやすい。12 文字以上または独自の表現を使用してください。';

  @override
  String get channelsTagWeakCommon =>
      '一般的な単語は推測されやすい — 攻撃者にタグ総当りを許します。独自の表現を使用してください。';

  @override
  String get channelsSlot0WarnTitle => 'Public チャンネルを上書きしますか?';

  @override
  String get channelsSlot0WarnBody =>
      'スロット 0 は既知の Public チャンネルです。ここにプライベート PSK を書き込むと、同じ鍵を持つノードとしか通話できなくなり、共通の Public チャンネルを失います。続行しますか?';

  @override
  String get channelsSlot0WarnContinue => 'スロット 0 を上書き';

  @override
  String get channelsSlot0WarnCancel => 'キャンセル';

  @override
  String get channelsCurrentKey => '現在の鍵';

  @override
  String get channelsRevealKey => '表示';

  @override
  String get channelsHideKey => '隠す';

  @override
  String get channelsClear => 'スロットをクリア';

  @override
  String channelsClearConfirmTitle(int idx) {
    return 'スロット $idx をクリアしますか?';
  }

  @override
  String get channelsClearConfirmBody =>
      'MeshCore にはプロトコルレベルの「クリア」がありません — このスロットは Public 既定値 (名前 + 鍵) に上書きされます。他ノードも同様の操作が必要です。';

  @override
  String get channelsClearConfirmAction => 'クリア';

  @override
  String channelsClearSnack(int idx) {
    return 'スロット $idx をクリア (Public 既定値にリセット)';
  }

  @override
  String get channelsDefaultBadge => '既定';

  @override
  String get channelsSetDefaultTooltip => '起動時の既定チャンネルに設定';

  @override
  String get channelsClearDefaultTooltip => '既定チャンネル設定を解除';

  @override
  String channelsSetDefaultSnack(int idx) {
    return 'スロット $idx を起動時の既定に設定';
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
      'Meshmore デバイス、または任意の QR リーダーでスキャン。このコードを持つ人はチャンネルに参加できます — 信頼できる相手のみと共有してください。';

  @override
  String get channelsQrPayload => 'ペイロード (コピー用)';

  @override
  String get channelsQrClose => '閉じる';

  @override
  String get deviceConfigTitle => 'デバイス設定';

  @override
  String get deviceRegionBand => 'リージョン / バンド';

  @override
  String get deviceRegionCurrent => '現在の設定';

  @override
  String get deviceRegionUnknown => 'デバイス応答待ち…';

  @override
  String get deviceRegionCustom => 'カスタム（プリセット非該当）';

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
  String get deviceRegionSuggestTitle => '推奨リージョンを適用しますか？';

  @override
  String deviceRegionSuggestBody(String lat, String lon, String label) {
    return 'スマートフォンの GPS（$lat, $lon）に基づくと、該当するプリセットは「$label」です。国境付近では誤判定する可能性があるため、適用前に現地の法令に適合するか必ず確認してください。';
  }

  @override
  String get deviceRegionSuggestApply => '適用';

  @override
  String get deviceRegionSuggestNoFix =>
      'GPS の取得に失敗しました — 屋外で位置情報の許可を確認してから再試行してください。';

  @override
  String get deviceRegionSuggestNoMatch => '現在地が出荷時プリセットの対象外です — 手動で選択してください。';

  @override
  String deviceRegionAppliedToast(String label) {
    return '$label を適用しました。メッシュ内の全ノードで同じプリセットを使用してください。';
  }

  @override
  String get deviceRegionDisclaimerShort => 'コミュニティによる値であり、規制上の保証ではありません。';

  @override
  String get deviceRegionDisclaimerMore => '詳細';

  @override
  String get deviceRegionDisclaimer =>
      'プリセット値はコミュニティで合意された運用例であり、法令適合を保証するものではありません。利用地で合法なプリセットを選び、メッシュ内の全ノードで同じ値を使用してください。日本では設定値が合法でも不十分です。無線機本体が技適（技術基準適合証明）を取得している必要があり、海外から個人輸入したLoRaボードの多くは未取得です。未取得機の運用は設定内容にかかわらず電波法違反となります。日本（ARIB STD-T108）のプリセットはコミュニティ提案で、広範な実機検証は完了していません。実運用前に、法令適合性と動作をご自身のハードウェアで必ず確認してください。';

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
  String get deviceRadioParams => '周波数と帯域幅';

  @override
  String get deviceIdentityAdvert => 'アイデンティティ / アドバート';

  @override
  String get deviceChannelsSection => 'チャンネル';

  @override
  String get deviceOtherParamsSection => 'その他のパラメータ';

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
      'このラジオが送信するパケットに付けるハッシュ長です。中継は各パケット自身の長さに従うため、ノード間で揃える必要はありません。長いほど中継を区別しやすい一方、直接送信のペイロード容量が減ります。';

  @override
  String get devicePathHashUnread => 'パスハッシュ: 不明 (デバイス未問い合わせ)';

  @override
  String devicePathHashMismatch(String device, String form) {
    return '未適用: ラジオは $device バイト、フォームは $form です。';
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
  String get radioHealthTitle => '無線機の状態';

  @override
  String get radioHealthRead => '取得';

  @override
  String get radioHealthReading => '取得中…';

  @override
  String get radioHealthUnread =>
      'まだ取得していません。「取得」で無線機自身の統計(CMD_GET_STATS)を読みます。';

  @override
  String radioHealthNoise(String dbm) {
    return 'ノイズフロア $dbm dBm — 無線機自身の測定値';
  }

  @override
  String radioHealthLast(String rssi, String snr) {
    return '直近パケット RSSI $rssi dBm、SNR $snr dB — 無線機のパケット統計より';
  }

  @override
  String radioHealthBattery(String volts) {
    return 'バッテリー $volts V — 無線機のコア統計値(スマートフォン側の測定ではありません)';
  }

  @override
  String get radioHealthNotReported => 'このファームウェアでは報告されません';

  @override
  String radioHealthUptime(String uptime) {
    return '稼働 $uptime — 無線機の稼働カウンタ(電源再投入でリセットされます)';
  }

  @override
  String get radioHealthSource => 'すべて無線機自身のカウンタです。この画面の値はスマートフォン側の測定ではありません。';

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
  String get diagnosticsTitle => '診断 & 接続';

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
  String get otherManualAddSubOff => '受信したノードは自動でコンタクトに昇格します。';

  @override
  String get otherTelemetryModeTitle => 'テレメトリ共有 — 各種類を誰が要求できるか';

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
  String get otherMultiAcksLabel => 'マルチ ACK (0–3)';

  @override
  String get otherMultiAcksHelper =>
      '0 = シングル ACK (既定)。値が大きいほど送信確定までに待つ追加 ACK 数。';

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
  String get toolsOffline => '未接続 — ツールには無線機が必要です。';

  @override
  String get toolsRunning => '実行中';

  @override
  String get toolsStart => '開始';

  @override
  String get toolsStop => '停止';

  @override
  String get toolsCopyReport => 'レポートをコピー';

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
  String get pingMethodTelemetry =>
      'テレメトリ要求 — 相手には通知されず、テレメトリを共有している場合のみ応答します。';

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
  String get settingsHubInfo => '情報';

  @override
  String get settingsNotifDeniedPermanent =>
      '通知が永続的に拒否されました。バックグラウンドサービスには常駐通知が必要です。';

  @override
  String get settingsNotifDeniedTransient =>
      'バックグラウンドサービスには通知の許可が必要です。「設定を開く」から許可してください。';

  @override
  String get deviceAdvertPropagatesHint =>
      '名前・位置の変更は次のアドバートで反映されます (ノード → アドバート送信)。';

  @override
  String get settingsHubMaps => 'オフライン地図';

  @override
  String get mapsTitle => 'オフライン地図';

  @override
  String get mapsOffline =>
      'ネットワークがありません。新しい地図の設定はオンライン時のみ可能です。ダウンロードは自動で再開します。';

  @override
  String get mapsStorage => 'ストレージ';

  @override
  String mapsUsed(String used, String budget) {
    return '$budget 中 $used 使用';
  }

  @override
  String mapsBreakdown(String packs, String layers, String view) {
    return '地域 $packs・イベント地図 $layers・閲覧済みタイル $view';
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
  String get mapsNoPacks =>
      'まだ地域がありません。オフライン利用を許可するサーバー(米国内の USGS、または追加したタイルサーバー)から取得します。';

  @override
  String get mapsArchives => '地域ファイル';

  @override
  String get mapsNoArchives =>
      '地域ファイルがありません。地域ファイルは、信頼できる配信元の .pmtiles ファイルで、一つの地域をまとめてダウンロードします。リンクを追加してください。';

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
  String get mapsLayers => 'イベント地図';

  @override
  String get mapsNoLayersShort => 'イベントマップ未登録';

  @override
  String get mapsManageLayers => 'イベントマップを管理…';

  @override
  String get mapsAddLayer => 'イベント地図を追加';

  @override
  String get mapsNoLayers =>
      'イベント地図はありません。GeoJSON の URL(祭りの街区図、レースのコース、キャンプ配置など)を追加してください。';

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
  String get layerRefusalNotGeoJson => 'その URL は GeoJSON を返しませんでした。';

  @override
  String get layerRefusalTooLarge => '10 MB を超えています。重ね表示には大きすぎます。';

  @override
  String get mapsSelfTest => 'セルフテスト';

  @override
  String get selfTestIntro =>
      'この端末でオフライン地図を一通り検証します(実際の地図サーバー、保存、ダウンロード、中断と再開、期限切れ削除)。サンドボックスで実行し終了後に削除するため、あなたの地図には影響しません。所要約1分、通信量は1 MB未満です。';

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
  String get selfTestCopy => 'レポートをコピー';

  @override
  String get selfTestCopied => 'レポートをコピーしました';

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
  String get locGroupAutoPublish => '自動送信';

  @override
  String get locGroupBeacon => 'ビーコン';

  @override
  String get locGroupManual => '手動';

  @override
  String get deviceManageChannels => 'チャンネルを管理';

  @override
  String deviceActiveChannelSub(String name) {
    return '有効: $name · スロット · 名前 + PSK · #ハッシュタグ';
  }

  @override
  String deviceNowParams(
      String freq, String bw, String sf, String cr, String tx) {
    return 'デバイスの現在値: ${freq}MHz ${bw}kHz SF$sf CR$cr ${tx}dBm';
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
    return 'リンク MTU: $mtu (1 フレーム全体には $need 必要)';
  }

  @override
  String diagnosticsMtuRefusedLine(String mtu, String need) {
    return 'このリンクは $mtu バイトでネゴシエートしましたが、ラジオの 1 フレームには $need 必要です。再接続して再交渉してください。MTU がそれ以上の値に上がらないラジオでは全フレームを送れません';
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
  String diagnosticsFramingLine(String truncated, String trailing) {
    return '不完全なフレーム: 途中で切れた $truncated 件、余りのバイトがある $trailing 件';
  }

  @override
  String get diagnosticsScanConnect => 'スキャンして接続';

  @override
  String get diagnosticsForgetShort => '解除';

  @override
  String diagnosticsPairedLine(String name) {
    return 'ペアリング済み: $name — 起動時に自動再接続します';
  }

  @override
  String get nodesClearSearch => '検索をクリア';

  @override
  String get networksTitle => 'ネットワーク';

  @override
  String get networksTileSubtitle => '複数の無線機で共有する無線設定';

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
  String get placeCreateAction => '報告';

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
  String get placeSent => '報告しました。期限が来ると自動で消えます。';

  @override
  String placeBudgetRefused(int n, String time) {
    return '直近1時間に $n 件送信しました。次は $time に送れます。';
  }

  @override
  String get placeNoIdentity => '先に無線機に接続してください。場所はあなたとして報告されます。';

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
    return '$name が $time に報告';
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
  String get placeDirections => '経路';

  @override
  String get placeDirectionsCopied => '座標をコピーしました';

  @override
  String get placeHistoryTitle => '場所';

  @override
  String get placeHistoryEmpty => 'まだ場所はありません。地図を長押しして報告できます。';

  @override
  String get placeStateLive => '有効';

  @override
  String get placeStateExpired => '期限切れ';

  @override
  String get placeSearchHint => 'ラベルまたは報告者で検索';

  @override
  String get placeWithinAny => '残り時間の指定なし';

  @override
  String get placeWithinHour => '1時間以内に期限';

  @override
  String get placeWithinDay => '24時間以内に期限';

  @override
  String get placeKeyedOnly => '鍵のある場所のみ';

  @override
  String get placeExportLedger => '台帳を書き出す';

  @override
  String get placeExportShared => '台帳を共有できます。';

  @override
  String placeExportDone(String path) {
    return '台帳を $path に保存しました';
  }

  @override
  String get placeExportFailed => '台帳を書き出せませんでした。';

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
      'ラジオはペアリング後に次の接続で暗号化できず、保存したペアリングを失っています。電源を入れ直してアプリを開き直し、再ペアリングしてください。繰り返す場合はラジオのボンド保存側の問題です。';

  @override
  String get failureServiceMissing =>
      'このデバイスは MeshCore サービスを公開していないため、MeshCore ラジオではない可能性があります。';

  @override
  String get failureCharacteristicMissing =>
      'ラジオのリンクに、アプリが必要とするキャラクタリスティックがありません。ファームウェアがこのアプリの想定より古い可能性があります。';

  @override
  String failureMtuTooSmall(String mtu, String need) {
    return 'このリンクは $mtu バイトでネゴシエートしましたが、ラジオの 1 フレームには $need 必要です。再接続して再交渉してください。リンクをそれ以上に広げられないラジオは全フレームを送れません。';
  }

  @override
  String get failureFrameTruncated =>
      'フレームが途中で切れて届き、デコードできませんでした。リンクがラジオの最長フレームを運べません。件数は診断ページに表示されます。';

  @override
  String get failureFrameTrailingBytes =>
      'フレームの終端より後ろに余分なバイトがありました。推測せずに破棄しました。件数は診断ページに表示されます。';

  @override
  String get failureStorageFull =>
      'ストレージが満杯のため書き込みを拒否しました。無言で削除はしていません。空き容量を確保してください。履歴はそのまま残ります。';

  @override
  String get failureRadioSilent =>
      'ラジオは要求を受け取りましたが、時間内に応答しませんでした。実行済みの可能性があります。再試行の前にラジオを確認してください。';

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
      '位置情報が無効のため、距離・方位・プレイス報告の基準がありません。それ以外は動作します。';

  @override
  String get degradedMapOffline =>
      '地図タイルを取得できません。同梱のベースマップと端末に保存済みの範囲は表示され、他の機能には影響しません。';

  @override
  String get sosTitle => '緊急';

  @override
  String get sosEntryTooltip => '緊急警報とチェックイン';

  @override
  String get sosRepeatsOneHour => '最大1時間、繰り返し送信します。';

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
  String get sosNoIdentity => '無線が名前を返していないため、警報にコールサインを載せられません。';

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
      '無線は約2分後に各パケットを一度だけ再送します。それ以外の繰り返しはアプリと共に止まります。';

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
  String get sosRefusedTooLong => 'コールサインと位置を含めると長すぎます。短くしてください。';

  @override
  String get sosRefusedHold => '長押しが完了していません。';

  @override
  String get checkinTitle => 'チェックイン';

  @override
  String get checkinEntryTooltip => 'チェックイン';

  @override
  String get checkinIntro => '期限付きの1通のみ。期限切れはこのアプリが判断します。無線側にタイマーはありません。';

  @override
  String checkinInMinutes(int minutes) {
    return '期限は $minutes 分後';
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
  String get checkinAnsweredChannel => '応答あり（チャンネル・主張のみで鍵の裏付けなし）。';

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
  String get mediaEncoding => '写真をメッシュ用に調整しています…';

  @override
  String mediaCostLine(int chunks, String airtime) {
    return '$chunks パケット · 送信時間は約 $airtime';
  }

  @override
  String get mediaOverBudget => 'この写真は最低品質でもメッシュの上限に収まりません。送信はできますが途中で切れます。';

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
      'パブリックチャンネルではメディアは無効です。先にそのチャンネルの設定で有効にしてください。';

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
  String get mediaReceiveComplete => '写真を受信しました。';

  @override
  String get mediaDecodeFailed => '写真は届きましたが読み取れません。';

  @override
  String get mediaPhotoSemantics => 'メッシュで受信した写真';

  @override
  String get placePhotoNotFetched => '写真は未取得です。報告自体は完全で、写真は任意であり届かないこともあります。';

  @override
  String get placePhotoMayNotArrive => '写真は届かないことがあります。テキストは届きます。';

  @override
  String get placePhotoFetch => '写真を取得';

  @override
  String get placePhotoFetching => 'メッシュに写真を問い合わせています…';

  @override
  String get geofenceTitle => 'ジオフェンス';

  @override
  String get geofenceExplainer =>
      'フェンスは見張る円です。入ったときと出たときに一度ずつ知らせるので、境界を歩いても通知が連続しません。';

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
  String get geofenceExplainerShort => '到着・出発を知らせる円';

  @override
  String get coverageTitle => 'カバレッジ';

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
  String get blockedKeysTitle => 'ブロックした鍵';

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
  String get reportAction => '報告…';

  @override
  String get reportSheetTitle => 'このメッセージを報告';

  @override
  String get reportObservationLabel => '何を見ましたか？（任意）';

  @override
  String get reportNothingSent =>
      '何も送信していません。アプリはこの端末にファイルを作成しただけです。送り先はあなたが決めます。';

  @override
  String reportBundleWritten(String path) {
    return 'バンドルを書き出しました: $path';
  }

  @override
  String get reportCopyBundle => 'バンドルをコピー';

  @override
  String get reportCopied => 'バンドルをコピーしました。';

  @override
  String get blockedKeysNotPersisted =>
      'この一覧を端末に保存できませんでした。今は機能しますが、再起動後は空になります。';

  @override
  String get reportActionSub => '送信先を選べるよう、端末にファイルを作成します。自動送信はしません。';

  @override
  String nodeMarkerSemantics(String name) {
    return '$name — 詳細はタップ';
  }

  @override
  String placePinSemantics(String label, String expiry) {
    return '$label、$expiry';
  }

  @override
  String placeClusterSemantics(int count) {
    return 'ここに $count 件の場所';
  }

  @override
  String get mapCanvasSemantics => 'マップ上のマーカーをタップすると開きます';
}
