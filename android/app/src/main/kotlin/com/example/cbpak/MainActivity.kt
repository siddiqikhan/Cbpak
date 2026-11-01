package com.example.cbpak

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "cbpak/location"
    private val permissionRequestCode = 6201
    private var pendingResult: MethodChannel.Result? = null
    private var locationListener: LocationListener? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "openMapAt") {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    if (latitude == null || longitude == null || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
                        result.error("invalid_coordinates", "Location coordinates are not valid.", null)
                    } else {
                        try {
                            val uri = Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude")
                            startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.apps.maps"))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("maps_unavailable", "Google Maps is not available on this phone.", null)
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "openMapSearch") {
                    val query = call.argument<String>("query")?.trim().orEmpty()
                    if (query.isEmpty()) {
                        result.error("empty_query", "Enter a destination first.", null)
                    } else {
                        try {
                            val uri = Uri.parse("geo:0,0?q=${Uri.encode(query)}")
                            startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.apps.maps"))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("maps_unavailable", "Google Maps is not available on this phone.", null)
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "openWhatsApp") {
                    val rawPhone = call.argument<String>("phone").orEmpty()
                    var digits = rawPhone.filter { it.isDigit() }
                    if (digits.startsWith("0")) digits = "92" + digits.drop(1)
                    if (digits.length < 10) {
                        result.error("invalid_phone", "The driver's phone number is not valid.", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits")))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("whatsapp_unavailable", "Could not open WhatsApp for this number.", null)
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "openGoogleMapsPicker") {
                    try {
                        val mapIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://maps.google.com"))
                            .setPackage("com.google.android.apps.maps")
                        startActivity(mapIntent)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("maps_unavailable", "Google Maps is not available on this phone.", null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "getCurrentLocation") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("location_in_progress", "A location request is already running.", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                if (hasLocationPermission()) {
                    requestLocation()
                } else {
                    requestPermissions(
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                        permissionRequestCode,
                    )
                }
            }
    }

    private fun hasLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        if (hasLocationPermission()) requestLocation()
        else finishWithError("permission_denied", "Allow location access or enter your pickup manually.")
    }

    @Suppress("MissingPermission")
    private fun requestLocation() {
        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        val hasFinePermission =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val provider = when {
            hasFinePermission && manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> {
                finishWithError("location_disabled", "Turn on your phone location and try again.")
                return
            }
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationListener?.let { manager.removeUpdates(it) }
                handler.removeCallbacksAndMessages(null)
                val result = pendingResult
                pendingResult = null
                locationListener = null
                result?.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude))
            }
        }
        locationListener = listener
        try {
            manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        } catch (error: SecurityException) {
            finishWithError("permission_denied", "Allow location access or enter your pickup manually.")
            return
        }
        handler.postDelayed({
            locationListener?.let { manager.removeUpdates(it) }
            locationListener = null
            finishWithError("location_timeout", "Could not get a GPS fix. Try again or enter pickup manually.")
        }, 20000)
    }

    private fun finishWithError(code: String, message: String) {
        handler.removeCallbacksAndMessages(null)
        val result = pendingResult
        pendingResult = null
        locationListener = null
        result?.error(code, message, null)
    }
}

