import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong/latlong.dart';
import 'package:flutter/foundation.dart';

import 'move_state.dart';
import 'move_marker_controller.dart';

typedef MoveCallBack = void Function(MoveState moveState, {LatLng latLng});
typedef PopupBuilder = Widget Function(BuildContext context,
    {LatLng latLng, double mileage, int index});

typedef MarkerBuilder = Marker Function(int index);

class Popup {
  final double width;
  final double height;
  final PopupBuilder popupBuilder;

  Popup({this.width, this.height, this.popupBuilder});
}

class MoveMarkerOptions extends LayerOptions {
  final Marker marker;
  final MarkerBuilder markerBuilder;
  final List<LatLng> points;
  final MoveMarkerController moveMarkerController;
  final MoveCallBack moveCallBack;
  final Popup popup;

  // auto move to map center
  final bool moveCenter;

  // Moving animation time per 100 meters default 500ms
  final Duration duration;

  MoveMarkerOptions({
    Key key,
    Stream<Null> rebuild,
    this.marker,
    this.markerBuilder,
    this.points = const [],
    MoveMarkerController moveMarkerController,
    this.moveCenter = true,
    Duration duration,
    this.moveCallBack,
    this.popup,
  })
      : this.moveMarkerController =
      moveMarkerController ?? MoveMarkerController(),
        this.duration = duration ?? Duration(microseconds: 500),
        assert(points.isNotEmpty),
        assert(marker != null || markerBuilder != null),
        super(key: key, rebuild: rebuild);
}
