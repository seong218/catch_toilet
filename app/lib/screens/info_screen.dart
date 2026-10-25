import 'package:flutter/material.dart';

import '../data/health_articles.dart';
import '../models/health_article.dart';
import '../widgets/health_article_body.dart';
import '../widgets/health_article_card.dart';
import '../widgets/health_category_tabs.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  final HealthCategory? selectedCategory;
  final ValueChanged<HealthCategory?> onCategoryChanged;

  static const backgroundColor = Color(0xFFF2F6FE);

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      HealthCategoryTabs(
        selectedCategory: widget.selectedCategory,
        onSelected: widget.onCategoryChanged,
      ),
      Expanded(
        child: IndexedStack(
          index: widget.selectedCategory == null ? 0 : 1,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(20) / 20;
                final columns = scale > 1.4 || constraints.maxWidth < 300
                    ? 1
                    : 2;
                final width =
                    (constraints.maxWidth - 48 - 12 * (columns - 1)) / columns;
                final height = columns == 1 ? 360.0 * scale : width * 1.65;
                return GridView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                  itemCount: healthArticles.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: height,
                  ),
                  itemBuilder: (context, index) {
                    final article = healthArticles[index];
                    return HealthArticleCard(
                      key: ValueKey(article.id),
                      article: article,
                      onTap: () => widget.onCategoryChanged(article.category),
                    );
                  },
                );
              },
            ),
            if (widget.selectedCategory != null)
              HealthArticleBody(
                key: ValueKey(widget.selectedCategory),
                article: healthArticles.firstWhere(
                  (item) => item.category == widget.selectedCategory,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
