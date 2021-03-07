import 'dart:async';

import 'move_event.dart';
import 'move_state.dart';
import 'package:latlong/latlong.dart';

class MoveMarkerController {
  StreamController<MoveEvent> streamController;

  MoveState state;

  void start() {
    streamController?.add(MoveEvent.start());
  }

  void stop() {
    streamController?.add(MoveEvent.stop());
  }

  void pause() {
    streamController?.add(MoveEvent.pause());
  }

  void resume() {
    streamController?.add(MoveEvent.resume());
  }

  void moveTo(LatLng point) {
    streamController?.add(MoveEvent.moveTo(point));
  }
}
