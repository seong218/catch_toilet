import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'repositories/api_restroom_repository.dart';
import 'repositories/mock_restroom_repository.dart';
import 'services/api_service.dart';

void main() {
  try {
    runApp(
      CatchToiletApp(
        repository: AppConfig.useMock
            ? MockRestroomRepository()
            : ApiRestroomRepository(ApiService(AppConfig.apiBaseUrl)),
      ),
    );
  } on FormatException {
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '서버 주소 설정을 확인해 주세요.\nAPI_BASE_URL에 올바른 HTTP 또는 HTTPS 주소가 필요합니다.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
