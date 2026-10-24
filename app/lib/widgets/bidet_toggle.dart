import 'package:flutter/material.dart';

class BidetToggle extends StatelessWidget {
  const BidetToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: const Text('비데 있는 칸만 추천'),
      subtitle: const Text('사용 가능한 비데 칸을 찾아요'),
      secondary: const Icon(Icons.water_drop_outlined),
      value: value,
      onChanged: onChanged,
    ),
  );
}
