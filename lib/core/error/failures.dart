import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  final int? statusCode;

  const Failure(this.message, [this.statusCode]);

  @override
  List<Object?> get props => [message, statusCode];
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, [super.statusCode]);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Отсутствует подключение к сети']);
}

class ParsingFailure extends Failure {
  const ParsingFailure([super.message = 'Ошибка обработки данных ответа']);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Непредвиденная ошибка']);
}

