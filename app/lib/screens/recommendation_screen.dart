import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/recommendation_result.dart';

class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({
    super.key,
    required this.controller,
    required this.onOpenDetail,
    required this.onChangeLocation,
  });

  final AppController controller;
  final ValueChanged<int> onOpenDetail;
  final VoidCallback onChangeLocation;

  static const backgroundColor = Color(0xFFF2F7FF);
  static const blue = Color(0xFF2563FF);

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  bool _hasRequested = false;
  bool _requesting = false;
  bool _showProgress = false;
  Timer? _progressTimer;

  Future<void> _request() async {
    if (_requesting ||
        (_hasRequested &&
            (widget.controller.recommendationLoading ||
                widget.controller.recommendationLocating))) {
      return;
    }
    setState(() {
      _hasRequested = true;
      _requesting = true;
    });
    // Reserve a small indicator for longer requests; fast responses do not
    // flash a loading state or change the button's label.
    _progressTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showProgress = true);
    });
    try {
      await widget.controller.requestRecommendation();
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() {
          _requesting = false;
          _showProgress = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final busy =
          _requesting ||
          (_hasRequested &&
              (controller.recommendationLoading ||
                  controller.recommendationLocating));
      final narrow = MediaQuery.sizeOf(context).width < 360;
      return ListView(
        key: const PageStorageKey('recommendation'),
        padding: EdgeInsets.fromLTRB(narrow ? 20 : 28, 0, narrow ? 20 : 28, 24),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCFDDF8),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      '화장실 추천 받기',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const _FieldLabel('*성별 선택'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _GenderButton(
                        label: '남자',
                        selected: controller.gender == 'male',
                        onPressed: () => controller.setGender('male'),
                      ),
                    ),
                    SizedBox(width: narrow ? 16 : 32),
                    Expanded(
                      child: _GenderButton(
                        label: '여자',
                        selected: controller.gender == 'female',
                        onPressed: () => controller.setGender('female'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _FieldLabel('*비데 유무'),
                const SizedBox(height: 6),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                    side: const BorderSide(color: Color(0xFFCCCCCC)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SwitchListTile(
                    key: const ValueKey('recommendation-bidet'),
                    value: controller.bidetRequired,
                    onChanged: controller.setBidetRequired,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    dense: true,
                    activeThumbColor: Colors.white,
                    activeTrackColor: RecommendationScreen.blue,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFB9C1CE),
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    title: const Text(
                      '비데 설치 화장실',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  key: const ValueKey('request-recommendation'),
                  onPressed: busy ? null : _request,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black,
                    disabledForegroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    elevation: 3,
                    shadowColor: const Color(0x33000000),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: _showProgress
                            ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const Expanded(
                        child: Text('추천 받기', textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          RecommendationResult(
            controller: controller,
            hasRequested: _hasRequested,
            onOpenDetail: widget.onOpenDetail,
            onRetry: _request,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: widget.onChangeLocation,
            icon: const Icon(Icons.my_location_rounded, size: 18),
            label: Text(
              controller.hasSelectedLocation
                  ? '${controller.location.label} · 위치 변경'
                  : '현재 GPS 위치로 추천 · 위치 변경',
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF667085),
            ),
          ),
        ],
      );
    },
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Color(0xFF929292), fontSize: 13, height: 1.4),
  );
}

class _GenderButton extends StatelessWidget {
  const _GenderButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? RecommendationScreen.blue : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF999999),
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        side: BorderSide(
          color: selected ? RecommendationScreen.blue : const Color(0xFFCCCCCC),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    ),
  );
}
