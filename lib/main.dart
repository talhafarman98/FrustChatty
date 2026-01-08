import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
// FIX: Added 'as p' to avoid conflict with BuildContext
import 'package:path/path.dart' as p; 
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animations/animations.dart';

// --- MAIN ENTRY POINT ---
void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const FrustChatApp(),
    ),
  );
}

// --- APP THEME & CONSTANTS ---
class FrustChatApp extends StatelessWidget {
  const FrustChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'FrustChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Color(state.accentColor),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: SharedAxisPageTransitionsBuilder(
              transitionType: SharedAxisTransitionType.horizontal,
            ),
          },
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// --- DATABASE MODELS ---
class Contact {
  final int? id;
  final String name;
  final String number;
  final String? imagePath;
  final String lastMessage;
  final int lastMessageTime;
  // Customization per chat
  final String? customBgPath; 
  final int? customBgColor;
  final int? customBubbleColor;
  final double? customTransparency;

  Contact({
    this.id, required this.name, required this.number, this.imagePath, 
    this.lastMessage = "", this.lastMessageTime = 0,
    this.customBgPath, this.customBgColor, this.customBubbleColor, this.customTransparency
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'number': number, 'imagePath': imagePath, 
    'lastMessage': lastMessage, 'lastMessageTime': lastMessageTime,
    'customBgPath': customBgPath, 'customBgColor': customBgColor,
    'customBubbleColor': customBubbleColor, 'customTransparency': customTransparency
  };

  static Contact fromMap(Map<String, dynamic> map) => Contact(
    id: map['id'], name: map['name'], number: map['number'], imagePath: map['imagePath'], 
    lastMessage: map['lastMessage'] ?? "", lastMessageTime: map['lastMessageTime'] ?? 0,
    customBgPath: map['customBgPath'], customBgColor: map['customBgColor'],
    customBubbleColor: map['customBubbleColor'], customTransparency: map['customTransparency']
  );
}

class Message {
  final int? id;
  final int contactId;
  final String text;
  final int timestamp;
  final int isDeleted; // 0 = false, 1 = true
  final String? mediaPath; // Path to image/video if sent

  Message({this.id, required this.contactId, required this.text, required this.timestamp, this.isDeleted = 0, this.mediaPath});

  Map<String, dynamic> toMap() => {
    'id': id, 'contactId': contactId, 'text': text, 'timestamp': timestamp, 
    'isDeleted': isDeleted, 'mediaPath': mediaPath
  };
  
  static Message fromMap(Map<String, dynamic> map) => Message(
    id: map['id'], contactId: map['contactId'], text: map['text'], 
    timestamp: map['timestamp'], isDeleted: map['isDeleted'] ?? 0,
    mediaPath: map['mediaPath']
  );
}

// --- STATE MANAGEMENT ---
class AppState extends ChangeNotifier {
  Database? _db;
  List<Contact> contacts = [];
  List<Contact> filteredContacts = [];
  List<Message> currentMessages = [];
  
  // Global Settings
  int accentColor = 0xFF7C4DFF; // Deep Purple Default
  String fontFamily = 'Outfit';
  double globalFontSize = 16.0;

  AppState() { _initDB(); }

