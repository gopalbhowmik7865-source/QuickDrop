String normalizePhoneValue(String? value) {
  if (value == null) {
    return '';
  }

  final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10) {
    return '+91$digits';
  }
  if (digits.length == 11 && digits.startsWith('0')) {
    return '+91${digits.substring(1)}';
  }
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+$digits';
  }
  return value.toString().trim();
}

bool orderMatchesSessionPhone(Map<String, dynamic> data, String sessionPhone) {
  final normalizedSession = normalizePhoneValue(sessionPhone);
  if (normalizedSession.isEmpty) {
    return false;
  }

  final candidates = <String?>[
    data['ownerPhone']?.toString(),
    data['phoneNumber']?.toString(),
    data['phone']?.toString(),
    data['customerPhone']?.toString(),
    data['customer']?['phone']?.toString(),
  ];

  return candidates.any((candidate) {
    if (candidate == null || candidate.trim().isEmpty) {
      return false;
    }
    return normalizePhoneValue(candidate) == normalizedSession;
  });
}

bool shouldUseFallbackProducts(
  Iterable<Map<String, dynamic>> docs, {
  required String firestoreCategory,
}) {
  if (docs.isEmpty) {
    return true;
  }

  final expectedCategory = firestoreCategory.trim().toLowerCase();
  if (expectedCategory.isEmpty) {
    return false;
  }

  final matches = docs.where((data) {
    final rawCategory = data['category']?.toString().trim().toLowerCase() ?? '';
    return rawCategory.isEmpty
        ? false
        : rawCategory.contains(expectedCategory) ||
            expectedCategory.contains(rawCategory);
  });

  return matches.isEmpty;
}
