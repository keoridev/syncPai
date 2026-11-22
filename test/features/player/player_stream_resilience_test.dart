import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_cubit.dart';

void main() {
  group('PlayerCubit stream resilience & friendly errors', () {
    test('detects ffurl_write / 0xffffff99 and transient TCP errors', () {
      expect(
        PlayerCubit.isTransientStreamError('tcp: ffurl_write returned 0xffffff99'),
        isTrue,
      );
      expect(
        PlayerCubit.isTransientStreamError('ffurl_read_returned 0xdfb9b0bb'),
        isTrue,
      );
      expect(
        PlayerCubit.isTransientStreamError('Connection timed out'),
        isTrue,
      );
      expect(
        PlayerCubit.isTransientStreamError('Unsupported codec h264'),
        isFalse,
      );
    });

    test('formats raw hex network errors into clean Russian copy', () {
      final msg = PlayerCubit.formatFriendlyStreamError(
        'tcp: ffurl_write returned 0xffffff99',
      );
      expect(
        msg,
        'Потеряно соединение с видеосервером. Проверьте интернет и нажмите «Повторить».',
      );
      expect(msg.contains('0xffffff99'), isFalse);
      expect(msg.contains('ffurl_write'), isFalse);
    });
  });
}

