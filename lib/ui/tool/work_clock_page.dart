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

  @override
  void initState() {
    super.initState();
    selectedDay = DateTime.now();
    loadWorkData();
  }

  Future<void> loadWorkData() async {
    setState(() {});
  }

  Widget buildCalendarGrid() {
    bool hasClock = workList.any((item) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                children: const [
                  Column(
                    children: [
                      Text("1", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      Text("出勤天数"),
                    ],
                  ),
                  Column(
                    children: [
                      Text("8.00 h", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      Text("总工时"),
                    ],
                  ),
                  Column(
                    children: [
                      Text("99999.00 元", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                      Text("预估工资"),
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
              value: "全部工地",
              decoration: const InputDecoration(
                labelText: "筛选工地（只看该工地记录）",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: "全部工地", child: Text("全部工地")),
              ],
              onChanged: (v) {},
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
                ElevatedButton(onPressed: () {}, child: const Text("自动打卡 8H")),
                ElevatedButton(onPressed: () {}, child: const Text("手动打卡")),
                ElevatedButton(onPressed: () {}, child: const Text("补签")),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
