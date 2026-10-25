import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class WelcomeBackground extends StatelessWidget {
  const WelcomeBackground({super.key});

  @override
  Widget build(BuildContext context) =>
      const IgnorePointer(child: CustomPaint(painter: _BackgroundPainter()));
}

class WelcomeEmblem extends StatefulWidget {
  const WelcomeEmblem({super.key, required this.size});

  final double size;

  @override
  State<WelcomeEmblem> createState() => _WelcomeEmblemState();
}

class _WelcomeEmblemState extends State<WelcomeEmblem> {
  ImageStream? _stream;
  ImageInfo? _logo;
  late final ImageStreamListener _listener = ImageStreamListener((image, _) {
    setState(() {
      _logo?.dispose();
      _logo = image;
    });
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = const AssetImage(
      'assets/images/branding/logo.png',
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _EmblemPainter(_logo?.image),
    ),
  );
}

// Draw the soft background from 1.png at the current screen size.
class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 402, size.height / 874);
    final glow = Paint()
      ..color = const Color(0xFFC8DFFC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);
    canvas.drawCircle(const Offset(38, 52), 163, glow);
    canvas.drawCircle(const Offset(326, 831), 164, glow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) => false;
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter(this.logo);

  final ui.Image? logo;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 304, size.height / 304);
    const center = Offset(152, 152);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFBCD6FF);
    canvas.drawCircle(center, 151.5, ring);
    canvas.drawCircle(center, 113, ring..color = const Color(0xFF8BAFE7));
    final fill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFC4DAFC), Color(0xFFDDEAFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: 86));
    canvas.drawCircle(center, 86, fill);
    fill.shader = const LinearGradient(
      colors: [Color(0xFFCDE1FB), Color(0xFFE2EDFC)],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(Rect.fromCircle(center: center, radius: 65));
    canvas.drawCircle(center, 65, fill);

    final image = logo;
    if (image != null) {
      const width = 76.0;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(
          center: center,
          width: width,
          height: width * image.height / image.width,
        ),
        Paint()
          ..filterQuality = FilterQuality.high
          // Blend the original PNG's white backing into the blue rings.
          ..blendMode = BlendMode.multiply,
      );
    }

    const blue = Color(0xFF1B72FC);
    const signal = Offset(279, 69);
    canvas.drawCircle(signal, 11, Paint()..color = const Color(0xFFC5DEFF));
    canvas.drawCircle(signal, 7, Paint()..color = const Color(0xFF9FC5FF));
    canvas.drawCircle(signal, 4, Paint()..color = blue);
    canvas.drawCircle(
      signal,
      4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmblemPainter oldDelegate) => oldDelegate.logo != logo;
}
