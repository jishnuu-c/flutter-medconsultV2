import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppWebSocketService {
  WebSocketChannel? _channel;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  void connect(String url, {String? token}) {
    if (_isConnected) return;
    try {
      final wsUri = Uri.parse(url);
      _channel = WebSocketChannel.connect(wsUri);
      _isConnected = true;
    } catch (_) {
      _isConnected = false;
    }
  }

  Stream<dynamic>? watch(String destination) {
    if (!_isConnected || _channel == null) return null;
    return _channel!.stream;
  }

  void publish(String destination, Map<String, dynamic> body) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(body.toString());
  }

  void disconnect() {
    if (_isConnected) {
      _channel?.sink.close();
      _isConnected = false;
    }
  }
}

final webSocketServiceProvider = Provider<AppWebSocketService>((ref) {
  return AppWebSocketService();
});
