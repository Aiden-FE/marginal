import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/platform_services.dart';
import '../../app/reader_projection.dart';
import '../../core/types.dart';
import '../agent/agent_page.dart';
import '../approvals/approvals_page.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.services,
    required this.work,
    required this.initialChapterId,
  });
  final PlatformServices services;
  final Work work;
  final String initialChapterId;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  List<Chapter> _chapters = const [];
  String _text = '';
  int _index = 0;
  bool _loading = true;
  final Map<int, Uint8List> _images = {};
  late final ReaderProjectionService _projectionService =
      ReaderProjectionService(widget.services.repository);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chapters = await _projectionService.chapters(widget.work.id);
    if (chapters.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    var index = chapters.indexWhere((c) => c.id == widget.initialChapterId);
    if (index < 0) index = 0;
    await _open(chapters, index);
    final settings = Map<String, dynamic>.from(widget.work.settings)
      ..['reader'] = {'chapterId': chapters[index].id};
    await widget.services.repository.putWork(
      Work(
        id: widget.work.id,
        title: widget.work.title,
        author: widget.work.author,
        importSource: widget.work.importSource,
        createdAt: widget.work.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        settings: settings,
      ),
    );
  }

  Future<void> _open(List<Chapter> chapters, int index) async {
    final projection = await _projectionService.projection(
      widget.work.id,
      chapters[index],
    );
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _index = index;
      _text = projection.text;
      _images
        ..clear()
        ..addAll(projection.images);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final paragraphs = _paragraphs(_text);
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? widget.work.title : _chapters[_index].title),
        actions: [
          IconButton(
            onPressed: () => _push(
              ApprovalsPage(services: widget.services, work: widget.work),
            ),
            icon: const Icon(Icons.fact_check),
          ),
          IconButton(
            onPressed: () =>
                _push(AgentPage(services: widget.services, work: widget.work)),
            icon: const Icon(Icons.smart_toy),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isEmpty
          ? const Center(child: Text('该书稿还没有章节。'))
          : Scrollbar(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
                itemCount: paragraphs.length,
                itemBuilder: (context, i) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paragraphs[i],
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(height: 1.8),
                    ),
                    if (_images.containsKey(i))
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Image.memory(
                          _images[i]!,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _loading || _chapters.isEmpty
          ? null
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _index > 0
                        ? () => _open(_chapters, _index - 1)
                        : null,
                    child: const Text('上一章'),
                  ),
                  Text('第 ${_index + 1}/${_chapters.length} 章'),
                  TextButton(
                    onPressed: _index + 1 < _chapters.length
                        ? () => _open(_chapters, _index + 1)
                        : null,
                    child: const Text('下一章'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await _open(_chapters, _index);
  }

  List<String> _paragraphs(String value) => value
      .split(RegExp(r'\n\s*\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
