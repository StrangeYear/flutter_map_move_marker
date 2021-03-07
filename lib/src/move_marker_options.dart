import 'package:flutter_map/flutter_map.dart';
import 'package:latlong/latlong.dart';
import 'package:flutter/foundation.dart';

import 'move_state.dart';
import 'move_marker_controller.dart';

typedef MoveCallBack = void Function(MoveState moveState, {LatLng latLng});

class MoveMarkerOptions extends LayerOptions {
  final Marker marker;
  final List<LatLng> points;
  final MoveMarkerController moveMarkerController;
  final MoveCallBack moveCallBack;

  // auto move to map center
  final bool moveCenter;

  // Moving animation time per 100 meters default 500ms
  final Duration duration;

  MoveMarkerOptions({
    Key key,
    Stream<Null> rebuild,
    @required this.marker,
    this.points = const [],
    MoveMarkerController moveMarkerController,
    this.moveCenter = true,
    Duration duration,
    this.moveCallBack,
  })  : this.moveMarkerController =
            moveMarkerController ?? MoveMarkerController(),
        this.duration = duration ?? Duration(microseconds: 500),
        assert(points.isNotEmpty),
        super(key: key, rebuild: rebuild);
}
