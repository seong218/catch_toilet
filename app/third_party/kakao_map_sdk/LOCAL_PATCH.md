# Catch Toilet iOS teardown fix

Base: `kakao_map_sdk` **1.3.1**, from its published pub.dev archive.
Archive SHA-256: `01ce4dec9b03d718d5bfcc95f246ea1816af431cdf4fc6172cf49e08981e0987`.
[Upstream repository](https://github.com/gunyu1019/flutter_kakao_maps),
[published package](https://pub.dev/packages/kakao_map_sdk/versions/1.3.1).
The original BSD-3-Clause `LICENSE` is retained. Runtime sources, tests and package metadata are included;
upstream example and documentation assets are omitted. No native SDK binaries are vendored.

## Patch (2026-10-25)

Six local Runner crash reports showed this same path:

```
FlutterEngine.destroyContext
  → FlutterPlatformViewsController deallocation
  → KakaoMapView.deinit
  → KakaoMapController.onMapDestroy
  → FlutterMethodChannel.invokeMethod
  → FlutterEngine.sendOnChannel assertion / SIGABRT
```

`KakaoMapView.deinit` now invokes `disposeWithoutCallback`. Both this path and the
normal `onMapDestroy` path share the existing idempotent cleanup. Only normal,
explicit `finish()` sends the Dart destroy event; native deallocation never sends
to an engine whose lifetime cannot be guaranteed. Delegate/observer removal,
Kakao engine pause/reset and overlay cleanup are preserved.

Changed upstream files:

- `ios/kakao_map_sdk/Sources/kakao_map_sdk/view/KakaoMapView.swift`
- `ios/kakao_map_sdk/Sources/kakao_map_sdk/controller/KakaoMapController.swift`

The app uses a relative path dependency so fresh checkouts receive the same fix.
Do not patch the global Pub cache or generated SPM folders. When upgrading,
compare upstream teardown behavior and repeat real map open → app termination →
relaunch checks before removing this local dependency. App and upstream package
tests do not by themselves cover Flutter engine destruction.
