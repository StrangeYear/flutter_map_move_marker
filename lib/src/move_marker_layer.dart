import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:synchronized/synchronized.dart';

import 'move_marker_options.dart';
import 'move_state.dart';
import 'move_event.dart';

class MoveMarkerLayer extends StatefulWidget {
  final MoveMarkerOptions markerOptions;
  final MapState mapState;
  final Stream<Null> stream;

  MoveMarkerLayer(this.markerOptions, this.mapState, this.stream, {Key? key})
      : super(key: key);

  @override
  _MoveMarkerLayerState createState() => _MoveMarkerLayerState();
}

class _MoveMarkerLayerState extends State<MoveMarkerLayer>
    with SingleTickerProviderStateMixin {
  bool get isRunning =>
      widget.markerOptions.moveMarkerController.state == MoveState.runState;

  bool get isEnded =>
      widget.markerOptions.moveMarkerController.state == MoveState.endedState;

  bool get isStarted =>
      widget.markerOptions.moveMarkerController.state ==
      MoveState.notStartedState;

  bool get isPaused =>
      widget.markerOptions.moveMarkerController.state == MoveState.pausedState;

  final Distance _distance = Distance();

  final Lock _stateLock = Lock();

  late int _currentIndex;
  late List<LatLng> _points;
  late List<Duration> _durations;

  late LatLng _latLng;
  double _mileage = 0;

  late AnimationController _animationController;
  late Tween<double> _latTween;
  late Tween<double> _lngTween;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _currentIndex = 0;
    widget.markerOptions.moveMarkerController.state = MoveState.notStartedState;
    widget.markerOptions.moveMarkerController.streamController =
        StreamController<MoveEvent>.broadcast();
    widget.markerOptions.moveMarkerController.streamController.stream
        .listen((event) => _handleAction(event));

    _animationController = AnimationController(
        duration: Duration(seconds: 5), vsync: this)
      ..addListener(() {
        // Get the latest longitude and latitude update interface
        // of the current animation value every time the animation is modified
        var latLng = LatLng(
            _latTween.evaluate(_animation), _lngTween.evaluate(_animation));
        // If the next coordinate is not in the map, modify the center of the map
        if (widget.markerOptions.moveCenter && !_boundsContainsMarker(latLng)) {
          widget.mapState.move(latLng, widget.mapState.zoom, source: MapEventSource.mapController);
        }
        setState(() {
          _latLng = latLng;
        });
      });

    // Set up linear animation
    _animation =
        CurvedAnimation(parent: _animationController, curve: Curves.linear);

    _filterPoints();

    // 设置当前marker坐标为第一个point
    _latLng = _points[0];
    _latTween = Tween(end: _latLng.latitude)..animate(_animation);
    _lngTween = Tween(end: _latLng.longitude)..animate(_animation);
    setState(() {});
  }

  @override
  void dispose() {
    _animationController.dispose();
    widget.markerOptions.moveMarkerController.streamController.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(MoveMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markerOptions.duration != widget.markerOptions.duration) {
      // Recalculate durations
      var ratio = widget.markerOptions.duration.inMicroseconds /
          oldWidget.markerOptions.duration.inMicroseconds;
      _durations = _durations.map((e) => e * ratio).toList();
    }
    if (widget.markerOptions.moveMarkerController.state ==
        MoveState.notInitState) {
      _updateState(MoveState.runState);
      _animate();
    }
  }

  void _filterPoints() {
    var durations = <Duration>[];
    // The animation time needed to calculate the coordinates
    for (var i = 0; i < widget.markerOptions.points.length; i++) {
      var latLng = widget.markerOptions.points[i];
      if (i == widget.markerOptions.points.length - 1) {
        durations.add(Duration(microseconds: 50));
      } else {
        // Calculate the distance according to the coordinate points
        var nextLatLng = widget.markerOptions.points[i + 1];
        // unit m
        var pointDistance = _distance.distance(latLng, nextLatLng);
        // Calculate animation time based on distance
        var duration = widget.markerOptions.duration * (pointDistance * 100.0);
        durations.add(duration);
      }
    }

    _points = widget.markerOptions.points;
    _durations = durations;
  }

  void _handleAction(MoveEvent event) {
    switch (event.action) {
      case MoveEventAction.start:
        return _start();
      case MoveEventAction.stop:
        return _stop();
      case MoveEventAction.pause:
        return _pause();
      case MoveEventAction.resume:
        return _resume();
      case MoveEventAction.moveTo:
        return _moveTo(event.point!);
    }
  }

  _start() async {
    if (isRunning) {
      return;
    }
    await _stateLock.synchronized(() async {
      if (isRunning) {
        return;
      }

      if (isPaused) {
        _resume();
      } else {
        _mileage = 0;
        _updateState(MoveState.runState);
        _animate();
      }
    });
  }

  _stop() async {
    if (isEnded) {
      return;
    }
    await _stateLock.synchronized(() async {
      if (isEnded) {
        return;
      }
      _currentIndex = 0;
      _updateState(MoveState.endedState);
      _animationController.stop();
      _mileage = 0;
    });
  }

  _pause() async {
    if (!isRunning) {
      return;
    }
    await _stateLock.synchronized(() async {
      if (!isRunning) {
        return;
      }
      _updateState(MoveState.pausedState);
      _animationController.stop(canceled: false);
    });
  }

  _resume() async {
    if (!isPaused) {
      return;
    }
    await _stateLock.synchronized(() async {
      if (!isPaused) {
        return;
      }

      _updateState(MoveState.runState);
      // Finish the previous animation first
      await _animationController.forward();
      _animate();
    });
  }

  _updateState(MoveState moveState) {
    widget.markerOptions.moveMarkerController.state = moveState;
    _callback(moveState);
  }

  _animate() async {
    // If it starts from first point or last point, move the marker to first point
    if (_currentIndex == 0 || _currentIndex == _points.length - 1) {
      if (_currentIndex != 0) _currentIndex = 0;
      var latLng = _points[0];
      if (_latLng != latLng) {
        _updateState(MoveState.notInitState);
        setState(() {
          _latLng = latLng;
        });
        return;
      }
    }

    while (_currentIndex < _points.length - 1) {
      if (!isRunning) {
        return;
      }

      _animationController.duration = _durations[_currentIndex];
      _currentIndex += 1;
      var nextLatLng = _points[_currentIndex];
      bool res = await _updateLatLng(nextLatLng);
      if (!res) {
        // Animation execution failure indicates that the pause loop has been terminated by other methods
        return;
      }
    }

    if (_animationController.isCompleted) {
      var latLng = _points[0];
      _latTween.end = latLng.latitude;
      _lngTween.end = latLng.longitude;
      _updateState(MoveState.endedState);
    }
  }

  _callback(MoveState moveState, {LatLng? latLng}) {
    if (widget.markerOptions.moveCallBack != null) {
      widget.markerOptions.moveCallBack!(
        moveState,
        latLng: latLng,
      );
    }
  }

  _moveTo(LatLng point) async {
    // todo
    await _stateLock.synchronized(() async {
      await _updateLatLng(point);
      _updateState(MoveState.endedState);
    });
  }

  Future<bool> _updateLatLng(LatLng latLng) async {
    _latTween.begin = _latTween.end;
    _lngTween.begin = _lngTween.end;
    _latTween.end = latLng.latitude;
    _lngTween.end = latLng.longitude;

    // 计算里程 current += (latLng - _latLng)
    var mileage = _getDistance(_latLng, latLng);

    try {
      if (!isRunning) {
        return false;
      }
      _animationController.reset();
      _callback(MoveState.runningState, latLng: latLng);
      await _animationController.forward(from: 0.0);
      _mileage += mileage;
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  CustomPoint<double> _parseLatLng(LatLng latLng) {
    var marker = _getMarker();
    var pos = widget.mapState.project(latLng);
    pos = pos.multiplyBy(widget.mapState
            .getZoomScale(widget.mapState.zoom, widget.mapState.zoom)) -
        widget.mapState.getPixelOrigin();

    var pixelPosX = (pos.x - (marker.width - marker.anchor.left)).toDouble();
    var pixelPosY = (pos.y - (marker.height - marker.anchor.top)).toDouble();

    return CustomPoint(pixelPosX, pixelPosY);
  }

  bool _boundsContainsMarker(LatLng latLng) {
    var marker = _getMarker();
    var pixelPoint = widget.mapState.project(latLng);

    final width = marker.width - marker.anchor.left;
    final height = marker.height - marker.anchor.top;

    var sw = CustomPoint(pixelPoint.x + width, pixelPoint.y - height);
    var ne = CustomPoint(pixelPoint.x - width, pixelPoint.y + height);
    return widget.mapState.pixelBounds.containsPartialBounds(Bounds(sw, ne));
  }

  Marker _getMarker() {
    return widget.markerOptions.marker != null
        ? widget.markerOptions.marker!
        : widget.markerOptions.markerBuilder!(_currentIndex);
  }

  List<Widget> _build() {
    var customPoint = _parseLatLng(_latLng);
    var marker = _getMarker();
    return [
      Positioned(
        width: marker.width,
        height: marker.height,
        left: customPoint.x,
        top: customPoint.y,
        child: marker.builder(context),
      ),
      if (widget.markerOptions.popup != null)
        // 构建popup 带上坐标和里程
        Positioned(
          width: widget.markerOptions.popup!.width,
          height: widget.markerOptions.popup!.height,
          left: customPoint.x + marker.width,
          top: customPoint.y -
              widget.markerOptions.popup!.height +
              marker.height / 2,
          child: widget.markerOptions.popup!.popupBuilder(
            context,
            latLng: _points[_currentIndex],
            mileage: _mileage,
            index: _currentIndex,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: widget.stream,
      builder: (context, snapshot) {
        return _points.isNotEmpty
            ? Container(
                child: Stack(
                  children: _build(),
                ),
              )
            : Container();
      },
    );
  }
}

double _getDistance(LatLng latLng1, LatLng latLng2) {
  /// 单位：米
  double def = 6378137.0;
  double radLat1 = _rad(latLng1.latitude);
  double radLat2 = _rad(latLng2.latitude);
  double a = radLat1 - radLat2;
  double b = _rad(latLng1.longitude) - _rad(latLng2.longitude);
  double s = 2 *
      asin(sqrt(pow(sin(a / 2), 2) +
          cos(radLat1) * cos(radLat2) * pow(sin(b / 2), 2)));
  return (s * def).roundToDouble();
}

double _rad(double d) {
  return d * pi / 180.0;
}
