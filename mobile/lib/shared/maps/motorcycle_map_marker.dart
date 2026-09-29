import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<BitmapDescriptor> buildMotorcycleMapMarker({
  Color backgroundColor = const Color(0xFF1976D2),
}) async {
  const canvasSize = 112.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(canvasSize / 2, canvasSize / 2);

  canvas.drawCircle(
    center,
    48,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    43,
    Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill,
  );

  final iconPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(Icons.two_wheeler.codePoint),
      style: TextStyle(
        color: Colors.white,
        fontSize: 55,
        fontFamily: Icons.two_wheeler.fontFamily,
        package: Icons.two_wheeler.fontPackage,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  iconPainter.paint(
    canvas,
    center - Offset(iconPainter.width / 2, iconPainter.height / 2),
  );

  final image = await recorder.endRecording().toImage(
        canvasSize.toInt(),
        canvasSize.toInt(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  }
  return BitmapDescriptor.bytes(
    data.buffer.asUint8List(),
    width: 56,
    height: 56,
  );
}
