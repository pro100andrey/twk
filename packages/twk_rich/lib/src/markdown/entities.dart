/// Character references: [decodeEntity].
library;

/// The text the character reference [entity] stands for, `&` and `;`
/// included in it; null for a name this table does not know.
///
/// Numeric references are decoded whole, a code point that is not a
/// character becoming U+FFFD. Of the named ones this knows those of HTML 4
/// and `&apos;`.
String? decodeEntity(String entity) {
  final name = entity.substring(1, entity.length - 1);
  if (name.startsWith('#')) {
    final hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
    final code = int.parse(name.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
    final valid =
        code > 0 && code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF);
    return String.fromCharCode(valid ? code : 0xFFFD);
  }
  final code = _named[name];
  return code == null ? null : String.fromCharCode(code);
}

final Map<String, int> _named = () {
  final latin1 = _latin1.split(' ');
  final others = _others.split(' ');
  return {
    for (var k = 0; k < latin1.length; k++) latin1[k]: 0xA0 + k,
    for (var k = 0; k < others.length; k += 2)
      others[k]: int.parse(others[k + 1], radix: 16),
  };
}();

/// The names of U+00A0 to U+00FF, in order.
const _latin1 =
    'nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not '
    'shy reg macr deg plusmn sup2 sup3 acute micro para middot cedil sup1 '
    'ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde Auml '
    'Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml '
    'ETH Ntilde Ograve Oacute Ocirc Otilde Ouml times Oslash Ugrave Uacute '
    'Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde auml aring '
    'aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth '
    'ntilde ograve oacute ocirc otilde ouml divide oslash ugrave uacute '
    'ucirc uuml yacute thorn yuml';

/// The other names, each followed by its code point in hex.
const _others =
    'quot 22 amp 26 apos 27 lt 3C gt 3E OElig 152 oelig 153 Scaron 160 '
    'scaron 161 Yuml 178 fnof 192 circ 2C6 tilde 2DC Alpha 391 Beta 392 '
    'Gamma 393 Delta 394 Epsilon 395 Zeta 396 Eta 397 Theta 398 Iota 399 '
    'Kappa 39A Lambda 39B Mu 39C Nu 39D Xi 39E Omicron 39F Pi 3A0 Rho 3A1 '
    'Sigma 3A3 Tau 3A4 Upsilon 3A5 Phi 3A6 Chi 3A7 Psi 3A8 Omega 3A9 '
    'alpha 3B1 beta 3B2 gamma 3B3 delta 3B4 epsilon 3B5 zeta 3B6 eta 3B7 '
    'theta 3B8 iota 3B9 kappa 3BA lambda 3BB mu 3BC nu 3BD xi 3BE '
    'omicron 3BF pi 3C0 rho 3C1 sigmaf 3C2 sigma 3C3 tau 3C4 upsilon 3C5 '
    'phi 3C6 chi 3C7 psi 3C8 omega 3C9 thetasym 3D1 upsih 3D2 piv 3D6 '
    'ensp 2002 emsp 2003 thinsp 2009 zwnj 200C zwj 200D lrm 200E rlm 200F '
    'ndash 2013 mdash 2014 lsquo 2018 rsquo 2019 sbquo 201A ldquo 201C '
    'rdquo 201D bdquo 201E dagger 2020 Dagger 2021 bull 2022 hellip 2026 '
    'permil 2030 prime 2032 Prime 2033 lsaquo 2039 rsaquo 203A oline 203E '
    'frasl 2044 euro 20AC image 2111 weierp 2118 real 211C trade 2122 '
    'alefsym 2135 larr 2190 uarr 2191 rarr 2192 darr 2193 harr 2194 '
    'crarr 21B5 lArr 21D0 uArr 21D1 rArr 21D2 dArr 21D3 hArr 21D4 '
    'forall 2200 part 2202 exist 2203 empty 2205 nabla 2207 isin 2208 '
    'notin 2209 ni 220B prod 220F sum 2211 minus 2212 lowast 2217 '
    'radic 221A prop 221D infin 221E ang 2220 and 2227 or 2228 cap 2229 '
    'cup 222A int 222B there4 2234 sim 223C cong 2245 asymp 2248 ne 2260 '
    'equiv 2261 le 2264 ge 2265 sub 2282 sup 2283 nsub 2284 sube 2286 '
    'supe 2287 oplus 2295 otimes 2297 perp 22A5 sdot 22C5 lceil 2308 '
    'rceil 2309 lfloor 230A rfloor 230B lang 27E8 rang 27E9 loz 25CA '
    'spades 2660 clubs 2663 hearts 2665 diams 2666';
