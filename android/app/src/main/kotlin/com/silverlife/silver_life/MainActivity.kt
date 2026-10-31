package com.silverlife.silver_life

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val tracker by lazy { PetWalkTracker(this) }

    override fun onResume() {
        super.onResume()
        tracker.appeared()
    }

    override fun onPause() {
        tracker.disappeared()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "silver_life/pet_walk").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("pet_walk", MODE_PRIVATE)
            when (call.method) {
                "status" -> {
                    val owner = call.argument<String>("owner") ?: ""
                    val same = prefs.getString("owner", "") == owner
                    val sensor = (getSystemService(SENSOR_SERVICE) as SensorManager).getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                    result.success(mapOf("supported" to (sensor != null), "active" to (same && prefs.getBoolean("active", false)),
                        "paused" to (same && prefs.getBoolean("paused", false)), "steps" to (if(same) prefs.getInt("steps",0) else 0),
                        "session" to (if(same) prefs.getString("session",null) else null),
                        "lat" to (if(same && prefs.contains("lat")) prefs.getFloat("lat",0f).toDouble() else null),
                        "lng" to (if(same && prefs.contains("lng")) prefs.getFloat("lng",0f).toDouble() else null),
                        "accuracy" to (if(same && prefs.contains("accuracy")) prefs.getFloat("accuracy",0f).toDouble() else null),
                        "location_at" to (if(same) prefs.getLong("location_at",0) else 0)))
                }
                "start" -> {
                    if (!tracker.hasActivityPermission() && !tracker.hasLocationPermission()) {
                        result.error("permission", "걸음 수 또는 위치 권한을 허용해주세요.", null)
                        return@setMethodCallHandler
                    }
                    tracker.start(call.argument<String>("owner") ?: "", call.argument<String>("session") ?: "")
                    result.success(null)
                }
                "pause" -> { tracker.pause(); result.success(null) }
                "resume" -> { tracker.resume(); result.success(null) }
                "stop" -> { tracker.stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
