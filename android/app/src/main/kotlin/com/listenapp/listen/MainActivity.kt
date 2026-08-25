package com.listenapp.listen

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val decoderExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_DECODER_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "decodeToWavChunks") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val chunkSeconds = call.argument<Int>("chunkSeconds") ?: 300
                if (path.isNullOrBlank() || chunkSeconds !in 30..1800) {
                    result.error("invalid_arguments", "音频路径或分片长度无效", null)
                    return@setMethodCallHandler
                }
                decoderExecutor.execute {
                    try {
                        val paths = AndroidAudioDecoder(cacheDir, chunkSeconds).decode(path)
                        runOnUiThread { result.success(paths) }
                    } catch (error: Throwable) {
                        runOnUiThread {
                            result.error(
                                "audio_decode_failed",
                                error.message ?: "Android 音频解码失败",
                                null,
                            )
                        }
                    }
                }
            }
    }

    override fun onDestroy() {
        decoderExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val AUDIO_DECODER_CHANNEL = "listen/audio_decoder"
    }
}

private class AndroidAudioDecoder(
    private val outputDirectory: File,
    private val chunkSeconds: Int,
) {
    fun decode(inputPath: String): List<String> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var writer: WavChunkWriter? = null
        try {
            extractor.setDataSource(inputPath)
            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index)
                    .getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: error("节目文件中没有音频轨道")
            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)
                ?: error("无法识别音频格式")
            val activeCodec = MediaCodec.createDecoderByType(mime)
            codec = activeCodec
            activeCodec.configure(inputFormat, null, null, 0)
            activeCodec.start()

            val bufferInfo = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var sampleRate = 0
            var channels = 0
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT

            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = activeCodec.dequeueInputBuffer(TIMEOUT_MICROSECONDS)
                    if (inputIndex >= 0) {
                        val inputBuffer = activeCodec.getInputBuffer(inputIndex)
                            ?: error("无法取得音频输入缓冲区")
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            activeCodec.queueInputBuffer(
                                inputIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputEnded = true
                        } else {
                            activeCodec.queueInputBuffer(
                                inputIndex, 0, sampleSize, extractor.sampleTime, 0,
                            )
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = activeCodec.dequeueOutputBuffer(
                    bufferInfo,
                    TIMEOUT_MICROSECONDS,
                )
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = activeCodec.outputFormat
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        pcmEncoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        } else {
                            AudioFormat.ENCODING_PCM_16BIT
                        }
                        writer = WavChunkWriter(
                            directory = outputDirectory,
                            samplesPerChunk = TARGET_SAMPLE_RATE * chunkSeconds,
                        )
                    }
                    outputIndex >= 0 -> {
                        if (bufferInfo.size > 0) {
                            val activeWriter = writer
                                ?: error("解码器未提供音频输出格式")
                            val outputBuffer = activeCodec.getOutputBuffer(outputIndex)
                                ?: error("无法取得音频输出缓冲区")
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            val monoSamples = pcmToMono(
                                outputBuffer.slice().order(ByteOrder.nativeOrder()),
                                channels,
                                pcmEncoding,
                            )
                            activeWriter.writeResampled(monoSamples, sampleRate)
                        }
                        outputEnded = bufferInfo.flags and
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        activeCodec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
            return writer?.finish().orEmpty().also {
                if (it.isEmpty()) error("没有从节目中解码出声音")
            }
        } catch (error: Throwable) {
            writer?.discard()
            throw error
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            extractor.release()
        }
    }

    private fun pcmToMono(
        buffer: ByteBuffer,
        channelCount: Int,
        encoding: Int,
    ): FloatArray {
        require(channelCount > 0) { "音频声道数无效" }
        val bytesPerSample = when (encoding) {
            AudioFormat.ENCODING_PCM_8BIT -> 1
            AudioFormat.ENCODING_PCM_16BIT -> 2
            AudioFormat.ENCODING_PCM_FLOAT -> 4
            else -> error("暂不支持该 PCM 编码：$encoding")
        }
        val frameCount = buffer.remaining() / (bytesPerSample * channelCount)
        val mono = FloatArray(frameCount)
        for (frame in 0 until frameCount) {
            var sum = 0f
            repeat(channelCount) {
                sum += when (encoding) {
                    AudioFormat.ENCODING_PCM_8BIT ->
                        ((buffer.get().toInt() and 0xff) - 128) / 128f
                    AudioFormat.ENCODING_PCM_FLOAT -> buffer.float
                    else -> buffer.short / 32768f
                }
            }
            mono[frame] = (sum / channelCount).coerceIn(-1f, 1f)
        }
        return mono
    }

    companion object {
        private const val TARGET_SAMPLE_RATE = 16_000
        private const val TIMEOUT_MICROSECONDS = 10_000L
    }
}

