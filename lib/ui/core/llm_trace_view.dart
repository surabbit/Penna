import 'package:flutter/material.dart';

import '../../core/harness/llm_trace.dart';
import '../../l10n/l10n.dart';
import 'theme.dart';
import 'widgets.dart';

// 「请求记录」:对话栏顶栏那个按钮和点开的窗口。
// 左边挑一次请求,右边看它发给模型的全文(连 system 提示、历史、当前提问)和模型回来的全文。
// 文本和别处一样能选中复制(右键菜单)。

/// 打开请求记录。
Future<void> showLlmTrace(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _TraceDialog(),
);

class _TraceDialog extends StatefulWidget {
  const _TraceDialog();

  @override
  State<_TraceDialog> createState() => _TraceDialogState();
}

class _TraceDialogState extends State<_TraceDialog> {
  /// 眼前看的是第几条(0 是最新那次)。
  int _at = 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
    title: Row(
      children: [
        Expanded(
          child: Text(tr('请求记录'), style: const TextStyle(fontSize: 16)),
        ),
        TextButton(onPressed: llmTraces.clear, child: Text(tr('清空'))),
        IconButton(
          tooltip: tr('关闭'),
          iconSize: 18,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
    content: SizedBox(
      width: 1000,
      height: 640,
      child: ListenableBuilder(
        listenable: llmTraces,
        builder: (context, _) {
          final entries = llmTraces.entries;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                tr('还没有向模型发过请求'),
                style: TextStyle(color: PennaColors.slate500),
              ),
            );
          }
          final at = _at.clamp(0, entries.length - 1).toInt();
          final trace = entries[at];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 232,
                child: ListView.separated(
                  padding: const EdgeInsets.all(6),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (_, i) => _EntryRow(
                    trace: entries[i],
                    selected: i == at,
                    onTap: () => setState(() => _at = i),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, color: PennaColors.border),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Text(
                        trace.head,
                        style: TextStyle(
                          fontSize: 12,
                          color: PennaColors.slate500,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: PennaColors.border),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          '${trace.requestText}\n\n'
                          '──── ${tr('回复')} · ${trace.reply.length} 字 ────\n'
                          '${trace.replyText}',
                          contextMenuBuilder: pennaTextMenu,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.trace,
    required this.selected,
    required this.onTap,
  });

  final LlmTrace trace;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? PennaColors.slate100 : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trace.head,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: trace.error != null
                  ? PennaColors.diffDelText
                  : PennaColors.slate700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            trace.messages.length == 0
                ? ''
                : tr('{0} 条消息', [trace.messages.length]),
            style: TextStyle(fontSize: 10.5, color: PennaColors.slate400),
          ),
        ],
      ),
    ),
  );
}
