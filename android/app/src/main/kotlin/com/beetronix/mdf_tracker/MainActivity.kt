package com.beetronix.mdf_tracker

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.atan2

/**
 * Adds one platform channel the `camera` plugin has no equivalent for:
 * the phone's real horizontal field of view, derived from Camera2's own
 * sensor-size and focal-length characteristics rather than an assumed
 * constant. See mobile/lib/src/core/camera/camera_intrinsics_reader.dart.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mdf_tracker/camera_intrinsics"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "horizontalFovDegrees") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val cameraId = call.argument<String>("cameraId")
                if (cameraId == null) {
                    result.error("missing_argument", "cameraId is required", null)
                    return@setMethodCallHandler
                }

                result.success(horizontalFovDegrees(cameraId))
            }
    }

    /**
     * Derives horizontal FOV, in degrees, from the sensor's physical width and
     * the shortest available focal length (the widest zoom level) - the same
     * relation the app's own pinhole model uses in reverse to turn image width
     * back into a focal length in pixels.
     *
     * [cameraId] is the id the `camera` plugin already uses as
     * `CameraDescription.name` on Android, so callers can pass that straight
     * through without any translation.
     *
     * Returns null when the characteristics this needs are unavailable (rare,
     * but some hardware or emulators omit them), so the caller can fall back
     * to its configured default rather than guessing.
     */
    private fun horizontalFovDegrees(cameraId: String): Double? {
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val characteristics = manager.getCameraCharacteristics(cameraId)

            val sensorSize = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                ?: return null
            val focalLengths = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?: return null
            val focalLength = focalLengths.minOrNull() ?: return null
            if (focalLength <= 0f) return null

            val radians = 2.0 * atan2(sensorSize.width.toDouble(), 2.0 * focalLength.toDouble())
            Math.toDegrees(radians)
        } catch (e: Exception) {
            null
        }
    }
}
