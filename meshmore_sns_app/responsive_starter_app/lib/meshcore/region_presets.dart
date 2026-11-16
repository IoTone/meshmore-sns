// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import '../gen/app_localizations.dart';

/// R39 — LoRa region presets + geofence resolver.
///
/// Provenance (corrected 2026-10-28). The authority is the MeshCore project's
/// own feed, `https://api.meshcore.nz/api/v1/config`
/// (`config.suggested_radio_settings.entries`). An earlier version of this
/// header said the values were mirrored from github.com/zjs81/meshcore-open;
/// that client hard-codes `cr4_5` for nearly every preset and has no
/// `path_hash_size`, which is how four coding rates here came to be wrong.
/// Each preset says where it came from ([PresetSource]); a checked-in
/// snapshot of the feed (`test/meshcore/fixtures/meshcore_api_presets.json`)
/// is compared with this table by `region_presets_test.dart`, so drift is a
/// test failure. TX power is NOT in the feed: it is this app's own default
/// per band. The values are **not** regulatory guarantees — they
/// are the operating points the community has converged on within
/// each country's ISM band. The user remains responsible for
/// confirming legality where they are.
///
/// Why mirror rather than fetch: the app is offline-first
/// (mesh radio first, network second), so the presets are baked
/// into the binary. They evolve maybe once a year; bumping the app
/// is the right cadence.
/// Where a preset's radio numbers come from.
enum PresetSource {
  /// Listed by the MeshCore project's own feed (api.meshcore.nz).
  meshcoreApi,

  /// Not in that feed: a community or regulatory value this app carries.
  thirdParty,
}

class RegionPreset {
  const RegionPreset({
    required this.id,
    required this.label,
    required this.frequencyMhz,
    required this.bandwidthKhz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.txPowerDbm,
    this.note,
    this.source = PresetSource.thirdParty,
    this.pathHashSize,
  });

  /// See [PresetSource].
  final PresetSource source;

  /// Path-hash size in bytes (1..3) the feed lists for this preset, or null
  /// when the feed says nothing. It is the length a node stamps on the
  /// packets it sends, a regional convention rather than something firmware
  /// requires every node to share (`Mesh.cpp:89` reads each packet's own
  /// size). A preset that carries one applies it.
  final int? pathHashSize;

  /// Stable identifier used for shared_preferences persistence.
  /// Snake_case, never translated.
  final String id;

  /// User-visible label. Place names are NOT translated.
  final String label;

  final double frequencyMhz;
  final double bandwidthKhz;
  final int spreadingFactor;

  /// Coding rate denominator: 5 → 4/5, 6 → 4/6, 7 → 4/7, 8 → 4/8.
  final int codingRate;

  /// Recommended TX power in dBm. Firmware caps to the hardware /
  /// regulatory limit regardless.
  final int txPowerDbm;

  /// Optional one-line regulatory hint shown under the preset chip.
  final String? note;
}

const String kCustomPresetId = 'custom';

