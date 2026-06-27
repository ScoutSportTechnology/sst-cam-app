import 'recording.dart';

/// State of an on-demand overlayed-export (burn) job on the camera (#6 A6c).
/// The camera replays the stored overlay timeline onto the clean L1, encodes a
/// throwaway L2, and exposes it for a single download.
enum ExportJobState { unknown, pending, running, ready, failed }

/// Reply to both the export request and a poll. When [state] is
/// [ExportJobState.ready] the [token] is set (a one-shot L2 download token);
/// when [ExportJobState.failed] the [errorMessage] explains why.
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
  bool get isTerminal => isReady || isFailed;
}
