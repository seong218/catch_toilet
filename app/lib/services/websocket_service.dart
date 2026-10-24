import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/json_fields.dart';
import '../models/stall_update.dart';
import '../repositories/restroom_repository.dart';

class WebsocketService {
  WebsocketService(
    this.uri, {
    this.connectionTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(seconds: 1),
  });

  final Uri uri;
  final Duration connectionTimeout;
  final Duration retryDelay;
  final _updates = StreamController<StallUpdate>.broadcast();
  final _connections = StreamController<RealtimeStatus>.broadcast();
  Stream<StallUpdate> get updates => _updates.stream;
  Stream<RealtimeStatus> get connectionChanges => _connections.stream;
  RealtimeStatus status = RealtimeStatus.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Future<void>? _connecting;
  bool _disposed = false;
  bool _paused = false;
  int _epoch = 0;
  int _failures = 0;

  void _setStatus(RealtimeStatus value) {
    if (_disposed || status == value) return;
    status = value;
    _connections.add(value);
  }

  Future<void> connect() {
    if (_disposed) return Future.value();
    _paused = false;
    if (status == RealtimeStatus.connected) return Future.value();
    if (_connecting != null) return _connecting!;
    _retry?.cancel();
    final pending = _open();
    _connecting = pending;
    return pending.whenComplete(() {
      if (identical(_connecting, pending)) _connecting = null;
    });
  }

  Future<void> _open() async {
    final epoch = ++_epoch;
    _setStatus(RealtimeStatus.connecting);
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      // Listen before awaiting ready so handshake/early stream errors are handled.
      _subscription = channel.stream.listen(
        (Object? message) {
          if (_disposed || epoch != _epoch) return;
          try {
            if (message is! String) {
              throw const FormatException('Expected text');
            }
            final json = jsonObject(jsonDecode(message));
            if (json['type'] != 'stall.updated') return;
            _updates.add(StallUpdate.fromJson(json));
          } on FormatException {
            // A broken known event could hide a change: reconnect and REST-resync.
            _lost(epoch);
          }
        },
        onError: (Object error) => _lost(epoch),
        onDone: () => _lost(epoch),
        cancelOnError: true,
      );
      await channel.ready.timeout(connectionTimeout);
      if (_disposed || _paused || epoch != _epoch) return;
      _failures = 0;
      _setStatus(RealtimeStatus.connected);
    } catch (_) {
      _lost(epoch);
    }
  }

  void _lost(int epoch) {
    if (_disposed || epoch != _epoch) return;
    ++_epoch;
    _connecting = null;
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    _setStatus(RealtimeStatus.disconnected);
    unawaited(_close(subscription, channel));
    if (!_paused) {
      final milliseconds = min(
        30000,
        retryDelay.inMilliseconds * (1 << min(_failures++, 5)),
      );
      _retry = Timer(Duration(milliseconds: milliseconds), () {
        if (!_disposed && !_paused) unawaited(connect());
      });
    }
  }

  Future<void> _close(
    StreamSubscription<dynamic>? subscription,
    WebSocketChannel? channel,
  ) async {
    try {
      await subscription?.cancel();
    } catch (_) {
      /* Already closed. */
    }
    try {
      await channel?.sink.close(1000).timeout(connectionTimeout);
    } catch (_) {
      /* A failed handshake may never expose a writable sink. */
    }
  }

  void suspend() {
    _paused = true;
    _retry?.cancel();
    _lost(_epoch);
    // A timed-out older attempt must not hold up a foreground reconnection.
    _connecting = null;
  }

  void dispose() {
    suspend();
    _disposed = true;
    unawaited(_updates.close());
    unawaited(_connections.close());
  }
}
