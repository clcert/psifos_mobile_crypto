import 'package:pointycastle/ecc/curves/secp521r1.dart';
import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/ecc/api.dart' as ecc_api;
import 'package:psifos_mobile_crypto/crypto/ecc/ec_tdkg/ec_tdkg.dart';

class TrusteeSyncStep3 {
  /* parses step 3 input into usable classes */
  static List<BigInt> parseInput(Map<String, dynamic> input) {
    List<BigInt> recv_shares = input['recv_shares']
        .map((e) => BigInt.parse(e['encrypted_share']))
        .toList();
    return recv_shares;
  }

  static Map<String, String> handle(List<BigInt> recv_shares, int threshold,
      int numParticipants, int participantId) {
    /* make sure data is received from the correct number of participants */
    assert(recv_shares.length == numParticipants);

    /* curve parameters */
    final domainParams = ECCurve_secp521r1();
    final basePoint = domainParams.G as fp.ECPoint;

    /* First we compute the share of the secret */
    BigInt secret = ECTDKG.calculateShareSecret(recv_shares);

    /* Then we compute the verification key using the computed secret */
    ecc_api.ECPoint verificationKey =
        ECTDKG.calculateVerificationKey(secret, basePoint);

    return {
      'secret': secret.toString(),
      'verification_key': verificationKey.toString(),
    };
  }
}
