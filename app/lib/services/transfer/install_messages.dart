/// Human readable reasons for DownloadManager and PackageInstaller codes.
abstract final class TransferMessages {
  /// `DownloadManager.COLUMN_REASON` of a failed download.
  static String downloadFailure(int reason) {
    if (reason == 401 || reason == 403) {
      return 'Сервер отказал в доступе (HTTP $reason): ссылка на APK устарела или токен неверный. Нажмите «Повторить».';
    }
    if (reason == 404) return 'APK не найден на сервере (HTTP 404).';
    if (reason >= 400 && reason < 600) return 'Ошибка сервера HTTP $reason.';
    return switch (reason) {
      1006 => 'Недостаточно места на устройстве.',
      1001 || 1007 => 'Не удалось записать файл: хранилище недоступно.',
      1004 || 1008 => 'Связь прервалась и докачать файл не удалось. Нажмите «Повторить».',
      1005 => 'Слишком много перенаправлений при скачивании.',
      _ => 'Ошибка загрузки (код $reason).',
    };
  }

  /// `DownloadManager.COLUMN_REASON` of a paused download.
  static String downloadPause(int reason) => switch (reason) {
        1 => 'Сбой сети — повтор через несколько секунд…',
        2 => 'Ожидание подключения к сети…',
        3 => 'Ожидание Wi-Fi: файл слишком большой для мобильной сети…',
        _ => 'Загрузка приостановлена системой…',
      };

  /// `PackageInstaller.EXTRA_STATUS` / `EXTRA_STATUS_MESSAGE` of a failed install.
  static String installFailure(int? code, String? message) {
    final m = message ?? '';
    if (m.contains('VERSION_DOWNGRADE')) {
      return 'На телефоне стоит более новая версия этого приложения (versionCode больше). '
          'Увеличьте versionCode в параметрах сборки или удалите установленное приложение.';
    }
    if (m.contains('UPDATE_INCOMPATIBLE') || m.contains('SIGNATURE')) {
      return 'Уже установлено приложение с этим пакетом, но подписанное другим ключом. '
          'Удалите его с телефона и установите снова (данные старой версии удалятся).';
    }
    return switch (code) {
      3 => 'Установка отменена.',
      2 => 'Установка заблокирована политикой устройства или Play Protect.',
      4 => 'APK повреждён или не подписан.',
      5 => 'Конфликт с установленным приложением (другая подпись или более новая версия). '
          'Удалите установленное приложение и повторите.',
      6 => 'Недостаточно места на устройстве.',
      7 => 'APK несовместим с этим устройством (версия Android или архитектура процессора).',
      8 => 'Истекло время ожидания установки.',
      _ => m.isEmpty ? 'Установка не удалась.' : 'Установка не удалась: $m',
    };
  }
}
