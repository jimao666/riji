// 首页底栏的 Tab 身份。
//
// 职责：给每个 Tab 一个与位置无关的身份（文案、图标），并按功能管理开关
// 推出当前可见的 Tab 列表。日记排在底栏中间，待办、日历、探索可在设置 →
// 功能管理中关闭，关闭后各 Tab（包括日记）的下标都会变，所以首页一律按身份
// 而不是下标判断“当前是哪一页”，启动时也按身份落在日记页。
//
// 设置不是 Tab：它是从日记页顶栏“更多 → 设置”推入的二级页（见
// `openSettingsPage`）。

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/services/app_features.dart';
import '../../../l10n/app_localizations.dart';
import '../../app_surface/models/app_surface_enums.dart';

/// 首页 Tab。底栏中的顺序不是声明顺序，见 [visibleHomeTabs]。
enum HomeTab {
  diaries,
  todos,
  calendar,
  explore,
  tool;

  /// 底栏文案。
  String label(AppLocalizations l10n) => switch (this) {
    HomeTab.diaries => l10n.navDiaries,
    HomeTab.todos => l10n.navTodos,
    HomeTab.calendar => l10n.navCalendar,
    HomeTab.explore => l10n.navExplore,
    HomeTab.tool => "工具",
  };

  /// 底栏图标。
  FaIconData get icon => switch (this) {
    HomeTab.diaries => FontAwesomeIcons.solidRectangleList,
    HomeTab.todos => FontAwesomeIcons.solidSquareCheck,
    HomeTab.calendar => FontAwesomeIcons.solidCalendar,
    HomeTab.explore => FontAwesomeIcons.solidCompass,
    HomeTab.tool => FontAwesomeIcons.solidScrewdriverWrench,
  };

  /// 是否有首页的“新建”FAB（玻璃底栏时为并排按钮）：日记页新建日记，
  /// 待办页新建待办；其余 Tab 没有。
  bool get hasCreateFab => switch(this){
    HomeTab.diaries => true,
    HomeTab.todos => true,
    _ => false,
  };

  /// 这个 Tab 的背景区域（“背景与材质”里可以单独设置）。
  AppBackgroundArea get backgroundArea => switch (this) {
    HomeTab.diaries => AppBackgroundArea.diaries,
    HomeTab.todos => AppBackgroundArea.todos,
    HomeTab.calendar => AppBackgroundArea.calendar,
    HomeTab.explore => AppBackgroundArea.explore,
    HomeTab.tool => AppBackgroundArea.explore,
  };
}

/// 按功能开关推出可见的 Tab，即底栏（宽窗口为侧边栏）从左到右的顺序。
List<HomeTab> visibleHomeTabs(AppFeatures features) =>
    _withDiariesCentered(<HomeTab>[
      if (features.calendar) HomeTab.calendar,
      if (features.todos) HomeTab.todos,
      if (features.explore) HomeTab.explore,
      if (features.tool) HomeTab.tool,
    ]);

/// 全部 Tab 都开启时的底栏顺序（设置里导航栏样式的预览用）。
final List<HomeTab> allHomeTabsInBarOrder = List<HomeTab>.unmodifiable(
  _withDiariesCentered(<HomeTab>[
    HomeTab.calendar,
    HomeTab.todos,
    HomeTab.explore,
    HomeTab.tool,
  ]),
);

/// 把日记插到 [others] 的中点（`length ~/ 2`，偶数个 Tab 时偏左）。
List<HomeTab> _withDiariesCentered(List<HomeTab> others) {
  final middle = others.length ~/ 2;
  return <HomeTab>[
    ...others.take(middle),
    HomeTab.diaries,
    ...others.skip(middle),
  ];
}
