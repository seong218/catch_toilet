class AppConfig {
  static const appName = 'Catch Toilet';
  static const appVersion = '1.0.0';

  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

  // Kakao Maps uses a native app key, never an Admin key or Client Secret.
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
