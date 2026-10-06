import 'package:appbuilder/services/transfer/install_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('install failures are explained', () {
    expect(TransferMessages.installFailure(5, 'INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match'),
        contains('другим ключом'));
    expect(TransferMessages.installFailure(5, 'INSTALL_FAILED_VERSION_DOWNGRADE'), contains('versionCode'));
    expect(TransferMessages.installFailure(3, null), 'Установка отменена.');
    expect(TransferMessages.installFailure(6, null), contains('места'));
    expect(TransferMessages.installFailure(1, 'boom'), 'Установка не удалась: boom');
  });

  test('download failures and pauses are explained', () {
    expect(TransferMessages.downloadFailure(403), contains('Повторить'));
    expect(TransferMessages.downloadFailure(404), contains('404'));
    expect(TransferMessages.downloadFailure(1006), contains('места'));
    expect(TransferMessages.downloadPause(2), contains('сети'));
    expect(TransferMessages.downloadPause(3), contains('Wi-Fi'));
  });
}
