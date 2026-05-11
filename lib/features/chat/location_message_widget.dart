import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'chat_controller.dart';

class LocationMessageWidget extends StatefulWidget {
  const LocationMessageWidget({required this.attachment, super.key});

  final ChatAttachment attachment;

  @override
  State<LocationMessageWidget> createState() => _LocationMessageWidgetState();
}

class _LocationMessageWidgetState extends State<LocationMessageWidget> {
  double? _distanceMeters;

  @override
  void initState() {
    super.initState();
    _loadDistance();
  }

  Future<void> _loadDistance() async {
    final location = widget.attachment.location;
    if (location == null) {
      return;
    }
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final current = await Geolocator.getCurrentPosition();
      if (!mounted) {
        return;
      }
      setState(() {
        _distanceMeters = Geolocator.distanceBetween(
          current.latitude,
          current.longitude,
          location.latitude,
          location.longitude,
        );
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.attachment.location;
    if (location == null) {
      return const SizedBox.shrink();
    }
    final center = LatLng(location.latitude, location.longitude);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _FullMapView(center: center)),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 150,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.essential.flutter',
                    ),
                    MarkerLayer(
                      markers: <Marker>[
                        Marker(
                          point: center,
                          child: const Icon(Icons.location_on, size: 36),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(location.address ?? '共有された位置情報'),
                    Text(
                      '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_distanceMeters != null)
                      Text(
                        _distanceMeters! < 1000
                            ? '${_distanceMeters!.round()} m nearby'
                            : '${(_distanceMeters! / 1000).toStringAsFixed(1)} km away',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullMapView extends StatelessWidget {
  const _FullMapView({required this.center});

  final LatLng center;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('位置情報')),
      body: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 16),
        children: <Widget>[
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.essential.flutter',
          ),
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: center,
                child: const Icon(Icons.location_on, size: 42),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
