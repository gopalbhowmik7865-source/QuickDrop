import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _prefsLoggedInKey = 'user_logged_in';
  static const String _prefsNameKey = 'user_name';
  static const String _prefsPhoneKey = 'user_phone';
  static const String _prefsAddressKey = 'user_address';

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  void _log(String message) {
    developer.log(message, name: 'QuickDropAuth');
  }

  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required Future<void> Function(UserCredential userCredential)
    onVerificationCompleted,
    void Function(FirebaseAuthException error)? onVerificationFailed,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    debugPrint(
      'QuickDropAuth verifyPhoneNumber.start: phoneNumber=$phoneNumber, forceResendingToken=${forceResendingToken?.toString() ?? 'null'}',
    );
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        debugPrint(
          'QuickDropAuth CALLBACK verificationCompleted: providerId=${credential.providerId}, smsCode=${credential.smsCode ?? 'null'}',
        );
        final userCredential = await _firebaseAuth.signInWithCredential(
          credential,
        );
        await onVerificationCompleted(userCredential);
      },
      verificationFailed: (FirebaseAuthException error) {
        debugPrint(
          'QuickDropAuth CALLBACK verificationFailed: code=${error.code}, message=${error.message ?? 'null'}',
        );
        onVerificationFailed?.call(error);
      },
      codeSent: (String verificationId, int? resendToken) {
        debugPrint(
          'QuickDropAuth CALLBACK codeSent: verificationId=$verificationId, resendToken=${resendToken?.toString() ?? 'null'}',
        );
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        debugPrint(
          'QuickDropAuth CALLBACK codeAutoRetrievalTimeout: verificationId=$verificationId',
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

  Future<void> loginLocally({
    required String name,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final savedLoggedIn = await prefs.setBool(_prefsLoggedInKey, true);
    final savedName = await prefs.setString(_prefsNameKey, name.trim());
    final savedPhone = await prefs.setString(_prefsPhoneKey, phone.trim());

    // Keep address key available for profile UI compatibility.
    await prefs.setString(
      _prefsAddressKey,
      prefs.getString(_prefsAddressKey) ?? '',
    );

    final storedLoggedIn = prefs.getBool(_prefsLoggedInKey) ?? false;
    final storedName = prefs.getString(_prefsNameKey);
    final storedPhone = prefs.getString(_prefsPhoneKey);
    final verified = savedLoggedIn &&
        savedName &&
        savedPhone &&
        storedLoggedIn &&
        storedName == name.trim() &&
        storedPhone == phone.trim();

    _log(
      'loginLocally: savedLoggedIn=$savedLoggedIn, savedName=$savedName, '
      'savedPhone=$savedPhone, storedLoggedIn=$storedLoggedIn, '
      'storedName=$storedName, storedPhone=$storedPhone, verified=$verified',
    );

    await prefs.reload();
    debugPrint(
      'QuickDropAuth loginLocally persisted: user_logged_in=${prefs.getBool(_prefsLoggedInKey) ?? false}, '
      'phone=${prefs.getString(_prefsPhoneKey)?.trim() ?? ''}',
    );
    _log(
      'loginLocally persisted values: user_logged_in=${prefs.getBool(_prefsLoggedInKey) ?? false}, '
      'phone=${prefs.getString(_prefsPhoneKey)?.trim() ?? ''}',
    );

    if (!verified) {
      throw Exception('Unable to persist login session. Please try again.');
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_prefsLoggedInKey) ?? false;
    final name = prefs.getString(_prefsNameKey)?.trim() ?? '';
    final phone = prefs.getString(_prefsPhoneKey)?.trim() ?? '';
    final hasRequiredData = name.isNotEmpty && phone.isNotEmpty;

    _log(
      'startup session check: user_logged_in=$loggedIn, phone=$phone, '
      'name=$name, hasRequiredData=$hasRequiredData',
    );
    debugPrint(
      'QuickDropAuth startup: user_logged_in=$loggedIn, phone=$phone',
    );

    if (loggedIn && hasRequiredData) {
      return true;
    }

    if (loggedIn && !hasRequiredData) {
      _log('startup session check: partial session found, keeping it until logout.');
    }

    return false;
  }

  Future<Map<String, dynamic>?> loadCurrentUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final loggedIn = prefs.getBool(_prefsLoggedInKey) ?? false;
    final name = prefs.getString(_prefsNameKey)?.trim() ?? '';
    final phone = prefs.getString(_prefsPhoneKey)?.trim() ?? '';
    final address = prefs.getString(_prefsAddressKey)?.trim() ?? '';

    if (!loggedIn || name.isEmpty || phone.isEmpty) {
      _log('loadCurrentUserProfile: session unavailable.');
      return null;
    }

    final profile = <String, dynamic>{
      'name': name,
      'phoneNumber': phone,
      'address': address,
    };

    _log('loadCurrentUserProfile: loaded profile for phone=$phone');
    return profile;
  }

  Future<String?> getCurrentUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final loggedIn = prefs.getBool(_prefsLoggedInKey) ?? false;
    final phone = prefs.getString(_prefsPhoneKey)?.trim();

    if (!loggedIn || phone == null || phone.isEmpty) {
      _log('getCurrentUserPhone: no valid session phone found.');
      return null;
    }

    return phone;
  }

  Future<String?> getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final loggedIn = prefs.getBool(_prefsLoggedInKey) ?? false;
    final name = prefs.getString(_prefsNameKey)?.trim();

    if (!loggedIn || name == null || name.isEmpty) {
      _log('getCurrentUserName: no valid session name found.');
      return null;
    }

    return name;
  }

  Future<void> updateCurrentUserProfile({
    required String name,
    required String address,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final loggedIn = prefs.getBool(_prefsLoggedInKey) ?? false;

    if (!loggedIn) {
      _log('updateCurrentUserProfile: no local session available.');
      throw Exception('No user session found. Please log in again.');
    }

    final savedName = await prefs.setString(_prefsNameKey, name.trim());
    final savedAddress = await prefs.setString(_prefsAddressKey, address.trim());

    _log(
      'updateCurrentUserProfile: savedName=$savedName, '
      'savedAddress=$savedAddress, name=${name.trim()}',
    );
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.remove(_prefsLoggedInKey);
    await prefs.remove(_prefsNameKey);
    await prefs.remove(_prefsPhoneKey);
    await prefs.remove(_prefsAddressKey);
    _log('signOut: local session cleared.');
  }
}
