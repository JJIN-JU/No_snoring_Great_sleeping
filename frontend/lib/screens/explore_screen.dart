import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  int _mainIndex = 0;
  int _subIndex = 0;

  static const List<String> _mainTabs = [
    '소리',
    '음악',
  ];

  static const Map<String, List<ExploreCategory>> _categories = {
    '소리': [
      ExploreCategory(
        name: '자연',
        description: '자연의 반복적인 소리로 편안한 수면 분위기를 만들어보세요.',
        items: [
          ExploreItem(
            title: '빗소리',
            subtitle: '비 · 자연음',
            query: '수면 빗소리 1시간',
            icon: Icons.water_drop_rounded,
            colors: [Color(0xFF263B5E), Color(0xFF4B6B8C)],
          ),
          ExploreItem(
            title: '비 오는 숲',
            subtitle: '숲 · 빗소리',
            query: '비 오는 숲 소리 수면 1시간',
            icon: Icons.forest_rounded,
            colors: [Color(0xFF1F4E3A), Color(0xFF4B7D5B)],
          ),
          ExploreItem(
            title: '파도',
            subtitle: '바다 · 파도 소리',
            query: '잔잔한 파도 소리 수면 1시간',
            icon: Icons.waves_rounded,
            colors: [Color(0xFF1E4D63), Color(0xFF4C8DA6)],
          ),
          ExploreItem(
            title: '계곡물',
            subtitle: '물소리 · 자연음',
            query: '계곡물 소리 수면 1시간',
            icon: Icons.water_rounded,
            colors: [Color(0xFF1B5B5A), Color(0xFF53A6A2)],
          ),
          ExploreItem(
            title: '바람',
            subtitle: '바람 · 자연음',
            query: '바람 소리 수면 1시간',
            icon: Icons.air_rounded,
            colors: [Color(0xFF34435E), Color(0xFF7D8FB3)],
          ),
          ExploreItem(
            title: '밤벌레',
            subtitle: '밤 · 자연음',
            query: '밤벌레 소리 수면 1시간',
            icon: Icons.nightlight_round,
            colors: [Color(0xFF26304F), Color(0xFF5A6EA8)],
          ),
        ],
      ),
      ExploreCategory(
        name: '생활 소음',
        description: '익숙하고 일정한 생활 소음으로 주변 소리를 부드럽게 덮어보세요.',
        items: [
          ExploreItem(
            title: '선풍기',
            subtitle: '생활 백색소음',
            query: '선풍기 소리 수면 1시간',
            icon: Icons.air_rounded,
            colors: [Color(0xFF3C4658), Color(0xFF818C9D)],
          ),
          ExploreItem(
            title: '에어컨',
            subtitle: '생활 소음',
            query: '에어컨 소리 수면 1시간',
            icon: Icons.ac_unit_rounded,
            colors: [Color(0xFF2F4F68), Color(0xFF7EB3D0)],
          ),
          ExploreItem(
            title: '가습기',
            subtitle: '잔잔한 기계음',
            query: '가습기 소리 수면 1시간',
            icon: Icons.cloud_rounded,
            colors: [Color(0xFF385066), Color(0xFF79A7C2)],
          ),
          ExploreItem(
            title: '기차 안 소리',
            subtitle: '이동 · 백색소음',
            query: '기차 안 소리 수면 1시간',
            icon: Icons.train_rounded,
            colors: [Color(0xFF3B3E58), Color(0xFF7F829E)],
          ),
        ],
      ),
      ExploreCategory(
        name: '감성 ASMR',
        description: '따뜻하고 잔잔한 소리로 잠들기 전 감성을 채워보세요.',
        items: [
          ExploreItem(
            title: '장작',
            subtitle: '불멍 · ASMR',
            query: '장작 타는 소리 수면 ASMR',
            icon: Icons.local_fire_department_rounded,
            colors: [Color(0xFF5E3426), Color(0xFFC2763D)],
          ),
          ExploreItem(
            title: '캠핑장 밤',
            subtitle: '캠핑 · 밤소리',
            query: '캠핑장 밤소리 수면 ASMR',
            icon: Icons.cabin_rounded,
            colors: [Color(0xFF3E352B), Color(0xFF9B7650)],
          ),
          ExploreItem(
            title: '책장 넘기는 소리',
            subtitle: '책 · ASMR',
            query: '책장 넘기는 소리 수면 ASMR',
            icon: Icons.menu_book_rounded,
            colors: [Color(0xFF4D3D5C), Color(0xFF9C79B8)],
          ),
          ExploreItem(
            title: '눈 내리는 밤',
            subtitle: '겨울 · 감성음',
            query: '눈 내리는 밤 소리 수면 ASMR',
            icon: Icons.severe_cold_rounded,
            colors: [Color(0xFF34445E), Color(0xFF9AB5D8)],
          ),
        ],
      ),
      ExploreCategory(
        name: '노이즈',
        description: '일정한 노이즈로 주변 소리를 줄이고 수면 환경을 안정시켜보세요.',
        items: [
          ExploreItem(
            title: '화이트 노이즈',
            subtitle: '밝고 일정한 노이즈',
            query: '화이트 노이즈 수면 1시간',
            icon: Icons.graphic_eq_rounded,
            colors: [Color(0xFF4C4C5A), Color(0xFFA5A5B8)],
          ),
          ExploreItem(
            title: '핑크 노이즈',
            subtitle: '부드러운 노이즈',
            query: '핑크 노이즈 수면 1시간',
            icon: Icons.blur_on_rounded,
            colors: [Color(0xFF5F3F58), Color(0xFFC986B1)],
          ),
          ExploreItem(
            title: '브라운 노이즈',
            subtitle: '낮고 깊은 노이즈',
            query: '브라운 노이즈 수면 1시간',
            icon: Icons.blur_circular_rounded,
            colors: [Color(0xFF3B2C25), Color(0xFF8B6B55)],
          ),
        ],
      ),
    ],
    '음악': [
      ExploreCategory(
        name: '피아노',
        description: '잔잔한 피아노 선율로 잠들기 전 분위기를 차분하게 만들어보세요.',
        items: [
          ExploreItem(
            title: '몽환적 피아노',
            subtitle: '피아노 · 수면 음악',
            query: '몽환적 피아노 수면 음악',
            icon: Icons.piano_rounded,
            colors: [Color(0xFF3B315F), Color(0xFF7863A6)],
          ),
          ExploreItem(
            title: '깊은 수면 피아노',
            subtitle: 'Deep Sleep · Piano',
            query: '깊은 수면 피아노 음악',
            icon: Icons.nightlight_round,
            colors: [Color(0xFF252B4F), Color(0xFF596BB4)],
          ),
          ExploreItem(
            title: '잔잔한 밤 피아노',
            subtitle: '밤 · 피아노',
            query: '잔잔한 밤 피아노 수면 음악',
            icon: Icons.dark_mode_rounded,
            colors: [Color(0xFF2D345C), Color(0xFF6878C2)],
          ),
          ExploreItem(
            title: '빗소리 피아노',
            subtitle: '비 · 피아노',
            query: '빗소리 피아노 수면 음악',
            icon: Icons.water_drop_rounded,
            colors: [Color(0xFF30496C), Color(0xFF708EC6)],
          ),
        ],
      ),
      ExploreCategory(
        name: '힐링',
        description: '부드러운 악기 소리로 긴장을 풀고 편안한 밤을 준비해보세요.',
        items: [
          ExploreItem(
            title: '잔잔한 기타',
            subtitle: '기타 · 힐링',
            query: '잔잔한 기타 수면 음악',
            icon: Icons.music_note_rounded,
            colors: [Color(0xFF5C3D2E), Color(0xFFC08A5A)],
          ),
          ExploreItem(
            title: '오르골 수면 음악',
            subtitle: '오르골 · 감성',
            query: '오르골 수면 음악',
            icon: Icons.auto_awesome_rounded,
            colors: [Color(0xFF493A68), Color(0xFFA385D6)],
          ),
          ExploreItem(
            title: '잔잔한 첼로',
            subtitle: '첼로 · 힐링',
            query: '잔잔한 첼로 수면 음악',
            icon: Icons.music_note_rounded,
            colors: [Color(0xFF563A3A), Color(0xFFB87B7B)],
          ),
          ExploreItem(
            title: '수면 하프 음악',
            subtitle: '하프 · 수면',
            query: '수면 하프 음악',
            icon: Icons.spa_rounded,
            colors: [Color(0xFF39515C), Color(0xFF86B5C5)],
          ),
        ],
      ),
      ExploreCategory(
        name: '명상',
        description: '호흡과 마음을 안정시키는 명상 음악을 찾아보세요.',
        items: [
          ExploreItem(
            title: '호흡 명상 음악',
            subtitle: '호흡 · 명상',
            query: '호흡 명상 음악 수면',
            icon: Icons.self_improvement_rounded,
            colors: [Color(0xFF254B4B), Color(0xFF65A3A0)],
          ),
          ExploreItem(
            title: '마음 안정 음악',
            subtitle: '안정 · 힐링',
            query: '마음 안정 음악 수면',
            icon: Icons.favorite_border_rounded,
            colors: [Color(0xFF4C3B61), Color(0xFFA57BD0)],
          ),
          ExploreItem(
            title: '수면 유도 명상 음악',
            subtitle: '수면 유도 · 명상',
            query: '수면 유도 명상 음악',
            icon: Icons.bedtime_rounded,
            colors: [Color(0xFF273A5E), Color(0xFF6482C1)],
          ),
          ExploreItem(
            title: '싱잉볼 명상 음악',
            subtitle: '싱잉볼 · 명상',
            query: '싱잉볼 명상 음악 수면',
            icon: Icons.radio_button_checked_rounded,
            colors: [Color(0xFF4F3F66), Color(0xFFB194D8)],
          ),
        ],
      ),
      ExploreCategory(
        name: '감성',
        description: '몽환적이고 감성적인 음악으로 편안한 수면 분위기를 만들어보세요.',
        items: [
          ExploreItem(
            title: '로파이 수면 음악',
            subtitle: 'Lo-fi · 편안한 밤',
            query: '로파이 수면 음악',
            icon: Icons.headphones_rounded,
            colors: [Color(0xFF2C3558), Color(0xFF6D78A8)],
          ),
          ExploreItem(
            title: '몽환적 앰비언트',
            subtitle: 'Ambient · Dream',
            query: '몽환적 앰비언트 수면 음악',
            icon: Icons.auto_awesome_rounded,
            colors: [Color(0xFF32305A), Color(0xFF8878D6)],
          ),
          ExploreItem(
            title: '우주 수면 음악',
            subtitle: 'Space · Sleep',
            query: '우주 수면 음악',
            icon: Icons.public_rounded,
            colors: [Color(0xFF1F2B52), Color(0xFF5C6FC4)],
          ),
        ],
      ),
    ],
  };

  Future<void> _openYoutubeSearch(ExploreItem item) async {
    final encodedQuery = Uri.encodeComponent(item.query);

    final uri = Uri.parse(
      'https://www.youtube.com/results?search_query=$encodedQuery',
    );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube를 열 수 없습니다.'),
        ),
      );
    }
  }

  void _changeMainTab(int index) {
    setState(() {
      _mainIndex = index;
      _subIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mainTab = _mainTabs[_mainIndex];
    final categories = _categories[mainTab] ?? const <ExploreCategory>[];
    final selectedCategory = categories[_subIndex];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 10),
          child: Center(
            child: Text(
              '수면 콘텐츠',
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  '원하는 수면 소리와 음악을 분류별로 찾아보세요.\n카드를 누르면 YouTube 검색 결과로 연결됩니다.',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _MainTabSelector(
          tabs: _mainTabs,
          selectedIndex: _mainIndex,
          onChanged: _changeMainTab,
        ),

        const SizedBox(height: 14),

        _SubCategorySelector(
          categories: categories,
          selectedIndex: _subIndex,
          onChanged: (index) {
            setState(() {
              _subIndex = index;
            });
          },
        ),

        const SizedBox(height: 16),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(selectedCategory.name),
              Text(
                selectedCategory.description,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                itemCount: selectedCategory.items.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final item = selectedCategory.items[index];

                  return _ExploreContentCard(
                    item: item,
                    onTap: () => _openYoutubeSearch(item),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ExploreCategory {
  final String name;
  final String description;
  final List<ExploreItem> items;

  const ExploreCategory({
    required this.name,
    required this.description,
    required this.items,
  });
}

class ExploreItem {
  final String title;
  final String subtitle;
  final String query;
  final IconData icon;
  final List<Color> colors;

  const ExploreItem({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.icon,
    required this.colors,
  });
}

class _MainTabSelector extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _MainTabSelector({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final active = selectedIndex == index;

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? const Color(0xFF10142A) : AppColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SubCategorySelector extends StatelessWidget {
  final List<ExploreCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _SubCategorySelector({
    required this.categories,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(categories.length, (index) {
          final active = selectedIndex == index;

          return Padding(
            padding: EdgeInsets.only(
              right: index == categories.length - 1 ? 0 : 8,
            ),
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: active ? AppColors.cardAlt : AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  categories[index].name,
                  style: TextStyle(
                    color: active ? AppColors.foreground : AppColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ExploreContentCard extends StatelessWidget {
  final ExploreItem item;
  final VoidCallback onTap;

  const _ExploreContentCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardAlt,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -10,
                top: -8,
                child: Icon(
                  item.icon,
                  color: item.colors.last.withValues(alpha: 0.22),
                  size: 76,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: item.colors,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      item.icon,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 15.5,
                      height: 1.22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'YouTube 검색',
                        style: TextStyle(
                          color: AppColors.primary.withValues(alpha: 0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}