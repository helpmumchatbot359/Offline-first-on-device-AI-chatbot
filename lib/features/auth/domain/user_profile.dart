import 'package:equatable/equatable.dart';

/// The small identity the chat screen needs: a friendly name and an email.
///
/// The backend only needs the email/password to sign in, so the app keeps this
/// profile on the phone. It is never used for authentication decisions.
class UserProfile extends Equatable {
  const UserProfile({required this.name, required this.email});

  final String name;
  final String email;

  /// First letter of the name, falling back to the email, then to "M".
  String get initial {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return 'M';
    return String.fromCharCode(source.runes.first).toUpperCase();
  }

  /// Just the first word, so long names still fit in the app bar.
  String get firstName {
    final clean = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (clean.isEmpty) return 'Mama';
    return clean.split(RegExp(r'\s+')).first;
  }

  @override
  List<Object?> get props => [name, email];
}
