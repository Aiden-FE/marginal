import 'package:flutter/material.dart';

import '../../app/marginal_theme.dart';
import '../../app/platform_services.dart';
import '../library/library_page.dart';

enum HomeVariant { continueFirst, libraryDesk, readingRhythm, aiCoReader }

class HomePrototypePage extends StatefulWidget {
  const HomePrototypePage({
    super.key,
    required this.services,
    this.initialVariant,
  });

  final PlatformServices services;
  final HomeVariant? initialVariant;

  @override
  State<HomePrototypePage> createState() => _HomePrototypePageState();
}

class _HomePrototypePageState extends State<HomePrototypePage> {
  late HomeVariant _variant =
      widget.initialVariant ?? HomeVariant.continueFirst;
  bool _providerConnected = true;
  bool _autoRead = false;
  bool _showCompleted = false;
  String? _prototypeProviderName;

  String get _providerName {
    if (_prototypeProviderName?.isNotEmpty == true) return _prototypeProviderName!;
    final configured = widget.services.providerStore.providers
        .where((provider) => provider.id != 'demo')
        .toList();
    return configured.isEmpty ? '内置演示供应商' : configured.first.name;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openConfig() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _AiConfigSheet(
        providerName: _providerName,
        connected: _providerConnected,
        onSave: (name, connected) {
          setState(() {
            _prototypeProviderName = name;
            _providerConnected = connected;
          });
          Navigator.of(sheetContext).pop();
          _toast('AI 配置已保存到本次原型会话');
        },
      ),
    );
  }

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryPage(services: widget.services),
      ),
    );
  }

  void _openAgent() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AgentPreviewSheet(
        providerName: _providerName,
        connected: _providerConnected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? MarginalColors.nightBg : MarginalColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(_variant),
                child: _buildVariant(),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _PrototypeSwitcher(
                current: _variant,
                onChanged: (variant) => setState(() => _variant = variant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariant() => switch (_variant) {
    HomeVariant.continueFirst => _ContinueFirst(
      providerName: _providerName,
      connected: _providerConnected,
      autoRead: _autoRead,
      onRead: () => _toast('演示：打开《雾中来信》· 第 07 章'),
      onImport: () => _toast('演示：打开导入 TXT / .mabk 流程'),
      onConfig: _openConfig,
      onAgent: _openAgent,
      onLibrary: _openLibrary,
      onToggleAutoRead: () => setState(() => _autoRead = !_autoRead),
    ),
    HomeVariant.libraryDesk => _LibraryDesk(
      providerName: _providerName,
      connected: _providerConnected,
      showCompleted: _showCompleted,
      onRead: () => _toast('演示：继续阅读《雾中来信》'),
      onImport: () => _toast('演示：打开导入 TXT / .mabk 流程'),
      onConfig: _openConfig,
      onAgent: _openAgent,
      onLibrary: _openLibrary,
      onToggleCompleted: () => setState(() => _showCompleted = !_showCompleted),
    ),
    HomeVariant.readingRhythm => _ReadingRhythm(
      providerName: _providerName,
      connected: _providerConnected,
      onRead: () => _toast('演示：从上次位置继续阅读'),
      onConfig: _openConfig,
      onAgent: _openAgent,
      onLibrary: _openLibrary,
    ),
    HomeVariant.aiCoReader => _AiCoReader(
      providerName: _providerName,
      connected: _providerConnected,
      onRead: () => _toast('演示：回到《雾中来信》'),
      onConfig: _openConfig,
      onAgent: _openAgent,
      onLibrary: _openLibrary,
    ),
  };
}

class _ContinueFirst extends StatelessWidget {
  const _ContinueFirst({
    required this.providerName,
    required this.connected,
    required this.autoRead,
    required this.onRead,
    required this.onImport,
    required this.onConfig,
    required this.onAgent,
    required this.onLibrary,
    required this.onToggleAutoRead,
  });

  final String providerName;
  final bool connected;
  final bool autoRead;
  final VoidCallback onRead;
  final VoidCallback onImport;
  final VoidCallback onConfig;
  final VoidCallback onAgent;
  final VoidCallback onLibrary;
  final VoidCallback onToggleAutoRead;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopBar(
            eyebrow: 'MARGINAL / HOME',
            title: '晚上好，Aiden',
            trailing: IconButton(
              tooltip: 'AI 配置',
              onPressed: onConfig,
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '把注意力留给故事。',
              style: MarginalTheme.serif.copyWith(
                fontSize: 32,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _ContinueHero(onRead: onRead),
          const SizedBox(height: 20),
          _SectionHeader(
            title: '阅读工作台',
            action: TextButton(onPressed: onLibrary, child: const Text('查看书库')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    value: '42%',
                    label: '本周阅读',
                    icon: Icons.auto_stories_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    value: '7',
                    label: '连续天数',
                    icon: Icons.local_fire_department_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    value: '12',
                    label: '实体卡',
                    icon: Icons.style_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _AiStatusCard(
            providerName: providerName,
            connected: connected,
            onConfig: onConfig,
            onAgent: onAgent,
            compact: true,
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.play_circle_outline_rounded,
            title: autoRead ? '自动阅读已开启' : '自动阅读',
            subtitle: autoRead ? '按段落平滑滚动，不打断沉浸感' : '用更轻的节奏读完这一章',
            trailing: Switch.adaptive(
              value: autoRead,
              onChanged: (_) => onToggleAutoRead(),
            ),
          ),
          const SizedBox(height: 14),
          _OutlinedAction(
            icon: Icons.file_upload_outlined,
            label: '导入一本新书',
            onPressed: onImport,
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _LibraryDesk extends StatelessWidget {
  const _LibraryDesk({
    required this.providerName,
    required this.connected,
    required this.showCompleted,
    required this.onRead,
    required this.onImport,
    required this.onConfig,
    required this.onAgent,
    required this.onLibrary,
    required this.onToggleCompleted,
  });

  final String providerName;
  final bool connected;
  final bool showCompleted;
  final VoidCallback onRead;
  final VoidCallback onImport;
  final VoidCallback onConfig;
  final VoidCallback onAgent;
  final VoidCallback onLibrary;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopBar(
            eyebrow: 'MARGINAL / LIBRARY DESK',
            title: '书库工作台',
            trailing: IconButton(
              tooltip: 'AI 配置',
              onPressed: onConfig,
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索书名、作者或标签',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: '导入',
                        onPressed: onImport,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _FilterChip(label: '全部 3', selected: true, onTap: onLibrary),
                _FilterChip(label: '待读 2', onTap: onRead),
                _FilterChip(label: '收藏 1', onTap: () {}),
                _FilterChip(
                  label: showCompleted ? '已读完' : '显示已读',
                  onTap: onToggleCompleted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '正在阅读',
              style: MarginalTheme.serif.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _DeskBookCard(onRead: onRead),
          const SizedBox(height: 18),
          _SectionHeader(
            title: '你的书架',
            action: TextButton(onPressed: onImport, child: const Text('导入')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: .86,
              children: [
                _ShelfBook(
                  title: '潮汐档案',
                  meta: '未开始 · 18 章',
                  tone: const Color(0xFF6B7D70),
                  onTap: onRead,
                ),
                _ShelfBook(
                  title: '南方旧梦',
                  meta: '读至 68%',
                  tone: const Color(0xFF91725E),
                  onTap: onRead,
                ),
                if (showCompleted)
                  _ShelfBook(
                    title: '山茶文具店',
                    meta: '已读完',
                    tone: const Color(0xFF9B6F7E),
                    onTap: onRead,
                  ),
                _ImportTile(onTap: onImport),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AiStatusCard(
            providerName: providerName,
            connected: connected,
            onConfig: onConfig,
            onAgent: onAgent,
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _ReadingRhythm extends StatelessWidget {
  const _ReadingRhythm({
    required this.providerName,
    required this.connected,
    required this.onRead,
    required this.onConfig,
    required this.onAgent,
    required this.onLibrary,
  });

  final String providerName;
  final bool connected;
  final VoidCallback onRead;
  final VoidCallback onConfig;
  final VoidCallback onAgent;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopBar(
            eyebrow: 'MARGINAL / READING RHYTHM',
            title: '阅读节奏',
            trailing: IconButton(
              tooltip: 'AI 配置',
              onPressed: onConfig,
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '7',
                  style: MarginalTheme.serif.copyWith(
                    fontSize: 76,
                    height: .9,
                    fontWeight: FontWeight.w700,
                    color: MarginalColors.accent,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 10),
                  child: Text(
                    '天连续阅读\n今晚再读 12 分钟',
                    style: TextStyle(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MarginalColors.ink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本周阅读量',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final value in [
                      0.42,
                      0.68,
                      0.36,
                      0.82,
                      0.58,
                      0.74,
                      0.3,
                    ])
                      _Bar(value: value, active: value == .74),
                  ],
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '一',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      '二',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      '三',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      '四',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      '五',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      '六',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Text(
                      '日',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: '今晚的下一步',
            action: TextButton(onPressed: onRead, child: const Text('继续阅读')),
          ),
          _RhythmStep(
            number: '01',
            title: '读完第 07 章剩余部分',
            subtitle: '约 12 分钟 · 上次停在「雨开始下了」',
            onTap: onRead,
          ),
          _RhythmStep(
            number: '02',
            title: '确认 3 张新实体卡',
            subtitle: 'AI 已从本章发现角色与场景',
            onTap: onAgent,
          ),
          _RhythmStep(
            number: '03',
            title: '为关键段落生成一张插图',
            subtitle: '保持正典人物设定一致',
            onTap: onAgent,
          ),
          const SizedBox(height: 16),
          _AiStatusCard(
            providerName: providerName,
            connected: connected,
            onConfig: onConfig,
            onAgent: onAgent,
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.menu_book_outlined,
            title: '全书进度',
            subtitle: '3 本书 · 1 本正在阅读 · 1 本已完成',
            trailing: IconButton(
              onPressed: onLibrary,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _AiCoReader extends StatelessWidget {
  const _AiCoReader({
    required this.providerName,
    required this.connected,
    required this.onRead,
    required this.onConfig,
    required this.onAgent,
    required this.onLibrary,
  });

  final String providerName;
  final bool connected;
  final VoidCallback onRead;
  final VoidCallback onConfig;
  final VoidCallback onAgent;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopBar(
            eyebrow: 'MARGINAL / AI CO-READER',
            title: 'AI 共读台',
            trailing: IconButton(
              tooltip: '配置 provider',
              onPressed: onConfig,
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Text(
              '让 AI 参与，但不替你阅读。',
              style: MarginalTheme.serif.copyWith(
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
          ),
          _AiStatusCard(
            providerName: providerName,
            connected: connected,
            onConfig: onConfig,
            onAgent: onAgent,
            prominent: true,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '共读请求',
              style: MarginalTheme.serif.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _PromptCard(
            title: '解释这一段的叙事视角',
            detail: '《雾中来信》· 第 07 章 · 段落 12',
            status: '待发送',
            onTap: onAgent,
          ),
          _PromptCard(
            title: '整理本章出现的人物关系',
            detail: '写入实体卡前需要你的确认',
            status: '需批准',
            onTap: onAgent,
          ),
          const SizedBox(height: 14),
          _SectionHeader(
            title: '继续阅读',
            action: TextButton(onPressed: onLibrary, child: const Text('打开书库')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MiniContinueCard(onRead: onRead),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 30),
    child: child,
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.eyebrow,
    required this.title,
    required this.trailing,
  });
  final String eyebrow;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.8,
                  color: MarginalColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: MarginalTheme.serif.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: MarginalColors.ink,
                ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}

class _ContinueHero extends StatelessWidget {
  const _ContinueHero({required this.onRead});
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: MarginalColors.ink,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: MarginalColors.ink.withValues(alpha: .18),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '继续上次阅读',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BookCover(
              title: '雾中\n来信',
              tone: Color(0xFF81654E),
              large: true,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '雾中来信',
                    style: MarginalTheme.serif.copyWith(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '北岛 · 第 07 章 / 雨季来客',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: .42,
                          minHeight: 5,
                          color: Color(0xFFE2B66B),
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '42%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onRead,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE2B66B),
                      foregroundColor: MarginalColors.ink,
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('继续阅读'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DeskBookCard extends StatelessWidget {
  const _DeskBookCard({required this.onRead});
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: MarginalColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: MarginalColors.line),
    ),
    child: Row(
      children: [
        const _BookCover(title: '雾中\n来信', tone: Color(0xFF81654E)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '雾中来信',
                style: MarginalTheme.serif.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MarginalColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '第 07 章 · 雨季来客',
                style: TextStyle(fontSize: 12, color: MarginalColors.muted),
              ),
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                value: .42,
                minHeight: 4,
                color: MarginalColors.accent,
                backgroundColor: MarginalColors.surface2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onRead,
          icon: const Icon(
            Icons.arrow_forward_rounded,
            color: MarginalColors.accent,
          ),
        ),
      ],
    ),
  );
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.title,
    required this.tone,
    this.large = false,
  });
  final String title;
  final Color tone;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    width: large ? 86 : 62,
    height: large ? 116 : 84,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tone.withValues(alpha: .7), tone],
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Text(
      title,
      textAlign: TextAlign.center,
      style: MarginalTheme.serif.copyWith(
        color: Colors.white,
        fontSize: large ? 18 : 14,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: MarginalColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: MarginalColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: MarginalColors.accent),
        const SizedBox(height: 12),
        Text(
          value,
          style: MarginalTheme.serif.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MarginalColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: MarginalColors.muted),
        ),
      ],
    ),
  );
}

class _AiStatusCard extends StatelessWidget {
  const _AiStatusCard({
    required this.providerName,
    required this.connected,
    required this.onConfig,
    required this.onAgent,
    this.compact = false,
    this.prominent = false,
  });
  final String providerName;
  final bool connected;
  final VoidCallback onConfig;
  final VoidCallback onAgent;
  final bool compact;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: EdgeInsets.all(prominent ? 18 : 14),
    decoration: BoxDecoration(
      color: prominent ? MarginalColors.accentSoft : MarginalColors.surface,
      borderRadius: BorderRadius.circular(prominent ? 20 : 16),
      border: Border.all(
        color: prominent
            ? MarginalColors.accent.withValues(alpha: .3)
            : MarginalColors.line,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? MarginalColors.ok : MarginalColors.danger,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'AI 阅读能力',
              style: MarginalTheme.serif.copyWith(
                fontSize: prominent ? 20 : 16,
                fontWeight: FontWeight.w700,
                color: MarginalColors.ink,
              ),
            ),
            const Spacer(),
            TextButton(onPressed: onConfig, child: const Text('配置')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          connected ? '$providerName · 连接正常' : '尚未连接 provider · 仅可使用本地演示',
          style: const TextStyle(fontSize: 12, color: MarginalColors.muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Capability(label: '章节修复', enabled: connected),
            ),
            Expanded(
              child: _Capability(label: '实体提取', enabled: connected),
            ),
            Expanded(
              child: _Capability(label: '段落插图', enabled: connected),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAgent,
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('打开阅读 Agent'),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.enabled});
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        enabled ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 15,
        color: enabled ? MarginalColors.ok : MarginalColors.muted,
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: MarginalColors.muted),
        ),
      ),
    ],
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: MarginalColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: MarginalColors.line),
    ),
    child: Row(
      children: [
        Icon(icon, color: MarginalColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: MarginalColors.muted,
                ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});
  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: MarginalTheme.serif.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: MarginalColors.ink,
            ),
          ),
        ),
        action,
      ],
    ),
  );
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: selected
          ? MarginalColors.accent
          : MarginalColors.surface,
      labelStyle: TextStyle(
        color: selected ? Colors.white : MarginalColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ShelfBook extends StatelessWidget {
  const _ShelfBook({
    required this.title,
    required this.meta,
    required this.tone,
    required this.onTap,
  });
  final String title;
  final String meta;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarginalColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarginalColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BookCover(title: title.substring(0, 1), tone: tone),
          const Spacer(),
          Text(
            title,
            style: MarginalTheme.serif.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MarginalColors.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            meta,
            style: const TextStyle(fontSize: 11, color: MarginalColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _ImportTile extends StatelessWidget {
  const _ImportTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MarginalColors.line,
          style: BorderStyle.solid,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_circle_outline,
            color: MarginalColors.accent,
            size: 26,
          ),
          SizedBox(height: 8),
          Text('导入书稿', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 3),
          Text(
            'TXT / .mabk',
            style: TextStyle(fontSize: 11, color: MarginalColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.active});
  final double value;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 76,
    alignment: Alignment.bottomCenter,
    child: FractionallySizedBox(
      heightFactor: value,
      child: Container(
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE2B66B) : Colors.white24,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    ),
  );
}

class _RhythmStep extends StatelessWidget {
  const _RhythmStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String number;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: MarginalColors.accent,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MarginalColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_outward_rounded,
            size: 18,
            color: MarginalColors.muted,
          ),
        ],
      ),
    ),
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.title,
    required this.detail,
    required this.status,
    required this.onTap,
  });
  final String title;
  final String detail;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MarginalColors.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: MarginalColors.accent,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: MarginalColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: status == '需批准'
                    ? const Color(0xFFF1DFD5)
                    : MarginalColors.surface2,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  color: status == '需批准'
                      ? MarginalColors.danger
                      : MarginalColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniContinueCard extends StatelessWidget {
  const _MiniContinueCard({required this.onRead});
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: MarginalColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MarginalColors.line),
    ),
    child: Row(
      children: [
        const _BookCover(title: '雾中\n来信', tone: Color(0xFF81654E)),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 07 章 · 雨季来客',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 5),
              Text(
                '读至 42% · 上次停在 12 段',
                style: TextStyle(fontSize: 12, color: MarginalColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRead,
          icon: const Icon(
            Icons.play_arrow_rounded,
            color: MarginalColors.accent,
          ),
        ),
      ],
    ),
  );
}

class _PrototypeSwitcher extends StatelessWidget {
  const _PrototypeSwitcher({required this.current, required this.onChanged});
  final HomeVariant current;
  final ValueChanged<HomeVariant> onChanged;

  static const labels = {
    HomeVariant.continueFirst: ('A', '继续阅读'),
    HomeVariant.libraryDesk: ('B', '书库工作台'),
    HomeVariant.readingRhythm: ('C', '阅读节奏'),
    HomeVariant.aiCoReader: ('D', 'AI 共读台'),
  };

  @override
  Widget build(BuildContext context) {
    final index = HomeVariant.values.indexOf(current);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: MarginalColors.ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            onPressed: () => onChanged(
              HomeVariant.values[(index - 1 + HomeVariant.values.length) %
                  HomeVariant.values.length],
            ),
          ),
          Text(
            '${labels[current]!.$1}  ${labels[current]!.$2}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
            onPressed: () => onChanged(
              HomeVariant.values[(index + 1) % HomeVariant.values.length],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiConfigSheet extends StatefulWidget {
  const _AiConfigSheet({
    required this.providerName,
    required this.connected,
    required this.onSave,
  });
  final String providerName;
  final bool connected;
  final void Function(String name, bool connected) onSave;

  @override
  State<_AiConfigSheet> createState() => _AiConfigSheetState();
}

class _AiConfigSheetState extends State<_AiConfigSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.providerName,
  );
  late bool _connected = widget.connected;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.of(context).viewInsets.bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI 配置',
          style: MarginalTheme.serif.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: MarginalColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '原型态：只保存在本次会话，用来体验首页信息架构。',
          style: TextStyle(fontSize: 12, color: MarginalColors.muted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Provider 名称',
            prefixIcon: Icon(Icons.hub_outlined),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          decoration: InputDecoration(
            labelText: 'Model',
            hintText: 'gpt-4o-mini / demo',
            prefixIcon: Icon(Icons.memory_outlined),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'sk-…',
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('连接诊断通过'),
          subtitle: const Text('切换后可观察 AI 能力卡的完整/降级状态'),
          value: _connected,
          onChanged: (value) => setState(() => _connected = value),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => widget.onSave(_name.text.trim(), _connected),
            icon: const Icon(Icons.check_rounded),
            label: const Text('保存本次会话配置'),
          ),
        ),
      ],
    ),
  );
}

class _AgentPreviewSheet extends StatelessWidget {
  const _AgentPreviewSheet({
    required this.providerName,
    required this.connected,
  });
  final String providerName;
  final bool connected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MarginalColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.forum_outlined,
                color: MarginalColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '阅读 Agent',
                style: MarginalTheme.serif.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: MarginalColors.ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: connected
                    ? MarginalColors.accentSoft
                    : MarginalColors.surface2,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                connected ? '已连接' : '演示模式',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '当前 provider：$providerName',
          style: const TextStyle(fontSize: 12, color: MarginalColors.muted),
        ),
        const SizedBox(height: 14),
        const Text('你可以问：', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(label: const Text('总结这一章'), onPressed: () {}),
            ActionChip(label: const Text('找出人物关系'), onPressed: () {}),
            ActionChip(label: const Text('解释这段伏笔'), onPressed: () {}),
          ],
        ),
        const SizedBox(height: 18),
        const TextField(
          decoration: InputDecoration(
            hintText: '询问当前书稿…',
            suffixIcon: Icon(Icons.send_rounded),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '涉及写入书稿的操作会先生成提案，并等待你的批准。',
          style: TextStyle(fontSize: 11, color: MarginalColors.muted),
        ),
      ],
    ),
  );
}
