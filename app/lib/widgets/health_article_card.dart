import 'package:flutter/material.dart';

import '../models/health_article.dart';

class HealthArticleCard extends StatelessWidget {
  const HealthArticleCard({
    super.key,
    required this.article,
    required this.onTap,
  });

  final HealthArticle article;
  final VoidCallback onTap;

  // Preserve the supplied image pixels and crop only in the card viewport.
  Alignment get _imageAlignment => switch (article.category) {
    HealthCategory.constipation => const Alignment(-0.48, 0),
    HealthCategory.hemorrhoids => Alignment.center,
    HealthCategory.stoolShape => Alignment.centerLeft,
    HealthCategory.stoolColor => const Alignment(-0.08, 0),
  };

  bool get _leftAlignedTitle =>
      article.category == HealthCategory.constipation ||
      article.category == HealthCategory.hemorrhoids;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    onTap: onTap,
    label: '${article.category.label}, ${article.title}',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F2340),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              article.imageAsset,
              fit: BoxFit.cover,
              alignment: _imageAlignment,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFFDCE6F2),
                child: Center(child: Icon(Icons.menu_book_rounded, size: 48)),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.36, 0.65, 1],
                  colors: [
                    Colors.transparent,
                    Color(0x260C1520),
                    Color(0xB8000000),
                  ],
                ),
              ),
            ),
            Align(
              alignment: _leftAlignedTitle
                  ? Alignment.bottomLeft
                  : Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _leftAlignedTitle ? 16 : 10,
                  24,
                  _leftAlignedTitle ? 16 : 10,
                  24,
                ),
                child: Text(
                  article.coverTitle,
                  textAlign: _leftAlignedTitle
                      ? TextAlign.left
                      : TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    letterSpacing: -0.7,
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap),
            ),
          ],
        ),
      ),
    ),
  );
}
