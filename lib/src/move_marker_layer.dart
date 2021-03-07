import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong/latlong.dart';

import 'move_marker_options.dart';
import 'move_state.dart';
import 'move_event.dart';

class MoveMarkerLayer extends StatefulWidget {
  final MoveMarkerOptions markerOptions;
  final MapState mapState;
  final Stream<Null> stream;

  MoveMarkerLayer(this.markerOptions, this.mapState, this.stream, {Key key})
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

  int _currentIndex;
  List<LatLng> _points;
  List<Duration> _durations;

  LatLng _latLng;

  AnimationController _animationController;
  Tween<double> _latTween;
  Tween<double> _lngTween;
  Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _currentIndex = 0;
    widget.markerOptions.moveMarkerController.state = MoveState.notStartedState;
    widget.markerOptions.moveMarkerController.streamController =
        StreamController<MoveEvent>.broadcast();
    widget.markerOptions.moveMarkerController.streamController.stream
        .listen((event) => _handleAction(event));

    _animationController =
        AnimationController(duration: Duration(seconds: 5), vsync: this)
          ..addListener(() {
            // Get the latest longitude and latitude update interface
            // of the current animation value every time the animation is modified
            var latLng = LatLng(
                _latTween.evaluate(_animation), _lngTween.evaluate(_animation));
            // If the next coordinate is not in the map, modify the center of the map
            if (widget.markerOptions.moveCenter &&
                !_boundsContainsMarker(widget.markerOptions.marker, latLng)) {
              widget.mapState.move(latLng, widget.mapState.zoom ?? 18.0);
            }
            setState(() {
              _latLng = latLng;
            });
          });

    // Set up linear animation
    _animation =
        CurvedAnimation(parent: _animationController, curve: Curves.linear);

    _filterPoints();

    if (_points.isNotEmpty) {
      // 设置当前marker坐标为第一个point
      _latLng = _points[0];
      _latTween = Tween(end: _latLng.latitude)..animate(_animation);
      _lngTween = Tween(end: _latLng.longitude)..animate(_animation);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
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
    if (widget.markerOptions.moveMarkerController.state == MoveState.runState) {
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
        return _moveTo(event.point);
    }
  }

  _start() {
    if (isRunning) {
      return;
    }

    if (isPaused) {
      _resume();
    } else {
      widget.markerOptions.moveMarkerController.state = MoveState.runState;
      _callback(MoveState.runState);
      _animate();
    }
  }

  _stop() {
    if (isEnded) {
      return;
    }

    _currentIndex = 0;
    _animationController.stop();
    widget.markerOptions.moveMarkerController.state = MoveState.endedState;
    _callback(MoveState.endedState);
  }

  _pause() {
    if (!isRunning) {
      return;
    }
    _animationController.stop(canceled: false);
    widget.markerOptions.moveMarkerController.state = MoveState.pausedState;
    _callback(MoveState.pausedState);
  }

  _resume() async {
    if (!isPaused) {
      return;
    }

    // Finish the previous animation first
    await _animationController.forward();
    widget.markerOptions.moveMarkerController.state = MoveState.runState;
    _callback(MoveState.runState);
    _animate();
  }

  _animate() async {
    // If it starts from first point, move the marker to first point
    if (_currentIndex == 0) {
      var latLng = _points[0];
      if (_latLng != latLng) {
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
        break;
      }
    }
    _currentIndex = 0;
    widget.markerOptions.moveMarkerController.state = MoveState.endedState;
    _callback(MoveState.endedState);
  }

  _callback(MoveState moveState, {LatLng latLng}) {
    if (widget.markerOptions.moveCallBack != null) {
      widget.markerOptions.moveCallBack(
        moveState,
        latLng: latLng,
      );
    }
  }

  _moveTo(LatLng point) {
    // todo
  }

  Future<bool> _updateLatLng(LatLng latLng) async {
    _latTween.begin = _latTween.end;
    _lngTween.begin = _lngTween.end;
    _latTween.end = latLng.latitude;
    _lngTween.end = latLng.longitude;
    try {
      if (!isRunning) {
        return false;
      }
      _animationController.reset();
      await _animationController.forward(from: 0.0);
      _callback(MoveState.runState, latLng: latLng);
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  CustomPoint _parseLatLng(LatLng latLng) {
    var pos = widget.mapState.project(latLng);
    pos = pos.multiplyBy(widget.mapState
            .getZoomScale(widget.mapState.zoom, widget.mapState.zoom)) -
        widget.mapState.getPixelOrigin();

    var pixelPosX = (pos.x -
            (widget.markerOptions.marker.width -
                widget.markerOptions.marker.anchor.left))
        .toDouble();
    var pixelPosY = (pos.y -
            (widget.markerOptions.marker.height -
                widget.markerOptions.marker.anchor.top))
        .toDouble();

    return CustomPoint(pixelPosX, pixelPosY);
  }

  bool _boundsContainsMarker(Marker marker, LatLng latLng) {
    var pixelPoint = widget.mapState.project(latLng);

    final width = marker.width - marker.anchor.left;
    final height = marker.height - marker.anchor.top;

    var sw = CustomPoint(pixelPoint.x + width, pixelPoint.y - height);
    var ne = CustomPoint(pixelPoint.x - width, pixelPoint.y + height);
    return widget.mapState.pixelBounds.containsPartialBounds(Bounds(sw, ne));
  }

  Widget _build() {
    var customPoint = _parseLatLng(_latLng);
    return Positioned(
      width: widget.markerOptions.marker.width,
      height: widget.markerOptions.marker.height,
      left: customPoint.x,
      top: customPoint.y,
      child: widget.markerOptions.marker.builder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: widget.stream,
      builder: (context, snapshot) {
        return _points.isNotEmpty
            ? Container(
                child: Stack(
                  children: [_build()],
                ),
              )
            : Container();
      },
    );
  }
}
