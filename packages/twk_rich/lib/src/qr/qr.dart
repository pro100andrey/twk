/// QR codes: text a phone's camera reads off the terminal, such as the URL
/// of a sign-in or of a page, the configuration of a Wi-Fi network.
///
/// [QrSymbol] encodes text as ISO/IEC 18004 says, in the numeric,
/// alphanumeric or byte mode, at one of the four levels of error
/// correction ([QrErrorCorrection]), in the smallest of the 40 versions it
/// fits in, under the mask the standard's penalty rules choose. [QrCode]
/// draws it in half blocks, dark on light, with its quiet zone.
library;

import 'qr_code.dart';
import 'symbol.dart';

export 'qr_code.dart';
export 'symbol.dart' show QrErrorCorrection, QrMode, QrSymbol;
