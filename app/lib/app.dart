import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'repositories/restroom_repository.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/restroom_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_controller.dart';
import 'widgets/location_editor.dart';

class CatchyToiletApp extends StatefulWidget {
  const CatchyToiletApp({super.key, required this.repository});
  final RestroomRepository repository;

  @override
  State<CatchyToiletApp> createState() => _CatchyToiletAppState();
}

class _CatchyToiletAppState extends State<CatchyToiletApp>
    with WidgetsBindingObserver {
  late final AppController _controller = AppController(widget.repository);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    home: _AppShell(controller: _controller),
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
    final location = await editLocation(context, widget.controller.location);
    if (!mounted || location == null) return;
    await widget.controller.setLocation(location);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Row(
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                HomeScreen(
                  controller: widget.controller,
                  onOpenDetail: _openDetail,
                  onChangeLocation: _changeLocation,
                ),
                MapScreen(
                  controller: widget.controller,
                  onOpenDetail: _openDetail,
                  onChangeLocation: _changeLocation,
                ),
                SettingsScreen(
                  controller: widget.controller,
                  onChangeLocation: _changeLocation,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: '지도',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '설정',
          ),
        ],
      ),
    ),
  );
}
