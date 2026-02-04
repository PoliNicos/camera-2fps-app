import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("❌ Errore inizializzazione camere: $e");
  }
  runApp(
    const MaterialApp(home: Camera2FPS(), debugShowCheckedModeBanner: false),
  );
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

  // ═══════════════════════════════════════════════════════════
  // VARIABILI PER TIME-LAPSE 2 FPS
  // ═══════════════════════════════════════════════════════════
  Timer? _captureTimer;
  List<String> _capturedFrames = [];
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
      enableAudio: false, // No audio per time-lapse
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
      // ═══════════════════════════════════════════════════════
      // STOP REGISTRAZIONE
      // ═══════════════════════════════════════════════════════
      _captureTimer?.cancel();
      setState(() => isRecording = false);

      final duration = DateTime.now().difference(_recordingStartTime!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ $_frameCount frame catturati in ${duration.inSeconds}s\n"
            "📁 Frame salvati in memoria temporanea",
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );

      // Opzionale: qui puoi chiamare _createVideoFromFrames()
      // se hai implementato FFmpeg

      _capturedFrames.clear();
      _frameCount = 0;
      _recordingStartTime = null;
    } else {
      // ═══════════════════════════════════════════════════════
      // START REGISTRAZIONE - Cattura frame ogni 500ms (2 FPS)
      // ═══════════════════════════════════════════════════════
      setState(() {
        isRecording = true;
        _frameCount = 0;
        _recordingStartTime = DateTime.now();
      });

      // Timer che cattura un frame ogni 500ms = 2 FPS
      _captureTimer = Timer.periodic(const Duration(milliseconds: 500), (
        timer,
      ) async {
        await _captureFrame();
      });
    }
  }

  Future<void> _captureFrame() async {
    if (controller == null || !controller!.value.isInitialized) return;

    try {
      // Ottieni directory temporanea
      final Directory appDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filePath = '${appDir.path}/frame_$timestamp.jpg';

      // Cattura foto
      final XFile imageFile = await controller!.takePicture();

      // Copia nella directory permanente
      await File(imageFile.path).copy(filePath);

      // Aggiungi alla lista
      _capturedFrames.add(filePath);

      // Aggiorna contatore (solo se ancora in registrazione)
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

  // ═══════════════════════════════════════════════════════════
  // (OPZIONALE) CONVERTI FRAME IN VIDEO CON FFMPEG
  // Decommenta se hai aggiunto ffmpeg_kit_flutter al pubspec.yaml
  // ═══════════════════════════════════════════════════════════
  /*
  Future<void> _createVideoFromFrames() async {
    if (_capturedFrames.isEmpty) return;
    
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String outputPath = '${appDir.path}/timelapse_${DateTime.now().millisecondsSinceEpoch}.mp4';
    
    // Pattern per le immagini
    final String pattern = '${(await getTemporaryDirectory()).path}/frame_*.jpg';
    
    // Comando FFmpeg: unisce frame a 2 FPS
    final String command = '-framerate 2 -pattern_type glob -i "$pattern" -c:v libx264 -pix_fmt yuv420p "$outputPath"';
    
    try {
      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (returnCode!.isValueSuccess()) {
          debugPrint("✅ Video creato: $outputPath");
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Video salvato: $outputPath")),
            );
          }
        } else {
          debugPrint("❌ Errore creazione video");
        }
      });
    } catch (e) {
      debugPrint("❌ Errore FFmpeg: $e");
    }
  }
  */

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
          // ═══════════════════════════════════════════════════════
          // MENU RISOLUZIONE
          // ═══════════════════════════════════════════════════════
          DropdownButton<ResolutionPreset>(
            value: selectedRes,
            dropdownColor: Colors.grey[900],
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            underline: Container(),
            items:
                [
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
                      "⚠️ Ferma la registrazione prima di cambiare risoluzione",
                    ),
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
          // ═══════════════════════════════════════════════════════
          // ANTEPRIMA CAMERA
          // ═══════════════════════════════════════════════════════
          ClipRect(
            child: AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: CameraPreview(controller!),
            ),
          ),

          // ═══════════════════════════════════════════════════════
          // INDICATORE REGISTRAZIONE
          // ═══════════════════════════════════════════════════════
          if (isRecording)
            Positioned(
              top: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                    // Pallino rosso lampeggiante
                    TweenAnimationBuilder(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, value, child) {
                        return Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(
                              value > 0.5 ? 1.0 : 0.3,
                            ),
                          ),
                        );
                      },
                      onEnd: () {
                        if (mounted && isRecording) {
                          setState(() {}); // Riavvia animazione
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

          // ═══════════════════════════════════════════════════════
          // PULSANTE REGISTRAZIONE
          // ═══════════════════════════════════════════════════════
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

          // ═══════════════════════════════════════════════════════
          // INFO 2 FPS
          // ═══════════════════════════════════════════════════════
          if (!isRecording)
            Positioned(
              bottom: 150,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  "⏱️ 2 Frame/Secondo",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