/// All shipped region presets, in roughly alphabetical-by-region
/// order. Selecting one prefills the radio params; matching
/// firmware values back to a preset uses [matchPresetByRadioParams].
const List<RegionPreset> kRegionPresets = <RegionPreset>[
  // --- North America ---
  RegionPreset(
    id: 'us_canada',
    source: PresetSource.meshcoreApi,
    label: 'USA / Canada',
    frequencyMhz: 910.525,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 22,
    note: 'FCC 902–928 MHz ISM · ≤30 dBm · feed lists path hash 3 for Canada only, so it is not applied',
  ),
  RegionPreset(
    id: 'us_arizona',
    label: 'USA — Arizona',
    frequencyMhz: 908.205,
    bandwidthKhz: 62.5,
    spreadingFactor: 10,
    codingRate: 5,
    txPowerDbm: 20,
    note: 'AZ regional variant',
  ),
  // --- Japan ---
  // ARIB STD-T108 CH37 (923.2 MHz centre) — a valid 200 kHz unit
  // channel; our 125 kHz signal fits inside it. This is also the
  // LoRaWAN AS923-JP / Meshtastic-JP default region, so it aligns
  // with those ecosystems (NOT with the nascent MeshCore-JP
  // community proposal, which is 920.8 MHz / SF12 / CR 4/8 — see
  // MeshCore issues #2079 JP_STRICT and #2218 ARIB-LBT, both still
  // open mid-2026; the earlier #460 was parked without shipping a
  // preset, so MeshCore ships no canonical JP entry).
  //
  // Regulatory basis (license-free 特定小電力, verified 2026-07):
  //  - Power: ≤13 dBm (20 mW) conducted, referenced to a ≤3 dBi
  //    antenna (≈16 dBm EIRP ceiling). Higher gain → cut conducted.
  //  - LBT: carrier sense at −80 dBm; minimum sense 128 µs (the
  //    "5 ms" figure is the long-burst class boundary, not the
  //    floor). Mandated + enforced by the device FIRMWARE, not us.
  //  - Duty: CH33–38 (incl. CH37) cap TX at ≤360 s per rolling
  //    hour (~10%). A chatty mesh must respect this.
  //  - 技適: legal params do NOT make operation legal — the radio
  //    HARDWARE must be 技適-certified. Most grey-import LoRa boards
  //    are not. Surfaced in deviceRegionDisclaimer.
  RegionPreset(
    id: 'jp_arib_t108',
    label: 'Japan (ARIB STD-T108)',
    frequencyMhz: 923.2,
    bandwidthKhz: 125,
    spreadingFactor: 10,
    codingRate: 5,
    txPowerDbm: 13,
    note: '920 MHz CH37 · LBT required · ≤10%/h duty · ≤13 dBm',
  ),
  // MeshCore-JP community convention (proposal-stage, small user
  // base): 920.8 MHz = ARIB CH25, in the CH24–32 group which — in
  // long-sense LBT mode — carries no explicit hourly duty cap (unlike
  // CH33–38). SF12 / CR 4/8 is their deliberate max-range choice. This
  // is the tuple to pick to interoperate with other MeshCore-JP nodes;
  // it will NOT reach the ARIB-T108 default preset above. Same legal
  // basis (≤13 dBm conducted, mandatory firmware LBT, 技適 hardware).
  // Source: MeshCore issues #2079 / #2218 (@jirogit), open mid-2026.
  RegionPreset(
    id: 'jp_meshcore',
    label: 'Japan (MeshCore-JP)',
    frequencyMhz: 920.8,
    bandwidthKhz: 125,
    spreadingFactor: 12,
    codingRate: 8,
    txPowerDbm: 13,
    note: '920.8 MHz CH25 · LBT required · ≤13 dBm · MeshCore-JP',
  ),
  // --- EU / UK ---
  RegionPreset(
    id: 'eu_uk_long',
    source: PresetSource.meshcoreApi,
    label: 'EU / UK (Long Range)',
    frequencyMhz: 869.525,
    bandwidthKhz: 250,
    spreadingFactor: 11,
    codingRate: 5,
    txPowerDbm: 14,
    note: 'ERC 869.4–869.65 · ≤27 dBm · the feed marks this one Deprecated',
  ),
  RegionPreset(
    id: 'eu_uk_medium',
    label: 'EU / UK (Medium Range)',
    frequencyMhz: 869.525,
    bandwidthKhz: 250,
    spreadingFactor: 10,
    codingRate: 5,
    txPowerDbm: 14,
  ),
  RegionPreset(
    id: 'eu_uk_narrow',
    source: PresetSource.meshcoreApi,
    label: 'EU / UK (Narrow)',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 8,
    txPowerDbm: 14,
  ),
  RegionPreset(
    id: 'ch',
    source: PresetSource.meshcoreApi,
    label: 'Switzerland',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 8,
    note: 'SR 869.618 MHz · CR4-8 in the community preset',
    txPowerDbm: 14,
  ),
  RegionPreset(
    id: 'cz',
    source: PresetSource.meshcoreApi,
    pathHashSize: 2,
    label: 'Czech Republic',
    frequencyMhz: 869.432,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 14,
  ),
  RegionPreset(
    id: 'pt_869',
    source: PresetSource.meshcoreApi,
    label: 'Portugal (869 MHz)',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 6,
    txPowerDbm: 14,
  ),
  // --- Australia / NZ ---
  RegionPreset(
    id: 'au_default',
    source: PresetSource.meshcoreApi,
    label: 'Australia',
    frequencyMhz: 915.8,
    bandwidthKhz: 250,
    spreadingFactor: 10,
    codingRate: 5,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'au_narrow',
    source: PresetSource.meshcoreApi,
    label: 'Australia (Narrow)',
    frequencyMhz: 916.575,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 7,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'au_sa_wa_qld',
    source: PresetSource.meshcoreApi,
    label: 'Australia (SA / WA / QLD)',
    frequencyMhz: 923.125,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 5,
    note: 'This is the QLD tuple (CR4-5); SA and WA use CR4-8, see the next entry',
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'nz_default',
    source: PresetSource.meshcoreApi,
    pathHashSize: 1,
    label: 'New Zealand',
    frequencyMhz: 917.375,
    bandwidthKhz: 250,
    spreadingFactor: 11,
    codingRate: 5,
    txPowerDbm: 20,
  ),
  // --- SE Asia ---
  RegionPreset(
    id: 'vn',
    source: PresetSource.meshcoreApi,
    label: 'Vietnam',
    frequencyMhz: 920.250,
    bandwidthKhz: 250,
    spreadingFactor: 11,
    codingRate: 5,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'us_socal',
    source: PresetSource.meshcoreApi,
    label: 'USA — Southern California',
    frequencyMhz: 927.875,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 22,
    pathHashSize: 3,
  ),
  RegionPreset(
    id: 'au_mid',
    source: PresetSource.meshcoreApi,
    label: 'Australia (Mid)',
    frequencyMhz: 915.075,
    bandwidthKhz: 125,
    spreadingFactor: 9,
    codingRate: 5,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'au_sa_wa',
    source: PresetSource.meshcoreApi,
    label: 'Australia (SA / WA)',
    frequencyMhz: 923.125,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 8,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'br',
    source: PresetSource.meshcoreApi,
    label: 'Brazil',
    frequencyMhz: 923.125,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 8,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'cr',
    source: PresetSource.meshcoreApi,
    label: 'Costa Rica',
    frequencyMhz: 910.525,
    bandwidthKhz: 125,
    spreadingFactor: 11,
    codingRate: 5,
    txPowerDbm: 20,
  ),
  RegionPreset(
    id: 'eu433_long',
    source: PresetSource.meshcoreApi,
    label: 'EU 433 MHz (Long Range)',
    frequencyMhz: 433.65,
    bandwidthKhz: 250,
    spreadingFactor: 11,
    codingRate: 5,
    txPowerDbm: 10,
  ),
  RegionPreset(
    id: 'eu433_narrow',
    source: PresetSource.meshcoreApi,
    label: 'EU 433 MHz (Narrow)',
    frequencyMhz: 433.65,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 8,
    txPowerDbm: 10,
  ),
  RegionPreset(
    id: 'hu',
    source: PresetSource.meshcoreApi,
    label: 'Hungary',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 14,
    pathHashSize: 2,
  ),
  RegionPreset(
    id: 'nl',
    source: PresetSource.meshcoreApi,
    label: 'Netherlands',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 14,
  ),
  RegionPreset(
    id: 'nl_limburg',
    source: PresetSource.meshcoreApi,
    label: 'Netherlands (Limburg)',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 8,
    txPowerDbm: 14,
    pathHashSize: 2,
  ),
  RegionPreset(
    id: 'nz_narrow',
    source: PresetSource.meshcoreApi,
    label: 'New Zealand (Narrow)',
    frequencyMhz: 917.375,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 20,
    pathHashSize: 2,
  ),
  RegionPreset(
    id: 'pt_433',
    source: PresetSource.meshcoreApi,
    label: 'Portugal (433 MHz)',
    frequencyMhz: 433.375,
    bandwidthKhz: 62.5,
    spreadingFactor: 9,
    codingRate: 6,
    txPowerDbm: 10,
  ),
  RegionPreset(
    id: 'sk',
    source: PresetSource.meshcoreApi,
    label: 'Slovakia',
    frequencyMhz: 869.618,
    bandwidthKhz: 62.5,
    spreadingFactor: 7,
    codingRate: 5,
    txPowerDbm: 14,
    pathHashSize: 2,
  ),
  RegionPreset(
    id: 'vn_narrow',
    source: PresetSource.meshcoreApi,
    label: 'Vietnam (Narrow)',
    frequencyMhz: 920.25,
    bandwidthKhz: 62.5,
    spreadingFactor: 8,
    codingRate: 5,
    txPowerDbm: 20,
  ),
];

