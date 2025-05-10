import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:training_purpose/fullscreen.dart';

void main() {
  runApp(MaterialApp(
    home: ChatPage(
      senderId: 'uniqueid3',
      receiverId: 'uniqueid2',
    ),
  ));
}

class ChatPage extends StatefulWidget {
  final String senderId;
  final String receiverId;

  const ChatPage({super.key, required this.senderId, required this.receiverId});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late IO.Socket _socket;
  List<Map<String, dynamic>> messages = [];
  final TextEditingController _msgController = TextEditingController();
  bool isLoadingMore = false;
  String? lastLoadedTimestamp;

  @override
  void initState() {
    super.initState();
    connectSocket();
    fetchMessages();
  }

  void connectSocket() {
    _socket = IO.io('http://localhost:5000', <String, dynamic>{
      'transports': ['websocket'],
      'query': {
        'userId': widget.senderId,
      },
    });

    _socket.onConnect((_) {
      print('Connected to server');
    });

    _socket.on('receive_message', (data) {
      if (data['senderId'] == widget.receiverId) {
        setState(() {
          messages.add(data);
        });
      }
    });
  }

  void fetchMessages() async {
    if (isLoadingMore) return;
    isLoadingMore = true;

    final response = await http.get(Uri.parse(
        'http://localhost:5000/api/messages?senderId=${widget.senderId}&receiverId=${widget.receiverId}&limit=30${lastLoadedTimestamp != null ? '&before=$lastLoadedTimestamp' : ''}'));

    if (response.statusCode == 200) {
      List<dynamic> newMessages = json.decode(response.body);
      setState(() {
        messages.insertAll(0, newMessages.cast<Map<String, dynamic>>());
        if (newMessages.isNotEmpty) {
          lastLoadedTimestamp = newMessages.first['timestamp'];
        }
      });
    }
    isLoadingMore = false;
  }

  void sendMessage(String text) {
    final msg = {
      'senderId': widget.senderId,
      'receiverId': widget.receiverId,
      'message': text,
      'isImage': false,
    };
    _socket.emit('send_message', msg);
    setState(() {
      messages.add({
        ...msg,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _msgController.clear();
  }

  Future<void> sendImage(File imageFile) async {
    final mimeType = lookupMimeType(imageFile.path);

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://localhost:5000/upload-image'),
    );

    request.files.add(await http.MultipartFile.fromPath(
      'image',
      imageFile.path,
      contentType: mimeType != null ? MediaType.parse(mimeType) : null,
    ));

    request.fields['senderId'] = widget.senderId;
    request.fields['receiverId'] = widget.receiverId;

    try {
      var response = await request.send();

      if (response.statusCode == 200) {
        final resBody = await response.stream.bytesToString();
        final jsonData = json.decode(resBody);
        final filePath = jsonData['filePath'];

        final msg = {
          'senderId': widget.senderId,
          'receiverId': widget.receiverId,
          'message': filePath,
          'isImage': true,
          'timestamp': DateTime.now().toIso8601String(),
        };

        _socket.emit('send_message', msg);
        setState(() {
          messages.add(msg);
        });
      } else {
        print("❌ Image upload failed: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error uploading image: $e");
    }
  }

  Future<void> _pickImageAndSend() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final File imageFile = File(pickedFile.path);
      sendImage(imageFile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (scrollInfo.metrics.pixels ==
                    scrollInfo.metrics.minScrollExtent) {
                  fetchMessages();
                }
                return true;
              },
              child: ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[messages.length - 1 - index];
                  final isMe = msg['senderId'] == widget.senderId;
                  return ListTile(
                    title: Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                          padding: EdgeInsets.all(10),
                          color: isMe ? Colors.blue : Colors.grey[300],
                          child: msg['isImage'] ?? false
                              ? GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FullScreenImage(
                                            imageUrl:
                                                'http://localhost:5000${msg['message']}',
                                          ),
                                        ));
                                  },
                                  child: Image.network(
                                    'http://localhost:5000${msg['thumbnail'] ?? msg['message']}',
                                    width: 150,
                                    height: 150,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Text(msg['message'] ?? '')),
                    ),
                    subtitle: Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(
                        msg['timestamp']?.toString() ?? '',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.image),
                  onPressed: _pickImageAndSend, // Trigger image picker
                ),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(labelText: 'Message'),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () => sendMessage(_msgController.text.trim()),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
  }
}
