import 'recording.dart';

/// State of an on-demand overlayed-export (burn) job on the camera (#6 A6c).
/// The camera replays the stored overlay timeline onto the clean L1 and
/// encodes an L2 that persists in the match folder beside the L1 — it appears
/// in listings/downloads like any recording, and a re-export of an
/// already-burned recording returns the existing file fast.
enum ExportJobState { unknown, pending, running, ready, failed }

/// Reply to both the export request and a poll. When [state] is
/// [ExportJobState.ready] the [token] is set (a short-lived L2 download
/// token); when [ExportJobState.failed] the [errorMessage] explains why.
class ExportJob {
  const ExportJob({
    required this.jobId,
    required this.state,
    this.token,
    this.errorMessage,
  });

  final String jobId;
  final ExportJobState state;
  final DownloadToken? token;
  final String? errorMessage;

  bool get isReady => state == ExportJobState.ready;
  bool get isFailed => state == ExportJobState.failed;

  /// The camera has no record of this job — typically the firmware restarted
  /// since the request. Terminal: there is nothing left to poll for.
  bool get isUnknown => state == ExportJobState.unknown;

  bool get isTerminal => isReady || isFailed || isUnknown;
}
