// AiRspace UI — EN / JA.
//
// Japan is a launch market for the target hardware, so Japanese is a first-class
// requirement, not a later localization pass.
//
// THE LOAD-BEARING FINDING: CJK NEEDS A LARGER ANGULAR FLOOR THAN LATIN.
// The 1.2 deg text floor is derived from Latin letterforms, which carry ~2–4
// strokes per glyph. A kanji like 態 carries 14 strokes in the same em box, so
// at 1.2 deg it is a grey smudge — legible as "there is text here" and nothing
// more. Every stroke has to survive the display's pixel grid AND the eye's
// acuity limit, so the floor scales with stroke density, not with glyph count.
//
//   Latin  >= 1.2 deg     Kana  >= 1.5 deg     Kanji >= 1.8 deg
//
// The DENSEST GLYPH IN THE STRING sets the floor, because mixed kana+kanji is
// the norm in Japanese and one unreadable kanji ruins the line. So a pure
// katakana label like ティア1 sits at 1.5, while 無線機 is promoted to 1.8.
//
// Second consequence: monospace CJK is DOUBLE WIDTH. A label box sized for
// "SETTINGS" will not hold 設定 at the same advance count. Layout must measure,
// never assume.

export const LOCALES = ['en', 'ja'];

// Catalogs are flat key -> string, one object per locale, exactly like the
// meshmore-sns JSON catalogs so the two apps can share a translation pipeline.
// Fallback chain: locale -> en -> the raw key (never blank; the key itself is a
// useful debugging indicator on a device you are wearing).
const CAT = {
  en: {
    'hud.tier1': 'TIER 1 · MESH',
    'hud.tier2': 'TIER 2 · UPLINK',
    'hud.tier0': 'TIER 0 · DARK',
    'hud.peers': 'PEERS',
    'hud.channel': 'CH0 PUBLIC',
    'hud.queue': 'QUEUE',
    'hud.batt': 'BATT',
    'hud.link': 'LINK',
    'hud.n': 'N', 'hud.e': 'E', 'hud.s': 'S', 'hud.w': 'W',
    'node.bearingUnknown': 'BEARING UNKNOWN',
    'range.100m': '100 m', 'range.1km': '1 km', 'range.10km': '10 km',
    'station.identity': 'IDENTITY',
    'station.radio': 'RADIO',
    'station.voice': 'VOICE',
    'station.theme': 'THEME',
    'station.access': 'ACCESS',
    'station.uplink': 'UPLINK',
    'station.safety': 'SAFETY',
    'w.advertLoc': 'ADVERT LOC',
    'w.rename': 'RENAME',
    'w.txPower': 'TX POWER',
    'w.sf': 'SF',
    'w.tts': 'TTS',
    'w.pttOnly': 'PTT ONLY',
    'w.rate': 'RATE',
    'w.reduceMotion': 'REDUCE MOTION',
    'w.seated': 'SEATED 120°',
    'w.textScale': 'TEXT SCALE',
    'w.grabRegion': 'GRAB REGION',
    'w.autoSync': 'AUTO SYNC',
    'w.halt': 'HALT — PUSH',
    'w.theme': 'THEME',
    'vectrex.foot': 'LOW POWER — FLAT VECTOR OVERLAY (VECTREX MODE)',
    'msg.onMyWay': 'on my way',
  },
  ja: {
    'hud.tier1': 'ティア1・メッシュ',
    'hud.tier2': 'ティア2・アップリンク',
    'hud.tier0': 'ティア0・停波',
    'hud.peers': 'ピア',
    'hud.channel': 'CH0 パブリック',
    'hud.queue': '送信待ち',
    'hud.batt': '電池',
    'hud.link': '接続',
    'hud.n': '北', 'hud.e': '東', 'hud.s': '南', 'hud.w': '西',
    'node.bearingUnknown': '方位不明',
    'range.100m': '100 m', 'range.1km': '1 km', 'range.10km': '10 km',
    'station.identity': '識別情報',
    'station.radio': '無線機',
    'station.voice': '音声',
    'station.theme': 'テーマ',
    'station.access': 'アクセシビリティ',
    'station.uplink': 'アップリンク',
    'station.safety': '安全',
    'w.advertLoc': '位置の公開',
    'w.rename': '名前を変更',
    'w.txPower': '送信出力',
    'w.sf': 'SF',
    'w.tts': '読み上げ',
    'w.pttOnly': 'PTTのみ',
    'w.rate': '速度',
    'w.reduceMotion': 'モーション低減',
    'w.seated': '着席 120°',
    'w.textScale': '文字サイズ',
    'w.grabRegion': '地図を取得',
    'w.autoSync': '自動同期',
    'w.halt': '停止 — 押す',
    'w.theme': 'テーマ',
    'vectrex.foot': '低電力 — 平面ベクター表示（VECTREXモード）',
    'msg.onMyWay': '向かっています',
  },
};

let current = 'en';
export const getLocale = () => current;
export const setLocale = (l) => { current = LOCALES.includes(l) ? l : 'en'; };

export function t(key) {
  return CAT[current]?.[key] ?? CAT.en[key] ?? key;
}

const CJK = /[　-〿぀-ゟ゠-ヿ㐀-䶿一-鿿＀-￯]/;
const KANJI = /[㐀-䶿一-鿿]/;

export const hasCJK = (s) => CJK.test(s);

// The angular floor for a specific string. Callers pass their intended size and
// get back the size they are actually allowed to use.
export function minDegFor(text, base = 1.2) {
  if (KANJI.test(text)) return Math.max(base, 1.8);
  if (CJK.test(text)) return Math.max(base, 1.5);
  return base;
}

// One family covers mono + full Japanese, which is exactly why the SNS brief
// picked it: it serves the console layer, JA localization, and the
// kanji-as-graphic motif without a second license to clear.
export const FONT_STACK =
  '"M PLUS 1 Code", ui-monospace, "SF Mono", Menlo, "Hiragino Sans", "Noto Sans CJK JP", monospace';

export async function loadFonts() {
  if (!document.fonts) return;
  try {
    // Canvas text silently falls back if the face is not resolved yet, which
    // renders Japanese as tofu on the first frame and never repaints.
    await Promise.all([
      document.fonts.load('400 44px "M PLUS 1 Code"'),
      document.fonts.load('400 44px "M PLUS 1 Code"', '設定'),
    ]);
    await document.fonts.ready;
  } catch { /* fall back to the stack */ }
}

// Kinsoku shori, the minimum viable subset: Japanese does not use spaces, so a
// naive break can leave a line starting with a closing bracket or a small kana.
const NO_START = '、。，．）」』】〉》”’ヽヾーぁぃぅぇぉっゃゅょゎヵヶ！？';
const NO_END = '（「『【〈《“‘';

export function wrapJa(text, perLine) {
  if (!hasCJK(text)) return text.split(/\s+/).reduce((acc, w) => {
    const last = acc[acc.length - 1];
    if (last && (last + ' ' + w).length <= perLine) acc[acc.length - 1] = last + ' ' + w;
    else acc.push(w);
    return acc;
  }, []);
  const out = [];
  let line = '';
  for (const ch of text) {
    if (line.length >= perLine && !NO_START.includes(ch) && !NO_END.includes(line[line.length - 1])) {
      out.push(line); line = '';
    }
    line += ch;
  }
  if (line) out.push(line);
  return out;
}
