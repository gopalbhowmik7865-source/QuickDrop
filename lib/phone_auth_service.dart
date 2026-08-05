import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PhoneAuthService {
  PhoneAuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required Future<void> Function(UserCredential userCredential)
    onVerificationCompleted,
    void Function(FirebaseAuthException error)? onVerificationFailed,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
    int? forceResendingToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    debugPrint(
      'QuickDropPhoneAuth verifyPhoneNumber.start: phoneNumber=$phoneNumber, forceResendingToken=${forceResendingToken?.toString() ?? 'null'}',
    );

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        debugPrint(
          'QuickDropPhoneAuth CALLBACK verificationCompleted: providerId=${credential.providerId}, smsCode=${credential.smsCode ?? 'null'}',
        );

        final userCredential = await _firebaseAuth.signInWithCredential(
          credential,
        );
        await onVerificationCompleted(userCredential);
      },
      verificationFailed: (FirebaseAuthException error) {
        debugPrint(
          'QuickDropPhoneAuth CALLBACK verificationFailed: code=${error.code}, message=${error.message ?? 'null'}',
        );
        onVerificationFailed?.call(error);
      },
      codeSent: (String verificationId, int? resendToken) {
        debugPrint(
          'QuickDropPhoneAuth CALLBACK codeSent: verificationId=$verificationId, resendToken=${resendToken?.toString() ?? 'null'}',
        );
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        debugPrint(
          'QuickDropPhoneAuth CALLBACK codeAutoRetrievalTimeout: verificationId=$verificationId',
        );
        onCodeAutoRetrievalTimeout?.call(verificationId);
      },
    );
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String otp,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );

    return _firebaseAuth.signInWithCredential(credential);
  }
}
