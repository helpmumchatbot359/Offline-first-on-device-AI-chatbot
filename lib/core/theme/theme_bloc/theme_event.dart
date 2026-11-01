import 'package:equatable/equatable.dart';

abstract class ThemeEvent extends Equatable {
  const ThemeEvent();
  @override
  List<Object?> get props => [];
}

/// Read the saved choice from the phone.
class ThemeLoaded extends ThemeEvent {
  const ThemeLoaded();
}

/// The person tapped the sun/moon button.
class ThemeToggled extends ThemeEvent {
  const ThemeToggled();
}
