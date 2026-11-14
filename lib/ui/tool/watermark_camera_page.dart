import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ===== 水印上的品牌信息，想改名字就改这里 =====
const String kWatermarkBrandName = "王记相机";
const String kWatermarkLogoAsset = "assets/app_icon/mingcute_icon.png";

/// 水印相机：拍照后自动在照片上烙上
/// 时间 / 日期星期 / 定位地址 / 经纬度 / 天气风向温度 / logo 品牌
/// 配色与圆角风格跟「记工打卡」页保持一致（主色 0xFF00798C、胶囊按钮、白卡圆角）。
class WatermarkCameraPage extends StatefulWidget {
  const WatermarkCameraPage({super.key, this.initialPlace});

  /// 可从记工页传入当前工地，会自动填进地点框
  final String? initialPlace;

  @override
  State<WatermarkCameraPage> createState() => _WatermarkCameraPageState();
}

class _WatermarkCameraPageState extends State<WatermarkCameraPage> {
  static const Color brand = Color(0xFF00798C);
  static const Color pageBg = Color(0xFFF4F6F7);

  final TextEditingController placeCtrl = TextEditingController();
  final TextEditingController noteCtrl = TextEditingController();
  final GlobalKey repaintKey = GlobalKey();

  File? photoFile;
  int imgWidth = 0;
  int imgHeight = 0;
  double displayWidth = 1.0;

  int posIndex = 0; // 0 左下 1 右下 2 左上 3 右上
  DateTime shotTime = DateTime.now();
  bool saving = false;
  bool loading = false;

  // 定位 / 天气
  double? latitude;
  double? longitude;
  String addressText = "";
  String weatherText = "";
  String windText = "";
  bool locating = false;
  bool weatherFailed = false;

  bool showAddress = true;
  bool showWeather = true;
  bool showLatLng = true;

  static const String placeKey = "wm_camera_place";

  @override
  void initState() {
    super.initState();
    loadLastPlace();
    loadLocationAndWeather();
  }

