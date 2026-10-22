import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  runApp(const AiVideoEditorApp());
}

class AiVideoEditorApp extends StatefulWidget {
  const AiVideoEditorApp({super.key});

  @override
  State<AiVideoEditorApp> createState() => _AiVideoEditorAppState();
}

class _AiVideoEditorAppState extends State<AiVideoEditorApp> {
  Locale _locale = const Locale('ar');

  void _toggleLanguage() {
    setState(() {
      _locale = _locale.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '.edit',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        primaryColor: const Color(0xFFFFD700),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD700),
          secondary: Color(0xFF00CEC9),
          surface: Color(0xFF1E1E24),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141418),
          elevation: 0,
        ),
      ),
      home: HomeScreen(
        currentLocale: _locale,
        onToggleLanguage: _toggleLanguage,
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class HomeScreen extends StatefulWidget {
  final Locale currentLocale;
  final VoidCallback onToggleLanguage;

  const HomeScreen({
    super.key,
    required this.currentLocale,
    required this.onToggleLanguage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  String backendUrl = 'http://127.0.0.1:8000';
  String? projectId;

  PlatformFile? _videoFile;
  PlatformFile? _audioFile;

  bool _isUploading = false;
  bool _isProcessing = false;
  String _jobStatus = 'idle'; // idle, uploading, planning, processing, completed, error
  double _processingProgress = 0.0;
  String? _statusMessage;
  String? _previewVideoUrl;

  VideoPlayerController? _videoPlayerController;

  final List<ChatMessage> _messages = [];

  final List<String> _samplePromptsAr = [
    "اجعل فيديو السيارة سينمائياً وقوياً",
    "زامِن التقطيعات مع إيقاع الموسيقى",
    "اجعل الإضاءة مشرقة وفخمة",
  ];

  final List<String> _samplePromptsEn = [
    "Make my car video look cinematic and aggressive.",
    "Synchronize cuts with the music beat.",
    "Make my house look luxurious and bright.",
  ];

  @override
  void initState() {
    super.initState();
    _addInitialAiMessage();
  }

  void _addInitialAiMessage() {
    final isAr = widget.currentLocale.languageCode == 'ar';
    _messages.add(ChatMessage(
      text: isAr
          ? "أهلاً بك! أنا مساعدك الذكي لمونتاج الفيديو. ارفع مقاطعك واضف الموسيقى واخبرني بالتعديل المطلوب."
          : "Welcome! I'm your AI video editing assistant. Upload footage, add music, and tell me what edit you want.",
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _promptController.dispose();
    _chatScrollController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _videoFile = result.files.first;
          _previewVideoUrl = null;
        });
        _addMessage(
          widget.currentLocale.languageCode == 'ar'
              ? "تم اختيار الفيديو: ${_videoFile!.name}"
              : "Selected video: ${_videoFile!.name}",
          isUser: false,
        );
      }
    } catch (e) {
      _showSnackBar("Error picking video: $e");
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _audioFile = result.files.first;
        });
        _addMessage(
          widget.currentLocale.languageCode == 'ar'
              ? "تم اختيار ملف الصوت: ${_audioFile!.name}"
              : "Selected audio: ${_audioFile!.name}",
          isUser: false,
        );
      }
    } catch (e) {
      _showSnackBar("Error picking audio: $e");
    }
  }

  void _addMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submitPrompt(String promptText) async {
    final text = promptText.trim();
    if (text.isEmpty) return;

    if (_videoFile == null) {
      _showSnackBar(
        widget.currentLocale.languageCode == 'ar'
            ? "الرجاء رفع فيديو أولاً!"
            : "Please select a video file first!",
      );
      return;
    }

    _promptController.clear();
    _addMessage(text, isUser: true);

    setState(() {
      _isUploading = true;
      _jobStatus = 'uploading';
      _statusMessage = widget.currentLocale.languageCode == 'ar'
          ? 'جاري تجهيز المشروع وإرسال البيانات...'
          : 'Setting up project & uploading media...';
    });

    try {
      final uri = Uri.parse('$backendUrl/api/projects');
      var request = http.MultipartRequest('POST', uri);
      request.fields['prompt'] = text;
      request.fields['language'] = widget.currentLocale.languageCode;
      if (projectId != null) {
        request.fields['project_id'] = projectId!;
      }

      if (_videoFile?.path != null) {
        request.files.add(await http.MultipartFile.fromPath('video', _videoFile!.path!));
      } else if (_videoFile?.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'video',
          _videoFile!.bytes!,
          filename: _videoFile!.name,
        ));
      }

      if (_audioFile?.path != null) {
        request.files.add(await http.MultipartFile.fromPath('audio', _audioFile!.path!));
      } else if (_audioFile?.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'audio',
          _audioFile!.bytes!,
          filename: _audioFile!.name,
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        projectId = data['project_id'];
        final aiExplanation = data['ai_explanation'] ?? '';

        _addMessage(aiExplanation, isUser: false);

        final jobId = data['job_id'];
        _pollJobStatus(jobId);
      } else {
        final err = jsonDecode(response.body);
        setState(() {
          _isUploading = false;
          _isProcessing = false;
          _jobStatus = 'error';
          _statusMessage = err['detail'] ?? 'Failed to submit request';
        });
        _addMessage('Error: ${_statusMessage}', isUser: false);
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _isProcessing = false;
        _jobStatus = 'error';
        _statusMessage = 'Network error: $e';
      });
      _addMessage('Network error occurred while connecting to backend.', isUser: false);
    }
  }

  Future<void> _pollJobStatus(String jobId) async {
    setState(() {
      _isUploading = false;
      _isProcessing = true;
      _jobStatus = 'processing';
      _statusMessage = widget.currentLocale.languageCode == 'ar'
          ? 'جاري إنشاء وتقطيع الفيديو...'
          : 'Processing and rendering video edit...';
    });

    bool finished = false;
    while (!finished) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final res = await http.get(Uri.parse('$backendUrl/api/jobs/$jobId'));
        if (res.statusCode == 200) {
          final jobData = jsonDecode(res.body);
          final status = jobData['status'];
          final progress = (jobData['progress'] as num?)?.toDouble() ?? 0.0;
          final msg = jobData['message'] ?? '';

          setState(() {
            _processingProgress = progress;
            _statusMessage = msg;
          });

          if (status == 'completed') {
            finished = true;
            final outputUrl = '$backendUrl${jobData['output_url']}';
            setState(() {
              _isProcessing = false;
              _jobStatus = 'completed';
              _previewVideoUrl = outputUrl;
            });
            _initializeVideoPlayer(outputUrl);
            _addMessage(
              widget.currentLocale.languageCode == 'ar'
                  ? "اكتمل التعديل! يمكنك الآن مشاهدة ومعاينة الفيديو."
                  : "Edit completed! You can now preview and export your video below.",
              isUser: false,
            );
          } else if (status == 'failed') {
            finished = true;
            setState(() {
              _isProcessing = false;
              _jobStatus = 'error';
              _statusMessage = jobData['error'] ?? 'Rendering failed';
            });
            _addMessage('Processing failed: ${_statusMessage}', isUser: false);
          }
        }
      } catch (e) {
        finished = true;
        setState(() {
          _isProcessing = false;
          _jobStatus = 'error';
          _statusMessage = 'Error checking job status: $e';
        });
      }
    }
  }

  void _initializeVideoPlayer(String url) {
    _videoPlayerController?.dispose();
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        setState(() {});
        _videoPlayerController!.play();
      });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.currentLocale.languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              '.edit',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: isAr ? 'English' : 'العربية',
            onPressed: widget.onToggleLanguage,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Video Preview Area
            _buildVideoPreviewSection(isAr),

            // Selected Media & Action Badges
            _buildMediaSelectionHeader(isAr),

            // Processing Status Indicator
            if (_isUploading || _isProcessing) _buildStatusBanner(isAr),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildChatMessageTile(msg);
                },
              ),
            ),

            // Quick Prompt Chips
            _buildQuickPromptChips(isAr),

            // Bottom Input Bar
            _buildInputBar(isAr),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreviewSection(bool isAr) {
    return Container(
      width: double.infinity,
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3), width: 1),
      ),
      child: _previewVideoUrl != null && _videoPlayerController != null && _videoPlayerController!.value.isInitialized
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _videoPlayerController!.value.aspectRatio,
                    child: VideoPlayer(_videoPlayerController!),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: IconButton(
                      icon: Icon(
                        _videoPlayerController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        size: 40,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          if (_videoPlayerController!.value.isPlaying) {
                            _videoPlayerController!.pause();
                          } else {
                            _videoPlayerController!.play();
                          }
                        });
                      },
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(isAr ? 'تصدير (MP4)' : 'Export MP4'),
                      onPressed: () {
                        _showSnackBar(
                          isAr
                              ? "تم حفظ الفيديو بالصيغة العمودية 9:16 بنجاح!"
                              : "Export ready! High quality 9:16 vertical MP4 video.",
                        );
                      },
                    ),
                  )
                ],
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Styled Background Image depicting luxury car in front of a majestic palace
                  Image.network(
                    'https://images.unsplash.com/photo-1617814076367-b759c7d7e738?q=80&w=1000',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2A281E), Color(0xFF141418)],
                        ),
                      ),
                    ),
                  ),
                  // Dark luxury gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.75),
                        ],
                      ),
                    ),
                  ),
                  // Overlay Content: Icon & Text
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.cloud_upload_outlined,
                          size: 38,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _videoFile == null
                            ? (isAr ? 'اختر ملف فيديو لبدء المونتاج' : 'Select a video file to start editing')
                            : (isAr ? 'جاهز للتعديل بالذكاء الاصطناعي' : 'Ready for AI edit processing'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMediaSelectionHeader(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _pickVideo,
            icon: const Icon(Icons.add_a_photo, size: 18, color: Colors.black),
            label: Text(
              _videoFile == null ? (isAr ? '+ اختر فيديو' : '+ Select Video') : _videoFile!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFFD700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _pickAudio,
            icon: const Icon(Icons.audiotrack, size: 18, color: Color(0xFFFFD700)),
            label: Text(
              _audioFile == null ? (isAr ? '+ إضافة صوت' : '+ Add Audio') : _audioFile!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(bool isAr) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2B55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _statusMessage ?? (isAr ? 'جاري المعالجة...' : 'Processing...'),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                '${(_processingProgress * 100).toInt()}%',
                style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
              )
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _processingProgress,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessageTile(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: msg.isUser ? const Color(0xFF3A341C) : const Color(0xFF1E1E24),
          border: msg.isUser ? Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)) : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
        ),
      ),
    );
  }

  Widget _buildQuickPromptChips(bool isAr) {
    final prompts = isAr ? _samplePromptsAr : _samplePromptsEn;
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          final prompt = prompts[index];
          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: ActionChip(
              backgroundColor: const Color(0xFF1E1E24),
              side: BorderSide(color: const Color(0xFFFFD700).withOpacity(0.3)),
              label: Text(
                prompt,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              onPressed: () {
                _submitPrompt(prompt);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(bool isAr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF141418),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: isAr ? 'صف التعديل الذي تريده...' : 'Describe the edit you want...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: const Color(0xFF1E1E24),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (val) => _submitPrompt(val),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
            ),
            icon: const Icon(Icons.send_rounded, color: Colors.black),
            onPressed: () {
              _submitPrompt(_promptController.text);
            },
          ),
        ],
      ),
    );
  }
}
