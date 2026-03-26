import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Discovers the machine's LAN IPv4 address.
///
/// Priority:
/// 1. WiFi IP via [NetworkInfo]
/// 2. First non-loopback IPv4 via [NetworkInterface]
/// 3. Fallback: 127.0.0.1
class LanService {
  static Future<String> getLocalIp() async {
    // 1. Try network_info_plus (WiFi IP)
    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
        return wifiIp;
      }
    } catch (_) {}

    // 2. Enumerate network interfaces
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      // Prefer interfaces whose name contains 'Wi-Fi', 'wlan', or 'eth'
      final preferred = interfaces.where((i) {
        final name = i.name.toLowerCase();
        return name.contains('wi-fi') ||
            name.contains('wlan') ||
            name.contains('eth') ||
            name.contains('en0') ||
            name.contains('en1');
      });
      for (final iface in [...preferred, ...interfaces]) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    return '127.0.0.1';
  }
}
