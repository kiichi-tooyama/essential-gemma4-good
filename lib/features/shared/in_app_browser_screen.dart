import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InAppBrowserScreen extends StatefulWidget {
  const InAppBrowserScreen({required this.url, this.title, super.key});

  final String url;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InAppBrowserScreen(url: uri.toString(), title: title),
      ),
    );
  }

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  late final WebViewController _controller;
  var _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _loadingProgress = progress);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title?.trim().isNotEmpty ?? false
              ? widget.title!.trim()
              : Uri.parse(widget.url).host,
        ),
        actions: <Widget>[
          PopupMenuButton<_BrowserAction>(
            tooltip: 'メニュー',
            onSelected: (action) async {
              switch (action) {
                case _BrowserAction.openExternal:
                  await launchUrl(
                    Uri.parse(widget.url),
                    mode: LaunchMode.externalApplication,
                  );
                case _BrowserAction.reload:
                  await _controller.reload();
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<_BrowserAction>>[
              PopupMenuItem<_BrowserAction>(
                value: _BrowserAction.openExternal,
                child: Text('外部ブラウザーで開く'),
              ),
              PopupMenuItem<_BrowserAction>(
                value: _BrowserAction.reload,
                child: Text('再読み込み'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_loadingProgress < 100)
            LinearProgressIndicator(value: _loadingProgress / 100),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

enum _BrowserAction { openExternal, reload }
