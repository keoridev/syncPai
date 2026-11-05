import 'package:equatable/equatable.dart';

/// Статистика нахождения аниме в пользовательских списках ("В списках у людей").
class UserListsStats extends Equatable {
  final int watching;
  final int planned;
  final int onHold;
  final int dropped;
  final int completed;

  const UserListsStats({
    this.watching = 0,
    this.planned = 0,
    this.onHold = 0,
    this.dropped = 0,
    this.completed = 0,
  });

  int get total => watching + planned + onHold + dropped + completed;

  @override
  List<Object?> get props => [watching, planned, onHold, dropped, completed];
}

