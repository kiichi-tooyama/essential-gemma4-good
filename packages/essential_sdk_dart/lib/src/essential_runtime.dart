import 'dart:async';

import 'essential_task_router.dart';
import 'essential_task_types.dart';
import 'essential_types.dart';

abstract interface class EssentialRuntime {
  EssentialRuntimeFamily get family;
  bool get isAvailable;

  Future<void> initialize();
  String ensureRequestId(EssentialTaskRequest request);
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  );
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  );
  Future<void> cancel(String requestId);
  Future<void> dispose();
}

abstract base class EssentialBaseRuntime implements EssentialRuntime {
  int _requestCounter = 0;

  @override
  String ensureRequestId(EssentialTaskRequest request) {
    final id = request.id;
    if (id != null && id.isNotEmpty) {
      return id;
    }
    _requestCounter += 1;
    return '${family.name}-task-$_requestCounter';
  }
}

final class EssentialUnavailableRuntime extends EssentialBaseRuntime {
  EssentialUnavailableRuntime(this.family);

  @override
  final EssentialRuntimeFamily family;

  @override
  bool get isAvailable => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<EssentialTaskResponse> execute(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) {
    throw EssentialException(
      EssentialErrorCode.runtimeUnavailable,
      'Runtime ${family.wireName} is unavailable.',
    );
  }

  @override
  Stream<EssentialTaskEvent> stream(
    EssentialTaskRequest request,
    EssentialTaskRoutingDecision decision,
  ) {
    return Stream<EssentialTaskEvent>.error(
      EssentialException(
        EssentialErrorCode.runtimeUnavailable,
        'Runtime ${family.wireName} is unavailable.',
      ),
    );
  }

  @override
  Future<void> cancel(String requestId) async {}

  @override
  Future<void> dispose() async {}
}
