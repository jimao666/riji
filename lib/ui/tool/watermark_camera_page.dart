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

  bool _showLocation = true;
  bool _showLatLng = true;
  bool _showWeather = true;
  bool _useWhiteBg = false;

  String _projectName = "";
  String _noteText = "";
  String _manualAddress = "";
  String _manualWeather = "";

  Position? _currentPosition;
  String _netAddress = "";
  String _netWeather = "";

  @override
  void initState() {
    super.initState();
    _checkLocationAndFetch();
  }

  Future<bool> ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final req = await Permission.camera.request();
    if (req.isGranted) return true;
    if (req.isPermanentlyDenied && mounted) {
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("相机权限被拒绝"),
            content: const Text("请到系统设置开启相机权限"),
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("取消")),
              TextButton(onPressed: (){openAppSettings();Navigator.pop(context);}, child: const Text("去设置"))
            ],
          ));
    }
    return false;
  }

  Future<bool> ensureLocationPermission() async {
    final status = await Permission.location.status;
    if(status.isGranted) return true;
    final res = await Permission.location.request();
    if(res.isGranted) return true;
    if(res.isPermanentlyDenied && mounted){
      await showDialog(
          context: context,
          builder: (_)=>AlertDialog(
            title: const Text("定位权限被拒绝"),
            content: const Text("请到系统设置开启位置权限"),
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("取消")),
              TextButton(onPressed: (){openAppSettings();Navigator.pop(context);}, child: const Text("去设置"))
            ],
          ));
    }
    return false;
  }

  Future<void> _checkLocationAndFetch() async {
    bool serviceOk = await Geolocator.isLocationServiceEnabled();
    if(!serviceOk) return;
    bool permOk = await ensureLocationPermission();
    if(!permOk) return;

    Position? lastCache = await Geolocator.getLastKnownPosition(forceAndroidLocationManager: true);
    if(lastCache != null){
      setState((){
        _currentPosition = lastCache;
      });
      await _reverseGeocode(lastCache);
      await _fetchOpenMeteoWeather(lastCache.latitude, lastCache.longitude);
    }

    try{
      Position realPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 20)
          ),
          forceAndroidLocationManager: true
      );
      setState((){
        _currentPosition = realPos;
      });
      await _reverseGeocode(realPos);
      await _fetchOpenMeteoWeather(realPos.latitude, realPos.longitude);
    }catch(_){
      // 超时静默，优先使用缓存位置，不弹窗
    }
  }

  Future<void> _reverseGeocode(Position pos) async {
    try{
      HttpClient client = HttpClient();
      final uri = Uri.parse("https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&accept-language=zh-CN");
      final req = await client.getUrl(uri);
      req.headers.set("User-Agent","wangji_camera_app");
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final map = json.decode(body);
      Map address = map["address"]??{};
      String area = "${address["province"]??""} ${address["city"]??""} ${address["district"]??""}".trim();
      setState((){
        _netAddress = area;
      });
      client.close();
    }catch(_){}
  }

  Future<void> _fetchOpenMeteoWeather(double lat, double lon) async {
    try{
      HttpClient client = HttpClient();
      Uri uri = Uri.parse("https://api.open‑meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,wind_speed_10m,wind_direction_10m");
      var req = await client.getUrl(uri);
      var resp = await req.close();
      var str = await resp.transform(utf8.decoder).join();
      var js = json.decode(str);
      var curr = js["current"];
      double temp = curr["temperature_2m"]?.toDouble()??0;
      double windSp = curr["wind_speed_10m"]?.toDouble()??0;
      double windDir = curr["wind_direction_10m"]?.toDouble()??0;
      setState(() {
        _netWeather = "${temp.round()}℃ 风向${windDir.round()}° 风速${windSp.toStringAsFixed(1)}m/s";
      });
      client.close();
    }catch(_){}
  }

  String get _finalAddress => _netAddress.isNotEmpty ? _netAddress : _manualAddress;
  String get _finalWeather => _netWeather.isNotEmpty ? _netWeather : _manualWeather;

  Future<void> _takePhoto() async {
    bool camOk = await ensureCameraPermission();
    if(!camOk) return;
    final file = await _picker.pickImage(source: ImageSource.camera);
    if(file!=null){
      setState(()=>_capturedImage = file);
      await _drawWatermark(file.path);
    }
  }

  Future<void> _drawWatermark(String path) async {
    final data = await File(path).readAsBytes();
    ui.Image origin = await decodeImageFromList(data);
    final recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    canvas.drawImage(origin, Offset.zero, Paint());

    final double baseW = origin.width.toDouble();
    double scaleFactor = baseW / 360;

    double fontSizeTime = 19 * scaleFactor;
    double fontSizeNormal = 10.5 * scaleFactor;

    final now = DateTime.now();
    String timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";
    String dateStr = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${["周一","周二","周三","周四","周五","周六","周日"][now.weekday-1]}";

    List<String> rightLines = [];
    rightLines.add(timeStr);
    rightLines.add(dateStr);
    if(_showLocation && _finalAddress.isNotEmpty) rightLines.add(_finalAddress);
    if(_showWeather && _finalWeather.isNotEmpty) rightLines.add(_finalWeather);
    if(_showLatLng && _currentPosition!=null){
      rightLines.add("东经${_currentPosition!.longitude.toStringAsFixed(4)}° 北纬${_currentPosition!.latitude.toStringAsFixed(4)}°");
    }

    List<String> leftLines = [];
    leftLines.add(kWatermarkBrandName);
    if(_projectName.isNotEmpty) leftLines.add(_projectName);
    if(_noteText.isNotEmpty) leftLines.add(_noteText);

    double lineH = fontSizeTime *1.4;
    double padding = 10 * scaleFactor;
    int maxLineCount = leftLines.length > rightLines.length ? leftLines.length : rightLines.length;
    double totalH = maxLineCount * lineH + padding*2;
    double bottomY = origin.height.toDouble();
    double rectTop = bottomY - totalH;

    if(_useWhiteBg){
      canvas.drawRect(Rect.fromLTWH(0,rectTop,baseW,totalH), Paint()..color=Colors.white.withOpacity(0.85));
    }

    ui.Paragraph buildPara(String text, double fs, bool isBold, bool alignRight, double maxWidth){
      final paraBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: alignRight?ui.TextAlign.right:ui.TextAlign.left,
        fontSize: fs,
        fontWeight: isBold?ui.FontWeight.bold:ui.FontWeight.normal,
      ));
      paraBuilder.pushStyle(ui.TextStyle(
        color: _useWhiteBg?Colors.black:Colors.white,
        shadows: [
          if(!_useWhiteBg) ui.Shadow(color:Colors.black, blurRadius:2, offset:const Offset(1,1))
        ]
      ));
      paraBuilder.addText(text);
      paraBuilder.pop();
      final para = paraBuilder.build();
      para.layout(ui.ParagraphConstraints(width: maxWidth));
      return para;
    }

    double y = rectTop + padding;
    for(var s in leftLines){
      var p = buildPara(s, fontSizeNormal, s==kWatermarkBrandName, false, baseW*0.45);
      canvas.drawParagraph(p, Offset(padding,y));
      y+=lineH;
    }

    y = rectTop + padding;
    for(var s in rightLines){
      var fs = s==timeStr?fontSizeTime:fontSizeNormal;
      var p = buildPara(s, fs, s==timeStr, true, baseW - padding*2);
      canvas.drawParagraph(p, Offset(padding,y));
      y+=lineH;
    }

    ui.Image outImg = await recorder.endRecording().toImage(origin.width, origin.height);
    _renderImage = outImg;
    setState(() {});
  }

  Future<void> saveImage() async {
    if(_renderImage==null) return;
    final byte = await _renderImage!.toByteData(format: ui.ImageByteFormat.png);
    final arr = byte!.buffer.asUint8List();
    await Gal.putImageBytes(arr, album: kWatermarkBrandName);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已保存相册")));
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
            TextField(
              decoration: const InputDecoration(labelText:"工地名称"),
              onChanged: (v)=>_projectName = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText:"备注"),
              onChanged: (v)=>_noteText = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText:"兜底‑手动工地地址(网络差时填写)"),
              onChanged: (v)=>_manualAddress = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText:"兜底‑手动天气(网络差时填写)"),
              onChanged: (v)=>_manualWeather = v,
            ),
            const SizedBox(height:10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text("定位地址"), selected:_showLocation,onSelected:(b)=>setState(()=>_showLocation=b)),
                ChoiceChip(label: const Text("经纬度"), selected:_showLatLng,onSelected:(b)=>setState(()=>_showLatLng=b)),
                ChoiceChip(label: const Text("天气风向"), selected:_showWeather,onSelected:(b)=>setState(()=>_showWeather=b)),
                ChoiceChip(label: Text(_useWhiteBg?"白底":"透明底"), selected:_useWhiteBg,onSelected:(b)=>setState(()=>_useWhiteBg=b)),
              ],
            ),
            const SizedBox(height:12),
            ElevatedButton(onPressed: _takePhoto, child: const Text("📷拍照")),
            const SizedBox(height:12),
            if(_renderImage!=null)
              Column(
                children: [
                  RawImage(image:_renderImage),
                  const SizedBox(height:8),
                  ElevatedButton(onPressed: saveImage, child: const Text("💾保存图片"))
                ],
              )
          ],
        ),
      ),
    );
  }
}
