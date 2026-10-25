enum HealthCategory {
  constipation('변비'),
  hemorrhoids('치질'),
  stoolShape('변모'),
  stoolColor('변색');

  const HealthCategory(this.label);
  final String label;
}

class HealthArticle {
  const HealthArticle({
    required this.id,
    required this.category,
    required this.title,
    required this.coverTitle,
    required this.imageAsset,
    required this.sections,
    this.source,
  });

  final String id;
  final HealthCategory category;
  final String title;
  final String coverTitle;
  final String imageAsset;
  final List<HealthArticleSection> sections;
  final String? source;
}

class HealthArticleSection {
  const HealthArticleSection(this.body, {this.heading});

  final String? heading;
  final String body;
}