/// R68 — the family a preset is grouped under on Device configuration, so
/// the presets read as three short labelled lists rather than one wall
/// of chips. A preset with no entry falls under [RegionFamily.other] (shown
/// last, and only when non-empty), so adding a preset never hides it.
enum RegionFamily { americas, europe, asiaPacific, other }

const Map<String, RegionFamily> _kFamilyById = <String, RegionFamily>{
  'us_canada': RegionFamily.americas,
  'us_arizona': RegionFamily.americas,
  'eu_uk_long': RegionFamily.europe,
  'eu_uk_medium': RegionFamily.europe,
  'eu_uk_narrow': RegionFamily.europe,
  'ch': RegionFamily.europe,
  'cz': RegionFamily.europe,
  'pt_869': RegionFamily.europe,
  'jp_arib_t108': RegionFamily.asiaPacific,
  'jp_meshcore': RegionFamily.asiaPacific,
  'au_default': RegionFamily.asiaPacific,
  'au_narrow': RegionFamily.asiaPacific,
  'au_sa_wa_qld': RegionFamily.asiaPacific,
  'nz_default': RegionFamily.asiaPacific,
  'vn': RegionFamily.asiaPacific,
  'us_socal': RegionFamily.americas,
  'br': RegionFamily.americas,
  'cr': RegionFamily.americas,
  'eu433_long': RegionFamily.europe,
  'eu433_narrow': RegionFamily.europe,
  'hu': RegionFamily.europe,
  'nl': RegionFamily.europe,
  'nl_limburg': RegionFamily.europe,
  'pt_433': RegionFamily.europe,
  'sk': RegionFamily.europe,
  'au_mid': RegionFamily.asiaPacific,
  'au_sa_wa': RegionFamily.asiaPacific,
  'nz_narrow': RegionFamily.asiaPacific,
  'vn_narrow': RegionFamily.asiaPacific,
};

