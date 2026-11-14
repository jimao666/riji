import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class WorkClockPage extends StatefulWidget {
  const WorkClockPage({super.key});

  @override
  State<WorkClockPage> createState() => _WorkClockPageState();
}

class _WorkClockPageState extends State<WorkClockPage> {
  List<Map<String, dynamic>> recordList = [];
  final TextEditingController hourCtrl = TextEditingController();
  final TextEditingController placeCtrl = TextEditingController();
  final TextEditingController wageCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  bool panelExpanded = true;
  int monthDays = 0;
  double monthTotalHour = 0.0;
  double monthTotalWage = 0.0;
  double monthSettledWage = 0.0;
  double monthUnSettledWage = 0.0;
  int selectYear = DateTime.now().year;
  int selectMonth = DateTime.now().month;
  DateTime? selectedDay;
  String? filterPlace;
  String searchText = "";
  List<String> allPlaceList = [];

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    loadAllData();
    searchCtrl.addListener(() {
      setState(() {
        searchText = searchCtrl.text.trim();
      });
    });
  }

  Future<void> loadAllData() async {
    final sp = await SharedPreferences.getInstance();
    final rawRecord = sp.getString("work_record_v8");
    final rawWage = sp.getString("daily_wage");
    if (rawRecord != null) {
      final list = List<Map<String, dynamic>>.from(json.decode(rawRecord));
      for (var item in list) {
        item["isSettled"] ??= false;
      }
      recordList = list;
    }
    if (rawWage != null) {
      wageCtrl.text = rawWage;
    }
    collectPlace();
    calcMonthStat();
    setState(() {});
  }

  void collectPlace() {
    final set = <String>{};
    for (var r in recordList) {
      set.add(r["place"]);
    }
    allPlaceList = set.toList();
  }

  Future<void> saveRecords() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("work_record_v8", json.encode(recordList));
    collectPlace();
    calcMonthStat();
    setState(() {});
  }

  Future<void> saveWage() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("daily_wage", wageCtrl.text.trim());
    calcMonthStat();
    setState(() {});
  }

  void calcMonthStat() {
    final dayWage = double.tryParse(wageCtrl.text) ?? 0;
    if (dayWage > 99999) return;
    final list = getFilterRecords();
    final daySet = <String>{};
    double totalH = 0;
    double settled = 0;
    double unSettled = 0;
    for (var r in list) {
      final d = DateTime.parse(r["date"]);
      daySet.add("${d.year}-${d.month}-${d.day}");
      final h = double.tryParse(r["hour"]) ?? 0;
      totalH += h;
      final w = h / 8 * dayWage;
      if (r["isSettled"] == true) {
        settled += w;
      } else {
        unSettled += w;
      }
    }
    monthDays = daySet.length;
    monthTotalHour = totalH;
    monthTotalWage = settled + unSettled;
    monthSettledWage = settled;
    monthUnSettledWage = unSettled;
  }

  List<Map<String, dynamic>> getFilterRecords() {
    return recordList.where((r) {
      final d = DateTime.parse(r["date"]);
      final matchMonth = d.year == selectYear && d.month == selectMonth;
      final matchPlace = filterPlace == null || r["place"] == filterPlace;
      final matchSearch = searchText.isEmpty || r["place"].toString().contains(searchText);
      return matchMonth && matchPlace && matchSearch;
    }).toList();
  }

  List<Map<String, dynamic>> getDayRecords(DateTime day) {
    final dayStr = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
    return getFilterRecords().where((r) => r["date"] == dayStr).toList();
  }

  Set<String> getHasClockDaySet() {
    final list = getFilterRecords();
    return list.map((r) => r["date"].toString()).toSet();
  }

  bool todayAutoSigned() {
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return recordList.any((i) => i["date"] == todayStr && i["type"] == "全天打卡");
  }

  void autoClock() {
    if (todayAutoSigned()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ 今日已经自动打卡过了")));
      return;
    }
    final now = DateTime.now();
    final item = {
      "date": "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
      "time": now.toIso8601String(),
      "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
      "hour": "8.00",
      "type": "全天打卡",
      "isSettled": false,
    };
    recordList.add(item);
    saveRecords();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 全天打卡成功，工时8h")));
  }

  void manualClock() {
    final h = double.tryParse(hourCtrl.text);
    if (h == null || h <= 0 || h > 24) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ 请输入合法工时（0~24）")));
      return;
    }
    final now = DateTime.now();
    final item = {
      "date": "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
      "time": now.toIso8601String(),
      "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
      "hour": h.toStringAsFixed(2),
      "type": "手动打卡",
      "isSettled": false,
    };
    recordList.add(item);
    hourCtrl.clear();
    saveRecords();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 手动打卡成功")));
  }

  void doRepairSign() async {
    final pickDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 1)),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
    );
    if (pickDate == null) return;
    final repairHourCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("补签：${pickDate.year}-${pickDate.month}-${pickDate.day}"),
        content: TextField(
          controller: repairHourCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: "输入工时，例如 8 / 4"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              final h = double.tryParse(repairHourCtrl.text);
              if (h == null || h <= 0 || h > 24) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("工时无效")));
                return;
              }
              final item = {
                "date": "${pickDate.year}-${pickDate.month.toString().padLeft(2, '0')}-${pickDate.day.toString().padLeft(2, '0')}",
                "time": pickDate.toIso8601String(),
                "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
                "hour": h.toStringAsFixed(2),
                "type": "补签",
                "isSettled": false,
              };
              recordList.add(item);
              saveRecords();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 补签成功")));
            },
            child: const Text("确认补签"),
          ),
        ],
      ),
    );
  }

  void openFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("筛选工地"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text("全部工地"),
                onTap: () {
                  filterPlace = null;
                  calcMonthStat();
                  setState(() {});
                  Navigator.pop(ctx);
                },
                trailing: filterPlace == null ? const Icon(Icons.check, color: Colors.blue) : null,
              ),
              ...allPlaceList.map((p) => ListTile(
                title: Text(p),
                onTap: () {
                  filterPlace = p;
                  calcMonthStat();
                  setState(() {});
                  Navigator.pop(ctx);
                },
                trailing: filterPlace == p ? const Icon(Icons.check, color: Colors.blue) : null,
              )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
        ],
      ),
    );
  }

  void editRecord(int index) {
    final item = recordList[index];
    final editH = TextEditingController(text: item["hour"]);
    final editP = TextEditingController(text: item["place"]);
    bool settled = item["isSettled"] ?? false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (sbCtx, sbSet) {
        return AlertDialog(
          title: const Text("修改打卡记录"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: editP, decoration: const InputDecoration(labelText: "工地地点")),
              TextField(controller: editH, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "工时")),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("工钱已结清"),
                value: settled,
                onChanged: (v) {
                  sbSet(() {
                    settled = v ?? false;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            TextButton(onPressed: () {
              final h = double.tryParse(editH.text);
              if (h == null || h <= 0 || h > 24) return;
              recordList[index]["place"] = editP.text.trim();
              recordList[index]["hour"] = h.toStringAsFixed(2);
              recordList[index]["isSettled"] = settled;
              saveRecords();
              Navigator.pop(ctx);
            }, child: const Text("保存")),
          ],
        );
      }),
    );
  }

  void deleteRecord(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除？"),
        content: const Text("这条记录会被移除"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(onPressed: () {
            recordList.removeAt(index);
            saveRecords();
            Navigator.pop(ctx);
          }, child: const Text("删除", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("清空全部记录？"),
        content: const Text("全部记录无法恢复！建议先备份。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(onPressed: () {
            recordList.clear();
            saveRecords();
            Navigator.pop(ctx);
          }, child: const Text("清空", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  String buildShareText() {
    final list = getFilterRecords();
    var sb = StringBuffer();
    sb.writeln("===== $selectYear年$selectMonth月 记工表 ${filterPlace ?? '全部工地'} =====");
    for (var r in list) {
      final t = DateTime.parse(r["time"]);
      final timeStr = "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
      final settleText = (r["isSettled"] == true) ? "【已结】" : "【未结】";
      sb.writeln("日期：${r["date"]}｜打卡：$timeStr｜工地：${r["place"]}｜工时：${r["hour"]}h｜${r["type"]}$settleText");
    }
    sb.writeln("\n出勤天数：$monthDays 天");
    sb.writeln("总工时：${monthTotalHour.toStringAsFixed(2)} h");
    sb.writeln("预估工资：${monthTotalWage.toStringAsFixed(2)} 元｜已结：${monthSettledWage.toStringAsFixed(2)}｜未结：${monthUnSettledWage.toStringAsFixed(2)} 元");
    return sb.toString();
  }

  void doShare() async {
    final txt = buildShareText();
    await Share.share(txt, subject: "$selectYear年$selectMonth月记工");
  }

  Future<void> exportSelectDir() async {
    final txt = buildShareText();
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final name = "${selectYear}${selectMonth.toString().padLeft(2, '0')}_${filterPlace ?? "全部工地"}_记工.txt";
    final f = File("$dir/$name");
    await f.writeAsString(txt);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ 导出成功：$name")));
    }
  }

  Future<void> backupRecord() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final name = "记工备份_${DateTime.now().millisecondsSinceEpoch}.json";
    final f = File("$dir/$name");
    await f.writeAsString(json.encode(recordList));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅备份完成 $name")));
    }
  }

  Future<void> restoreRecord() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ["json"]);
    if (res == null) return;
    final file = File(res.files.single.path!);
    try {
      final content = await file.readAsString();
      final List<dynamic> importList = json.decode(content);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("恢复备份"),
          content: const Text("选择：覆盖现有记录 / 追加导入"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            TextButton(onPressed: () async {
              recordList.clear();
              recordList.addAll(importList.map((e) => Map<String, dynamic>.from(e)));
              await saveRecords();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅覆盖恢复完成")));
              Navigator.pop(ctx);
            }, child: const Text("覆盖")),
            TextButton(onPressed: () async {
              recordList.addAll(importList.map((e) => Map<String, dynamic>.from(e)));
              await saveRecords();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅追加导入完成")));
              Navigator.pop(ctx);
            }, child: const Text("追加")),
          ],
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌备份文件读取失败")));
    }
  }

  void openSummaryDialog() {
    final group = _groupByDay();
    final placeStat = _groupByPlace();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$selectYear年$selectMonth月 ${filterPlace ?? ''} 汇总"),
        scrollable: true,
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text("出勤：$monthDays 天"),
                        Text("总工时：${monthTotalHour.toStringAsFixed(2)} h"),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing:16,
                      children: [
                        Text("总工资：${monthTotalWage.toStringAsFixed(2)} 元"),
                        Text("已结：${monthSettledWage.toStringAsFixed(2)} 元"),
                        Text("未结：${monthUnSettledWage.toStringAsFixed(2)} 元"),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              const Text("【各工地统计】", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 120,
                child: ListView(
                  children: placeStat.entries.map((entry) {
                    final dSet = entry.value["days"] as Set;
                    return ListTile(
                      dense: true,
                      title: Text(entry.key),
                      subtitle: Text("${dSet.length}天｜${entry.value["hour"].toStringAsFixed(2)}h｜工资${entry.value["wage"].toStringAsFixed(2)}元"),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
              const Text("【按天明细】", style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  shrinkWrap: false,
                  itemCount: group.length,
                  itemBuilder: (dCtx, idx) {
                    final g = group[idx];
                    final week = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][g["dateObj"].weekday - 1];
                    return ExpansionTile(
                      title: Text("${g["dateStr"]} $week｜合计${g["sumHour"].toStringAsFixed(2)}h｜${g["count"]}条"),
                      children: g["items"].map<Widget>((sub) {
                        final dt = DateTime.parse(sub["time"]);
                        final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                        final settleTxt = sub["isSettled"] == true ? "✅已结" : "☐未结";
                        int realIndex = recordList.indexOf(sub);
                        return ListTile(
                          dense: true,
                          title: Text("${sub["place"]}｜${sub["hour"]}h｜$timeStr 【${sub["type"]}】$settleTxt"),
                          trailing: SizedBox(
                            width: 100,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    editRecord(realIndex);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever, size: 18, color: Colors.red),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    deleteRecord(realIndex);
                                  },
                                )
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(onPressed: doShare, icon: const Icon(Icons.share), tooltip: "分享"),
          IconButton(onPressed: exportSelectDir, icon: const Icon(Icons.file_download), tooltip: "导出TXT"),
          IconButton(onPressed: backupRecord, icon: const Icon(Icons.save_alt), tooltip: "备份"),
          IconButton(onPressed: restoreRecord, icon: const Icon(Icons.settings_backup_restore), tooltip: "恢复"),
          IconButton(
            onPressed: () {
              showDialog(context: context, builder: (cctx) => AlertDialog(
                title: const Text("确认清空全部记录？"),
                content: const Text("记录将全部删除，建议先备份！"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(cctx), child: const Text("取消")),
                  TextButton(onPressed: () {
                    Navigator.pop(cctx);
                    Navigator.pop(ctx);
                    clearAll();
                  }, style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text("确认清空"))
                ],
              ));
            },
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: "清空全部",
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _groupByDay() {
    final filter = getFilterRecords();
    final Map<String, List<Map<String, dynamic>>> group = {};
    for (var item in filter) {
      final key = item["date"];
      group.putIfAbsent(key, () => []);
      group[key]!.add(item);
    }
    final res = <Map<String, dynamic>>[];
    for (var entry in group.entries) {
      final day = DateTime.parse(entry.key);
      double sumH = 0;
      for (var i in entry.value) {
        sumH += double.parse(i["hour"]);
      }
      res.add({
        "dateStr": entry.key,
        "dateObj": day,
        "sumHour": sumH,
        "count": entry.value.length,
        "items": entry.value,
      });
    }
    res.sort((a, b) => a["dateObj"].compareTo(b["dateObj"]));
    return res;
  }

  Map<String, Map<String, dynamic>> _groupByPlace() {
    final filter = getFilterRecords();
    final dayWage = double.tryParse(wageCtrl.text) ?? 0;
    if(dayWage>99999) return {};
    final Map<String, Map<String, dynamic>> placeStat = {};
    for (var r in filter) {
      final p = r["place"].toString();
      final dStr = r["date"].toString();
      final h = double.tryParse(r["hour"])??0;
      final w = h / 8 * dayWage;
      placeStat.putIfAbsent(p, () => {"days": <String>{}, "hour": 0.0, "wage": 0.0});
      placeStat[p]!["days"].add(dStr);
      placeStat[p]!["hour"] += h;
      placeStat[p]!["wage"] += w;
    }
    return placeStat;
  }

  Widget buildCalendarGrid() {
    final firstDay = DateTime(selectYear, selectMonth, 1);
    final firstWeekDay = firstDay.weekday;
    final daysInMonth = DateTime(selectYear, selectMonth + 1, 0).day;
    final hasClockDays = getHasClockDaySet();
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month}-${today.day}";
    List<Widget> cells = [];
    const weekTitles = ["一", "二", "三", "四", "五", "六", "日"];
    for (var w in weekTitles) {
      cells.add(
        Expanded(
          child: Center(
            child: Text(w, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          ),
        ),
      );
    }
    for (int i = 1; i < firstWeekDay; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final dayDt = DateTime(selectYear, selectMonth, d);
      final dayKey = "${selectYear}-${selectMonth}-$d";
      final isClock = hasClockDays.contains(dayKey);
      final isSelected = selectedDay?.year == selectYear && selectedDay?.month == selectMonth && selectedDay?.day == d;
      final isToday = dayKey == todayStr;
      cells.add(
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                selectedDay = dayDt;
              });
            },
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00798C)
                          : isClock
                              ? Colors.green.shade200
                              : isToday
                                  ? Colors.blue.shade100
                                  : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "$d",
                      style: TextStyle(
                        fontSize: 15,
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isClock ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text("", style: TextStyle(fontSize: 10, color: Colors.grey))
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180, minHeight:160),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 7,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayRecords = selectedDay == null ? [] : getDayRecords(selectedDay!);
    return Scaffold(
      appBar: AppBar(
        title: const Text("记工打卡"),
        actions: [
          IconButton(
            onPressed: openSummaryDialog,
            tooltip: "月度汇总",
            icon: const Icon(Icons.calendar_view_month),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (selectMonth == 1) {
                        selectMonth = 12;
                        selectYear--;
                      } else {
                        selectMonth--;
                      }
                    });
                    calcMonthStat();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(child: Text("$selectYear 年 $selectMonth 月", textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500))),
                IconButton(
                  onPressed: () {
                    final now = DateTime.now();
                    if (selectYear == now.year && selectMonth == now.month) return;
                    setState(() {
                      if (selectMonth == 12) {
                        selectMonth = 1;
                        selectYear++;
                      } else {
                        selectMonth++;
                      }
                    });
                    calcMonthStat();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: panelExpanded ? "折叠面板" : "展开面板",
                  onPressed: () {
                    setState(() {
                      panelExpanded = !panelExpanded;
                    });
                  },
                  icon: Icon(panelExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                )
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                labelText: "搜索工地",
                hintText: "输入工地名称搜索",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (panelExpanded) ...[
              buildCalendarGrid(),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(children: [Text("$monthDays", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text("出勤天数")]),
                        Column(children: [Text("${monthTotalHour.toStringAsFixed(2)} h", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text("总工时")]),
                        Column(children: [Text("${monthTotalWage.toStringAsFixed(2)} 元", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text("预估工资")]),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing:16,
                      children: [
                        Text("已结:${monthSettledWage.toStringAsFixed(2)}"),
                        Text("未结:${monthUnSettledWage.toStringAsFixed(2)}"),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: wageCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (val) {
                  final num = double.tryParse(val);
                  if(num == null || num <=0 || num > 99999){
                    return;
                  }
                  saveWage();
                },
                decoration: const InputDecoration(
                    labelText: "日工价（8小时工资）",
                    hintText: "例如：260，上限99999",
                    border: OutlineInputBorder()
                ),
              ),
              const SizedBox(height: 10),
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return allPlaceList;
                  return allPlaceList.where((s) => s.contains(textEditingValue.text));
                },
                onSelected: (v) {
                  placeCtrl.text = v;
                },
                fieldViewBuilder: (context, _, focusNode, onSubmit) {
                  return TextField(
                    controller: placeCtrl,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: "工地/项目地点",
                      hintText: "输入，自动弹出历史工地",
                      border: OutlineInputBorder(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hourCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "手动打卡工时", hintText: "半天填4、3.5等", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              // 4个按钮横向一排：自动打卡8H｜手动打卡｜补签｜筛选
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: autoClock,
                      child: const Text("自动打卡8H",maxLines:1,overflow:TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: manualClock,
                      child: const Text("手动打卡",maxLines:1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: Colors.grey.shade200),
                      onPressed: doRepairSign,
                      child: const Text("补签",maxLines:1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: Colors.orange.shade100),
                      onPressed: openFilterDialog,
                      child: const Text("筛选",maxLines:1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text("${selectedDay?.year}-${selectedDay?.month}-${selectedDay?.day} 打卡记录", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            dayRecords.isEmpty
                ? const Padding(padding:EdgeInsets.symmetric(vertical:40),child:Center(child: Text("这一天没有打卡记录")))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dayRecords.length,
                    itemBuilder: (ctx, idx) {
                      final item = dayRecords[idx];
                      final realIdx = recordList.indexOf(item);
                      final dt = DateTime.parse(item["time"]);
                      final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                      final settleTxt = item["isSettled"] == true ? "✅已结" : "☐未结";
                      return ListTile(
                        dense: true,
                        title: Text("${item["place"]} ${item["hour"]}h $settleTxt"),
                        subtitle: Text("$timeStr ${item["type"]}"),
                        trailing: SizedBox(
                          width: 120,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(onPressed: () {
                                Clipboard.setData(ClipboardData(text:
                                    "日期：${item["date"]}\n打卡时刻：$timeStr\n工地：${item["place"]}\n工时：${item["hour"]} h\n类型：${item["type"]}\n结账状态：$settleTxt"));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已复制本条")));
                              }, icon: const Icon(Icons.copy, size: 18)),
                              IconButton(onPressed: () => editRecord(realIdx), icon: const Icon(Icons.edit, size: 18)),
                              IconButton(onPressed: () => deleteRecord(realIdx), icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
