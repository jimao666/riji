import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

// ===================== 常量配置 =====================
const String kWatermarkBrandName = "王记相机";
const String kWatermarkLogoAsset = "assets/app_icon/mingcute_icon.png";

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

  // 定位调试字段
  String _locStatus = "未开始";
  String _permStatus = "-";
  String _cachePosText = "无";
  String _geoReverseStatus = "-";
  String _locErrorMsg = "";

  Position? _currentPosition;
  String _addressText = "";
  String _weatherInfo = "";

  @override
  void initState() {
    super.initState();
    _checkLocationAndFetch();
  }

  // ---------------------- 权限校验 ----------------------
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
    setState(()=>_permStatus = status.name);
    if(status.isGranted) return true;
    final res = await Permission.location.request();
    setState(()=>_permStatus = res.name);
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

  // ---------------------- 定位核心（带调试信息） ----------------------
  Future<void> _checkLocationAndFetch() async {
    setState(() {
      _locStatus = "检测中";
      _locErrorMsg = "";
    });

    bool serviceOk = await Geolocator.isLocationServiceEnabled();
    if(!serviceOk){
      setState((){
        _locStatus = "失败";
        _locErrorMsg = "手机系统定位总开关未打开";
      });
      return;
    }

    bool permOk = await ensureLocationPermission();
    if(!permOk){
      setState((){
        _locStatus = "失败";
        _locErrorMsg = "没有定位权限";
      });
      return;
    }

    // 读取缓存上一次位置
    Position? lastCache = await Geolocator.getLastKnownPosition();
    if(lastCache != null){
      setState((){
        _cachePosText = "${lastCache.latitude.toStringAsFixed(4)},${lastCache.longitude.toStringAsFixed(4)}";
        _currentPosition = lastCache;
      });
      await _reverseGeocode(lastCache);
      await _fetchWeather(lastCache.latitude, lastCache.longitude);
    }else{
      setState(()=>_cachePosText = "无缓存位置");
    }

    // 请求实时位置，放宽精度，超时30秒
    try{
      Position realPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 30)
          )
      );
      setState((){
        _locStatus = "已定位";
        _currentPosition = realPos;
        _cachePosText = "${realPos.latitude.toStringAsFixed(4)},${realPos.longitude.toStringAsFixed(4)}";
      });
      await _reverseGeocode(realPos);
      await _fetchWeather(realPos.latitude, realPos.longitude);
    }catch(e){
      setState((){
        _locStatus = "获取实时位置失败";
        _locErrorMsg = e.toString();
      });
    }
  }

  // 逆地理，使用OpenStreetMap
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
        _addressText = area;
        _geoReverseStatus = "成功";
      });
      client.close();
    }catch(err){
      setState((){
        _geoReverseStatus = "解析地址失败:$err";
      });
    }
  }

  // open‑meteo天气
  Future<void> _fetchWeather(double lat, double lon) async {
    try{
      HttpClient client = HttpClient();
      Uri uri = Uri.parse("https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,wind_speed_10m,wind_direction_10m,weather_code");
      var req = await client.getUrl(uri);
      var resp = await req.close();
      var str = await resp.transform(utf8.decoder).join();
      var js = json.decode(str);
      var curr = js["current"];
      double temp = curr["temperature_2m"]?.toDouble()??0;
      double windSp = curr["wind_speed_10m"]?.toDouble()??0;
      setState(() {
        _weatherInfo = "${temp.round()}℃ 风速${windSp.toStringAsFixed(1)}m/s";
      });
      client.close();
    }catch(e){
      setState(()=>_weatherInfo = "天气获取失败");
    }
  }

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

    // 字号自适应
    double fontSizeTime = 19 * scaleFactor;
    double fontSizeNormal = 10.5 * scaleFactor;
    double fontSizeSmall = 9.5 * scaleFactor;

    final now = DateTime.now();
    String timeStr = "${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}";
    String dateStr = "${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${["周一","周二","周三","周四","周五","周六","周日"][now.weekday-1]}";

    List<String> rightLines = [];
    rightLines.add(timeStr);
    rightLines.add(dateStr);
    if(_showLocation && _addressText.isNotEmpty) rightLines.add(_addressText);
    if(_showWeather && _weatherInfo.isNotEmpty) rightLines.add(_weatherInfo);
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

    // 透明 / 白底切换
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
    // 左侧
    for(var s in leftLines){
      var p = buildPara(s, fontSizeNormal, s==kWatermarkBrandName, false, baseW*0.45);
      canvas.drawParagraph(p, Offset(padding,y));
      y+=lineH;
    }

    y = rectTop + padding;
    // 右侧右对齐
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
            // ========== 定位调试面板 ==========
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.grey.shade200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("📍定位状态: $_locStatus"),
                  Text("🔐权限: $_permStatus"),
                  Text("💾缓存位置: $_cachePosText"),
                  Text("🌐地址解析: $_geoReverseStatus"),
                  Text("⚠️错误: $_locErrorMsg", style: const TextStyle(color: Colors.red)),
                  const SizedBox(height:6),
                  ElevatedButton(onPressed: _checkLocationAndFetch, child: const Text("🔄刷新定位天气"))
                ],
              ),
            ),
            const SizedBox(height:12),
            TextField(
              decoration: const InputDecoration(labelText:"工地名称"),
              onChanged: (v)=>_projectName = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText:"备注"),
              onChanged: (v)=>_noteText = v,
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
