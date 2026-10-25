import '../models/health_article.dart';

// User-supplied text and manually checked transcriptions of 변모양.png / 변색.png.
// These are bundled editorial articles, independent of restroom/sensor API data.
const healthArticles = <HealthArticle>[
  HealthArticle(
    id: 'constipation',
    category: HealthCategory.constipation,
    title: '변비가 고민이신가요?',
    coverTitle: '변비가\n고민이신가요?',
    imageAsset: 'assets/images/info/original-constipation.png',
    sections: [
      HealthArticleSection(
        '변비는 전 인구의 5~20%가 증상을 호소할 만큼 흔한 소화기 질환 중 하나로, 배변 횟수가 3~4일에 한 번 미만이거나, 배변 시 무리한 힘이 필요하거나, 대변이 딱딱하게 굳어 잘 나오지 않거나, 배변 시 시원한 느낌이 들지 않을 경우 ‘변비’로 볼 수 있다. 변비에 걸리면 오랫동안 화장실에 있게 되고, 더부룩함으로 인해 식습관이 불규칙해져 일상생활에 지장을 주게 된다',
      ),
      HealthArticleSection(
        '배변량이 많더라도 배변 횟수가 주 3회 이하이거나 배변 주기가 불규칙하면 ‘이완성 변비’를 의심해야 한다. 이완성 변비란 변이 장 속에 머무르는 시간이 길어져 부피가 작고 단단한 변이 만들어지는 것으로 일반적인 변비와는 달리 변을 보지 않아도 고통스럽지 않다.',
      ),
      HealthArticleSection(
        '이런 증상은 대장의 운동력이 약해져 생기는데, 시간이 지날수록 배가 팽팽해지고 속이 더부룩하며 아랫배 쪽에서 딱딱한 것이 만져지기도 한다. 그 증상이 소화불량과 비슷해 변비로 의심하지 않는 경우가 많다. 이완성 변비는 대장이 노화된 노인들에게 주로 나타나지만, 다이어트, 스트레스로 인해 배변 장애를 겪는 젊은층에도 발생할 수 있다.',
      ),
      HealthArticleSection(
        '적게 먹으면 음식물 찌꺼기도 적기 때문에 대변이 많이 만들어지지 않아서 배출되지 못하고 머물러 있게 된다. 해결책은 먹는 양을 늘리거나, 식이섬유가 많은 식품으로 대체하는 것이다. 식이섬유를 1g 섭취하면 대변량이 2.7g 증가한다는 연구 결과가 있는데, 이는 식이섬유가 장 속 음식물 찌꺼기의 수분을 모으고 부풀어 오르는 성질이 있기 때문이다.',
        heading: '원인 1. 다이어트를 하고 있다.',
      ),
      HealthArticleSection(
        '몸속 수분 부족으로 대변이 딱딱해지는 경우에도 변비가 생긴다. 수분 섭취량 자체가 적은 것도 문제이지만, 커피, 짠 음식, 술 등을 많이 섭취해서 이뇨 작용이 활발해지는 것도 장에는 문제가 된다.',
        heading: '원인 2. 몸속 수분이 부족하다.',
      ),
      HealthArticleSection(
        '특히 식이섬유 식품을 섭취한 후 충분한 물을 마시지 않는다면 식이섬유가 몸속 수분을 모두 끌어들이고 배출돼 수분이 부족한 상태가 된다. 따라서 변비를 해소하기 위해서는 식이섬유 식품의 섭취와 더불어 하루 1.5~2L의 물을 마시는 것이 좋다.',
      ),
      HealthArticleSection(
        '신체 활동량이 적으면 장의 연동 운동 기능이 저하된다. 연동운동 기능이 저하되면 장 속에 대변이 가득 차 있어도 이를 밀어내지 못해서 변비가 생긴다. 이런 경우는 하루 30분~1시간씩 걷는 것이 도움된다.',
        heading: '원인 3. 신체 활동량이 적다.',
      ),
      HealthArticleSection(
        '배변 욕구가 없는데 신문이나 스마트폰 등을 보면서 변기에 앉아 있는 습관 역시 변비를 부추긴다. 변기에 오래 앉아 있으면 장이나 항문이 자극에 둔감해지기 때문이다. 변기는 변을 보고 싶을 때만 앉고 변 보기에 집중해야 하며 앉는 시간이 최대 10분을 넘기지 말아야 한다.',
        heading: '원인 4. 변기에 오래 앉아있는다.',
      ),
      HealthArticleSection(
        '대변을 참는 것도 좋지 않다. 변의가 느껴질 때 참다 보면 배변 반사 기능이 억제돼 직장에 대변이 차 있어도 화장실에 가고 싶은 생각이 들지 않게 된다. 이를 예방하기 위해서는 변의가 느껴지면 30분 안에 배변하는 것이 좋다.',
        heading: '원인 5. 변의를 참는다.',
      ),
      HealthArticleSection(
        '한국건강관리협회 서울강남지부 건강증진의원 김지연 과장은 “변비 예방과 해결을 위해서는 올바른 배변습관이 필요하다. 장이 운동을 시작하는 시간은 아침잠에서 깬 후와 아침 식사 후인데, 이 시간이 배변하기 가장 좋으므로 아침 일정한 시간에 배변하는 습관을 들이는 것이 좋다.”며 “변비가 있다면 변비를 악화시키는 인스턴트식품, 덜 익은 바나나, 연시 등은 적게 먹고, 변을 무르게 하는 고구마, 현미, 오이, 토마토, 해조류 등을 섭취하는 것이 좋다.”고 말했다.',
      ),
    ],
    source: '[출처] 대한민국 정책브리핑(www.korea.kr)',
  ),
  HealthArticle(
    id: 'hemorrhoids',
    category: HealthCategory.hemorrhoids,
    title: '치질이 고민이신가요?',
    coverTitle: '치질이\n고민이신가요?',
    imageAsset: 'assets/images/info/original-hemorrhoids.png',
    sections: [
      HealthArticleSection(
        '치질은 항문 주변의 혈관과 조직에 문제가 생겨 발생하는 질환으로, 주로 잘못된 배변 습관과 생활 습관이 원인이 된다. 특히 변비로 인해 배변할 때 과도하게 힘을 주거나, 화장실에 오랫동안 앉아 있는 습관은 항문 주변 혈관에 압력을 증가시켜 치질을 유발하거나 악화시킬 수 있다.',
      ),
      HealthArticleSection(
        '또한 장시간 앉아서 생활하거나 신체 활동이 부족한 경우에도 치질이 발생할 위험이 높아질 수 있다. 식이섬유와 수분 섭취가 부족하면 변이 딱딱해져 배변이 어려워지고, 이 과정에서 항문에 부담이 가해진다. 반대로 잦은 설사 역시 항문을 자극하여 치질을 악화시킬 수 있다.',
      ),
      HealthArticleSection(
        '이 밖에도 임신, 비만, 노화, 유전적 요인 등이 치질 발생에 영향을 줄 수 있다. 따라서 치질을 예방하기 위해서는 충분한 수분과 식이섬유를 섭취하고, 규칙적으로 운동하며, 화장실에서 오랫동안 앉아 있거나 무리하게 힘을 주는 습관을 피하는 것이 중요하다.',
      ),
    ],
  ),
  HealthArticle(
    id: 'stool-shape',
    category: HealthCategory.stoolShape,
    title: '대변 형태에 따른 건강 지표 분석',
    coverTitle: '대변 형태에 따른\n건강 지표 분석',
    imageAsset: 'assets/images/info/original-stool-shape.png',
    sections: [
      HealthArticleSection(
        '섬유질과 수분섭취가 모두 부족한 상태입니다. 충분한 수분섭취가 필요하며, 과일과 야채를 많이, 충분히 씹어서 드세요. 변비 치료가 필요할 수 있습니다.',
        heading: '작은 변 덩어리들이 분리되어 나오는 경우(토끼똥)',
      ),
      HealthArticleSection(
        '토끼똥 모양보다는 심각하지 않지만 섬유질과 수분이 부족한 상태입니다. 역시 변비 치료가 필요한 상태입니다.',
        heading:
            '소시지처럼 변이 전체적으로 뭉쳐 있기는 하지만 각각의 작은 변 덩어리들이 여전히 확인되며 엉기설기 뭉쳐진 형태',
      ),
      HealthArticleSection(
        '정상적인 대변 형태입니다. 다만 수분섭취가 부족할 수도 있으니 수분 섭취를 조금 더 늘려주세요.',
        heading: '소시지처럼 변이 전체적으로 뭉쳐 있는데 변 표면에 작은 금이 확인되며 약간 표면이 까슬까슬한 형태',
      ),
      HealthArticleSection(
        '이상적인 형태입니다. 이런 모양의 대변을 계속 유지할 수 있게 하세요.',
        heading: '바나나 모양과 같이 변이 모양이 잘 형성되어 있고, 변이 전반적으로 부드럽고 표면이 매끈한 상태',
      ),
      HealthArticleSection(
        '정상적인 대변 형태입니다. 하지만 곧 설사 형태로 발전할 수 있어 식이조절이 필요할 수 있습니다.',
        heading: '방울방울 형태의 변, 약간 변이 무르기는 하지만 변의 가장자리가 잘 구분되는 형태',
      ),
      HealthArticleSection(
        '설사 단계에 진입한 경우로 변 횟수가 많아지거나 복부 불편감이 동반된 경우 진료가 필요할 수 있습니다.',
        heading: '진흙 같은 형태',
      ),
      HealthArticleSection(
        '명확한 설사로, 탈수 증상, 발열, 세균 감염이 의심되는 경우 진료가 필요할 수 있습니다.',
        heading: '덩어리 없이 물만 나오는 변',
      ),
    ],
  ),
  HealthArticle(
    id: 'stool-color',
    category: HealthCategory.stoolColor,
    title: '대변 색조에 따른 건강 지표 분석',
    coverTitle: '대변 색조에 따른\n건강 지표 분석',
    imageAsset: 'assets/images/info/original-stool-color.png',
    sections: [
      HealthArticleSection(
        '정상적인 대변의 색깔은 쓸개에서 만들어지는 쓸개즙 때문에 황갈색을 띱니다. 하지만 가끔 대변의 색깔이 다른 경우가 생길 수도 있습니다.',
      ),
      HealthArticleSection('정상적인 대변색입니다.', heading: '황갈색'),
      HealthArticleSection(
        '대장/직장, 항문 출혈 소견입니다. 치질부터 대장암까지 출혈을 일으킬 수 있는 다양한 질환을 진료를 통해 감별해야 합니다.',
        heading: '붉은색',
      ),
      HealthArticleSection(
        '위나 소장에서 출혈이 있어 피가 소화되면서 어두운 색으로 변하게 됩니다. 철분을 포함한 영양제를 복용하는 경우에도 변 색이 어두워질 수 있습니다. 어지럽거나, 숨이 차거나, 속쓰림과 같은 복부 증상을 동반하는 경우 진료를 보는 것이 좋습니다.',
        heading: '검정색',
      ),
      HealthArticleSection(
        '간에서 만들어지는 소화액인 담즙이 장으로 잘 내려오지 못하는 질환을 의심할 수 있습니다. 간이나 담도를 살펴보기 위한 진료가 필요합니다.',
        heading: '회백색',
      ),
      HealthArticleSection(
        '음식이 장을 너무 빠르게 통과하는 경우, 초록색 야채나 식품색료를 많이 먹은 경우 나타날 수 있습니다.',
        heading: '초록색',
      ),
      HealthArticleSection(
        '대변에 기름기가 많고 냄새가 나는 경우는 대변에 지방이 과도하게 있다는 것입니다. 흡수장애가 동반된 소화기 계통 질환을 생각할 수 있습니다.',
        heading: '노란색',
      ),
    ],
  ),
];
