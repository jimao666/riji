import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:convert';
import 'dart:io';

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

  final FocusNode wageFocus = FocusNode();
  final FocusNode searchFocus = FocusNode();

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

  late DateTime _focusedDay;
  late DateTime _selectedCalendarDay;

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    _focusedDay = selectedDay!;
    _selectedCalendarDay = selectedDay!;
    loadAllData();
    searchCtrl.addListener(() {
      setState(() {
        searchText = searchCtrl.text.trim();
        calcMonthStat();
      });
    });
    // 日工价失去焦点时才保存并重算（清空也随之归零）
    wageFocus.addListener(() {
      if (!wageFocus.hasFocus) {
        saveWage();
      }
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
      set.add(r["place"].toString());
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
    if (mounted) setState(() {});
  }

  void calcMonthStat() {
    final dayWage = double.tryParse(wageCtrl.text.trim()) ?? 0;
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
      final matchSearch =
          searchText.isEmpty || r["place"].toString().contains(searchText);
      return matchMonth && matchPlace && matchSearch;
    }).toList();
  }

  /// 全月明细：按日期倒序（最近的一天在最上面）
  List<Map<String, dynamic>> getMonthRecordsDesc() {
    final list = getFilterRecords();
    list.sort((a, b) {
      final da = DateTime.parse(a["date"]);
      final db = DateTime.parse(b["date"]);
      if (da == db) {
        final ta = DateTime.parse(a["time"]);
        final tb = DateTime.parse(b["time"]);
        return tb.compareTo(ta);
      }
      return db.compareTo(da);
    });
    return list;
  }

  List<Map<String, dynamic>> getDayRecords(DateTime day) {
    final targetDateStr =
        "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
    return getFilterRecords().where((r) => r["date"] == targetDateStr).toList();
  }

  Set<String> getHasClockDaySet() {
    final list = getFilterRecords();
    return list.map((r) => r["date"].toString()).toSet();
  }

  bool todayAutoSigned() {
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return recordList.any((i) => i["date"] == todayStr && i["type"] == "全天打卡");
  }

  void autoClock() {
    if (todayAutoSigned()) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("⚠️ 今日已经自动打卡过了")));
      return;
    }
    final now = DateTime.now();
    final item = {
      "date":
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
      "time": now.toIso8601String(),
      "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
      "hour": "8.00",
      "type": "全天打卡",
      "isSettled": false,
    };
    recordList.add(item);
    saveRecords();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("✅ 全天打卡成功，工时8h")));
  }

  void manualClock() async {
    final TextEditingController dialogPlaceCtrl = TextEditingController();
    final TextEditingController dialogHourCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("手动打卡"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return allPlaceList;
                  return allPlaceList
                      .where((s) => s.contains(textEditingValue.text));
                },
                onSelected: (v) {
                  dialogPlaceCtrl.text = v;
                },
                fieldViewBuilder: (context, _, focusNode, onSubmit) {
                  return TextField(
                    controller: dialogPlaceCtrl,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: "工地/项目地点",
                      hintText: "输入，自动弹出历史工地",
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dialogHourCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "工时",
                  hintText: "例如：4 / 3.5 / 8",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              final h = double.tryParse(dialogHourCtrl.text);
              if (h == null || h <= 0 || h > 24) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("⚠️请输入合法工时（0~24）")));
                return;
              }
              final now = DateTime.now();
              final place = dialogPlaceCtrl.text.trim().isEmpty
                  ? "未填写工地"
                  : dialogPlaceCtrl.text.trim();
              final item = {
                "date":
                    "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
                "time": now.toIso8601String(),
                "place": place,
                "hour": h.toStringAsFixed(2),
                "type": "手动打卡",
                "isSettled": false,
              };
              recordList.add(item);
              saveRecords();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("✅手动打卡成功")));
            },
            child: const Text("确认打卡"),
          ),
        ],
      ),
    );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              final h = double.tryParse(repairHourCtrl.text);
              if (h == null || h <= 0 || h > 24) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("工时无效")));
                return;
              }
              final item = {
                "date":
                    "${pickDate.year}-${pickDate.month.toString().padLeft(2, '0')}-${pickDate.day.toString().padLeft(2, '0')}",
                "time": pickDate.toIso8601String(),
                "place": placeCtrl.text.trim().isEmpty
                    ? "未填写工地"
                    : placeCtrl.text.trim(),
                "hour": h.toStringAsFixed(2),
                "type": "补签",
                "isSettled": false,
              };
              recordList.add(item);
              saveRecords();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("✅ 补签成功")));
            },
            child: const Text("确认补签"),
          ),
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
              TextField(
                  controller: editP,
                  decoration: const InputDecoration(labelText: "工地地点")),
              TextField(
                controller: editH,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "工时"),
              ),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () {
                final h = double.tryParse(editH.text);
                if (h == null || h <= 0 || h > 24) return;
                recordList[index]["place"] = editP.text.trim();
                recordList[index]["hour"] = h.toStringAsFixed(2);
                recordList[index]["isSettled"] = settled;
                saveRecords();
                Navigator.pop(ctx);
              },
              child: const Text("保存"),
            ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              recordList.removeAt(index);
              saveRecords();
              Navigator.pop(ctx);
            },
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              recordList.clear();
              saveRecords();
              Navigator.pop(ctx);
            },
            child: const Text("清空", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String buildShareText() {
    final list = getFilterRecords();
    var sb = StringBuffer();
    sb.writeln(
        "===== $selectYear年$selectMonth月 记工表 ${filterPlace ?? '全部工地'} =====");
    for (var r in list) {
      final t = DateTime.parse(r["time"]);
      final timeStr =
          "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
      final settleText = (r["isSettled"] == true) ? "【已结】" : "【未结】";
      sb.writeln(
          "日期：${r["date"]}｜打卡：$timeStr｜工地：${r["place"]}｜工时：${r["hour"]}h｜${r["type"]}$settleText");
    }
    sb.writeln("\n出勤天数：$monthDays 天");
    sb.writeln("总工时：${monthTotalHour.toStringAsFixed(2)} h");
    sb.writeln(
        "预估工资：${monthTotalWage.toStringAsFixed(2)} 元｜已结：${monthSettledWage.toStringAsFixed(2)}｜未结：${monthUnSettledWage.toStringAsFixed(2)} 元");
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
    final name =
        "${selectYear}${selectMonth.toString().padLeft(2, '0')}_${filterPlace ?? "全部工地"}_记工.txt";
    final f = File("$dir/$name");
    await f.writeAsString(txt);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("✅ 导出成功：$name")));
    }
  }

  Future<void> backupRecord() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final name = "记工备份_${DateTime.now().millisecondsSinceEpoch}.json";
    final f = File("$dir/$name");
    await f.writeAsString(json.encode(recordList));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("✅备份完成 $name")));
    }
  }

  Future<void> restoreRecord() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ["json"]);
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () async {
                recordList.clear();
                recordList.addAll(
                    importList.map((e) => Map<String, dynamic>.from(e)));
                await saveRecords();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅覆盖恢复完成")));
                }
                Navigator.pop(ctx);
              },
              child: const Text("覆盖"),
            ),
            TextButton(
              onPressed: () async {
                recordList.addAll(
                    importList.map((e) => Map<String, dynamic>.from(e)));
                await saveRecords();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅追加导入完成")));
                }
                Navigator.pop(ctx);
              },
              child: const Text("追加"),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("❌备份文件读取失败")));
      }
    }
  }

  void jumpToDay(DateTime day) {
    FocusScope.of(context).unfocus();
    setState(() {
      selectedDay = DateTime(day.year, day.month, day.day);
      _selectedCalendarDay = DateTime(day.year, day.month, day.day);
      _focusedDay = DateTime(day.year, day.month, day.day);
      selectYear = day.year;
      selectMonth = day.month;
      calcMonthStat();
    });
  }

  void openSummaryDialog() {
    final group = _groupByDay();
    final placeStat = _groupByPlace();
    final allMonthRecords = getMonthRecordsDesc();
    const weekText = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

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
                      spacing: 16,
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
              const Text("【各工地统计】",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 130,
                child: ListView(
                  children: placeStat.entries.map((entry) {
                    final dSet = entry.value["days"] as Set;
                    return ListTile(
                      dense: true,
                      title: Text(entry.key),
                      subtitle: Text(
                          "${dSet.length}天｜${entry.value["hour"].toStringAsFixed(2)}h｜工资${entry.value["wage"].toStringAsFixed(2)}元"),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
              const Text("【全月打卡明细】点日期可查看当天",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SizedBox(
                height: 260,
                child: allMonthRecords.isEmpty
                    ? const Center(child: Text("本月暂无打卡记录"))
                    : ListView.builder(
                        itemCount: allMonthRecords.length,
                        itemBuilder: (dCtx, idx) {
                          final r = allMonthRecords[idx];
                          final d = DateTime.parse(r["date"]);
                          final t = DateTime.parse(r["time"]);
                          final wt = weekText[d.weekday - 1];
                          final timeStr =
                              "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
                          final settleTxt =
                              r["isSettled"] == true ? "✅已结" : "☐未结";
                          return ListTile(
                            dense: true,
                            onTap: () {
                              Navigator.pop(ctx);
                              jumpToDay(d);
                            },
                            leading: const Icon(Icons.event_note, size: 18),
                            title: Text(
                                "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} $wt",
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                "${r["place"]}｜${r["hour"]}h｜$timeStr｜${r["type"]}｜$settleTxt",
                                style: const TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, size: 16),
                          );
                        },
                      ),
              ),
              const Divider(),
              const Text("【按天分组明细（可点开）】",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 240,
                child: group.isEmpty
                    ? const Center(child: Text("本月暂无打卡记录"))
                    : ListView.builder(
                        itemCount: group.length,
                        itemBuilder: (dCtx, idx) {
                          final g = group[idx];
                          return ExpansionTile(
                            title: Text(
                                "${g["fullDateTitle"]}｜合计${g["sumHour"].toStringAsFixed(2)}h｜${g["count"]}条",
                                style: const TextStyle(fontSize: 13)),
                            children: g["items"].map<Widget>((sub) {
                              final dt = DateTime.parse(sub["time"]);
                              final timeStr =
                                  "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                              final settleTxt =
                                  sub["isSettled"] == true ? "✅已结" : "☐未结";
                              final realIndex = recordList.indexOf(sub);
                              return ListTile(
                                dense: true,
                                title: Text(
                                    "${sub["place"]}｜${sub["hour"]}h｜$timeStr 【${sub["type"]}】$settleTxt",
                                    style: const TextStyle(fontSize: 12)),
                                trailing: SizedBox(
                                  width: 88,
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
                                        icon: const Icon(Icons.delete_forever,
                                            size: 18, color: Colors.red),
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
          IconButton(
              onPressed: exportSelectDir,
              icon: const Icon(Icons.file_download),
              tooltip: "导出TXT"),
          IconButton(
              onPressed: backupRecord,
              icon: const Icon(Icons.save_alt),
              tooltip: "备份"),
          IconButton(
              onPressed: restoreRecord,
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: "恢复"),
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (cctx) => AlertDialog(
                  title: const Text("确认清空全部记录？"),
                  content: const Text("记录将全部删除，建议先备份！"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(cctx),
                        child: const Text("取消")),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(cctx);
                        Navigator.pop(ctx);
                        clearAll();
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("确认清空"),
                    )
                  ],
                ),
              );
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
    const weekText = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
    for (var entry in group.entries) {
      final day = DateTime.parse(entry.key);
      double sumH = 0;
      for (var i in entry.value) {
        sumH += double.parse(i["hour"]);
      }
      final fullTitle =
          "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')} ${weekText[day.weekday - 1]}";
      res.add({
        "dateStr": entry.key,
        "dateObj": day,
        "fullDateTitle": fullTitle,
        "sumHour": sumH,
        "count": entry.value.length,
        "items": entry.value,
      });
    }
    res.sort((a, b) => b["dateObj"].compareTo(a["dateObj"]));
    return res;
  }

  Map<String, Map<String, dynamic>> _groupByPlace() {
    final filter = getFilterRecords();
    final dayWage = double.tryParse(wageCtrl.text.trim()) ?? 0;
    final Map<String, Map<String, dynamic>> placeStat = {};
    for (var r in filter) {
      final p = r["place"].toString();
      final dStr = r["date"].toString();
      final h = double.tryParse(r["hour"]) ?? 0;
      final w = h / 8 * dayWage;
      placeStat.putIfAbsent(p, () => {"days": <String>{}, "hour": 0.0, "wage": 0.0});
      placeStat[p]!["days"].add(dStr);
      placeStat[p]!["hour"] += h;
      placeStat[p]!["wage"] += w;
    }
    return placeStat;
  }

  @override
  Widget build(BuildContext context) {
    final dayRecords = selectedDay == null ? [] : getDayRecords(selectedDay!);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
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
              // 搜索框 + 折叠展开按钮（顶部年月切换那一排已去掉）
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      focusNode: searchFocus,
                      decoration: const InputDecoration(
                        labelText: "搜索工地",
                        hintText: "输入工地名称搜索",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: panelExpanded ? "折叠面板" : "展开面板",
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        panelExpanded = !panelExpanded;
                      });
                    },
                    icon: Icon(
                        panelExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (panelExpanded) ...[
                // 缩小版日历（年月切换在日历头部自己完成）
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: TableCalendar(
                    firstDay: DateTime(2020, 1, 1),
                    lastDay: DateTime(2035, 12, 31),
                    focusedDay: _focusedDay,
                    rowHeight: 36,
                    daysOfWeekHeight: 22,
                    availableCalendarFormats: const {CalendarFormat.month: '月'},
                    selectedDayPredicate: (d) => isSameDay(_selectedCalendarDay, d),
                    onDaySelected: (selDay, focusDay) {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _selectedCalendarDay = selDay;
                        _focusedDay = focusDay;
                        selectedDay = selDay;
                        selectYear = focusDay.year;
                        selectMonth = focusDay.month;
                        calcMonthStat();
                      });
                    },
                    onPageChanged: (focusDay) {
                      setState(() {
                        _focusedDay = focusDay;
                        selectYear = focusDay.year;
                        selectMonth = focusDay.month;
                        calcMonthStat();
                      });
                    },
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      headerPadding:
                          EdgeInsets.symmetric(vertical: 0, horizontal: 6),
                      leftChevronIcon: Icon(Icons.chevron_left, size: 18),
                      rightChevronIcon: Icon(Icons.chevron_right, size: 18),
                      leftChevronVisible: true,
                      rightChevronVisible: true,
                    ),
                    calendarStyle: const CalendarStyle(
                      cellMargin: EdgeInsets.all(1),
                      cellPadding: EdgeInsets.all(1),
                      defaultTextStyle: TextStyle(fontSize: 12),
                      weekendTextStyle: TextStyle(fontSize: 12),
                      selectedTextStyle:
                          TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(fontSize: 10),
                      weekendStyle: TextStyle(fontSize: 10),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (ctx, day, focusedDay) {
                        final key = "${day.year}-${day.month}-${day.day}";
                        if (getHasClockDaySet().contains(key)) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("${day.day}",
                                    style: const TextStyle(fontSize: 12)),
                                const Text("已打卡",
                                    style: TextStyle(
                                        fontSize: 7, color: Colors.green)),
                              ],
                            ),
                          );
                        }
                        return null;
                      },
                      todayBuilder: (ctx, day, focusedDay) {
                        final key = "${day.year}-${day.month}-${day.day}";
                        final hasRecord = getHasClockDaySet().contains(key);
                        return Container(
                          decoration: const BoxDecoration(
                              color: Colors.blueAccent, shape: BoxShape.circle),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("${day.day}",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white)),
                                if (hasRecord)
                                  const Text("已打卡",
                                      style: TextStyle(
                                          fontSize: 7, color: Colors.white)),
                              ],
                            ),
                          ),
                        );
                      },
                      selectedBuilder: (ctx, day, focusedDay) {
                        final key = "${day.year}-${day.month}-${day.day}";
                        final hasRecord = getHasClockDaySet().contains(key);
                        return Container(
                          decoration: const BoxDecoration(
                              color: Color(0xFF00798C), shape: BoxShape.circle),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("${day.day}",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white)),
                                if (hasRecord)
                                  const Text("已打卡",
                                      style: TextStyle(
                                          fontSize: 7, color: Colors.white)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 日历下方统计那一排（已恢复）
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(children: [
                            Text("$monthDays",
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const Text("出勤天数",
                                style: TextStyle(fontSize: 12))
                          ]),
                          Column(children: [
                            Text("${monthTotalHour.toStringAsFixed(2)}h",
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const Text("总工时",
                                style: TextStyle(fontSize: 12))
                          ]),
                          Column(children: [
                            Text("${monthTotalWage.toStringAsFixed(2)}元",
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const Text("预估工资",
                                style: TextStyle(fontSize: 12))
                          ]),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        children: [
                          Text("已结:${monthSettledWage.toStringAsFixed(2)}",
                              style: const TextStyle(fontSize: 12)),
                          Text("未结:${monthUnSettledWage.toStringAsFixed(2)}",
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 一行：日工价 + 工地地点
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: wageCtrl,
                        focusNode: wageFocus,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        onSubmitted: (_) {
                          saveWage();
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: "日工价",
                          hintText: "如260",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: Autocomplete<String>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) return allPlaceList;
                          return allPlaceList
                              .where((s) => s.contains(textEditingValue.text));
                        },
                        onSelected: (v) {
                          placeCtrl.text = v;
                        },
                        fieldViewBuilder: (context, _, focusNode, onSubmit) {
                          return TextField(
                            controller: placeCtrl,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: "工地/项目地点",
                              hintText: "输入自动提示",
                              border: OutlineInputBorder(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 筛选工地
                DropdownButtonFormField<String?>(
                  value: filterPlace,
                  isDense: true,
                  decoration: const InputDecoration(
                      isDense: true,
                      labelText: "筛选工地",
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("全部工地")),
                    ...allPlaceList.map((e) => DropdownMenuItem(value: e, child: Text(e))),
                  ],
                  onChanged: (v) {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      filterPlace = v;
                    });
                    calcMonthStat();
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: autoClock,
                        child: const Text("自动打卡 8H",
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: manualClock,
                        child: const Text("手动打卡", maxLines: 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.grey.shade200),
                        onPressed: doRepairSign,
                        child: const Text("补签", maxLines: 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Text(
                  "${selectedDay?.year}-${selectedDay?.month}-${selectedDay?.day} 打卡记录",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              dayRecords.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text("这一天没有打卡记录")))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: dayRecords.length,
                      itemBuilder: (ctx, idx) {
                        final item = dayRecords[idx];
                        final realIdx = recordList.indexOf(item);
                        final dt = DateTime.parse(item["time"]);
                        final timeStr =
                            "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                        final settleTxt = item["isSettled"] == true ? "✅已结" : "☐未结";
                        return ListTile(
                          dense: true,
                          title: Text(
                              "${item["place"]} ${item["hour"]}h 【${item["type"]}】 $settleTxt"),
                          subtitle: Text(timeStr),
                          trailing: SizedBox(
                            width: 120,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(
                                        text:
                                            "日期：${item["date"]}\n打卡时刻：$timeStr\n工地：${item["place"]}\n工时：${item["hour"]} h\n类型：${item["type"]}\n结账状态：$settleTxt"));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("已复制本条")));
                                  },
                                  icon: const Icon(Icons.copy, size: 18),
                                ),
                                IconButton(
                                  onPressed: () => editRecord(realIdx),
                                  icon: const Icon(Icons.edit, size: 18),
                                ),
                                IconButton(
                                  onPressed: () => deleteRecord(realIdx),
                                  icon: const Icon(Icons.delete_forever,
                                      color: Colors.red, size: 18),
                                ),
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
      ),
    );
  }
}
