import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

const String kWatermarkBrandName = "王记相机";

class WatermarkCameraPage extends StatefulWidget {
  const WatermarkCameraPage({super.key});

  @override
  State<WatermarkCameraPage> createState() => _WatermarkCameraPageState();
}

class _WatermarkCameraPageState extends State<WatermarkCameraPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _capturedImage;
  ui.Image? _renderImage;

  bool _showAddress = true;
  bool _showLatLng = true;
  bool _showWeather = true;
  bool _watermarkAtTop = true;

  String _placeName = "";
  String _note = "";
  // 新增：手动位置，自动定位失败的兜底
  String _manualLocation = "";

  Position? _currentPosition;
  String _netAddress = "";
  String _netWeather = "";

  @override
  void initState() {
    super.initState();
    _fetchLocationInfo();
  }

  // 获取最终显示的地址：有网络自动地址优先，否则读取手动输入
  String get _finalShowAddress {
    if (_netAddress.isNotEmpty) return _netAddress;
    return _manualLocation;
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final res = await Permission.camera.request();
    if (res.isGranted) return true;
    if (res.isPermanentlyDenied && mounted) {
      await _showPermissionDialog("相机权限被拒绝", "请到系统设置开启相机权限");
    }
    return false;
  }

  Future<bool> _requestLocationPermission() async {
    final status = await Permission.location.status;
    if (status.isGranted) return true;
    final res = await Permission.location.request();
    if (res.isGranted) return true;
    if (res.isPermanentlyDenied && mounted) {
      await _showPermissionDialog("定位权限被拒绝", "请到系统设置开启位置权限");
    }
    return false;
  }

  Future<void> _showPermissionDialog(String title, String content) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(ctx);
            },
            child: const Text("去设置"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchLocationInfo() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    final permOk = await _requestLocationPermission();
    if (!permOk) return;

    final cachedPos = await Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);
    if (cachedPos != null) {
      setState(() => _currentPosition = cachedPos);
      _reverseGeo(cachedPos);
      _fetchWeather(cachedPos.latitude, cachedPos.longitude);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
        forceAndroidLocationManager: true,
      );
      setState(() => _currentPosition = pos);
      _reverseGeo(pos);
      _fetchWeather(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  Future<void> _reverseGeo(Position pos) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&accept-language=zh-CN");
      final req = await client.getUrl(uri);
      req.headers.set("User-Agent", "wangji_camera_app");
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final jsonData = json.decode(body);
      final addr = jsonData["address"] ?? {};
      final area = "${addr["province"] ?? ""} ${addr["city"] ?? ""} ${addr["district"] ?? ""}".trim();
      setState(() => _netAddress = area);
      client.close();
    } catch (_) {}
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
          "https://api.open‑meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,wind_speed_10m,wind_direction_10m");
      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final jsonData = json.decode(body);
      final curr = jsonData["current"];
      final temp = curr["temperature_2m"]?.toDouble() ?? 0;
      final windSp = curr["wind_speed_10m"]?.toDouble() ?? 0;
      final windDir = curr["wind_direction_10m"]?.toDouble() ?? 0;
      setState(() {
        _netWeather = "${temp.round()}℃ 风向${windDir.round()}° 风速${windSp.toStringAsFixed(1)}m/s";
      });
      client.close();
    } catch (_) {}
  }

  Future<void> _takePhoto() async {
    final camOk = await _requestCameraPermission();
    if (!camOk) return;
    final file = await _picker.pickImage(source: ImageSource.camera);
    if (file == null) return;
    setState(() => _capturedImage = file);
    await _drawWatermark(file.path);
  }

  Future<void> _drawWatermark(String path) async {
    final bytes = await File(path).readAsBytes();
    final originImg = await decodeImageFromList(bytes);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(originImg, Offset.zero, Paint());

    final double baseW = originImg.width.toDouble();
    double scaleFactor = baseW / 360;

    double fontSizeTime = 22 * scaleFactor;
    double fontSizeNormal = 11 * scaleFactor;
    double lineH = fontSizeNormal * 1.6;
    double padding = 12 * scaleFactor;

    final now = DateTime.now();
    String timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    String dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${["周一","周二","周三","周四","周五","周六","周日"][now.weekday-1]}";

    List<String> lines = [];
    lines.add(timeStr);
    lines.add(dateStr);

    // 使用合并后的最终地址
    if (_showAddress && _finalShowAddress.isNotEmpty) {
      lines.add("地址：$_finalShowAddress");
    }
    if (_showLatLng && _currentPosition != null) {
      lines.add("经纬度：东经${_currentPosition!.longitude.toStringAsFixed(4)}° 北纬${_currentPosition!.latitude.toStringAsFixed(4)}°");
    }
    if (_showWeather && _netWeather.isNotEmpty) {
      lines.add("天气：$_netWeather");
    }
    if (_placeName.isNotEmpty) {
      lines.add("工地：$_placeName");
    }
    if (_note.isNotEmpty) {
      lines.add("备注：$_note");
    }

    double totalH = lines.length * lineH + padding * 2;
    double drawY = _watermarkAtTop ? 0 : (originImg.height.toDouble() - totalH);

    canvas.drawRect(
      Rect.fromLTWH(0, drawY, baseW, totalH),
      Paint()..color = Colors.black.withOpacity(0.55),
    );

    ui.Paragraph buildPara(String text, double fs, bool isBold, double maxWidth) {
      final paraBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.left,
        fontSize: fs,
        fontWeight: isBold ? ui.FontWeight.bold : ui.FontWeight.normal,
      ));
      paraBuilder.pushStyle(ui.TextStyle(
        color: Colors.white,
        shadows: [
          const ui.Shadow(color: Colors.black, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ));
      paraBuilder.addText(text);
      paraBuilder.pop();
      final para = paraBuilder.build();
      para.layout(ui.ParagraphConstraints(width: maxWidth));
      return para;
    }

    double y = drawY + padding;
    for (var s in lines) {
      bool isTime = s == timeStr;
      var p = buildPara(s, isTime ? fontSizeTime : fontSizeNormal, isTime, baseW - padding * 2);
      canvas.drawParagraph(p, Offset(padding, y));
      y += lineH;
    }

    ui.Image outImg = await recorder.endRecording().toImage(originImg.width, originImg.height);
    _renderImage = outImg;
    setState(() {});
  }

  Future<void> _saveImage() async {
    if (_renderImage == null) return;
    final byte = await _renderImage!.toByteData(format: ui.ImageByteFormat.png);
    final arr = byte!.buffer.asUint8List();
    await Gal.putImageBytes(arr, album: kWatermarkBrandName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已保存相册")));
    }
  }

  void _resetCapture() {
    setState(() {
      _capturedImage = null;
      _renderImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("王记水印相机")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_renderImage != null)
              RawImage(image: _renderImage!)
            else
              const SizedBox(height: 180, child: Center(child: Text("拍照后预览图片"))),

            const SizedBox(height:14),

            TextField(
              decoration: const InputDecoration(labelText:"工地 / 地点"),
              onChanged: (v)=>_placeName = v,
            ),
            // =========新增手动位置输入框=========
            TextField(
              decoration: const InputDecoration(labelText:"手动位置（自动定位失败时生效）"),
              onChanged: (v)=>_manualLocation = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText:"备注"),
              onChanged: (v)=>_note = v,
            ),

            const SizedBox(height:12),

            Wrap(
              spacing:8,
              runSpacing:8,
              children: [
                FilterChip(
                  label: const Text("定位地址"),
                  selected: _showAddress,
                  onSelected: (b)=>setState(()=>_showAddress = b),
                ),
                FilterChip(
                  label: const Text("经纬度"),
                  selected: _showLatLng,
                  onSelected: (b)=>setState(()=>_showLatLng = b),
                ),
                FilterChip(
                  label: const Text("天气风向"),
                  selected: _showWeather,
                  onSelected: (b)=>setState(()=>_showWeather = b),
                ),
              ],
            ),

            const SizedBox(height:12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: ()=>setState(()=>_watermarkAtTop = !_watermarkAtTop),
                    child: Text(_watermarkAtTop ? "水印位置：顶部" : "水印位置：底部"),
                  ),
                ),
                const SizedBox(width:8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetCapture,
                    child: const Text("重拍"),
                  ),
                ),
              ],
            ),

            const SizedBox(height:12),

            ElevatedButton(
              onPressed: _takePhoto,
              child: const Text("📷拍照"),
            ),
            const SizedBox(height:8),
            ElevatedButton(
              onPressed: _renderImage!=null ? _saveImage : null,
              child: const Text("💾保存到相册"),
            ),
          ],
        ),
      ),
    );
  }
}
