import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'models/health_article.dart';
import 'repositories/restroom_repository.dart';
import 'screens/home_screen.dart';
import 'screens/info_screen.dart';
import 'screens/map_screen.dart';
import 'screens/recommendation_screen.dart';
import 'screens/restroom_detail_screen.dart';
import 'screens/welcome_screen.dart';
import 'state/app_controller.dart';
import 'widgets/location_editor.dart';
import 'widgets/recommendation_tab_icon.dart';

class CatchyToiletApp extends StatefulWidget {
  const CatchyToiletApp({super.key, required this.repository});
  final RestroomRepository repository;

  @override
  State<CatchyToiletApp> createState() => _CatchyToiletAppState();
}

class _CatchyToiletAppState extends State<CatchyToiletApp>
    with WidgetsBindingObserver {
  late final AppController _controller = AppController(widget.repository);
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _startApp() {
    if (_hasStarted) return;
    setState(() => _hasStarted = true);
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasStarted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.resume());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _controller.suspend();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppConfig.appName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: _hasStarted
        ? _AppShell(controller: _controller)
        : WelcomeScreen(onStart: _startApp),
  );
}

class _AppShell extends StatefulWidget {
  const _AppShell({required this.controller});
  final AppController controller;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _selectedIndex = 0;
  int _infoReturnIndex = 0;
  HealthCategory? _infoCategory;

  void _selectInfoCategory(HealthCategory? category) {
    if (_infoCategory == category) return;
    setState(() => _infoCategory = category);
  }

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (index == 2 && _selectedIndex != 2) {
        _infoReturnIndex = _selectedIndex;
      }
      _selectedIndex = index;
    });
  }

  void _openDetail(int id) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RestroomDetailScreen(
            controller: widget.controller,
            restroomId: id,
          ),
        ),
      ),
    );
  }

  Future<void> _changeLocation() async {
    final location = await editLocation(
      context,
      widget.controller.location,
      service: widget.controller.locationService,
    );
    if (!mounted || location == null) return;
    await widget.controller.setLocation(location);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _selectedIndex != 2 || _infoCategory == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _selectedIndex == 2 && _infoCategory != null) {
        _selectInfoCategory(null);
      }
    },
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Scaffold(
        extendBody: _selectedIndex == 0,
        backgroundColor: _selectedIndex == 3
            ? RecommendationScreen.backgroundColor
            : _selectedIndex == 2
            ? InfoScreen.backgroundColor
            : _selectedIndex == 1
            ? HomeScreen.backgroundColor
            : null,
        appBar: _selectedIndex == 0
            ? null
            : AppBar(
                titleSpacing: _selectedIndex == 2 || _selectedIndex == 3
                    ? 8
                    : null,
                centerTitle: false,
                toolbarHeight: _selectedIndex == 2 || _selectedIndex == 3
                    ? 64
                    : null,
                backgroundColor: _selectedIndex == 3
                    ? RecommendationScreen.backgroundColor
                    : _selectedIndex == 2
                    ? InfoScreen.backgroundColor
                    : _selectedIndex == 1
                    ? HomeScreen.backgroundColor
                    : null,
                foregroundColor: Colors.black,
                leading: _selectedIndex == 2
                    ? IconButton(
                        tooltip: _infoCategory == null
                            ? '이전 탭으로 돌아가기'
                            : '정보 목록으로 돌아가기',
                        onPressed: () => _infoCategory == null
                            ? _selectTab(_infoReturnIndex)
                            : _selectInfoCategory(null),
                        icon: const Icon(Icons.arrow_back, size: 28),
                      )
                    : _selectedIndex == 1 || _selectedIndex == 3
                    ? IconButton(
                        tooltip: '지도로 돌아가기',
                        onPressed: () => setState(() => _selectedIndex = 0),
                        icon: const Icon(Icons.arrow_back, size: 28),
                      )
                    : null,
                title: _selectedIndex == 3
                    ? const Text(
                        '추천',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _selectedIndex == 2
                    ? const Text(
                        '정보',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _selectedIndex == 1
                    ? const Text(
                        '화장실 목록',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : const Row(
                        children: [
                          Icon(Icons.wc_rounded),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Catchy Toilet',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
              ),
        body: SafeArea(
          top: _selectedIndex != 0,
          bottom: _selectedIndex != 0,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  MapScreen(
                    controller: widget.controller,
                    onOpenDetail: _openDetail,
                    onChangeLocation: _changeLocation,
                  ),
                  HomeScreen(
                    controller: widget.controller,
                    onOpenDetail: _openDetail,
                  ),
                  InfoScreen(
                    selectedCategory: _infoCategory,
                    onCategoryChanged: _selectInfoCategory,
                  ),
                  RecommendationScreen(
                    controller: widget.controller,
                    onOpenDetail: _openDetail,
                    onChangeLocation: _changeLocation,
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            boxShadow: [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: const Color(0xFFFFFDFE),
                indicatorColor: Colors.transparent,
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? Colors.black
                        : const Color(0xFF808080),
                    size: 30,
                  ),
                ),
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => TextStyle(
                    color: states.contains(WidgetState.selected)
                        ? Colors.black
                        : const Color(0xFF808080),
                    fontSize: 14,
                    fontWeight: states.contains(WidgetState.selected)
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              child: NavigationBar(
                height: _selectedIndex == 0 ? 100 : 80,
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.location_on_outlined),
                    label: '지도',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.checklist_rounded),
                    label: '목록',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.lightbulb_outline_rounded),
                    label: '정보',
                  ),
                  NavigationDestination(
                    icon: RecommendationTabIcon(),
                    label: '추천',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
