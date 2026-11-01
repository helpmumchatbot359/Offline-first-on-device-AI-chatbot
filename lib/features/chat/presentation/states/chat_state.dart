import 'package:equatable/equatable.dart';
import '../../domain/chat_turn.dart';

class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.isOnline = true,
    this.isLoading = true,
  });

  final List<ChatTurn> messages;
  final bool isGenerating;
  final bool isOnline;
  final bool isLoading; // reading saved history

  /// Stop only makes sense while the on-phone model is writing.
  bool get canStop =>
      isGenerating && messages.isNotEmpty && messages.last.isOffline;

  ChatState copyWith({
    List<ChatTurn>? messages,
    bool? isGenerating,
    bool? isOnline,
    bool? isLoading,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      isOnline: isOnline ?? this.isOnline,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [messages, isGenerating, isOnline, isLoading];
}
