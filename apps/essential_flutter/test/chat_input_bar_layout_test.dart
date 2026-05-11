import 'package:essential_flutter/features/chat/chat_controller.dart';
import 'package:essential_flutter/features/chat/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat input keeps a wide text field on narrow phones', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ChatInputBar(
                controller: controller,
                enabled: true,
                isGenerating: false,
                modelLabel: 'Gemma',
                adapterLabel: null,
                hasAvailableModels: true,
                onChooseModel: () {},
                onChooseAdapter: () {},
                onOpenModels: () {},
                onSendText: () async {},
                onSendMultimodal:
                    (String text, List<ChatAttachment> attachments) async {},
                onQuickAction: (String prompt) async {},
                onStop: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFieldWidth = tester.getSize(find.byType(TextField)).width;
    expect(textFieldWidth, greaterThanOrEqualTo(230));
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });
}
