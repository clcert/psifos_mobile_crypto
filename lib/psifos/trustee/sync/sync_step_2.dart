import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/ecc/api.dart' as ecc_api;
import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:psifos_mobile_crypto/crypto/ecc/ec_dsa/export.dart';
import 'package:psifos_mobile_crypto/crypto/ecc/ec_keypair/export.dart';
import 'package:psifos_mobile_crypto/crypto/ecc/ec_tdkg/export.dart';
import 'package:psifos_mobile_crypto/crypto/modp/rsa/export.dart';
import 'package:psifos_mobile_crypto/crypto/utils/export.dart';

class TrusteeSyncStep2 {
  /* Parses step 2 input into usable classes */
  static Map<String, dynamic> parseInput(
      Map<String, dynamic> keyPairs,
      Map<String, dynamic> certificates,
      Map<String, dynamic> input,
      String curveName) {
    final domainParams = ecc_api.ECDomainParameters(curveName);

    /* parse private keys from keypair */
    final encryptionPrivateKey =
        RSAPrivateKey.fromJson(keyPairs['encryption']['private_key']);
    final signaturePrivateKey = ECPrivateKey.fromJson(
        keyPairs['signature']['private_key'], domainParams);

    /* parse signature keys from certificates*/
    List<ECPublicKey> signaturePublicKeys = [];
    for (final certJson in certificates["certificates"]) {
      /* No need to verify certificate signature, already done in step 1 */
      signaturePublicKeys.add(
          ECPublicKey.fromJson(certJson["signature_public_key"], domainParams));
    }

    /* parse the signed encrypted shares */
    final signedEncryptedShares = input['signed_encrypted_shares'];

    /* parse the signed coefficients */
    final signedCoefficients = input['signed_coefficients'];

    return {
      'encryption_private_key': encryptionPrivateKey,
      'signature_private_key': signaturePrivateKey,
      'signature_public_keys': signaturePublicKeys,
      'signed_encrypted_shares': signedEncryptedShares,
      'signed_coefficients': signedCoefficients,
    };
  }

  static Map<String, dynamic> handle(
      RSAPrivateKey encryptionPrivateKey,
      ECPrivateKey signaturePrivateKey,
      List<ECPublicKey> signaturePublicKeys,
      List<dynamic> signedEncryptedShares,
      List<dynamic> signedCoefficients,
      String curveName,
      int threshold,
      int numParticipants,
      int participantId) {
    /* make sure data is received from the correct number of participants */
    assert(signaturePublicKeys.length == numParticipants);
    assert(signedEncryptedShares.length == numParticipants);
    assert(signedCoefficients.length == numParticipants);

    /* curve parameters */
    final domainParams = ecc_api.ECDomainParameters(curveName);
    final basePoint = domainParams.G as fp.ECPoint;
    final curveOrder = domainParams.n;

    List<Map<String, dynamic>> acknowledgements = [];
    List<String> validShares = [];
    for (int j = 1; j <= numParticipants; j++) {
      final participantSignatureKey = signaturePublicKeys[j - 1];
      final participantSignedEncryptedShare = signedEncryptedShares[j - 1];
      final participantSignedCoefficients = signedCoefficients[j - 1];

      /* verify the encrypted share signature */
      BigInt encryptedShare =
          BigInt.parse(participantSignedEncryptedShare['encrypted_share']);
      ECSignature shareSignature =
          ECSignature.fromJson(participantSignedEncryptedShare['signature']);
      final encryptedShareBytes = Convert.fromBigIntToUint8List(encryptedShare);

      final verified = ECDSA.verify(
          participantSignatureKey, encryptedShareBytes, shareSignature);
      if (!verified) {
        throw Exception('Share signature could not be verified.');
      }

      /* decrypt the share */
      final decryptedShareBytes =
          RSA.decrypt(encryptionPrivateKey, encryptedShareBytes);
      BigInt decryptedShare =
          Convert.fromUint8ListToBigInt(decryptedShareBytes);

      /* verify the coefficients signatures */
      List<ecc_api.ECPoint> coefficients = [];
      for (Map<String, dynamic> signedCoefficient
          in participantSignedCoefficients) {
        /* get coefficient and signature */
        BigInt x = BigInt.parse(signedCoefficient['coefficient']['x']);
        BigInt y = BigInt.parse(signedCoefficient['coefficient']['y']);

        ecc_api.ECPoint coefficient = domainParams.curve.createPoint(x, y);
        ECSignature signature =
            ECSignature.fromJson(signedCoefficient['signature']);

        /* coefficient as bytes */
        String coefficientStr = coefficient.toString();
        final coefficientBytes =
            Uint8List.fromList(utf8.encode(coefficientStr));
        final verified =
            ECDSA.verify(participantSignatureKey, coefficientBytes, signature);
        if (!verified) {
          throw Exception('Coefficient signature could not be verified.');
        }
        coefficients.add(coefficient);
      }

      /* validate the share */
      ECSignature ack;
      final valid = ECTDKG.validateShare(
          BigInt.from(j), decryptedShare, coefficients, basePoint, curveOrder);
      if (valid) {
        String shareStr = decryptedShare.toString();
        validShares.add(shareStr);
        ack = ECDSA.sign(signaturePrivateKey,
            Uint8List.fromList("${participantId}|${j}".codeUnits));
      } else {
        ack = ECDSA.sign(signaturePrivateKey, Uint8List.fromList([0]));
      }
      acknowledgements.add(ack.toJson());
    }
    return {
      "acknowledgements": acknowledgements,
      "valid_shares": validShares,
    };
  }
}
