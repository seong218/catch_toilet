import 'package:flutter/material.dart';

class RestroomListFilters extends StatelessWidget {
  const RestroomListFilters({
    super.key,
    required this.gender,
    required this.accessibleOnly,
    required this.bidetOnly,
    required this.onGenderChanged,
    required this.onAccessibleChanged,
    required this.onBidetChanged,
  });

  final String gender;
  final bool accessibleOnly;
  final bool bidetOnly;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<bool> onAccessibleChanged;
  final ValueChanged<bool> onBidetChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _chip('남자', gender == 'male', () => onGenderChanged('male')),
            const SizedBox(width: 10),
            _chip('여자', gender == 'female', () => onGenderChanged('female')),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _chip('비데', bidetOnly, () => onBidetChanged(!bidetOnly)),
            const SizedBox(width: 10),
            _chip(
              '장애인',
              accessibleOnly,
              () => onAccessibleChanged(!accessibleOnly),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onPressed) =>
      Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(73, 34),
            visualDensity: const VisualDensity(vertical: -2),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            backgroundColor: selected ? const Color(0xFF2864FF) : Colors.white,
            foregroundColor: selected ? Colors.white : const Color(0xFF999999),
            side: selected
                ? BorderSide.none
                : const BorderSide(color: Color(0xFFCCCCCC)),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          child: Text(label),
        ),
      );
}
