import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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

  int monthDays = 0;
  double monthTotalHour = 0.0;
  double monthTotalWage = 0.0;

  int selectYear = DateTime.now().year;
  int selectMonth = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  Future<void> loadAllData() async {
    final sp = await SharedPreferences.getInstance();
    final rawRecord = sp.getString("work_record_v4");
    final rawWage = sp.getString("daily_wage");
    if (rawRecord != null) {
      recordList = List<Map<String, dynamic>>.from(json.decode(rawRecord));
    }
    if (rawWage != null) {
      wageCtrl.text = rawWage;
    }
    calcMonthStat();
    setState(() {});
  }

  Future<void> saveRecords() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("work_record_v4", json.encode(recordList));
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
    double dayWage = double.tryParse(wageCtrl.text) ?? 0;
    Set<String> daySet = {};
    double totalH = 0.0;
    for (var r in recordList) {
      final d = DateTime.parse(r["date"]);
      if (d.year == selectYear && d.month == selectMonth) {
        daySet.add(r["date"]);
        totalH += double.parse(r["hour"]);
      }
    }
    monthDays = daySet.length;
    monthTotalHour = totalH;
    monthTotalWage = totalH / 8 * dayWage;
  }

  bool todayHasAutoClock() {
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return recordList.any((item) => item["date"] == todayStr && item["type"] == "auto");
  }

  void autoClock() {
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    if (todayHasAutoClock()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ 今日已经提交全天打卡记录")),
      );
      return;
    }
    final item = {
      "date": todayStr,
      "time": now.toIso8601String(),
      "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
      "hour": "8.00",
      "type": "auto",
    };
    setState(() {
      recordList.add(item);
    });
    saveRecords();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ 全天打卡成功，工时8小时")),
      );
    }
  }

  void manualClock() {
    final h = double.tryParse(hourCtrl.text);
    if (h == null || h <= 0 || h > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ 请输入合法工时（0~24）")),
      );
      return;
    }
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final item = {
      "date": todayStr,
      "time": now.toIso8601String(),
      "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
      "hour": h.toStringAsFixed(2),
      "type": "manual",
    };
    setState(() {
      recordList.add(item);
      hourCtrl.clear();
    });
    saveRecords();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ 手动打卡保存成功")),
      );
    }
  }

  void editRecord(int index) {
    final item = recordList[index];
    final editHourCtrl = TextEditingController(text: item["hour"]);
    final editPlaceCtrl = TextEditingController(text: item["place"]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("修改本条打卡"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editPlaceCtrl,
              decoration: const InputDecoration(labelText: "工地地点"),
            ),
            TextField(
              controller: editHourCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "工时"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              final h = double.tryParse(editHourCtrl.text);
              if (h == null || h <= 0 || h > 24) return;
              setState(() {
                recordList[index]["place"] = editPlaceCtrl.text.trim();
                recordList[index]["hour"] = h.toStringAsFixed(2);
              });
              saveRecords();
              Navigator.pop(ctx);
            },
            child: const Text("保存修改"),
          ),
        ],
      ),
    );
  }

  void deleteItem(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("确定删除这条打卡记录？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                recordList.removeAt(index);
              });
              saveRecords();
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
        title: const Text("清空全部记录"),
        content: const Text("全部记录将永久删除，无法恢复！"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                recordList.clear();
              });
              saveRecords();
            },
            child: const Text("清空全部", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void copyOne(Map<String, dynamic> item) {
    final dt = DateTime.parse(item["time"]);
    String showTime =
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    String txt =
        "日期：${item['date']}\n打卡时间：$showTime\n工地：${item['place']}\n工时：${item['hour']} h";
    Clipboard.setData(ClipboardData(text: txt));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已复制本条")));
  }

  void copyAll() {
    final filterList = recordList.where((r) {
      final d = DateTime.parse(r["date"]);
      return d.year == selectYear && d.month == selectMonth;
    }).toList();
    String buf = "===== $selectYear年$selectMonth月 记工记录 =====\n";
    for (var r in filterList) {
      final dt = DateTime.parse(r["time"]);
      String showTime =
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      buf +=
          "日期：${r['date']}｜打卡：$showTime｜工地：${r['place']}｜工时：${r['hour']}h\n";
    }
    buf += "\n本月出勤天数：$monthDays 天\n总工时：${monthTotalHour.toStringAsFixed(2)} h\n预估工资：${monthTotalWage.toStringAsFixed(2)} 元";
    Clipboard.setData(ClipboardData(text: buf));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("已复制本月全部记录")));
  }

  Future<void> exportFile() async {
    final filterList = recordList.where((r) {
      final d = DateTime.parse(r["date"]);
      return d.year == selectYear && d.month == selectMonth;
    }).toList();
    String buf = "===== $selectYear年$selectMonth月 记工记录 =====\n";
    for (var r in filterList) {
      final dt = DateTime.parse(r["time"]);
      String showTime =
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      buf +=
          "日期：${r['date']}｜打卡：$showTime｜工地：${r['place']}｜工时：${r['hour']}h\n";
    }
    buf += "\n本月出勤天数：$monthDays 天\n总工时：${monthTotalHour.toStringAsFixed(2)} h\n预估工资：${monthTotalWage.toStringAsFixed(2)} 元";
    final dir = await getExternalStorageDirectory();
    if (dir == null) return;
    final file = File("${dir.path}/$selectYear${selectMonth.toString().padLeft(2, '0')}_记工表.txt");
    await file.writeAsString(buf);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ 导出成功：${file.path}")));
    }
  }

  List<Map<String, dynamic>> get filterRecords {
    return recordList.where((r) {
      final d = DateTime.parse(r["date"]);
      return d.year == selectYear && d.month == selectMonth;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("记工打卡"),
        actions: [
          IconButton(onPressed: copyAll, icon: const Icon(Icons.copy_all)),
          IconButton(onPressed: exportFile, icon: const Icon(Icons.download)),
          IconButton(onPressed: clearAll, icon: const Icon(Icons.delete_forever, color: Colors.red)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                Text(
                  "$selectYear 年 $selectMonth 月",
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                ),
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
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      Text(
                        "$monthDays",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Text("出勤天数"),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        "${monthTotalHour.toStringAsFixed(2)} h",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Text("总工时"),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        "${monthTotalWage.toStringAsFixed(2)} 元",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Text("预估工资"),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: wageCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => saveWage(),
              decoration: const InputDecoration(
                labelText: "日工价（8小时工资）",
                hintText: "例如：260",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: placeCtrl,
              decoration: const InputDecoration(
                labelText: "工地/项目地点",
                hintText: "填写工地名称",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: hourCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "手动打卡工时",
                hintText: "半天填4、3.5等",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: autoClock,
                    child: const Text("自动打卡｜全天8h"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: manualClock,
                    child: const Text("手动打卡"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "打卡记录",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filterRecords.isEmpty
                  ? const Center(child: Text("本月暂无打卡记录"))
                  : ListView.builder(
                      itemCount: filterRecords.length,
                      itemBuilder: (ctx, idx) {
                        final item = filterRecords[idx];
                        final realIndex = recordList.indexOf(item);
                        final dt = DateTime.parse(item["time"]);
                        String showTime =
                            "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("日期：${item['date']}"),
                                      Text("打卡时刻：$showTime"),
                                      Text("工地：${item['place']}"),
                                      Text("工时：${item['hour']} h"),
                                      Text(item["type"] == "auto" ? "类型：全天打卡" : "类型：零散工时"),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    IconButton(
                                      onPressed: () => copyOne(item),
                                      icon: const Icon(Icons.copy, size: 20),
                                    ),
                                    IconButton(
                                      onPressed: () => editRecord(realIndex),
                                      icon: const Icon(Icons.edit, size: 20),
                                    ),
                                    IconButton(
                                      onPressed: () => deleteItem(realIndex),
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

