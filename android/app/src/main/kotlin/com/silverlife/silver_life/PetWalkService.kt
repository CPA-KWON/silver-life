package com.silverlife.silver_life

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.*
import android.location.*
import android.os.*

/** User-started foreground walk. Counter + last position stay on this device;
 *  only the active walk's progress is submitted to the authenticated pet RPC. */
class PetWalkService : Service(), SensorEventListener, LocationListener {
    private val prefs by lazy { getSharedPreferences("pet_walk", MODE_PRIVATE) }
    private val sensors by lazy { getSystemService(SENSOR_SERVICE) as SensorManager }
    private val locations by lazy { getSystemService(LOCATION_SERVICE) as LocationManager }
    private var baseline: Float? = null
    private var carry = 0

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "stop" -> { prefs.edit().putBoolean("active", false).putBoolean("paused", false).apply(); cleanup(); stopSelf(); return START_NOT_STICKY }
            "pause" -> { prefs.edit().putBoolean("paused", true).apply(); cleanupSensors(); updateNotification(); return START_STICKY }
            "start" -> {
                val owner = intent.getStringExtra("owner") ?: ""
                val session = intent.getStringExtra("session") ?: ""
                if (prefs.getString("session", "") != session || prefs.getString("owner", "") != owner) {
                    prefs.edit().clear().putString("owner", owner).putString("session", session)
                        .putLong("started_at", System.currentTimeMillis()).putInt("steps", 0).apply()
                }
                prefs.edit().putBoolean("active", true).putBoolean("paused", false).apply()
            }
            "resume" -> prefs.edit().putBoolean("paused", false).apply()
        }
        if (!prefs.getBoolean("active", false)) { stopSelf(); return START_NOT_STICKY }
        val hasActivity = Build.VERSION.SDK_INT < 29 || checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        val hasLocation = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!hasActivity && !hasLocation) { prefs.edit().putBoolean("active", false).apply(); stopSelf(); return START_NOT_STICKY }
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel("pet_walk", "콩이와 산책", NotificationManager.IMPORTANCE_LOW))
        if (Build.VERSION.SDK_INT >= 34) {
            var type = 0
            if (hasActivity) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            if (hasLocation) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            startForeground(501, notification(), type)
        } else startForeground(501, notification())
        if (!prefs.getBoolean("paused", false)) {
            cleanupSensors(); carry = prefs.getInt("steps", 0); baseline = null
            if (hasActivity) sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)?.let { sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }
            if (hasLocation) {
                try {
                    for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                        if (locations.isProviderEnabled(provider)) locations.requestLocationUpdates(provider, 10000L, 5f, this)
                    }
                } catch (_: SecurityException) { }
            }
        }
        return START_STICKY
    }
    private fun notification(): Notification {
        val launch = PendingIntent.getActivity(this, 0, packageManager.getLaunchIntentForPackage(packageName), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val text = if (prefs.getBoolean("paused", false)) "잠시 쉬고 있어요" else "${prefs.getInt("steps", 0)}걸음 · 화면을 꺼도 기록해요"
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "pet_walk") else Notification.Builder(this)
        return builder.setContentTitle("콩이와 산책 중").setContentText(text).setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentIntent(launch).setOngoing(true).build()
    }
    private fun updateNotification() { (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(501, notification()) }
    override fun onSensorChanged(event: SensorEvent) {
        if (prefs.getBoolean("paused", false)) return
        val total = event.values[0]
        if (baseline == null || total < baseline!!) { baseline = total; carry = prefs.getInt("steps", 0) }
        val steps = carry + (total - baseline!!).toInt().coerceAtLeast(0)
        if (steps != prefs.getInt("steps", 0)) { prefs.edit().putInt("steps", steps).apply(); updateNotification() }
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { }
    override fun onLocationChanged(location: Location) {
        if (Build.VERSION.SDK_INT >= 31 && location.isMock) return
        if (Build.VERSION.SDK_INT < 31 && location.isFromMockProvider) return
        prefs.edit().putFloat("lat", location.latitude.toFloat()).putFloat("lng", location.longitude.toFloat())
            .putFloat("accuracy", location.accuracy).putLong("location_at", System.currentTimeMillis()).apply()
    }
    private fun cleanupSensors() { sensors.unregisterListener(this); try { locations.removeUpdates(this) } catch (_: SecurityException) { }; baseline = null }
    private fun cleanup() { cleanupSensors(); if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true) }
    override fun onDestroy() { cleanupSensors(); super.onDestroy() }
}