  @override
  void dispose() {
    placeCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> loadLastPlace() async {
    if (widget.initialPlace != null && widget.initialPlace!.isNotEmpty) {
      placeCtrl.text = widget.initialPlace!;
      return;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getString(placeKey);
      if (saved != null && saved.isNotEmpty) {
        placeCtrl.text = saved;
      }
    } catch (_) {}
  }

  // ===================== 权限 =====================

  /// 相机权限：已授权返回 true；未授权当场申请；被永久拒绝则弹窗引导去设置
  Future<bool> ensureCameraPermission() async {
    try {
      final PermissionStatus status = await Permission.camera.status;
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        await showPermissionDialog(
          "相机权限被拒绝",
          "需要「相机」权限才能拍照打卡。请到系统设置里为本应用打开相机权限。",
        );
        return false;
      }

      final PermissionStatus result = await Permission.camera.request();
      if (result.isGranted) return true;

      if (result.isPermanentlyDenied) {
        await showPermissionDialog(
          "相机权限被拒绝",
          "需要「相机」权限才能拍照打卡。请到系统设置里为本应用打开相机权限。",
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("没有相机权限，无法拍照")),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("权限检查失败：$e")),
        );
      }
      return false;
    }
  }

  /// 定位权限：已授权返回 true；未授权当场申请；被永久拒绝弹窗引导去设置
  Future<bool> ensureLocationPermission() async {
    try {
      final PermissionStatus status = await Permission.locationWhenInUse.status;
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        await showPermissionDialog(
          "定位权限被拒绝",
          "需要「位置信息」权限才能把地址和经纬度印在照片上。请到系统设置里打开。",
        );
        return false;
      }

      final PermissionStatus result =
          await Permission.locationWhenInUse.request();
      if (result.isGranted) return true;

      if (result.isPermanentlyDenied) {
        await showPermissionDialog(
          "定位权限被拒绝",
          "需要「位置信息」权限才能把地址和经纬度印在照片上。请到系统设置里打开。",
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("没有定位权限，水印只显示时间")),
        );
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> showPermissionDialog(String title, String content) async {
    if (!mounted) return;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("我知道了"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("去设置"),
          ),
        ],
      ),
    );
    if (go == true) {
      await openAppSettings();
    }
  }

  // ===================== 定位 =====================

  Future<void> loadLocationAndWeather() async {
    if (locating) return;
    setState(() {
      locating = true;
    });
    try {
      final bool serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) {
          setState(() {
            locating = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("手机定位服务未开启，打开后才能显示地址")),
          );
        }
        return;
      }

      // 定位权限：没授权就当场申请，被永久拒绝弹窗引导去设置
      final bool hasLocationPermission = await ensureLocationPermission();
      if (!hasLocationPermission) {
        return;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      setState(() {
        latitude = pos.latitude;
        longitude = pos.longitude;
      });

      // 反向地理编码（geolocator 14 已移除该接口，改用 OpenStreetMap 免费接口）
      await fetchAddress(pos.latitude, pos.longitude);

      // 天气（open-meteo 免费接口，不需要 key）
      await fetchWeather(pos.latitude, pos.longitude);
    } catch (_) {
      // 定位失败不阻塞拍照
    } finally {
      if (mounted) {
        setState(() {
          locating = false;
        });
      }
    }
  }

  /// 用 OpenStreetMap 免费接口把经纬度换成「省 市 区」中文地址
  Future<void> fetchAddress(double lat, double lon) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse?format=jsonv2"
        "&lat=${lat.toStringAsFixed(6)}"
        "&lon=${lon.toStringAsFixed(6)}"
        "&accept-language=zh-CN&zoom=16",
      );
      final request = await client.getUrl(uri);
      request.headers.set("User-Agent", "Jotsy/0.14 (personal app)");
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> json = jsonDecode(body);
      final Map<String, dynamic> addr =
          Map<String, dynamic>.from((json["address"] ?? {}) as Map);

      String pick(List<String> keys) {
        for (final String k in keys) {
          final dynamic v = addr[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
        return "";
      }

      final List<String> parts = <String>[];
      final String state = pick(["state", "province"]);
      final String city = pick(["city", "town", "county", "municipality"]);
      final String district =
          pick(["suburb", "city_district", "district", "neighbourhood"]);
      if (state.isNotEmpty) parts.add(state);
      if (city.isNotEmpty) parts.add(city);
      if (district.isNotEmpty) parts.add(district);
      final String road = pick(["road", "pedestrian", "footway"]);
      if (parts.isEmpty && road.isNotEmpty) parts.add(road);

      if (mounted && parts.isNotEmpty) {
        setState(() {
          addressText = parts.join(" ");
        });
      }
    } catch (_) {
      // 地址拿不到就只显示经纬度，不影响水印
    } finally {
      client.close(force: true);
    }
  }

  Future<void> fetchWeather(double lat, double lon) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(
        "https://api.open-meteo.com/v1/forecast"
        "?latitude=${lat.toStringAsFixed(4)}"
        "&longitude=${lon.toStringAsFixed(4)}"
        "&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m"
        "&wind_speed_unit=ms"
        "&timezone=auto",
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
            const Duration(seconds: 12),
          );
      final body = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> json = jsonDecode(body);
      final Map<String, dynamic> current =
          Map<String, dynamic>.from(json["current"] as Map);

      final double temp = (current["temperature_2m"] as num).toDouble();
      final int code = (current["weather_code"] as num).toInt();
      final double windSpeed = (current["wind_speed_10m"] as num).toDouble();
      final double windDir = (current["wind_direction_10m"] as num).toDouble();

      if (!mounted) return;
      setState(() {
        weatherText = "${weatherCodeToText(code)} ${temp.round()}℃";
        windText = "${windDirToText(windDir)} ${windLevel(windSpeed)}级";
        weatherFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          weatherFailed = true;
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  String weatherCodeToText(int code) {
    if (code == 0) return "晴";
    if (code == 1) return "晴间多云";
    if (code == 2) return "多云";
    if (code == 3) return "阴";
    if (code == 45 || code == 48) return "雾";
    if (code >= 51 && code <= 55) return "毛毛雨";
    if (code == 56 || code == 57) return "冻毛毛雨";
    if (code == 61) return "小雨";
    if (code == 63) return "中雨";
    if (code == 65) return "大雨";
    if (code == 66 || code == 67) return "冻雨";
    if (code == 71) return "小雪";
    if (code == 73) return "中雪";
    if (code == 75) return "大雪";
    if (code == 77) return "米雪";
    if (code == 80 || code == 81) return "阵雨";
    if (code == 82) return "强阵雨";
    if (code == 85 || code == 86) return "阵雪";
    if (code == 95) return "雷阵雨";
    if (code == 96 || code == 99) return "雷阵雨伴冰雹";
    return "未知";
  }

  String windDirToText(double deg) {
    const List<String> dirs = ["北风", "东北风", "东风", "东南风", "南风", "西南风", "西风", "西北风"];
    final int index = (((deg % 360) / 45).round() % 8);
    return dirs[index];
  }

  int windLevel(double ms) {
    if (ms < 0.3) return 0;
    if (ms < 1.6) return 1;
    if (ms < 3.4) return 2;
    if (ms < 5.5) return 3;
    if (ms < 8.0) return 4;
    if (ms < 10.8) return 5;
    if (ms < 13.9) return 6;
    if (ms < 17.2) return 7;
    if (ms < 20.8) return 8;
    if (ms < 24.5) return 9;
    if (ms < 28.5) return 10;
    if (ms < 32.7) return 11;
    return 12;
  }

  // ===================== 拍照 =====================

  Future<void> takePhoto() async {
    if (loading) return;

    // 先确认相机权限：已授权直接拍，没授权就申请，被永久拒绝弹窗去设置
    final bool hasCameraPermission = await ensureCameraPermission();
    if (!hasCameraPermission) return;

    setState(() {
      loading = true;
    });
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();

      if (!mounted) return;
      setState(() {
        photoFile = File(picked.path);
        imgWidth = w;
        imgHeight = h;
        shotTime = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("打开相机失败：$e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> saveToGallery() async {
    if (saving) return;
    setState(() {
      saving = true;
    });
    try {
      final boundary =
          repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception("画面还没准备好");
      }
      double ratio = displayWidth <= 1 ? 1.0 : imgWidth / displayWidth;
      if (ratio < 1) ratio = 1;
      if (ratio > 4) ratio = 4;

      final ui.Image shot = await boundary.toImage(pixelRatio: ratio);
      final ByteData? data =
          await shot.toByteData(format: ui.ImageByteFormat.png);
      shot.dispose();
      if (data == null) {
        throw Exception("生成图片失败");
      }
      final Uint8List pngBytes = data.buffer.asUint8List();

      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(
          "${tmpDir.path}/wm_${DateTime.now().millisecondsSinceEpoch}.png");
      await tmpFile.writeAsBytes(pngBytes, flush: true);

      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putImage(tmpFile.path, album: "王记相机");

      final place = placeCtrl.text.trim();
      if (place.isNotEmpty) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(placeKey, place);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ 已保存到相册（王记相机）")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("保存失败：$e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  void resetPhoto() {
    setState(() {
      photoFile = null;
      imgWidth = 0;
      imgHeight = 0;
    });
  }

  // ===================== 水印文字 =====================

  String get timeText {
    final h = shotTime.hour.toString().padLeft(2, '0');
    final m = shotTime.minute.toString().padLeft(2, '0');
    final s = shotTime.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  String get dateText {
    const weekText = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
    final y = shotTime.year;
    final m = shotTime.month.toString().padLeft(2, '0');
    final d = shotTime.day.toString().padLeft(2, '0');
    return "$y-$m-$d ${weekText[shotTime.weekday - 1]}";
  }

  String get latLngText {
    if (latitude == null || longitude == null) return "";
    final lat = latitude!;
    final lon = longitude!;
    final latDir = lat >= 0 ? "北纬" : "南纬";
    final lonDir = lon >= 0 ? "东经" : "西经";
    return "$lonDir${lon.abs().toStringAsFixed(4)}° $latDir${lat.abs().toStringAsFixed(4)}°";
  }

  List<Shadow> get textShadow => const [
        Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
        Shadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 0)),
      ];

  Alignment get watermarkAlignment {
    switch (posIndex) {
      case 1:
        return Alignment.bottomRight;
      case 2:
        return Alignment.topLeft;
      case 3:
        return Alignment.topRight;
      default:
        return Alignment.bottomLeft;
    }
  }

  Widget buildWatermark() {
    final place = placeCtrl.text.trim();
    final note = noteCtrl.text.trim();
    final isRight = posIndex == 1 || posIndex == 3;
    final crossAlign =
        isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = isRight ? TextAlign.right : TextAlign.left;

    final List<Widget> lines = [];

    // 1 时间
    lines.add(
      Text(
        timeText,
        style: TextStyle(
          fontSize: 34,
          height: 1.05,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: Colors.white,
          shadows: textShadow,
        ),
      ),
    );
    lines.add(const SizedBox(height: 3));

    // 2 日期 + 星期
    lines.add(
      Text(
        dateText,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          shadows: textShadow,
        ),
      ),
    );

    // 3 定位地址
    if (showAddress && addressText.isNotEmpty) {
      lines.add(const SizedBox(height: 4));
      lines.add(
        Text(
          addressText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 12,
            height: 1.25,
            color: Colors.white,
            shadows: textShadow,
          ),
        ),
      );
    }

    // 4 经纬度
    if (showLatLng && latLngText.isNotEmpty) {
      lines.add(const SizedBox(height: 2));
      lines.add(
        Text(
          latLngText,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            letterSpacing: 0.3,
            color: Colors.white.withValues(alpha: 0.92),
            shadows: textShadow,
          ),
        ),
      );
    }

    // 5 天气 + 风
    if (showWeather && weatherText.isNotEmpty) {
      lines.add(const SizedBox(height: 3));
      lines.add(
        Text(
          windText.isEmpty ? weatherText : "$weatherText  $windText",
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 12,
            height: 1.2,
            color: Colors.white,
            shadows: textShadow,
          ),
        ),
      );
    }

    // 6 工地 / 备注
    if (place.isNotEmpty) {
      lines.add(const SizedBox(height: 5));
      lines.add(
        Text(
          place,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 15,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: textShadow,
          ),
        ),
      );
    }
    if (note.isNotEmpty) {
      lines.add(const SizedBox(height: 3));
      lines.add(
        Text(
          note,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 12,
            height: 1.25,
            color: Colors.white.withValues(alpha: 0.92),
            shadows: textShadow,
          ),
        ),
      );
    }

    // 7 品牌 logo
    lines.add(const SizedBox(height: 9));
    lines.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.asset(
              kWatermarkLogoAsset,
              width: 18,
              height: 18,
              errorBuilder: (ctx, err, stack) => const SizedBox(
                width: 18,
                height: 18,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            kWatermarkBrandName,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.95),
              shadows: textShadow,
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: watermarkAlignment,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: displayWidth > 40 ? displayWidth * 0.76 : 260,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAlign,
            children: lines,
          ),
        ),
      ),
    );
  }

  // ===================== 界面 =====================

  Widget buildPreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: Colors.black,
          child: LayoutBuilder(
            builder: (ctx, cons) {
              double w = cons.maxWidth;
              double h = w * imgHeight / imgWidth;
              if (h > cons.maxHeight) {
                h = cons.maxHeight;
                w = h * imgWidth / imgHeight;
              }
              displayWidth = w;
              return Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          photoFile!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                        buildWatermark(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget buildChipRow() {
    Widget chip(String label, bool on, ValueChanged<bool> onChanged) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: on,
          showCheckmark: false,
          selectedColor: brand.withValues(alpha: 0.14),
          side: BorderSide(
            color: on ? brand : Colors.grey.shade300,
          ),
          labelStyle: TextStyle(
            color: on ? brand : Colors.grey.shade600,
            fontWeight: on ? FontWeight.w600 : FontWeight.normal,
          ),
          shape: const StadiumBorder(),
          onSelected: onChanged,
        ),
      );
    }

    return Wrap(
      children: [
        chip("定位地址", showAddress, (v) {
          setState(() {
            showAddress = v;
          });
        }),
        chip("经纬度", showLatLng, (v) {
          setState(() {
            showLatLng = v;
          });
        }),
        chip("天气风向", showWeather, (v) {
          setState(() {
            showWeather = v;
          });
        }),
      ],
    );
  }

  Widget buildEmptyGuide() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.photo_camera_outlined, size: 40, color: brand),
          ),
          const SizedBox(height: 18),
          Text(
            kWatermarkBrandName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            "时间 · 日期星期 · 地址 · 经纬度 · 天气风向\n一拍完全部烙在照片上",
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, height: 1.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          _statusLine(),
          const SizedBox(height: 20),
          SizedButton(
            onPressed: loading ? null : takePhoto,
            icon: Icons.photo_camera,
            label: loading ? "正在打开相机" : "打开相机拍照",
            primary: true,
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _statusLine() {
    String text;
    IconData icon;
    Color color;
    if (locating && latitude == null) {
      text = "正在获取定位…";
      icon = Icons.gps_fixed;
      color = Colors.grey.shade500;
    } else if (latitude == null) {
      text = "未开启定位（水印只显示时间）";
      icon = Icons.location_off;
      color = Colors.orange.shade700;
    } else if (weatherFailed || weatherText.isEmpty) {
      text = "已定位${addressText.isEmpty ? "" : "：$addressText"}（天气获取失败）";
      icon = Icons.place;
      color = brand;
    } else {
      text = "$addressText  $weatherText  $windText";
      icon = Icons.place;
      color = brand;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
        if (latitude == null || weatherFailed)
          GestureDetector(
            onTap: loadLocationAndWeather,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text("重试",
                  style: TextStyle(
                      fontSize: 12,
                      color: brand,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget buildBottomCard() {
    final hasPhoto = photoFile != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhoto) ...[
            buildChipRow(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: placeCtrl,
                    decoration: _inputDeco("工地 / 地点", "例：中海工地"),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: noteCtrl,
                    decoration: _inputDeco("备注（可空）", "例：刷第二遍"),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedButton(
                    onPressed: () {
                      setState(() {
                        posIndex = (posIndex + 1) % 4;
                      });
                    },
                    icon: Icons.flip,
                    label: "水印位置",
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedButton(
                    onPressed: resetPhoto,
                    icon: Icons.refresh,
                    label: "重拍",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedButton(
              onPressed: saving ? null : saveToGallery,
              icon: saving ? null : Icons.save_alt,
              label: saving ? "保存中…" : "保存到相册",
              primary: true,
              fullWidth: true,
              busy: saving,
            ),
          ] else ...[
            SizedButton(
              onPressed: loading ? null : takePhoto,
              icon: Icons.photo_camera,
              label: loading ? "正在打开相机" : "拍照",
              primary: true,
              fullWidth: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedButton(
                    onPressed: locating ? null : loadLocationAndWeather,
                    icon: Icons.gps_fixed,
                    label: locating ? "定位中…" : "刷新定位天气",
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, String hint) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontSize: 13),
      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: brand, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoFile != null;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Text(kWatermarkBrandName),
        centerTitle: true,
        backgroundColor: pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: hasPhoto ? buildPreview() : buildEmptyGuide(),
              ),
            ),
            buildBottomCard(),
          ],
        ),
      ),
    );
  }
}

/// 统一样式的胶囊按钮（主色实心 / 白底描边两种）
class SizedButton extends StatelessWidget {
  const SizedButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.primary = false,
    this.fullWidth = false,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool primary;
  final bool fullWidth;
  final bool busy;

  static const Color brand = Color(0xFF00798C);

  @override
  Widget build(BuildContext context) {
    final style = primary
        ? ElevatedButton.styleFrom(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            disabledBackgroundColor: brand.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white70,
            elevation: 0,
            minimumSize: const Size(0, 46),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: brand,
            side: BorderSide(color: brand.withValues(alpha: 0.6)),
            minimumSize: const Size(0, 44),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            textStyle: const TextStyle(fontSize: 13),
          );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        else if (icon != null)
          Icon(icon, size: 18),
        if (busy || icon != null) const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final button = primary
        ? ElevatedButton(onPressed: onPressed, style: style, child: content)
        : OutlinedButton(onPressed: onPressed, style: style, child: content);

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