  Future<void> _initDB() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      // FIX: Used p.join instead of join
      p.join(dbPath, 'frustchat_v2.db'),
      onCreate: (db, version) {
        db.execute('''CREATE TABLE contacts(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, number TEXT, imagePath TEXT, 
          lastMessage TEXT, lastMessageTime INTEGER,
          customBgPath TEXT, customBgColor INTEGER, customBubbleColor INTEGER, customTransparency REAL
        )''');
        db.execute('CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT, contactId INTEGER, text TEXT, timestamp INTEGER, isDeleted INTEGER, mediaPath TEXT)');
        db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
      },
      version: 2,
    );
    await _loadSettings();
    await loadContacts();
  }

  Future<void> _loadSettings() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> maps = await _db!.query('settings');
    for (var map in maps) {
      if (map['key'] == 'accentColor') accentColor = int.parse(map['value']);
      if (map['key'] == 'fontFamily') fontFamily = map['value'];
      if (map['key'] == 'globalFontSize') globalFontSize = double.parse(map['value']);
    }
    notifyListeners();
  }

  Future<void> saveSetting(String key, String value) async {
    await _db!.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    if (key == 'accentColor') accentColor = int.parse(value);
    if (key == 'fontFamily') fontFamily = value;
    if (key == 'globalFontSize') globalFontSize = double.parse(value);
    notifyListeners();
  }

  Future<void> loadContacts() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> maps = await _db!.query('contacts', orderBy: "lastMessageTime DESC");
    contacts = List.generate(maps.length, (i) => Contact.fromMap(maps[i]));
    filteredContacts = List.from(contacts);
    notifyListeners();
  }

  void searchContacts(String query) {
    if (query.isEmpty) {
      filteredContacts = List.from(contacts);
    } else {
      filteredContacts = contacts.where((c) => c.name.toLowerCase().contains(query.toLowerCase())).toList();
    }
    notifyListeners();
  }

  Future<void> addContact(String name, String number, String? path) async {
    await _db!.insert('contacts', Contact(name: name, number: number, imagePath: path).toMap());
    await loadContacts();
  }

  Future<void> deleteContact(int id) async {
    await _db!.delete('contacts', where: 'id = ?', whereArgs: [id]);
    await _db!.delete('messages', where: 'contactId = ?', whereArgs: [id]);
    await loadContacts();
  }

  Future<void> updateContactCustomization(Contact c, {String? bgPath, int? bgColor, int? bubbleColor, double? transparency}) async {
    Map<String, dynamic> data = {
      'customBgPath': bgPath ?? c.customBgPath,
      'customBgColor': bgColor ?? c.customBgColor,
      'customBubbleColor': bubbleColor ?? c.customBubbleColor,
      'customTransparency': transparency ?? c.customTransparency
    };
    await _db!.update('contacts', data, where: 'id = ?', whereArgs: [c.id]);
    await loadContacts(); 
    notifyListeners(); 
  }

  Future<void> loadMessages(int contactId) async {
    if (_db == null) return;
    final List<Map<String, dynamic>> maps = await _db!.query(
      'messages', where: 'contactId = ?', whereArgs: [contactId], orderBy: "timestamp ASC"
    );
    currentMessages = List.generate(maps.length, (i) => Message.fromMap(maps[i]));
    notifyListeners();
  }

  Future<void> sendMessage(int contactId, String text, {String? mediaPath}) async {
    int time = DateTime.now().millisecondsSinceEpoch;
    await _db!.insert('messages', Message(contactId: contactId, text: text, timestamp: time, mediaPath: mediaPath).toMap());
    
    String preview = mediaPath != null ? "📷 Image" : text;
    await _db!.update('contacts', {'lastMessage': preview, 'lastMessageTime': time}, where: 'id = ?', whereArgs: [contactId]);
    
    await loadMessages(contactId);
    await loadContacts();
  }

  Future<void> deleteMessage(int msgId) async {
    await _db!.update('messages', {'isDeleted': 1, 'text': 'This message is deleted'}, where: 'id = ?', whereArgs: [msgId]);
    final msg = currentMessages.firstWhere((m) => m.id == msgId);
    await loadMessages(msg.contactId);
  }

  // --- BACKUP ---
  Future<void> backupData(BuildContext context) async {
    try {
      final allContacts = await _db!.query('contacts');
      final allMessages = await _db!.query('messages');
      Map<String, dynamic> backup = {
        'contacts': allContacts,
        'messages': allMessages,
        'version': 2
      };
      String jsonString = jsonEncode(backup);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/frustchat_backup_v2.json');
      await file.writeAsString(jsonString);
      await Share.shareXFiles([XFile(file.path)], text: 'FrustChat Backup');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup Error: $e")));
    }
  }

  Future<void> restoreData(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        Map<String, dynamic> backup = jsonDecode(content);

        await _db!.delete('contacts');
        await _db!.delete('messages');
        Batch batch = _db!.batch();
        for (var c in backup['contacts']) batch.insert('contacts', c);
        for (var m in backup['messages']) batch.insert('messages', m);
        await batch.commit();
        await loadContacts();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restored!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Backup File")));
    }
  }
}

