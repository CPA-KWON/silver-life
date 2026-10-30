package com.silverlife.silver_life

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                "start", "pause", "resume", "stop", "configure" -> {
                    val action = call.method
                    val intent = Intent(this, PetWalkService::class.java).setAction(action)
                    if (action == "configure") {
                        val owner = call.argument<String>("owner") ?: ""
                        if (prefs.getString("owner", "") != owner) { result.success(null); return@setMethodCallHandler }
                    }
                    intent.putExtra("return_at", (call.argument<Number>("return_at")?.toLong() ?: 0L))
                    intent.putExtra("pet_name", call.argument<String>("pet_name") ?: "반려동물")
                    if (action == "start") {
                        val hasActivity = Build.VERSION.SDK_INT < 29 || checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
                        val hasLocation = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                        if (!hasActivity && !hasLocation) { result.error("permission", "걸음 수 또는 위치 권한이 필요해요.", null); return@setMethodCallHandler }
                        intent.putExtra("owner",call.argument<String>("owner")).putExtra("session",call.argument<String>("session"))
                    }
                    try {
                        if (action == "start" || action == "resume") {
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        } else startService(intent)
                        result.success(null)
                    } catch (e: Exception) { result.error("walk", "산책 기록을 시작하지 못했어요. 앱을 연 상태에서 다시 시도해주세요.", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
}
