import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memotion_pc/services/local_ws_server.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('LocalWsServer', () {
    test('starts and binds to a port', () async {
      final server = LocalWsServer();
      final port = await server.start();
      expect(port, greaterThanOrEqualTo(8765));
      expect(port, lessThanOrEqualTo(8800));
      expect(server.port, equals(port));
      await server.stop();
    });

    test('stop clears port', () async {
      final server = LocalWsServer();
      await server.start();
      await server.stop();
      expect(server.port, isNull);
    });

    test('receives messages from WebSocket client', () async {
      final server = LocalWsServer();
      final port = await server.start();

      final messagesReceived = <Map<String, dynamic>>[];
      final sub = server.messages.listen(messagesReceived.add);

      // Connect as client
      final client = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      client.sink.add(jsonEncode({'type': 'heartbeat_ping'}));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(messagesReceived, hasLength(1));
      expect(messagesReceived.first['type'], equals('heartbeat_ping'));

      await client.sink.close();
      await sub.cancel();
      await server.stop();
    });

    test('sends messages to connected client', () async {
      final server = LocalWsServer();
      final port = await server.start();

      final client = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );

      final received = <dynamic>[];
      final clientSub = client.stream.listen(received.add);

      await Future.delayed(const Duration(milliseconds: 100));
      server.send({'type': 'pair_confirmed'});
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, hasLength(1));
      final decoded = jsonDecode(received.first as String) as Map<String, dynamic>;
      expect(decoded['type'], equals('pair_confirmed'));

      await clientSub.cancel();
      await client.sink.close();
      await server.stop();
    });

    test('broadcasts connectionState when client connects', () async {
      final server = LocalWsServer();
      final port = await server.start();

      final states = <bool>[];
      final sub = server.connectionState.listen(states.add);

      final client = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );
      await Future.delayed(const Duration(milliseconds: 200));

      expect(states, contains(true));

      await client.sink.close();
      await Future.delayed(const Duration(milliseconds: 200));

      expect(states, contains(false));

      await sub.cancel();
      await server.stop();
    });
  });
}
