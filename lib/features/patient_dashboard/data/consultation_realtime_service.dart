import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/network/api_client.dart';
import '../../../core/auth/auth_session.dart';

/// Mirrors websocket.service.ts's watchConsultation: a STOMP client over the
/// backend's SockJS endpoint (`/ws`). SockJS's raw-websocket transport is
/// reached at `<endpoint>/websocket`, so a plain WebSocket + hand-rolled
/// STOMP frames gets us the same `/topic/consultation/{id}` subscription
/// Angular's RxStomp opens, without pulling in a full SockJS client.
///
/// Kept defensive end-to-end (mirrors the try/catch wrapping in
/// websocket.service.ts) — any failure to connect/subscribe/parse just means
/// no live push, never a crash.
class ConsultationRealtimeService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  bool _connected = false;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> watchConsultation(String consultationId) {
    _connect(consultationId);
    return _controller.stream;
  }

  void _connect(String consultationId) {
    try {
      final token = AuthSession.token;
      final wsBase = kBaseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      final uri = Uri.parse('$wsBase/ws/websocket');
      _channel = WebSocketChannel.connect(uri);

      final connectFrame = StringBuffer()
        ..write('CONNECT\n')
        ..write('accept-version:1.1,1.2\n')
        ..write('heart-beat:20000,0\n');
      if (token != null && token.isNotEmpty) {
        connectFrame.write('Authorization:Bearer $token\n');
      }
      connectFrame.write('\n\x00');
      _channel!.sink.add(connectFrame.toString());

      _sub = _channel!.stream.listen(
        (data) => _onFrame(data.toString(), consultationId),
        onError: (_) => _connected = false,
        onDone: () => _connected = false,
        cancelOnError: false,
      );

      // STOMP heart-beat, mirrors heartbeatOutgoing: 20000 in websocket.service.ts.
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          _channel?.sink.add('\n');
        } catch (_) {}
      });
    } catch (_) {
      _connected = false;
    }
  }

  void _onFrame(String raw, String consultationId) {
    if (raw.trim().isEmpty) return;
    final lines = raw.split('\n');
    final command = lines.isNotEmpty ? lines.first.trim() : '';

    if (command == 'CONNECTED') {
      _connected = true;
      _subscribe(consultationId);
      return;
    }

    if (command == 'MESSAGE') {
      final bodyStart = raw.indexOf('\n\n');
      if (bodyStart == -1) return;
      var body = raw.substring(bodyStart + 2);
      if (body.endsWith('\x00')) body = body.substring(0, body.length - 1);
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          _controller.add(decoded);
        }
      } catch (_) {}
    }
  }

  void _subscribe(String consultationId) {
    if (!_connected || _channel == null) return;
    final frame = StringBuffer()
      ..write('SUBSCRIBE\n')
      ..write('id:sub-$consultationId\n')
      ..write('destination:/topic/consultation/$consultationId\n')
      ..write('\n\x00');
    try {
      _channel!.sink.add(frame.toString());
    } catch (_) {}
  }

  void disconnect() {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      _channel?.sink.add('DISCONNECT\n\n\x00');
    } catch (_) {}
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connected = false;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
