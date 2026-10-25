import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/welcome_artwork.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const WelcomeBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final margin = constraints.maxWidth < 360 ? 24.0 : 42.0;
                final contentWidth = math.min(
                  400.0,
                  constraints.maxWidth - margin * 2,
                );
                final emblemSize = math.min(
                  math.min(304.0, contentWidth),
                  constraints.maxHeight * 0.39,
                );
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(margin, 0, margin, 48),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: math.max(24, constraints.maxHeight * 0.21),
                              bottom: 32,
                            ),
                            child: Column(
                              children: [
                                WelcomeEmblem(size: emblemSize),
                                const SizedBox(height: 16),
                                const Text(
                                  'CATCH TOILET',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '화장실의 빈칸을 실시간으로 확인하다.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF777777),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: contentWidth,
                            child: FilledButton(
                              onPressed: onStart,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1F64FE),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(60),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(child: Text('시작하기')),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_rounded, size: 24),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
