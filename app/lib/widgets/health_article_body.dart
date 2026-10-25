import 'package:flutter/material.dart';

import '../models/health_article.dart';

class HealthArticleBody extends StatefulWidget {
  const HealthArticleBody({super.key, required this.article});

  final HealthArticle article;

  @override
  State<HealthArticleBody> createState() => _HealthArticleBodyState();
}

class _HealthArticleBodyState extends State<HealthArticleBody> {
  final _scrollController = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            header: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFC5D4F5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Text(
                  widget.article.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: ColoredBox(
              color: Colors.white,
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  key: const ValueKey('health-article-scroll'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final section in widget.article.sections)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (section.heading != null) ...[
                                  Text(
                                    section.heading!,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      height: 1.6,
                                      color: Color(0xFF172B4D),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                  section.body,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.8,
                                    color: Color(0xFF252B37),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (widget.article.source != null)
                          Text(
                            widget.article.source!,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: Color(0xFF667085),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
