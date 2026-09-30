package com.example.quickdrop

import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.common.api.ApiException
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.AutocompletePrediction
import com.google.android.libraries.places.api.model.AutocompleteSessionToken
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest

private const val PLACES_CHANNEL = "quickdrop/places"
private const val PLACES_TAG = "QuickDropPlaces"

class MainActivity : FlutterActivity() {
	private var placesClient: com.google.android.libraries.places.api.net.PlacesClient? = null
	private var sessionToken: AutocompleteSessionToken? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		val applicationInfo = packageManager.getApplicationInfo(
			packageName,
			PackageManager.GET_META_DATA,
		)
		val apiKey = applicationInfo.metaData?.getString("com.google.android.geo.API_KEY")
			?.trim()
			.orEmpty()
		if (apiKey.isNotEmpty() && !Places.isInitialized()) {
			Places.initializeWithNewPlacesApiEnabled(applicationContext, apiKey)
		}
		placesClient = if (Places.isInitialized()) {
			Places.createClient(this)
		} else {
			Log.e(PLACES_TAG, "Google Places SDK was not initialized: API key is missing from manifest")
			null
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLACES_CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"autocomplete" -> autocomplete(call.argument<String>("query"), result)
					"placeDetails" -> placeDetails(call.argument<String>("placeId"), result)
					else -> result.notImplemented()
				}
			}
	}

	private fun autocomplete(query: String?, result: MethodChannel.Result) {
		val trimmedQuery = query?.trim().orEmpty()
		if (trimmedQuery.isEmpty()) {
			result.success(emptyList<Map<String, String>>())
			return
		}

		val client = placesClient
		if (client == null) {
			result.error("PLACES_UNAVAILABLE", "Google Places SDK is not initialized.", null)
			return
		}

		val token = sessionToken ?: AutocompleteSessionToken.newInstance().also {
			sessionToken = it
		}
		val request = FindAutocompletePredictionsRequest.builder()
			.setSessionToken(token)
			.setQuery(trimmedQuery)
			.setCountries(listOf("IN"))
			.build()

		client.findAutocompletePredictions(request)
			.addOnSuccessListener { response ->
				val suggestions = response.autocompletePredictions.map { prediction: AutocompletePrediction ->
					mapOf(
						"placeId" to prediction.placeId,
						"description" to prediction.getFullText(null).toString(),
					)
				}
				Log.d(PLACES_TAG, "Android SDK autocomplete status=OK predictions=${suggestions.size}")
				result.success(suggestions)
			}
			.addOnFailureListener { error ->
				val statusCode = (error as? ApiException)?.statusCode
				Log.e(PLACES_TAG, "Android SDK autocomplete status=${statusCode ?: "ERROR"} error=${error.message}")
				result.error("PLACES_AUTOCOMPLETE_FAILED", error.message, statusCode)
			}
	}

	private fun placeDetails(placeId: String?, result: MethodChannel.Result) {
		val trimmedPlaceId = placeId?.trim().orEmpty()
		val client = placesClient
		if (trimmedPlaceId.isEmpty() || client == null) {
			result.error("PLACES_DETAILS_FAILED", "Place details are unavailable.", null)
			return
		}

		val request = FetchPlaceRequest.newInstance(
			trimmedPlaceId,
			listOf(Place.Field.LOCATION),
		)
		client.fetchPlace(request)
			.addOnSuccessListener { response ->
				val location = response.place.location
				if (location == null) {
					result.error("PLACES_DETAILS_FAILED", "Place has no coordinates.", null)
					return@addOnSuccessListener
				}
				sessionToken = null
				Log.d(PLACES_TAG, "Android SDK place details status=OK")
				result.success(
					mapOf(
						"lat" to location.latitude,
						"lng" to location.longitude,
					),
				)
			}
			.addOnFailureListener { error ->
				val statusCode = (error as? ApiException)?.statusCode
				Log.e(PLACES_TAG, "Android SDK place details status=${statusCode ?: "ERROR"} error=${error.message}")
				result.error("PLACES_DETAILS_FAILED", error.message, statusCode)
			}
	}
}
