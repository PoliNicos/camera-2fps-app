package com.tuonome.camera_2fps_app  // ✅ Deve corrispondere a namespace in build.gradle.kts

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.camera2fps/video"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "createVideo") {
                val frames = call.argument<List<String>>("frames")
                val outputPath = call.argument<String>("outputPath")
                val fps = call.argument<Int>("fps") ?: 2

                if (frames != null && outputPath != null) {
                    try {
                        createVideoFromImages(frames, outputPath, fps)
                        result.success(outputPath)
                    } catch (e: Exception) {
                        Log.e("VideoCreator", "Error creating video", e)
                        result.error("VIDEO_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing frames or output path", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun createVideoFromImages(imagePaths: List<String>, outputPath: String, fps: Int) {
        Log.d("VideoCreator", "Starting video creation with ${imagePaths.size} frames at $fps FPS")

        // Leggi la prima immagine per ottenere dimensioni
        val firstBitmap = BitmapFactory.decodeFile(imagePaths[0])
        val width = firstBitmap.width
        val height = firstBitmap.height
        firstBitmap.recycle()

        Log.d("VideoCreator", "Video dimensions: ${width}x${height}")

        // Configura MediaFormat
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
        format.setInteger(MediaFormat.KEY_BIT_RATE, 2000000) // 2 Mbps
        format.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)

        // Crea encoder
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        // Crea muxer
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIndex = -1
        var muxerStarted = false

        val bufferInfo = MediaCodec.BufferInfo()
        val frameDurationUs = 1_000_000L / fps // Microseconds per frame

        try {
            // Processa ogni frame
            for ((index, imagePath) in imagePaths.withIndex()) {
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap == null) {
                    Log.w("VideoCreator", "Failed to load image: $imagePath")
                    continue
                }

                // Converti bitmap in YUV
                val inputBuffer = encoder.getInputBuffer(encoder.dequeueInputBuffer(-1))
                if (inputBuffer != null) {
                    val yuvData = bitmapToYUV420(bitmap, width, height)
                    inputBuffer.clear()
                    inputBuffer.put(yuvData)

                    val presentationTimeUs = index * frameDurationUs
                    encoder.queueInputBuffer(
                        encoder.dequeueInputBuffer(-1),
                        0,
                        yuvData.size,
                        presentationTimeUs,
                        0
                    )
                }

                bitmap.recycle()

                // Drain encoder
                while (true) {
                    val outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 0)
                    
                    if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (muxerStarted) {
                            throw RuntimeException("Format changed twice")
                        }
                        val newFormat = encoder.outputFormat
                        trackIndex = muxer.addTrack(newFormat)
                        muxer.start()
                        muxerStarted = true
                        Log.d("VideoCreator", "Muxer started")
                    } else if (outputBufferIndex >= 0) {
                        val outputBuffer = encoder.getOutputBuffer(outputBufferIndex)
                        if (outputBuffer != null && bufferInfo.size > 0) {
                            if (muxerStarted) {
                                outputBuffer.position(bufferInfo.offset)
                                outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                                muxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                            }
                        }
                        encoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    } else {
                        break
                    }
                }

                Log.d("VideoCreator", "Processed frame ${index + 1}/${imagePaths.size}")
            }

            // Segnala fine stream
            val inputBufferIndex = encoder.dequeueInputBuffer(-1)
            encoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)

            // Drain finale
            while (true) {
                val outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputBufferIndex >= 0) {
                    val outputBuffer = encoder.getOutputBuffer(outputBufferIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        if (muxerStarted) {
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            muxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                        }
                    }
                    encoder.releaseOutputBuffer(outputBufferIndex, false)

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
            }

            Log.d("VideoCreator", "Video creation completed: $outputPath")
        } finally {
            encoder.stop()
            encoder.release()
            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()
        }
    }

    private fun bitmapToYUV420(bitmap: Bitmap, width: Int, height: Int): ByteArray {
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val yuvSize = width * height * 3 / 2
        val yuv = ByteArray(yuvSize)

        var yIndex = 0
        var uvIndex = width * height

        for (j in 0 until height) {
            for (i in 0 until width) {
                val pixel = pixels[j * width + i]
                val r = (pixel shr 16) and 0xff
                val g = (pixel shr 8) and 0xff
                val b = pixel and 0xff

                // RGB to YUV conversion
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128

                yuv[yIndex++] = y.toByte()

                if (j % 2 == 0 && i % 2 == 0) {
                    yuv[uvIndex++] = u.toByte()
                    yuv[uvIndex++] = v.toByte()
                }
            }
        }

        return yuv
    }
}
