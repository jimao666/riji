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
  DateTime? selectedDay;
  final TextEditingController _workNameCtrl = TextEditingController();
  final TextEditingController _hourCtrl = TextEditingController();
  final TextEditingController _wageCtrl = TextEditingController();

  List<Map<String, dynamic>> workList = [];
  String selectedSite = "全部工地";
  List<String> siteList = ["全部工地"];

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    loadWorkData();
  }

  Future<void> loadWorkData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("work_record");
    if (raw != null) {
      final List list = json.decode(raw);
      workList = list.cast<Map<String, dynamic>>();
    }
    Set<String> sites = {};
    for (var item in workList) {
      if (item["place"] != null && item["place"].toString().trim().isNotEmpty) {
        sites.add(item["place"].toString().trim());
      }
    }
    siteList = ["全部工地", ...sites];
    setState(() {});
  }

  Future<void> saveWorkData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("work_record", json.encode(workList));
  }

  Widget buildCalendarGrid() {
    var filterList = workList;
    if (selectedSite != "全部工地") {
      filterList = workList.where((item) => item["place"] == selectedSite).toList();
    }
    bool hasClock = filterList.any((item) {
      DateTime itemDate = DateTime.parse(item["date"]);
      return itemDate.year == selectedDay!.year &&
          itemDate.month == selectedDay!.month &&
          itemDate.day == selectedDay!.day;
    });

    return Container(
      width: double.infinity,
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasClock ? const Color(0xFFD9F7E8) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: selectedDay ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2099),
          );
          if (picked != null) {
            setState(() {
              selectedDay = picked;
            });
            loadWorkData();
          }
        },
        child: Center(
          child: Text(
            hasClock
                ? "✅ 已打卡\n${selectedDay!.year}年${selectedDay!.month}月${selectedDay!.day}日"
                : "${selectedDay!.year}年${selectedDay!.month}月${selectedDay!.day}日",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: hasClock ? const Color(0xFF209658) : Colors.grey[700],
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> calcStat() {
    int days = 0;
    double hours = 0;
    double money = 0;
    final double wage = double.tryParse(_wageCtrl.text) ?? 0;

    var filterList = workList;
    if (selectedSite != "全部工地") {
      filterList = workList.where((item) => item["place"] == selectedSite).toList();
    }

    for (var item in filterList) {
      final d = DateTime.parse(item["date"]);
      if (d.year == selectedDay!.year && d.month == selectedDay!.month) {
        days++;
        final h = double.tryParse(item["hour"].toString()) ?? 0;
        hours += h;
        if (wage > 0) {
          money += h / 8 * wage;
        }
      }
    }
    return {"days": days, "hours": hours, "money": money};
  }

  void doAutoClock() {
    String placeName = _workNameCtrl.text.trim();
    if (placeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请先填写工地/项目地点！")));
      return;
    }
    final dateStr =
        "${selectedDay!.year}-${selectedDay!.month.toString().padLeft(2, '0')}-${selectedDay!.day.toString().padLeft(2, '0')}";
    final existIndex = workList.indexWhere((e) => e["date"] == dateStr && e["place"] == placeName);
    if (existIndex >= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("该工地今日已经打卡！")));
      return;
    }
    workList.add({
      "date": dateStr,
      "hour": 8.0,
      "place": placeName,
    });
    saveWorkData();
    loadWorkData();
  }

  void doManualClock() {
    final h = double.tryParse(_hourCtrl.text);
    String placeName = _workNameCtrl.text.trim();
    if (placeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请先填写工地/项目地点！")));
      return;
    }
    if (h == null || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请输入有效工时")));
      return;
    }
    final dateStr =
        "${selectedDay!.year}-${selectedDay!.month.toString().padLeft(2, '0')}-${selectedDay!.day.toString().padLeft(2, '0')}";
    final existIndex = workList.indexWhere((e) => e["date"] == dateStr && e["place"] == placeName);
    if (existIndex >= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("该工地今日已经打卡！")));
      return;
    }
    workList.add({
      "date": dateStr,
      "hour": h,
      "place": placeName,
    });
    saveWorkData();
    loadWorkData();
  }

  @override
  Widget build(BuildContext context) {
    final stat = calcStat();
    return Scaffold(
      appBar: AppBar(
        title: const Text("工时打卡"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      selectedDay = DateTime(
                        selectedDay!.year,
                        selectedDay!.month - 1,
                        selectedDay!.day,
                      );
                    });
                    loadWorkData();
                  },
                  icon: const Icon(Icons.arrow_back_ios),
                ),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDay ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2099),
                    );
                    if (picked != null) {
                      setState(() {
                        selectedDay = picked;
                      });
                      loadWorkData();
                    }
                  },
                  child: Text(
                    "${selectedDay?.year} 年 ${selectedDay?.month} 月",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      selectedDay = DateTime(
                        selectedDay!.year,
                        selectedDay!.month + 1,
                        selectedDay!.day,
                      );
                    });
                    loadWorkData();
                  },
                  icon: const Icon(Icons.arrow_forward_ios),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {});
                  },
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
              ],
            ),
            const SizedBox(height: 8),
            buildCalendarGrid(),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      Text("${stat["days"]}",
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      const Text("出勤天数"),
                    ],
                  ),
                  Column(
                    children: [
                      Text("${stat["hours"].toStringAsFixed(2)} h",
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      const Text("总工时"),
                    ],
                  ),
                  Column(
                    children: [
                      Text("${stat["money"].toStringAsFixed(2)} 元",
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      const Text("预估工资"),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _wageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "日工价（8小时工资）",
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workNameCtrl,
              decoration: const InputDecoration(
                labelText: "工地/项目地点",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedSite,
              decoration: const InputDecoration(
                labelText: "筛选工地（只看该工地记录）",
                border: OutlineInputBorder(),
              ),
              items: siteList.map((site) => DropdownMenuItem(value: site, child: Text(site))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedSite = v;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hourCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "手动打卡工时",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(onPressed: doAutoClock, child: const Text("自动打卡 8H")),
                ElevatedButton(onPressed: doManualClock, child: const Text("手动打卡")),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDay ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2099),
                    );
                    if (picked != null) {
                      setState(() {
                        selectedDay = picked;
                      });
                      loadWorkData();
                    }
                  },
                  child: const Text("补签"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
