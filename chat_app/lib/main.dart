import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Realtime Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatHomeScreen(),
    );
  }
}

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final TextEditingController _msgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().tryAutoLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isAuthenticated ? 'Chat: ${auth.username}' : 'Chat App'),
        actions: [
          if (auth.isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => auth.logout(),
            ),
        ],
      ),
      body: auth.isAuthenticated
          ? Column(
              children: [
                Expanded(
                  child: chat.messages.isEmpty
                      ? const Center(child: Text('No messages yet. Send one below!'))
                      : ListView.builder(
                          itemCount: chat.messages.length,
                          itemBuilder: (context, index) {
                            final msg = chat.messages[index];
                            final isMe = msg.senderId == auth.userId;
                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.deepPurple[100] : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(msg.content, style: const TextStyle(fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text(
                                      msg.status,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: msg.status == 'read'
                                            ? Colors.blue
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            decoration: const InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () {
                            if (_msgController.text.isNotEmpty) {
                              chat.sendMessage(_msgController.text);
                              _msgController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Welcome to Chat App', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      // Demo quick-login for verification
                      await auth.login('demo_user', 'password123');
                      if (context.mounted && auth.isAuthenticated) {
                        chat.initialize(auth.token!, auth.userId!);
                        chat.joinRoom('general');
                      }
                    },
                    child: const Text('Quick Login (Demo)'),
                  ),
                ],
              ),
            ),
    );
  }
}
