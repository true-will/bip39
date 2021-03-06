import 'dart:math';
import 'dart:typed_data';
// import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/digests/sha256.dart';
import 'package:hex/hex.dart';
import 'utils/pbkdf2.dart';
import 'wordlists/english.dart';

const int _SIZE_BYTE = 255;
const _INVALID_MNEMONIC = 'Invalid mnemonic';
const _INVALID_ENTROPY = 'Invalid entropy';
const _INVALID_CHECKSUM = 'Invalid mnemonic checksum';

typedef Uint8List RandomBytes(int size);

int _binaryToByte(String binary) {
  return int.parse(binary, radix: 2);
}

String _bytesToBinary(Uint8List bytes) {
  return bytes.map((byte) => byte.toRadixString(2).padLeft(8, '0')).join('');
}

//Uint8List _createUint8ListFromString( String s ) {
//  var ret = new Uint8List(s.length);
//  for( var i=0 ; i<s.length ; i++ ) {
//    ret[i] = s.codeUnitAt(i);
//  }
//  return ret;
//}
/*
ENT bits are generated from entropy bytes. 
A checksum is generated by taking the 
first (ENT / 32) bits of its SHA256 hash. 
*/
String _deriveChecksumBits(Uint8List entropy) {
  final ENT = entropy.length * 8;
  final CS = ENT ~/ 32;
  //******commented by archer947******
  // final hash = sha256.newInstance().convert(entropy);
  // return _bytesToBinary(Uint8List.fromList(hash.bytes)).substring(0, CS);
  //**********************************
  // sha256 digest using pointy castle
  final d = new SHA256Digest();
  return _bytesToBinary(d.process(entropy)).substring(0, CS);
}

// secure random bytes generator
Uint8List _randomBytes(int size) {
  final rng = Random.secure();
  final bytes = Uint8List(size);
  for (var i = 0; i < size; i++) {
    bytes[i] = rng.nextInt(_SIZE_BYTE);
  }
  return bytes;
}

/*
The mnemonic must encode entropy in a multiple of 32 bits. 
With more entropy security is improved but the sentence length increases. 
The allowed size of entropy is 128-256 bits.
*/
String generateMnemonic(
    {int strength = 128, RandomBytes randomBytes = _randomBytes}) {
  // check entropy is multiple of 32 bits
  assert(strength % 32 == 0);
  // calculate size of entropy in bytes
  int size = strength ~/ 8;
  // get list of random bytes of entropy size
  final entropy = randomBytes(size);
  // convert entropy to mnemonic
  return entropyToMnemonic(HEX.encode(entropy));
}

/*
This convert entropy to mnemonic.
@params : hex encoded entropy
*/
String entropyToMnemonic(String entropyString) {
  // decode hex string to get List of Bytes
  final entropy = HEX.decode(entropyString);

  // 128 <= ENT <= 256
  if (entropy.length < 16) {
    throw ArgumentError(_INVALID_ENTROPY);
  }
  if (entropy.length > 32) {
    throw ArgumentError(_INVALID_ENTROPY);
  }
  if (entropy.length % 4 != 0) {
    throw ArgumentError(_INVALID_ENTROPY);
  }
  // convert list into bits
  final entropyBits = _bytesToBinary(entropy);
  // calculate checksum bits
  final checksumBits = _deriveChecksumBits(entropy);
  // checksum is appended to the end of the initial entropy
  final bits = entropyBits + checksumBits;
  // these concatenated bits are split into groups of 11 bits,
  // each encoding a number from 0-2047,
  //  serving as an index into a wordlist.
  final regex = new RegExp(r".{1,11}", caseSensitive: false, multiLine: false);
  final chunks = regex
      .allMatches(bits)
      .map((match) => match.group(0))
      .toList(growable: false);
  List<String> wordlist = WORDLIST;
  // convert these numbers into words and
  // use the joined words as a mnemonic sentence.
  String words =
      chunks.map((binary) => wordlist[_binaryToByte(binary)]).join(' ');
  return words;
}

Uint8List mnemonicToSeed(String mnemonic, {String password = ''}) {
  final pbkdf2 = new PBKDF2(password: password);
  return pbkdf2.process(mnemonic);
}

String mnemonicToSeedHex(String mnemonic, {String password = ''}) {
  return mnemonicToSeed(mnemonic, password: password).map((byte) {
    return byte.toRadixString(16).padLeft(2, '0');
  }).join('');
}

bool validateMnemonic(String mnemonic) {
  try {
    mnemonicToEntropy(mnemonic);
  } catch (e) {
    return false;
  }
  return true;
}

String mnemonicToEntropy(mnemonic) {
  var words = mnemonic.split(' ');
  if (words.length % 3 != 0) {
    throw new ArgumentError(_INVALID_MNEMONIC);
  }
  final wordlist = WORDLIST;
  // convert word indices to 11 bit binary strings
  final bits = words.map((word) {
    final index = wordlist.indexOf(word);
    if (index == -1) {
      throw new ArgumentError(_INVALID_MNEMONIC);
    }
    return index.toRadixString(2).padLeft(11, '0');
  }).join('');
  // split the binary string into ENT/CS
  final dividerIndex = (bits.length / 33).floor() * 32;
  final entropyBits = bits.substring(0, dividerIndex);
  final checksumBits = bits.substring(dividerIndex);

  // calculate the checksum and compare
  final regex = RegExp(r".{1,8}");
  final entropyBytes = Uint8List.fromList(regex
      .allMatches(entropyBits)
      .map((match) => _binaryToByte(match.group(0)))
      .toList(growable: false));
  if (entropyBytes.length < 16) {
    throw StateError(_INVALID_ENTROPY);
  }
  if (entropyBytes.length > 32) {
    throw StateError(_INVALID_ENTROPY);
  }
  if (entropyBytes.length % 4 != 0) {
    throw StateError(_INVALID_ENTROPY);
  }
  final newChecksum = _deriveChecksumBits(entropyBytes);
  if (newChecksum != checksumBits) {
    throw StateError(_INVALID_CHECKSUM);
  }
  return entropyBytes.map((byte) {
    return byte.toRadixString(16).padLeft(2, '0');
  }).join('');
}
