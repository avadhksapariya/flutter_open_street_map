import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

class ScreenOpenStreetMap extends StatefulWidget {
  const ScreenOpenStreetMap({super.key});

  @override
  State<ScreenOpenStreetMap> createState() => _ScreenOpenStreetMapState();
}

class _ScreenOpenStreetMapState extends State<ScreenOpenStreetMap> {
  final MapController mapController = MapController();
  final TextEditingController locationController = TextEditingController();
  final Location location = Location();
  bool isLoading = true;
  LatLng? currentLocation;
  LatLng? destination;
  List<LatLng> route = [];

  @override
  void initState() {
    super.initState();
    initializeLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flutter Open Street Map"),
        foregroundColor: Colors.white,
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          isLoading == true
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: currentLocation ?? const LatLng(22.302567, 70.796376), // can be kept LatLng(0, 0)
                    initialZoom: 15,
                    minZoom: 2,
                    maxZoom: 20,
                  ),
                  children: [
                    TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
                    CurrentLocationLayer(
                      style: const LocationMarkerStyle(
                        marker: DefaultLocationMarker(
                          child: Icon(
                            Icons.location_pin,
                            color: Colors.white,
                          ),
                        ),
                        markerSize: Size(35, 35),
                        markerDirection: MarkerDirection.top,
                      ),
                    ),
                    if (destination != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: destination!,
                            height: 52,
                            width: 50,
                            child: const Icon(Icons.location_pin, color: Colors.red),
                          ),
                        ],
                      ),
                    // if (currentLocation != null && destination != null && route.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          strokeWidth: 5,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
          Positioned(
            top: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: locationController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Enter your location',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final location = locationController.text.trim();
                      if (location.isNotEmpty) {
                        getCordinates(location);
                      }
                    },
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: userCurrentLocation,
        foregroundColor: Colors.white,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Future<void> userCurrentLocation() async {
    if (currentLocation != null) {
      mapController.move(currentLocation!, 15);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Current location is not available."),
        ),
      );
    }
  }

  Future<void> initializeLocation() async {
    if (!await checkRequestPermission()) {
      return;
    }

    // Fetch initial location before subscribing
    LocationData? initialLocation = await location.getLocation();
    if (initialLocation.latitude != null && initialLocation.longitude != null) {
      setState(() {
        currentLocation = LatLng(initialLocation.latitude!, initialLocation.longitude!);
        isLoading = false;
      });
    }

    location.onLocationChanged.listen((LocationData locData) {
      if (locData.latitude != null && locData.longitude != null) {
        setState(() {
          currentLocation = LatLng(locData.latitude!, locData.longitude!);
          isLoading = false;
        });
      }
    });
  }

  Future<bool> checkRequestPermission() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return false;
      }

      PermissionStatus permissionStatus = await location.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await location.requestPermission();
        if (permissionStatus != PermissionStatus.granted) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> getCordinates(String location) async {
    const String tag = 'get_osm_cordinates';

    final url = Uri.parse("https://nominatim.openstreetmap.org/search?q=$location&format=json&limit=1");
    log('$tag URL: GET: $url');

    try {
      final response = await http.get(url);
      log('$tag response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);

          setState(() {
            destination = LatLng(lat, lon);
          });
          await fetchRoute();
          // method to fetch the route between current location and the destination using OSRM api.
        } else {
          errorMessage('Location not found, please try another search.');
        }
      } else {
        errorMessage('Failed to fetch location, Try again later.');
      }
    } catch (error) {
      log('$tag error: ${error.toString()}');
      return;
    }
  }

  Future<void> fetchRoute() async {
    if (currentLocation == null || destination == null) {
      return;
    }

    const String tag = 'get_osm_route';

    final url = Uri.parse("http://router.project-osrm.org/route/v1/driving/"
        '${currentLocation!.longitude},${currentLocation!.latitude};'
        '${destination!.longitude},${destination!.latitude}?overview=full&geometries=polyline');
    log('$tag URL: GET: $url');

    try {
      final response = await http.get(url);
      log('$tag response: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['routes'][0]['geometry'];
        decodePolyline(geometry);
      } else {
        errorMessage('Failed to fetch route, Try again later.');
      }
    } catch (error) {
      log('$tag error: ${error.toString()}');
      return;
    }
  }

  void decodePolyline(String encodedPolyline) {
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decodedPoints = polylinePoints.decodePolyline(encodedPolyline);

    setState(() {
      route = decodedPoints.map((point) => LatLng(point.latitude, point.longitude)).toList();
    });
  }

  void errorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
