package com.example.extractmp3

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaCodecInfo
import android.media.MediaMetadataRetriever
import com.naman14.androidlame.AndroidLame
import com.naman14.androidlame.LameBuilder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import android.util.Log

class AudioExtractorPlugin {
    companion object {
        private const val TAG = "AudioExtractor"
        private const val CHANNEL = "audio_extractor"
        private const val DURATION_CHANNEL = "audio_duration"
        private const val TIMEOUT_US = 10000L
        
        fun registerWith(flutterEngine: FlutterEngine) {
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )
            
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudio" -> extractAudio(call, result)
                    else -> result.notImplemented()
                }
            }
            
            val durationChannel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                DURATION_CHANNEL
            )
            
            durationChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDuration" -> getDuration(call, result)
                    else -> result.notImplemented()
                }
            }
        }
        
        private fun getDuration(call: MethodCall, result: MethodChannel.Result) {
            try {
                val filePath = call.argument<String>("filePath")!!
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(filePath)
                
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationStr?.toLongOrNull() ?: 0L
                val durationSeconds = durationMs / 1000.0
                
                retriever.release()
                
                result.success(durationSeconds)
            } catch (e: Exception) {
                Log.e(TAG, "Error getting duration", e)
                result.error("DURATION_ERROR", "Failed to get duration: ${e.message}", null)
            }
        }
        
        private fun extractAudio(call: MethodCall, result: MethodChannel.Result) {
            try {
                val inputPath = call.argument<String>("inputPath")!!
                val outputPath = call.argument<String>("outputPath")!!
                val startTime = call.argument<Double>("startTime")!!
                val endTime = call.argument<Double>("endTime")!!
                
                Log.d(TAG, "Starting extraction")
                Log.d(TAG, "Input: $inputPath")
                Log.d(TAG, "Output: $outputPath")
                Log.d(TAG, "Time: $startTime to $endTime seconds")
                
                val tempM4aPath = outputPath.replace(".mp3", "_temp.m4a")
                Log.d(TAG, "Temp M4A: $tempM4aPath")
                
                val extractSuccess = extractAudioSegment(
                    inputPath,
                    tempM4aPath,
                    (startTime * 1_000_000).toLong(),
                    (endTime * 1_000_000).toLong()
                )
                
                Log.d(TAG, "Extract to M4A success: $extractSuccess")
                
                if (!extractSuccess) {
                    File(tempM4aPath).delete()
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Failed to extract audio segment to M4A",
                        "outputPath" to null
                    ))
                    return
                }
                
                // Check temp file exists and has content
                val tempFile = File(tempM4aPath)
                if (!tempFile.exists() || tempFile.length() < 1000) {
                    Log.e(TAG, "Temp M4A file is missing or too small: ${tempFile.length()} bytes")
                    tempFile.delete()
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Extracted M4A file is invalid or too small",
                        "outputPath" to null
                    ))
                    return
                }
                
                Log.d(TAG, "Temp M4A file size: ${tempFile.length()} bytes")
                Log.d(TAG, "Converting M4A to MP3...")
                
                val convertSuccess = convertM4aToMp3(tempM4aPath, outputPath)
                
                Log.d(TAG, "Convert to MP3 success: $convertSuccess")
                
                tempFile.delete()
                
                if (convertSuccess) {
                    val outputFile = File(outputPath)
                    Log.d(TAG, "Final MP3 file size: ${outputFile.length()} bytes")
                    result.success(mapOf(
                        "success" to true,
                        "message" to "Extraction successful",
                        "outputPath" to outputPath
                    ))
                } else {
                    result.success(mapOf(
                        "success" to false,
                        "message" to "Failed to convert M4A to MP3",
                        "outputPath" to null
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error during extraction", e)
                result.success(mapOf(
                    "success" to false,
                    "message" to "Error: ${e.message}",
                    "outputPath" to null
                ))
            }
        }
        
        private fun extractAudioSegment(
            inputPath: String,
            outputPath: String,
            startTimeUs: Long,
            endTimeUs: Long
        ): Boolean {
            val extractor = MediaExtractor()
            var decoder: MediaCodec? = null
            var encoder: MediaCodec? = null
            var muxer: MediaMuxer? = null
            
            try {
                Log.d(TAG, "Setting up extractor...")
                extractor.setDataSource(inputPath)
                
                var audioTrackIndex = -1
                var inputFormat: MediaFormat? = null
                
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    Log.d(TAG, "Track $i: $mime")
                    
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        inputFormat = format
                        break
                    }
                }
                
                if (audioTrackIndex == -1 || inputFormat == null) {
                    Log.e(TAG, "No audio track found")
                    return false
                }
                
                extractor.selectTrack(audioTrackIndex)
                extractor.seekTo(startTimeUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                
                val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: ""
                
                Log.d(TAG, "Input format - Sample rate: $sampleRate, Channels: $channelCount, MIME: $mime")
                
                Log.d(TAG, "Creating decoder...")
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                
                val outputFormat = MediaFormat.createAudioFormat(
                    MediaFormat.MIMETYPE_AUDIO_AAC,
                    sampleRate,
                    channelCount
                )
                outputFormat.setInteger(MediaFormat.KEY_BIT_RATE, 192000)
                outputFormat.setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )
                outputFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
                
                Log.d(TAG, "Creating encoder...")
                encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                encoder.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()
                
                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                
                Log.d(TAG, "Creating muxer...")
                muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                
                var muxerTrackIndex = -1
                var muxerStarted = false
                
                val decoderBufferInfo = MediaCodec.BufferInfo()
                val encoderBufferInfo = MediaCodec.BufferInfo()
                
                var extractorDone = false
                var decoderDone = false
                var encoderDone = false
                var samplesProcessed = 0
                
                Log.d(TAG, "Starting transcode loop...")
                
                while (!encoderDone) {
                    // Feed decoder
                    if (!extractorDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                            val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                            val presentationTimeUs = extractor.sampleTime
                            
                            if (sampleSize < 0 || presentationTimeUs > endTimeUs) {
                                Log.d(TAG, "End of input reached. Samples processed: $samplesProcessed")
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                extractorDone = true
                            } else {
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    sampleSize,
                                    presentationTimeUs,
                                    0
                                )
                                extractor.advance()
                                samplesProcessed++
                            }
                        }
                    }
                    
                    // Get decoded data and feed to encoder
                    if (!decoderDone) {
                        val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                        
                        if (outputBufferIndex >= 0) {
                            val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                            
                            if (decoderBufferInfo.size > 0 && 
                                decoderBufferInfo.presentationTimeUs >= startTimeUs &&
                                decoderBufferInfo.presentationTimeUs <= endTimeUs) {
                                
                                val encoderInputBufferIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
                                if (encoderInputBufferIndex >= 0) {
                                    val encoderInputBuffer = encoder.getInputBuffer(encoderInputBufferIndex)
                                    encoderInputBuffer!!.clear()
                                    
                                    outputBuffer!!.position(decoderBufferInfo.offset)
                                    outputBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                                    encoderInputBuffer.put(outputBuffer)
                                    
                                    val flags = if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    } else {
                                        0
                                    }
                                    
                                    encoder.queueInputBuffer(
                                        encoderInputBufferIndex,
                                        0,
                                        decoderBufferInfo.size,
                                        decoderBufferInfo.presentationTimeUs - startTimeUs,
                                        flags
                                    )
                                }
                            }
                            
                            decoder.releaseOutputBuffer(outputBufferIndex, false)
                            
                            if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                Log.d(TAG, "Decoder done")
                                decoderDone = true
                            }
                        }
                    }
                    
                    // Get encoded data
                    val encoderOutputBufferIndex = encoder.dequeueOutputBuffer(encoderBufferInfo, TIMEOUT_US)
                    
                    if (encoderOutputBufferIndex >= 0) {
                        val encodedData = encoder.getOutputBuffer(encoderOutputBufferIndex)
                        
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 &&
                            encoderBufferInfo.size > 0) {
                            
                            if (!muxerStarted) {
                                Log.e(TAG, "Muxer not started when trying to write data")
                                return false
                            }
                            
                            encodedData!!.position(encoderBufferInfo.offset)
                            encodedData.limit(encoderBufferInfo.offset + encoderBufferInfo.size)
                            
                            muxer.writeSampleData(muxerTrackIndex, encodedData, encoderBufferInfo)
                        }
                        
                        encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                        
                        if ((encoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            Log.d(TAG, "Encoder done")
                            encoderDone = true
                        }
                    } else if (encoderOutputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (muxerStarted) {
                            Log.e(TAG, "Format changed twice")
                            return false
                        }
                        
                        val newFormat = encoder.outputFormat
                        Log.d(TAG, "Encoder output format changed: $newFormat")
                        muxerTrackIndex = muxer.addTrack(newFormat)
                        muxer.start()
                        muxerStarted = true
                        Log.d(TAG, "Muxer started")
                    }
                }
                
                Log.d(TAG, "Transcode complete. Total samples: $samplesProcessed")
                return true
                
            } catch (e: Exception) {
                Log.e(TAG, "Error in extractAudioSegment", e)
                return false
            } finally {
                try {
                    extractor.release()
                    decoder?.stop()
                    decoder?.release()
                    encoder?.stop()
                    encoder?.release()
                    muxer?.stop()
                    muxer?.release()
                } catch (e: Exception) {
                    Log.e(TAG, "Error cleaning up resources", e)
                }
            }
        }
        
        private fun convertM4aToMp3(inputM4aPath: String, outputMp3Path: String): Boolean {
            val extractor = MediaExtractor()
            var decoder: MediaCodec? = null
            var outputStream: FileOutputStream? = null
            var lame: AndroidLame? = null
            
            try {
                Log.d(TAG, "Converting M4A to MP3...")
                extractor.setDataSource(inputM4aPath)
                
                var audioTrackIndex = -1
                var inputFormat: MediaFormat? = null
                
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        inputFormat = format
                        break
                    }
                }
                
                if (audioTrackIndex == -1 || inputFormat == null) {
                    Log.e(TAG, "No audio track in M4A")
                    return false
                }
                
                extractor.selectTrack(audioTrackIndex)
                
                val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: ""
                
                Log.d(TAG, "M4A format - Sample rate: $sampleRate, Channels: $channelCount")
                
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                
                val lameBuilder = LameBuilder()
                    .setInSampleRate(sampleRate)
                    .setOutChannels(channelCount)
                    .setOutBitrate(192)
                    .setOutSampleRate(sampleRate)
                    .setQuality(5)
                
                lame = AndroidLame(lameBuilder)
                
                val outputFile = File(outputMp3Path)
                outputFile.parentFile?.mkdirs()
                outputStream = FileOutputStream(outputFile)
                
                val decoderBufferInfo = MediaCodec.BufferInfo()
                val mp3Buffer = ByteArray(8192)
                
                var extractorDone = false
                var pcmSamplesProcessed = 0
                
                Log.d(TAG, "Starting M4A decode and MP3 encode...")
                
                while (true) {
                    if (!extractorDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                        if (inputBufferIndex >= 0) {
                            val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                            val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                            
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                extractorDone = true
                            } else {
                                val presentationTimeUs = extractor.sampleTime
                                decoder.queueInputBuffer(
                                    inputBufferIndex,
                                    0,
                                    sampleSize,
                                    presentationTimeUs,
                                    0
                                )
                                extractor.advance()
                            }
                        }
                    }
                    
                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                    
                    if (outputBufferIndex >= 0) {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                        
                        if (decoderBufferInfo.size > 0) {
                            outputBuffer!!.position(decoderBufferInfo.offset)
                            outputBuffer.limit(decoderBufferInfo.offset + decoderBufferInfo.size)
                            
                            val pcmData = ShortArray(decoderBufferInfo.size / 2)
                            outputBuffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(pcmData)
                            
                            val bytesEncoded = if (channelCount == 1) {
                                lame.encode(pcmData, pcmData, pcmData.size, mp3Buffer)
                            } else {
                                val leftChannel = ShortArray(pcmData.size / 2)
                                val rightChannel = ShortArray(pcmData.size / 2)
                                
                                for (i in pcmData.indices step 2) {
                                    leftChannel[i / 2] = pcmData[i]
                                    if (i + 1 < pcmData.size) {
                                        rightChannel[i / 2] = pcmData[i + 1]
                                    }
                                }
                                
                                lame.encode(leftChannel, rightChannel, leftChannel.size, mp3Buffer)
                            }
                            
                            if (bytesEncoded > 0) {
                                outputStream.write(mp3Buffer, 0, bytesEncoded)
                                pcmSamplesProcessed += pcmData.size
                            }
                        }
                        
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                        
                        if ((decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    }
                }
                
                val flushBytes = lame.flush(mp3Buffer)
                if (flushBytes > 0) {
                    outputStream.write(mp3Buffer, 0, flushBytes)
                }
                
                Log.d(TAG, "M4A to MP3 conversion complete. PCM samples processed: $pcmSamplesProcessed")
                return true
                
            } catch (e: Exception) {
                Log.e(TAG, "Error converting M4A to MP3", e)
                return false
            } finally {
                try {
                    extractor.release()
                    decoder?.stop()
                    decoder?.release()
                    outputStream?.close()
                    lame?.close()
                } catch (e: Exception) {
                    Log.e(TAG, "Error cleaning up M4A conversion", e)
                }
            }
        }
    }
}