package com.silverlife.silver_life

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build

/** User-started walk, recorded only while the app is on screen (no foreground
 *  service: see docs/pet_walk_background.md). Counter + last position stay on this
 *  device; only the active walk's progress is submitted to the authenticated pet RPC.
 *  Steps taken while the app is closed or the screen is off are not counted. */
class PetWalkTracker(private val context: Context) : SensorEventListener, LocationListener {
    private val prefs by lazy { context.getSharedPreferences("pet_walk", Context.MODE_PRIVATE) }
    private val sensors by lazy { context.getSystemService(Context.SENSOR_SERVICE) as SensorManager }
    private val locations by lazy { context.getSystemService(Context.LOCATION_SERVICE) as LocationManager }
    private var baseline: Float? = null
    private var carry = 0
    private var onScreen = false

    fun hasActivityPermission() = Build.VERSION.SDK_INT < 29 ||
        context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    fun hasLocationPermission() =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun start(owner: String, session: String) {
        if (prefs.getString("session", "") != session || prefs.getString("owner", "") != owner) {
            prefs.edit().clear().putString("owner", owner).putString("session", session)
                .putLong("started_at", System.currentTimeMillis()).putInt("steps", 0).apply()
        }
        prefs.edit().putBoolean("active", true).putBoolean("paused", false).apply()
        listen()
    }

    fun pause() {
        prefs.edit().putBoolean("paused", true).apply()
        stopListening()
    }

    fun resume() {
        prefs.edit().putBoolean("paused", false).apply()
        listen()
    }

    fun stop() {
        prefs.edit().putBoolean("active", false).putBoolean("paused", false).apply()
        stopListening()
    }

    /** Called from the activity's onResume. */
    fun appeared() {
        onScreen = true
        listen()
    }

    /** Called from the activity's onPause. */
    fun disappeared() {
        onScreen = false
        stopListening()
    }

    private fun listen() {
        stopListening()
        if (!onScreen || !prefs.getBoolean("active", false) || prefs.getBoolean("paused", false)) return
        carry = prefs.getInt("steps", 0)
        if (hasActivityPermission()) {
            sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)?.let {
                sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
            }
        }
        if (hasLocationPermission()) {
            try {
                for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                    if (locations.isProviderEnabled(provider)) locations.requestLocationUpdates(provider, 10000L, 5f, this)
                }
            } catch (_: SecurityException) { }
        }
    }

    private fun stopListening() {
        sensors.unregisterListener(this)
        try { locations.removeUpdates(this) } catch (_: SecurityException) { }
        baseline = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (prefs.getBoolean("paused", false)) return
        val total = event.values[0]
        // The hardware counter keeps running while we aren't listening, so a new
        // baseline here is what leaves off-screen steps uncounted.
        if (baseline == null || total < baseline!!) { baseline = total; carry = prefs.getInt("steps", 0) }
        val steps = carry + (total - baseline!!).toInt().coerceAtLeast(0)
        if (steps != prefs.getInt("steps", 0)) prefs.edit().putInt("steps", steps).apply()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { }

    override fun onLocationChanged(location: Location) {
        if (Build.VERSION.SDK_INT >= 31 && location.isMock) return
        if (Build.VERSION.SDK_INT < 31 && location.isFromMockProvider) return
        prefs.edit().putFloat("lat", location.latitude.toFloat()).putFloat("lng", location.longitude.toFloat())
            .putFloat("accuracy", location.accuracy).putLong("location_at", System.currentTimeMillis()).apply()
    }
}