// --- WIDGETS ---

class GlowingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color glowColor;
  final double radius;

  const GlowingButton({super.key, required this.child, required this.onTap, required this.glowColor, this.radius = 16});

  @override
  State<GlowingButton> createState() => _GlowingButtonState();
}

class _GlowingButtonState extends State<GlowingButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _isPressed 
            ? [BoxShadow(color: widget.glowColor.withOpacity(0.6), blurRadius: 20, spreadRadius: 2)]
            : [],
        ),
        child: widget.child,
      ),
    );
  }
}

class GradientBorderContainer extends StatelessWidget {
  final Widget child;
  final double height;
  final Color accent;
  const GradientBorderContainer({super.key, required this.child, this.height = 60, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withOpacity(0.5), width: 1.5),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.1), blurRadius: 10)],
      ),
      child: child,
    );
  }
}

// --- SCREENS ---

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage("https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=1000&auto=format&fit=crop"), 
            fit: BoxFit.cover,
            opacity: 0.2
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF121212)],
          )
        ),
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("FrustChat", style: GoogleFonts.righteous(color: Colors.white, fontSize: 32)),
                    GlowingButton(
                      glowColor: Color(state.accentColor),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24)
                        ),
                        child: const Icon(Icons.settings, color: Colors.white),
                      ),
                    )
                  ],
                ),
              ),
              
              // SEARCH BAR
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GradientBorderContainer(
                  accent: Color(state.accentColor),
                  height: 50,
                  child: TextField(
                    onChanged: (val) => state.searchContacts(val),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, color: Colors.grey),
                      hintText: "Search chats...",
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12)
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // CHAT LIST
              Expanded(
                child: state.filteredContacts.isEmpty 
                  ? Center(child: Text("No chats found.", style: GoogleFonts.outfit(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: state.filteredContacts.length,
                      itemBuilder: (ctx, i) {
                        final contact = state.filteredContacts[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlowingButton(
                            glowColor: Color(state.accentColor),
                            onTap: () {
                              context.read<AppState>().loadMessages(contact.id!);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(contact: contact)));
                            },
                            child: GestureDetector(
                              onLongPress: () {
                                showDialog(
                                  context: context, 
                                  builder: (_) => AlertDialog(
                                    title: const Text("Delete Chat?"),
                                    content: const Text("This cannot be undone."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                                      TextButton(
                                        onPressed: () {
                                          state.deleteContact(contact.id!);
                                          Navigator.pop(context);
                                        }, 
                                        child: const Text("Delete", style: TextStyle(color: Colors.red))
                                      )
                                    ],
                                  )
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E).withOpacity(0.8),
                                  border: Border.all(color: Colors.white10),
                                  borderRadius: BorderRadius.circular(16)
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundImage: contact.imagePath != null ? FileImage(File(contact.imagePath!)) : null,
                                      backgroundColor: Colors.grey[900],
                                      child: contact.imagePath == null ? Text(contact.name[0], style: const TextStyle(color: Colors.white)) : null,
                                    ),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(contact.name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(
                                            contact.lastMessage.isEmpty ? "No messages yet" : contact.lastMessage, 
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.grey[500], fontSize: 13)
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (contact.lastMessageTime > 0)
                                      Text(
                                        DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(contact.lastMessageTime)),
                                        style: TextStyle(color: Color(state.accentColor), fontSize: 11)
                                      )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: GlowingButton(
        glowColor: Color(state.accentColor),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen())),
        child: Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: Color(state.accentColor),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2)
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtx = ScrollController();

  void _send(AppState state) {
    if (_ctrl.text.trim().isEmpty) return;
    state.sendMessage(widget.contact.id!, _ctrl.text);
    _ctrl.clear();
    _scrollToBottom();
  }

  void _sendFile(AppState state) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
       final appDir = await getApplicationDocumentsDirectory();
       // FIX: Used p.basename
       final fileName = p.basename(result.files.single.path!);
       final savedImage = await File(result.files.single.path!).copy('${appDir.path}/$fileName');
       state.sendMessage(widget.contact.id!, "", mediaPath: savedImage.path);
       _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtx.hasClients) {
        _scrollCtx.animateTo(_scrollCtx.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _showCustomizeDialog(AppState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Customize Chat", style: GoogleFonts.outfit(color: Colors.white, fontSize: 20)),
              const Divider(color: Colors.grey),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.white),
                title: const Text("Set Background Image", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (img != null) {
                     state.updateContactCustomization(widget.contact, bgPath: img.path);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.color_lens, color: Colors.white),
                title: const Text("Set Background Color", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickColor(state, (c) => state.updateContactCustomization(widget.contact, bgColor: c.value, bgPath: ""));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bubble_chart, color: Colors.white),
                title: const Text("Set Bubble Color", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickColor(state, (c) => state.updateContactCustomization(widget.contact, bubbleColor: c.value));
                },
              ),
            ],
          ),
        );
      }
    );
  }

  void _pickColor(AppState state, Function(Color) onSelect) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Pick Color", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: Colors.blue,
            onColorChanged: onSelect,
            enableAlpha: false,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentContact = state.contacts.firstWhere((c) => c.id == widget.contact.id, orElse: () => widget.contact);
    
    BoxDecoration bgDeco = const BoxDecoration(color: Colors.black);
    if (currentContact.customBgPath != null && currentContact.customBgPath!.isNotEmpty) {
      bgDeco = BoxDecoration(
        image: DecorationImage(image: FileImage(File(currentContact.customBgPath!)), fit: BoxFit.cover, opacity: currentContact.customTransparency ?? 0.5)
      );
    } else if (currentContact.customBgColor != null) {
      bgDeco = BoxDecoration(color: Color(currentContact.customBgColor!).withOpacity(currentContact.customTransparency ?? 1.0));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent))),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: currentContact.imagePath != null ? FileImage(File(currentContact.imagePath!)) : null,
              radius: 18,
              child: currentContact.imagePath == null ? Text(currentContact.name[0]) : null,
            ),
            const SizedBox(width: 10),
            Text(currentContact.name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showCustomizeDialog(state),
          )
        ],
        shape: const Border(bottom: BorderSide(color: Colors.white24, width: 1)),
      ),
      body: Container(
        decoration: bgDeco,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtx,
                padding: const EdgeInsets.fromLTRB(16, 120, 16, 16),
                itemCount: state.currentMessages.length,
                itemBuilder: (ctx, i) {
                  final msg = state.currentMessages[i];
                  return GestureDetector(
                    onLongPress: () {
                      if (msg.isDeleted == 0) {
                        showDialog(context: context, builder: (_) => AlertDialog(
                          title: const Text("Delete Message?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                            TextButton(onPressed: () { state.deleteMessage(msg.id!); Navigator.pop(context); }, child: const Text("Delete", style: TextStyle(color: Colors.red))),
                          ]
                        ));
                      }
                    },
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: msg.isDeleted == 1 
                                    ? Colors.grey[900] 
                                    : (currentContact.customBubbleColor != null ? Color(currentContact.customBubbleColor!) : Color(state.accentColor).withOpacity(0.2)),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(20),
                                    topRight: Radius.circular(20),
                                    bottomLeft: Radius.circular(20),
                                    bottomRight: Radius.circular(2)
                                  ),
                                  border: Border.all(color: Colors.white24, width: 1)
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (msg.mediaPath != null && msg.isDeleted == 0)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.file(File(msg.mediaPath!), height: 150, fit: BoxFit.cover),
                                        ),
                                      ),
                                    Text(
                                      msg.text,
                                      style: TextStyle(
                                        color: msg.isDeleted == 1 ? Colors.grey : Colors.white, 
                                        fontSize: state.globalFontSize,
                                        fontStyle: msg.isDeleted == 1 ? FontStyle.italic : FontStyle.normal
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp)),
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black,
                border: const Border(top: BorderSide(color: Colors.white24)),
                boxShadow: [BoxShadow(color: Color(state.accentColor).withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))]
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.attach_file, color: Color(state.accentColor)),
                    onPressed: () => _sendFile(state),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white24)
                      ),
                      child: TextField(
                        controller: _ctrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Type",
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlowingButton(
                    glowColor: Color(state.accentColor),
                    radius: 30,
                    onTap: () => _send(state),
                    child: CircleAvatar(
                      backgroundColor: Color(state.accentColor),
                      child: const Icon(Icons.arrow_upward, color: Colors.white),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});
  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _nameCtrl = TextEditingController();
  final _numCtrl = TextEditingController();
  String? _imagePath;

  Future<void> _pickImage() async {
    final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      // FIX: Used p.basename
      final fileName = p.basename(image.path);
      final savedImage = await File(image.path).copy('${appDir.path}/$fileName');
      setState(() => _imagePath = savedImage.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(context.watch<AppState>().accentColor);
    return Scaffold(
      appBar: AppBar(title: const Text("Create Entity"), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2),
                  image: _imagePath != null ? DecorationImage(image: FileImage(File(_imagePath!)), fit: BoxFit.cover) : null
                ),
                child: _imagePath == null ? const Icon(Icons.camera_alt, color: Colors.grey, size: 40) : null,
              ),
            ),
            const SizedBox(height: 30),
            GradientBorderContainer(
              accent: accent,
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Name", prefixIcon: Icon(Icons.person, color: Colors.grey), border: InputBorder.none, contentPadding: EdgeInsets.all(15)),
              ),
            ),
            const SizedBox(height: 20),
            GradientBorderContainer(
              accent: accent,
              child: TextField(
                controller: _numCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: "Number", prefixIcon: Icon(Icons.phone, color: Colors.grey), border: InputBorder.none, contentPadding: EdgeInsets.all(15)),
              ),
            ),
            const SizedBox(height: 40),
            GlowingButton(
              glowColor: accent,
              onTap: () {
                if (_nameCtrl.text.isNotEmpty) {
                  context.read<AppState>().addContact(_nameCtrl.text, _numCtrl.text, _imagePath);
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: double.infinity, height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(15)),
                child: const Text("Initialize Chat", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- SETTINGS HIERARCHY ---

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSettingsGroup(
            "Appearance",
            [
              ListTile(
                title: const Text("Global Font Size", style: TextStyle(color: Colors.white)),
                trailing: Text("${state.globalFontSize.toInt()}"),
                onTap: () => _showFontSizeDialog(context, state),
              ),
              ListTile(
                title: const Text("Accent Color", style: TextStyle(color: Colors.white)),
                trailing: CircleAvatar(backgroundColor: Color(state.accentColor), radius: 10),
                onTap: () => _pickGlobalColor(context, state),
              ),
            ]
          ),
          const SizedBox(height: 20),
          _buildSettingsGroup(
            "System",
            [
              ListTile(
                title: const Text("Data Management", style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataManagementScreen())),
              ),
            ]
          ),
          const SizedBox(height: 50),
          const Center(child: Text("Created by Muhammad Talha", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 10, bottom: 10), child: Text(title, style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10)
          ),
          child: Column(children: children),
        )
      ],
    );
  }

  void _showFontSizeDialog(BuildContext context, AppState state) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Font Size"),
      content: Slider(
        value: state.globalFontSize, min: 12, max: 24, 
        onChanged: (v) => state.saveSetting('globalFontSize', v.toString())
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
    ));
  }

  void _pickGlobalColor(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Accent Color"),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: Color(state.accentColor),
            onColorChanged: (c) => state.saveSetting('accentColor', c.value.toString()), 
            enableAlpha: false,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))],
      ),
    );
  }
}

class DataManagementScreen extends StatelessWidget {
  const DataManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text("Data Management"), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white10)
            ),
            child: Column(
              children: [
                 ListTile(
                  leading: const Icon(Icons.save, color: Colors.blue),
                  title: const Text("Backup All Chats", style: TextStyle(color: Colors.white)),
                  onTap: () => state.backupData(context),
                ),
                const Divider(color: Colors.grey, height: 1),
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.green),
                  title: const Text("Restore from Backup", style: TextStyle(color: Colors.white)),
                  onTap: () => state.restoreData(context),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
