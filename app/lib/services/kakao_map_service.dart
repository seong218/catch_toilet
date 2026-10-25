import 'package:flutter/foundation.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import '../config/app_config.dart';

enum MapAvailability { idle, ready, unconfigured, unsupported, failed }

enum MapFailure { connection, authentication, quota }

/// Initializes the native SDK once. Authentication happens when a map opens.
/// Free quota and paid API settings are managed in Kakao Developers.
class KakaoMapService extends ChangeNotifier {
  KakaoMapService({
    String nativeAppKey = AppConfig.kakaoNativeAppKey,
    KakaoMapSdk? sdk,
  }) : _nativeAppKey = nativeAppKey.trim(),
       _sdk = sdk ?? KakaoMapSdk.instance;

  static final instance = KakaoMapService();
  final String _nativeAppKey;
  final KakaoMapSdk _sdk;
  Future<void>? _initialization;
  MapAvailability availability = MapAvailability.idle;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (_nativeAppKey.isEmpty) {
      _set(MapAvailability.unconfigured);
      return;
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      _set(MapAvailability.unsupported);
      return;
    }
    try {
      await _sdk.initialize(_nativeAppKey).timeout(const Duration(seconds: 15));
      _set(MapAvailability.ready);
    } catch (_) {
      _set(MapAvailability.failed);
    }
  }

  static MapFailure classifyError(Object error) {
    if (error is KakaoAuthError) {
      if (error.code == 429) return MapFailure.quota;
      if ([400, 401, 403].contains(error.code)) {
        return MapFailure.authentication;
      }
    }
    return MapFailure.connection;
  }

  void _set(MapAvailability value) {
    availability = value;
    notifyListeners();
  }
}
