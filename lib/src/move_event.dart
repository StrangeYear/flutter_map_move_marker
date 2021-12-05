import 'package:latlong2/latlong.dart';

class MoveEvent {
  final LatLng? point;
  final MoveEventAction action;

  MoveEvent.start()
      : this.point = null,
        this.action = MoveEventAction.start;

  MoveEvent.stop()
      : this.point = null,
        this.action = MoveEventAction.stop;

  MoveEvent.pause()
      : this.point = null,
        this.action = MoveEventAction.pause;

  MoveEvent.resume()
      : this.point = null,
        this.action = MoveEventAction.resume;

  MoveEvent.moveTo(this.point)
      : this.action = MoveEventAction.moveTo,
        assert(point != null);
}

enum MoveEventAction {
  start,
  stop,
  pause,
  resume,
  moveTo,
}
