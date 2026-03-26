import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';

/// Local WebSocket server running on the PC's LAN.
///
/// Accepts exactly ONE client (1-to-1 pairing with Android).
/// All incoming messages are broadcast via [messages] stream.
/// Use [send] to send messages to the connected client.
class LocalWsServer {
  HttpServer? _server;
  WebSocketChannel? _client;
  int? _port;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<bool> get connectionState => _connectionController.stream;

  bool get hasClient => _client != null;
  int? get port => _port;

  /// Starts the server on a random port in [AppConstants.wsPortStart]..[AppConstants.wsPortEnd].
  /// Returns the bound port.
  Future<int> start() async {
    final rng = Random();
    const portRange = AppConstants.wsPortEnd - AppConstants.wsPortStart;

    for (var attempt = 0; attempt < 20; attempt++) {
      final port = AppConstants.wsPortStart + rng.nextInt(portRange);
      try {
        final handler = webSocketHandler(_handleConnection);
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          port,
          shared: false,
        );
        _port = port;
        developer.log('[LocalWsServer] Listening on port $port');
        return port;
      } catch (_) {
        // port in use, try another
      }
    }
    throw StateError(
        'Could not bind to any port in ${AppConstants.wsPortStart}-${AppConstants.wsPortEnd}');
  }

  void _handleConnection(WebSocketChannel channel) {
    if (_client != null) {
      developer.log('[LocalWsServer] Rejecting extra client');
      channel.sink.close(1008, 'Server busy');
      return;
    }

    developer.log('[LocalWsServer] Android connected');
    _client = channel;
    _connectionController.add(true);

    channel.stream.listen(
      (data) {
        if (data is! String || data.trim().isEmpty) return;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          developer.log('[LocalWsServer] ← ${json['type']}');
          _messageController.add(json);
        } catch (e) {
          developer.log('[LocalWsServer] Parse error: $e');
        }
      },
      onDone: () {
        developer.log('[LocalWsServer] Android disconnected');
        _client = null;
        _connectionController.add(false);
      },
      onError: (e) {
        developer.log('[LocalWsServer] Connection error: $e');
        _client = null;
        _connectionController.add(false);
      },
      cancelOnError: false,
    );
  }

  /// Sends a JSON message to the connected Android client.
  void send(Map<String, dynamic> message) {
    if (_client == null) {
      developer.log('[LocalWsServer] No client — drop ${message['type']}');
      return;
    }
    final encoded = jsonEncode(message);
    developer.log('[LocalWsServer] → ${message['type']}');
    _client!.sink.add(encoded);
  }

  /// Closes the active client connection without stopping the server.
  void kickClient() {
    _client?.sink.close(1000, 'Session ended');
    _client = null;
  }

  /// Stops the server and closes any active client.
  Future<void> stop() async {
    kickClient();
    await _server?.close(force: true);
    _server = null;
    _port = null;
    developer.log('[LocalWsServer] Stopped');
  }

  void dispose() {
    stop();
    _messageController.close();
    _connectionController.close();
  }
}
