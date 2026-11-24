import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import 'providers/llm_http.dart';

// 「请求记录」:每次问模型时,把发出去的完整消息和它回来的全文留一份,
// 对话栏顶栏的按钮能点开看(2026-11-24 用户要求)。
//
// 只在内存里,最近 [_max] 条,重启就清空——和「模型日志」一样的做法。
// 抓的位置是 streamChat():三种协议都从那儿出去,包一层就全都有了。

/// 一次请求的完整记录。
class LlmTrace {
  LlmTrace({
    required this.model,
    required this.baseUrl,
    required this.protocol,
    required this.messages,
    required this.temperature,
    required this.topP,
    this.effort,
    this.imageCount = 0,
  }) : time = DateTime.now();

  /// 开始发的时候的时刻。
  final DateTime time;
  final String model;
  final String baseUrl;
  final String protocol;

  /// 发给模型的全部消息(system 提示、历史、当前提问都在里面)。
  final List<Map<String, String>> messages;
  final double temperature;
  final double topP;
  final String? effort;

  /// 随消息一起发出去的图片张数。
  final int imageCount;

  /// 模型回来的全文:流式时边收边攒。
  String reply = '';

  /// 从开始到收完用了多久;还没收完是 null。
  Duration? took;

  /// 出错时给用户看的一句话(只记类型和认得的原因,原文可能带着地址里的 Key)。
  String? error;

  /// 收完了没有。
  bool get done => took != null;

  String get clock =>
      [time.hour, time.minute, time.second].map((n) => '$n'.padLeft(2, '0')).join(':');

  /// 列表里那一行。
  String get head => [
    model,
    clock,
    tr('{0} 字', [sentChars]),
    if (done) tr('{0} 秒', [took!.inSeconds]),
  ].join(' · ');

  /// 发过去的文字一共多少字(不数图片)。
  int get sentChars =>
      messages.fold(0, (sum, m) => sum + (m['content'] ?? '').length);

  /// 请求全文:每条消息一段,标出角色和字数。
  String get requestText => [
    tr('模型:{0} · 协议:{1}', [model, protocol]),
    tr('地址:{0}', [baseUrl]),
    tr('参数:温度 {0} · topP {1}', [temperature, topP]),
    if (effort != null) tr('思考强度:{0}', [effort!]),
    if (imageCount > 0) tr('随消息带的图:{0} 张', [imageCount]),
    '',
    for (final m in messages)
      '──── [${m['role'] ?? ''}] ${(m['content'] ?? '').length} 字 ────\n'
          '${m['content'] ?? ''}',
  ].join('\n');

  /// 回复全文(出错时把错误也接在后面)。
  String get replyText {
    final body = reply.isEmpty ? tr('(还没有回复)') : reply;
    return error == null ? body : '$body\n\n${tr('出错:{0}', [error!])}';
  }
}

/// 全部记录,新的在前。
class LlmTraces extends ChangeNotifier {
  /// 最多留这么多条;再早的丢掉。
  static const _max = 20;

  final List<LlmTrace> _all = [];

  List<LlmTrace> get entries => List.unmodifiable(_all);

  void add(LlmTrace trace) {
    _all.insert(0, trace);
    if (_all.length > _max) _all.removeRange(_max, _all.length);
    notifyListeners();
  }

  /// 有进展(收了新的一段、收完了):叫界面刷一下。
  void bump() => notifyListeners();

  void clear() {
    if (_all.isEmpty) return;
    _all.clear();
    notifyListeners();
  }
}

/// 全局一份。
final llmTraces = LlmTraces();

/// 记一次请求:[inner] 是真正去问模型的那条流,回复边收边攒进记录。
Stream<String> traceLlm(LlmRequest request, Stream<String> inner) {
  final trace = LlmTrace(
    model: request.model,
    baseUrl: request.baseUrl,
    protocol: request.protocol,
    messages: List.unmodifiable(request.messages),
    temperature: request.temperature,
    topP: request.topP,
    effort: request.effort,
    imageCount: request.images.values.fold(0, (sum, l) => sum + l.length),
  );
  llmTraces.add(trace);
  final watch = Stopwatch()..start();
  var ticks = 0;
  return inner.transform(
    StreamTransformer<String, String>.fromHandlers(
      handleData: (delta, sink) {
        trace.reply += delta;
        sink.add(delta);
        // 流式时每 8 段刷一次界面:每来一段都重建整个窗口太吵。
        if (++ticks % 8 == 0) llmTraces.bump();
      },
      handleError: (error, stack, sink) {
        trace.error = error is LlmException ? error.message : '${error.runtimeType}';
        watch.stop();
        trace.took = watch.elapsed;
        llmTraces.bump();
        sink.addError(error, stack);
      },
      handleDone: (sink) {
        if (!trace.done) {
          watch.stop();
          trace.took = watch.elapsed;
        }
        llmTraces.bump();
        sink.close();
      },
    ),
  );
}