RegionFamily regionFamilyOf(String presetId) =>
    _kFamilyById[presetId] ?? RegionFamily.other;

/// Returns the preset whose four LoRa params match the live device
/// values. Bandwidth uses a 0.5 kHz tolerance and frequency uses a
/// 1 kHz tolerance to absorb float rounding from the wire format
/// (uint32 ÷ 1000). Returns null if no match → caller should treat
/// the current config as "Custom".
RegionPreset? matchPresetByRadioParams({
  required double frequencyMhz,
  required double bandwidthKhz,
  required int spreadingFactor,
  required int codingRate,
}) {
  for (final RegionPreset p in kRegionPresets) {
    if ((p.frequencyMhz - frequencyMhz).abs() > 0.001) continue;
    if ((p.bandwidthKhz - bandwidthKhz).abs() > 0.5) continue;
    if (p.spreadingFactor != spreadingFactor) continue;
    if (p.codingRate != codingRate) continue;
    return p;
  }
  return null;
}

/// Translate a preset id to a locale-appropriate label. Place names
/// don't strictly translate, but the Japanese locale (for example)
/// expects 米国/カナダ rather than "USA / Canada" in the chip text.
/// Falls back to the English [RegionPreset.label] when l10n has no
/// key for the id.
String localizedPresetLabel(AppLocalizations l, String presetId) {
  switch (presetId) {
    case 'us_canada':
      return l.presetUsCanada;
    case 'us_arizona':
      return l.presetUsArizona;
    case 'jp_arib_t108':
      return l.presetJpAribT108;
    case 'jp_meshcore':
      return l.presetJpMeshcore;
    case 'eu_uk_long':
      return l.presetEuUkLong;
    case 'eu_uk_medium':
      return l.presetEuUkMedium;
    case 'eu_uk_narrow':
      return l.presetEuUkNarrow;
    case 'ch':
      return l.presetCh;
    case 'cz':
      return l.presetCz;
    case 'pt_869':
      return l.presetPt869;
    case 'au_default':
      return l.presetAu;
    case 'au_narrow':
      return l.presetAuNarrow;
    case 'au_sa_wa_qld':
      return l.presetAuSaWaQld;
    case 'nz_default':
      return l.presetNz;
    case 'vn':
      return l.presetVn;
  }
  // Unknown id: return the English label so a freshly-added
  // preset doesn't render as empty.
  return presetById(presetId)?.label ?? presetId;
}

