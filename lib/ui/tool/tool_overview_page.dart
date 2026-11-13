import 'package:flutter/material.dart';

class ToolOverviewPage extends StatelessWidget {
  const ToolOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("工具")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: InkWell(
                onTap: () {
                  // TODO：后续跳转记工打卡页面
                },
                child: const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(Icons.edit_calendar, size: 48),
                      SizedBox(height: 12),
                      Text("记工打卡", style: TextStyle(fontSize: 18)),
                      SizedBox(height:4),
                      Text("打卡记录、查看历史出勤、工资统计"),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: InkWell(
                onTap: () {
                  // TODO：后续跳转工程量计算页面
                },
                child: const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(Icons.calculate, size: 48),
                      SizedBox(height: 12),
                      Text("工程量计算", style: TextStyle(fontSize: 18)),
                      SizedBox(height:4),
                      Text("面积体积算量，保存算量单据，复制文本"),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

