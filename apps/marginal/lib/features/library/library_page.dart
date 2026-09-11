import 'package:flutter/material.dart';

import '../../app/import_service.dart';
import '../../app/platform_services.dart';
import '../../core/types.dart';
import '../reader/reader_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.services});
  final PlatformServices services;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Work> _works = const [];
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final works = await widget.services.repository.listWorks();
    if (mounted) setState(() => _works = works);
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final input = await const PickerFileSource().pick();
    if (input == null) return;
    try {
      final work = input.name.toLowerCase().endsWith('.mabk')
          ? await ImportService(widget.services.repository)
                .importMabk(input.bytes, copy: true)
          : await ImportService(widget.services.repository)
                .importTxt(input.name, input.bytes);
      await _refresh();
      messenger.showSnackBar(SnackBar(content: Text('已导入「${work.title}」')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _open(Work work) async {
    final chapters = await widget.services.repository.listChapters(work.id);
    if (!mounted || chapters.isEmpty) return;
    final saved = (work.settings['reader'] as Map?)?['chapterId'] as String?;
    final initial = chapters.any((c) => c.id == saved)
        ? saved!
        : chapters.first.id;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(
          services: widget.services,
          work: work,
          initialChapterId: initial,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('书库')),
    floatingActionButton: FloatingActionButton(
      onPressed: _import,
      tooltip: '导入 TXT / .mabk',
      child: const Icon(Icons.add),
    ),
    body: _works.isEmpty
        ? const Center(child: Text('还没有书稿。导入一本 TXT 开始阅读。'))
        : ListView.builder(
            itemCount: _works.length,
            itemBuilder: (context, i) {
              final work = _works[i];
              return ListTile(
                title: Text(work.title),
                subtitle: Text(work.importSource),
                onTap: () => _open(work),
              );
            },
          ),
  );
}