/// Lookup by id, or null if [id] is `'custom'` / unknown.
RegionPreset? presetById(String id) {
  for (final RegionPreset p in kRegionPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// Coarse country bounding box → preset id resolver, used by the
/// first-run wizard / "Suggest from my location" path. Boxes
/// deliberately overlap (e.g. Mexico inside the North America 902-928
/// ISM region uses the same `us_canada` preset, which is correct);
/// when multiple match, the **first** match in this table wins, so
/// narrower country-specific entries are listed before broader ones.
///
/// This is geofencing, not legal advice: a fix near a national
/// border may pick the neighbouring country's preset, so the UI
/// always shows the suggested label + asks the user to confirm.
List<({double latMin, double latMax, double lonMin, double lonMax,
       String presetId})> _kCountryBoxes() => const <
    ({
      double latMin,
      double latMax,
      double lonMin,
      double lonMax,
      String presetId
    })>[
  // Narrow regional preset BEFORE the broader US box.
  (
    latMin: 31.0,
    latMax: 37.0,
    lonMin: -115.0,
    lonMax: -109.0,
    presetId: 'us_arizona',
  ),
  // Continental USA + AK + HI (broad).
  (
    latMin: 18.0,
    latMax: 72.0,
    lonMin: -180.0,
    lonMax: -65.0,
    presetId: 'us_canada',
  ),
  // Canada — same 902-928 ISM band as the US.
  (
    latMin: 41.0,
    latMax: 84.0,
    lonMin: -141.0,
    lonMax: -52.0,
    presetId: 'us_canada',
  ),
  // Japan archipelago (Hokkaido down to Yaeyama; includes Okinawa).
  (
    latMin: 24.0,
    latMax: 46.0,
    lonMin: 122.0,
    lonMax: 146.0,
    presetId: 'jp_arib_t108',
  ),
  // Vietnam.
  (
    latMin: 8.0,
    latMax: 24.0,
    lonMin: 102.0,
    lonMax: 110.0,
    presetId: 'vn',
  ),
  // Australia — broad box; users west of ~129°E should pick the
  // SA/WA/QLD preset manually, but the default-narrow is also
  // legal.
  (
    latMin: -44.0,
    latMax: -10.0,
    lonMin: 112.0,
    lonMax: 154.0,
    presetId: 'au_default',
  ),
  // New Zealand main + Stewart.
  (
    latMin: -47.5,
    latMax: -34.0,
    lonMin: 165.0,
    lonMax: 179.5,
    presetId: 'nz_default',
  ),
  // EU country-specific overrides (BEFORE the broad EU box).
  (
    latMin: 36.9,
    latMax: 42.2,
    lonMin: -9.6,
    lonMax: -6.1,
    presetId: 'pt_869',
  ),
  (
    latMin: 45.8,
    latMax: 47.9,
    lonMin: 5.9,
    lonMax: 10.6,
    presetId: 'ch',
  ),
  (
    latMin: 48.5,
    latMax: 51.1,
    lonMin: 12.0,
    lonMax: 18.9,
    presetId: 'cz',
  ),
  // Broad EU / UK / EEA — 869 MHz long-range default.
  (
    latMin: 34.0,
    latMax: 71.5,
    lonMin: -11.0,
    lonMax: 32.0,
    presetId: 'eu_uk_long',
  ),
];

/// Geofence-based preset suggestion. Returns null when [lat]/[lon]
/// fall outside every shipped country box (e.g. ocean, polar, or a
/// country we don't yet have a preset for). Caller should fall
/// through to manual picker in that case.
RegionPreset? suggestPresetForLatLon(double lat, double lon) {
  for (final box in _kCountryBoxes()) {
    if (lat < box.latMin || lat > box.latMax) continue;
    if (lon < box.lonMin || lon > box.lonMax) continue;
    return presetById(box.presetId);
  }
  return null;
}