private class WavChunkWriter(
    private val directory: File,
    private val samplesPerChunk: Int,
) {
    private val paths = mutableListOf<String>()
    private var file: RandomAccessFile? = null
    private var currentPath: String? = null
    private var samplesInChunk = 0
    private var resampleAccumulator = 0L
    private var finished = false

    fun writeResampled(samples: FloatArray, sourceSampleRate: Int) {
        require(sourceSampleRate > 0) { "音频采样率无效" }
        for (sample in samples) {
            resampleAccumulator += TARGET_SAMPLE_RATE
            while (resampleAccumulator >= sourceSampleRate) {
                writeSample(sample)
                resampleAccumulator -= sourceSampleRate
            }
        }
    }

    private fun writeSample(sample: Float) {
        if (file == null) openChunk()
        val pcm = (sample.coerceIn(-1f, 1f) * Short.MAX_VALUE)
            .roundToInt()
            .toShort()
        file!!.write(pcm.toInt() and 0xff)
        file!!.write((pcm.toInt() ushr 8) and 0xff)
        samplesInChunk += 1
        if (samplesInChunk >= samplesPerChunk) closeChunk()
    }

    private fun openChunk() {
        directory.mkdirs()
        val path = File(
            directory,
            "listen-asr-${System.nanoTime()}-${paths.size}.wav",
        ).absolutePath
        currentPath = path
        file = RandomAccessFile(path, "rw").also { wav ->
            wav.setLength(0)
            repeat(WAV_HEADER_BYTES) { wav.write(0) }
        }
        samplesInChunk = 0
    }

    private fun closeChunk() {
        val activeFile = file ?: return
        val path = currentPath ?: return
        if (samplesInChunk == 0) {
            activeFile.close()
            File(path).delete()
        } else {
            writeHeader(activeFile, samplesInChunk)
            activeFile.close()
            paths += path
        }
        file = null
        currentPath = null
        samplesInChunk = 0
    }

    fun finish(): List<String> {
        if (!finished) {
            closeChunk()
            finished = true
        }
        return paths.toList()
    }

    fun discard() {
        runCatching { file?.close() }
        currentPath?.let { File(it).delete() }
        paths.forEach { File(it).delete() }
        file = null
        currentPath = null
        paths.clear()
        finished = true
    }

    private fun writeHeader(wav: RandomAccessFile, sampleCount: Int) {
        val dataBytes = sampleCount * 2
        wav.seek(0)
        wav.writeBytes("RIFF")
        writeIntLittleEndian(wav, 36 + dataBytes)
        wav.writeBytes("WAVE")
        wav.writeBytes("fmt ")
        writeIntLittleEndian(wav, 16)
        writeShortLittleEndian(wav, 1)
        writeShortLittleEndian(wav, 1)
        writeIntLittleEndian(wav, TARGET_SAMPLE_RATE)
        writeIntLittleEndian(wav, TARGET_SAMPLE_RATE * 2)
        writeShortLittleEndian(wav, 2)
        writeShortLittleEndian(wav, 16)
        wav.writeBytes("data")
        writeIntLittleEndian(wav, dataBytes)
    }

    private fun writeIntLittleEndian(file: RandomAccessFile, value: Int) {
        repeat(4) { shift -> file.write((value ushr (shift * 8)) and 0xff) }
    }

    private fun writeShortLittleEndian(file: RandomAccessFile, value: Int) {
        repeat(2) { shift -> file.write((value ushr (shift * 8)) and 0xff) }
    }

    companion object {
        private const val TARGET_SAMPLE_RATE = 16_000
        private const val WAV_HEADER_BYTES = 44
    }
}
