import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:video_editor/video_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';


late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("❌ Errore inizializzazione camere: $e");
  }
  runApp(const MaterialApp(
    home: Camera2FPS(),
    debugShowCheckedModeBanner: false,
  ));
}

class Camera2FPS extends StatefulWidget {
  const Camera2FPS({super.key});

  @override
  State<Camera2FPS> createState() => _Camera2FPSState();
}

class _Camera2FPSState extends State<Camera2FPS> {
  CameraController? controller;
  bool isRecording = false;
  ResolutionPreset selectedRes = ResolutionPreset.high;

  Timer? _captureTimer;
  final List<String> _capturedFrames = []; // ✅ FIXED: Aggiunto 'final'
  int _frameCount = 0;
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    _setupCamera(selectedRes);
  }

  Future<void> _setupCamera(ResolutionPreset res) async {
    if (controller != null) {
      await controller!.dispose();
    }

    controller = CameraController(
      _cameras[0],
      res,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("❌ Errore camera: $e");
    }
  }

  Future<void> toggleRecording() async {
    if (controller == null || !controller!.value.isInitialized) return;

    if (isRecording) {
      _captureTimer?.cancel();
      setState(() => isRecording = false);

      final duration = DateTime.now().difference(_recordingStartTime!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "✅ $_frameCount frame catturati in ${duration.inSeconds}s\n"
              "📁 Frame salvati in memoria temporanea"),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
      // ✅ ADD THIS LINE:
      if (_capturedFrames.isNotEmpty) {
        await createVideoFromFrames(_capturedFrames);
      }

      _capturedFrames.clear();
      _frameCount = 0;
      _recordingStartTime = null;
    } else {
      setState(() {
        isRecording = true;
        _frameCount = 0;
        _recordingStartTime = DateTime.now();
      });

      _captureTimer = Timer.periodic(
          const Duration(milliseconds: 500), (timer) async {
        await _captureFrame();
      });
    }
  }

  Future<void> _captureFrame() async {
    if (controller == null || !controller!.value.isInitialized) return;

    try {
      final Directory appDir = await getTemporaryDirectory();
      final String timestamp =
          DateTime.now().millisecondsSinceEpoch.toString();
      final String filePath = '${appDir.path}/frame_$timestamp.jpg';

      final XFile imageFile = await controller!.takePicture();

      await File(imageFile.path).copy(filePath);

      _capturedFrames.add(filePath);

      if (mounted && isRecording) {
        setState(() {
          _frameCount++;
        });
      }

      debugPrint("📸 Frame $_frameCount catturato: $filePath");
    } catch (e) {
      debugPrint("❌ Errore cattura frame: $e");
    }
  }

  
  Future<void> createVideoFromFrames(List<String> framePaths) async {
    if (framePaths.isEmpty) return;

    final Directory tempDir = await getTemporaryDirectory();
    final String videoPath =
        '${tempDir.path}/timelapse_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Prepare ImageSequence
    final List<ImageSequenceEntry> sequence = framePaths
        .map((path) => ImageSequenceEntry(path: path, duration: Duration(milliseconds: 500)))
        .toList(); // 500ms → 2 FPS

    try {
      await VideoEditor.createVideoFromImages(
        images: sequence,
        output: videoPath,
      );

      // Save to gallery
      final success = await GallerySaver.saveVideo(videoPath, albumName: 'Camera2FPS');
      if (success == true) {
        debugPrint("🎉 Video saved to gallery: $videoPath");
      } else {
        debugPrint("❌ Failed to save video to gallery");
      }
    } catch (e) {
      debugPrint("❌ Error creating video: $e");
    }
  }


  @override
  void dispose() {
    _captureTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                "Inizializzazione camera...",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("🎬 Camera 2 FPS (Time-Lapse)"),
        backgroundColor: Colors.black,
        actions: [
          DropdownButton<ResolutionPreset>(
            value: selectedRes,
            dropdownColor: Colors.grey[900],
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            underline: Container(),
            items: [
              ResolutionPreset.low,
              ResolutionPreset.medium,
              ResolutionPreset.high,
              ResolutionPreset.veryHigh,
              ResolutionPreset.ultraHigh,
            ].map((res) {
              return DropdownMenuItem(
                value: res,
                child: Text(res.toString().split('.').last.toUpperCase()),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null && !isRecording) {
                setState(() => selectedRes = val);
                _setupCamera(val);
              } else if (isRecording) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        "⚠️ Ferma la registrazione prima di cambiare risoluzione"),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 15),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          ClipRect(
            child: AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: CameraPreview(controller!),
            ),
          ),
          if (isRecording)
            Positioned(
              top: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, value, child) {
                        return Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white
                                .withOpacity(value > 0.5 ? 1.0 : 0.3),
                          ),
                        );
                      },
                      onEnd: () {
                        if (mounted && isRecording) {
                          setState(() {});
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "REC • Frame: $_frameCount",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: GestureDetector(
                onTap: toggleRecording,
                child: Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: [
                      BoxShadow(
                        color: (isRecording ? Colors.red : Colors.white)
                            .withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: isRecording ? 30 : 60,
                      width: isRecording ? 30 : 60,
                      decoration: BoxDecoration(
                        color: isRecording ? Colors.red : Colors.white,
                        borderRadius: BorderRadius.circular(
                          isRecording ? 8 : 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!isRecording)
            Positioned(
              bottom: 150,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  "⏱️ 2 Frame/Secondo",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}