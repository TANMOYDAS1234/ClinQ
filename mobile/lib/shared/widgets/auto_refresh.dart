import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often screens that show live clinic data (open slots, today's diary)
/// re-fetch while open. 15s keeps availability fresh without draining a phone;
/// change this one value to poll faster or slower.
const Duration kAutoRefreshInterval = Duration(seconds: 15);

/// Wraps a screen so its data refreshes on a timer while it is on screen and
/// the app is foregrounded, and again the moment the app resumes. This is on
/// top of the on-open fetch and pull-to-refresh — the belt-and-braces that make
/// availability feel live without a socket.
///
/// [onTick] is where the screen invalidates whatever providers it shows.
class AutoRefresh extends ConsumerStatefulWidget {
  const AutoRefresh({
    super.key,
    required this.onTick,
    required this.child,
    this.interval = kAutoRefreshInterval,
  });

  final void Function(WidgetRef ref) onTick;
  final Widget child;
  final Duration interval;

  @override
  ConsumerState<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<AutoRefresh> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) widget.onTick(ref);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Catch up immediately, then resume the cadence.
      if (mounted) widget.onTick(ref);
      _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
