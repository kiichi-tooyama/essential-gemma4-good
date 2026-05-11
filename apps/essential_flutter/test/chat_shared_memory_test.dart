import 'package:essential_flutter/features/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared memory prompt is framed as past context only', () async {
    final controller = ChatController();
    addTearDown(controller.dispose);

    await controller.addSharedMemory('ユーザーはPixelの電池設定について継続して相談している。');

    final prompt = controller.buildSharedMemoryPromptContext(
      respectCurrentSessionToggle: false,
    );

    expect(prompt, contains('過去の会話'));
    expect(prompt, contains('現在のユーザー発話ではありません'));
    expect(prompt, contains('挨拶'));
    expect(prompt, contains('Pixelの電池設定'));
  });

  test('shared memory compacts when storage is near the limit', () async {
    final controller = ChatController();
    addTearDown(controller.dispose);

    for (var index = 0; index < 18; index += 1) {
      await controller.addSharedMemory(
        'Pixel demo memory $index: ${List<String>.filled(20, 'web search location shared memory product review translation').join(' ')}',
      );
    }

    var compacted = false;
    await controller.summarizeAndWriteSharedMemorySection(
      'The user wants Pixel feature help, web-first answers, location weather demos, product comparison, and meeting translation tests.',
      enabled: true,
      summarize: (prompt) async {
        if (prompt.contains('共有メモリー全体')) {
          compacted = true;
          return '・Pixel相談はWeb検索と現在地情報を利用する\n・共有メモリは関連時だけ参考にする\n・会議翻訳と商品比較をデモで確認する';
        }
        return '・Pixel相談、Web検索、位置情報、商品比較、会議翻訳を継続中';
      },
    );

    expect(compacted, isTrue);
    expect(controller.sharedMemories.length, 1);
    expect(controller.sharedMemories.single.text, contains('共有メモリは関連時だけ参考'));
  });
}
