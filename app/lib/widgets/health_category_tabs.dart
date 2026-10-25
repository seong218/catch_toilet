import 'package:flutter/material.dart';

import '../models/health_article.dart';

class HealthCategoryTabs extends StatefulWidget {
  const HealthCategoryTabs({
    super.key,
    required this.selectedCategory,
    required this.onSelected,
  });

  final HealthCategory? selectedCategory;
  final ValueChanged<HealthCategory?> onSelected;

  @override
  State<HealthCategoryTabs> createState() => _HealthCategoryTabsState();
}

class _HealthCategoryTabsState extends State<HealthCategoryTabs> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(HealthCategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      _revealSelection();
    }
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedContext = _selectedKey.currentContext;
      if (mounted && selectedContext != null) {
        Scrollable.ensureVisible(selectedContext, alignment: 0.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
    child: Row(
      children: [
        for (final category in [null, ...HealthCategory.values])
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              key: widget.selectedCategory == category ? _selectedKey : null,
              label: Text(category?.label ?? '전체'),
              selected: widget.selectedCategory == category,
              onSelected: (_) => widget.onSelected(category),
              showCheckmark: false,
              selectedColor: const Color(0xFF2563FF),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 2,
              pressElevation: 1,
              shadowColor: const Color(0x330F2340),
              selectedShadowColor: const Color(0x332563FF),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              labelStyle: TextStyle(
                color: widget.selectedCategory == category
                    ? Colors.white
                    : const Color(0xFF737373),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(),
              side: BorderSide(
                color: widget.selectedCategory == category
                    ? const Color(0xFF2563FF)
                    : const Color(0xFFD1D1D1),
              ),
            ),
          ),
      ],
    ),
  );
}
