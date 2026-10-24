import 'package:flutter/material.dart';

import '../services/location_service.dart';

Future<UserLocation?> editLocation(
  BuildContext context,
  UserLocation current,
) => showDialog<UserLocation>(
  context: context,
  builder: (_) => _LocationEditor(current: current),
);

class _LocationEditor extends StatefulWidget {
  const _LocationEditor({required this.current});
  final UserLocation current;

  @override
  State<_LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<_LocationEditor> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.current.label);
  late final _x = TextEditingController(text: '${widget.current.x}');
  late final _y = TextEditingController(text: '${widget.current.y}');

  @override
  void dispose() {
    _label.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  String? _validateCoordinate(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || !number.isFinite ? '유한한 숫자를 입력해 주세요.' : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('기준 위치 설정'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GPS 대신 기준 위치를 사용해요.\n좌표 단위는 미터(m)입니다.'),
            const SizedBox(height: 20),
            TextFormField(
              controller: _label,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '위치 이름'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? '위치 이름을 입력해 주세요.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _x,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'X 좌표 (m)'),
              validator: _validateCoordinate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _y,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Y 좌표 (m)'),
              validator: _validateCoordinate,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            UserLocation(
              label: _label.text.trim(),
              x: double.parse(_x.text.trim()),
              y: double.parse(_y.text.trim()),
            ),
          );
        },
        child: const Text('적용'),
      ),
    ],
  );
}
