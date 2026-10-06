import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'build_log.dart';

/// Thrown when a pipeline stage fails; [message] is shown to the user.
class BuildFailure implements Exception {
  BuildFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProcessResultLines {
  ProcessResultLines(this.exitCode, this.output);

  final int exitCode;
  final List<String> output;
}

/// Runs external tools (npm, gradle, keytool, apksigner…) streaming their
/// output into the build log, with a hard timeout that kills the whole
/// process group.
class ProcessRunner {
  const ProcessRunner();

  Future<ProcessResultLines> run(
    List<String> command, {
    required String workingDirectory,
    required BuildLog log,
    Map<String, String> environment = const {},
    Set<String> removeEnvironment = const {},
    Duration timeout = const Duration(minutes: 10),
    bool logOutput = true,
  }) async {
    final env = Map<String, String>.of(Platform.environment)
      ..removeWhere((k, _) => removeEnvironment.contains(k))
      ..addAll(environment);
    final useSetsid = Platform.isLinux && File('/usr/bin/setsid').existsSync();
    final exe = useSetsid ? '/usr/bin/setsid' : command.first;
    final args = useSetsid ? command : command.sublist(1);

    log.add('\$ ${command.join(' ')}');
    final Process process;
    try {
      process = await Process.start(
        exe,
        args,
        workingDirectory: workingDirectory,
        environment: env,
        includeParentEnvironment: false,
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (e) {
      throw BuildFailure('Не удалось запустить «${command.first}»: ${e.message}. Проверьте, что инструмент установлен.');
    }
    // Interactive prompts must fail fast instead of hanging the build.
    unawaited(process.stdin.close());

    final output = <String>[];
    void onLine(String line) {
      output.add(line);
      if (output.length > 4000) output.removeAt(0);
      if (logOutput) log.add(line);
    }

    // asFuture() must be attached right away, otherwise a stream that has
    // already finished would never complete the future.
    final outDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(onLine)
        .asFuture<void>();
    final errDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(onLine)
        .asFuture<void>();

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      _killTree(process.pid, useSetsid);
    });
    final code = await process.exitCode;
    timer.cancel();
    await Future.wait([outDone, errDone]);

    if (timedOut) {
      throw BuildFailure('«${command.first}» превысил лимит времени ${timeout.inMinutes} мин и был остановлен.');
    }
    return ProcessResultLines(code, output);
  }

  /// Same as [run] but throws [BuildFailure] on a non-zero exit code.
  Future<ProcessResultLines> runChecked(
    List<String> command, {
    required String workingDirectory,
    required BuildLog log,
    required String failureMessage,
    Map<String, String> environment = const {},
    Set<String> removeEnvironment = const {},
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final result = await run(
      command,
      workingDirectory: workingDirectory,
      log: log,
      environment: environment,
      removeEnvironment: removeEnvironment,
      timeout: timeout,
    );
    if (result.exitCode != 0) {
      throw BuildFailure('$failureMessage (код выхода ${result.exitCode}). Подробности — в логе сборки.');
    }
    return result;
  }

  static void _killTree(int pid, bool groupLeader) {
    if (groupLeader) {
      // setsid made the child a process-group leader: kill the whole group.
      Process.runSync('kill', ['-KILL', '-$pid']);
    } else {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
  }
}
