import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';

class WorkClockPage extends StatefulWidget {
  const WorkClockPage({super.key});

  @override
  State<WorkClockPage> createState() => _WorkClockPageState();
}

class _WorkClockPageState extends State<WorkClockPage> {
  List<Map<String, dynamic>> recordList = [];
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
  bool foldBelowCalendar = false; // 控制：日历下方全部折叠，只保留打卡记录

  final TextEditingController wageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    loadAllData();
  }

  Future<void> loadAllData() async {
    final sp = await SharedPreferences.getInstance();
    final rawRecord = sp.getString("work_record_v8");
    if (rawRecord != null) {
      final list = List<Map<String, dynamic>>.from(json.decode(rawRecord));
      for (var item in list) {
        item["isSettled"] ??= false;
      }
      recordList = list;
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

  void calcMonthStat() {
    final list = getFilterRecords();
    final daySet = <String>{};
    double totalH = 0;
    double settled = 0;
    double unSettled = 0;
    for (var r in list) {
      final d = DateTime.parse(r["date"]);
      daySet.add("${d.year}-${d.month}-${d.day}");
      final h = double.tryParse(r["hour"]) ?? 0;
      final dayWage = double.tryParse(r["dayWage"] ?? "0") ?? 0;
      final w = h / 8 * dayWage;
      totalH += h;
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
      return matchMonth && matchPlace;
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

  void autoClock() async {
    if (todayAutoSigned()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ 今日已经自动打卡过了")));
      return;
    }
    final placeCtrl = TextEditingController();
    final dayWage = double.tryParse(wageCtrl.text) ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("自动打卡 8H"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: placeCtrl,
              decoration: const InputDecoration(labelText: "工地/项目地点", hintText: "填写工地"),
            ),
            Text("当前日工价：$dayWage", style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              final item = {
                "date": "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
                "time": now.toIso8601String(),
                "place": placeCtrl.text.trim().isEmpty ? "未填写工地" : placeCtrl.text.trim(),
                "hour": "8.00",
                "dayWage": dayWage.toString(),
                "type": "全天打卡",
                "isSettled": false,
              };
              recordList.add(item);
              saveRecords();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 全天打卡成功，工时8h")));
            },
            child: const Text("确认打卡"),
          ),
        ],
      ),
    );
  }

  void manualClock() {
    final placeCtrl = TextEditingController();
    final hourCtrl = TextEditingController();
    final dayWage = double.tryParse(wageCtrl.text) ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("手动打卡"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: placeCtrl,
              decoration: const InputDecoration(labelText: "工地/项目地点", hintText: "填写工地"),
            ),
            TextField(
              controller: hourCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "工时", hintText: "例如：4、3.5"),
            ),
            Text("当前日工价：$dayWage", style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
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
                "dayWage": dayWage.toString(),
                "type": "手动打卡",
                "isSettled": false,
              };
              recordList.add(item);
              saveRecords();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 手动打卡成功")));
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
    final repairPlaceCtrl = TextEditingController();
    final repairHourCtrl = TextEditingController();
    final dayWage = double.tryParse(wageCtrl.text) ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("补签：${pickDate.year}-${pickDate.month}-${pickDate.day}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repairPlaceCtrl,
              decoration: const InputDecoration(labelText: "工地/项目地点"),
            ),
            TextField(
              controller: repairHourCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "输入工时"),
            ),
            Text("当前日工价：$dayWage", style: const TextStyle(color: Colors.grey)),
          ],
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
                "place": repairPlaceCtrl.text.trim().isEmpty ? "未填写工地" : repairPlaceCtrl.text.trim(),
                "hour": h.toStringAsFixed(2),
                "dayWage": dayWage.toString(),
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

  // 和showDatePicker风格一致的日历
  Widget buildCalendar() {
    final DateTime firstDayOfMonth = DateTime(selectYear, selectMonth, 1);
    final int firstWeekday = firstDayOfMonth.weekday;
    final int daysCount = DateTime(selectYear, selectMonth + 1, 0).day;
    final Set<String> clockDays = getHasClockDaySet();

    List<Widget> dayItems = [];
    for (int i = 1; i < firstWeekday; i++) {
      dayItems.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysCount; d++) {
      final dateKey = "$selectYear-${selectMonth.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}";
      final bool selected = selectedDay?.year == selectYear && selectedDay?.month == selectMonth && selectedDay?.day == d;
      final bool hasRecord = clockDays.contains(dateKey);
      dayItems.add(
        InkWell(
          onTap: () {
            setState(() {
              selectedDay = DateTime(selectYear, selectMonth, d);
            });
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).primaryColor
                  : hasRecord
                      ? Colors.green.shade100
                      : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  "$d",
                  style: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 14),
                ),
                if (hasRecord && !selected)
                  const Positioned(bottom: 0, child: Icon(Icons.check, size: 8, color: Colors.green)),
              ],
            ),
          ),
        ),
      );
    }
    while (dayItems.length % 7 != 0) {
      dayItems.add(const SizedBox.shrink());
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    if (selectMonth == 1) {
                      selectYear--;
                      selectMonth = 12;
                    } else {
                      selectMonth--;
                    }
                  });
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Text("$selectYear 年 $selectMonth 月", style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (selectMonth == 12) {
                      selectYear++;
                      selectMonth = 1;
                    } else {
                      selectMonth++;
                    }
                  });
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text("一"), Text("二"), Text("三"), Text("四"), Text("五"), Text("六"), Text("日"),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            children: dayItems,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("记工打卡")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(hintText: "搜索工地", prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                searchText = v;
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            buildCalendar(),
            const SizedBox(height: 8),

            // 折叠按钮放在汇总右上角，点它：日历下面全部折叠，只留打卡记录
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      foldBelowCalendar = !foldBelowCalendar;
                    });
                  },
                  icon: Icon(foldBelowCalendar ? Icons.expand_more : Icons.expand_less),
                ),
              ],
            ),

            if (!foldBelowCalendar)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.lightBlue.shade50, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(children: [
                              Text("$monthDays", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                              const Text("出勤天数")
                            ]),
                            Column(children: [
                              Text("${monthTotalHour.toStringAsFixed(2)} h", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                              const Text("总工时")
                            ]),
                            Column(children: [
                              Text("${monthTotalWage.toStringAsFixed(2)} 元", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                              const Text("预估工资")
                            ]),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text("已结:${monthSettledWage.toStringAsFixed(2)}    未结:${monthUnSettledWage.toStringAsFixed(2)}"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: wageCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "日工价（8小时工资）"),
                    onChanged: (_) => calcMonthStat(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(onPressed: autoClock, child: const Text("自动打卡 8H"))),
                      const SizedBox(width: 6),
                      Expanded(child: ElevatedButton(onPressed: manualClock, child: const Text("手动打卡"))),
                      const SizedBox(width: 6),
                      Expanded(child: ElevatedButton(onPressed: doRepairSign, child: const Text("补签"))),
                      const SizedBox(width: 6),
                      Expanded(child: ElevatedButton(onPressed: openFilterDialog, child: const Text("筛选"))),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            Text("${selectedDay?.year}-${selectedDay?.month}-${selectedDay?.day} 打卡记录"),
            const SizedBox(height: 8),
            ...getDayRecords(selectedDay!).map((item) => Card(
              child: ListTile(
                title: Text(item["place"]),
                subtitle: Text("${item["type"]} | 工时：${item["hour"]}h | 日工价：${item["dayWage"]}"),
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }
}
