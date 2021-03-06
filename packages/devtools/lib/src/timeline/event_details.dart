// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'package:html_shim/html.dart' as html;

import '../globals.dart';
import '../profiler/cpu_profile_flame_chart.dart';
import '../profiler/cpu_profile_tables.dart';
import '../profiler/cpu_profiler.dart';
import '../ui/colors.dart';
import '../ui/elements.dart';
import '../ui/fake_flutter/dart_ui/dart_ui.dart';
import '../ui/flutter_html_shim.dart';
import '../ui/theme.dart';
import '../utils.dart';
import 'timeline_controller.dart';

class EventDetails extends CoreElement {
  EventDetails(this._timelineController) : super('div') {
    flex();
    layoutVertical();

    _initContent();
    _initListeners();

    // The size of the event details section will change as the splitter is
    // is moved. Observe resizing so that we can rebuild the flame chart canvas
    // as necessary.
    // TODO(jacobr): Change argument type when
    // https://github.com/dart-lang/sdk/issues/36798 is fixed.
    final observer = html.ResizeObserver((List<dynamic> entries, _) {
      _cpuProfiler.flameChart.updateForContainerResize();
    });
    observer.observe(element);

    assert(_tabNav != null);
    assert(_content != null);

    add([_tabNav.element, _content]);
  }

  static const _defaultTitleText = '[No event selected]';

  static const _defaultTitleBackground = ThemedColor(
    Color(0xFFF6F6F6),
    Color(0xFF2D2E31), // Material Dark Grey 900+2
  );

  final TimelineController _timelineController;

  CpuProfilerTabNav _tabNav;

  CoreElement _content;

  CoreElement _title;

  _CpuProfiler _cpuProfiler;

  CoreElement _gpuEventDetails;

  Color titleBackgroundColor = _defaultTitleBackground;

  Color titleTextColor = contrastForeground;

  void _initContent() {
    _title = div(text: _defaultTitleText, c: 'event-details-heading');
    _title.element.style
      ..color = colorToCss(titleTextColor)
      ..backgroundColor = colorToCss(titleBackgroundColor);

    final details = div(c: 'event-details')
      ..layoutVertical()
      ..flex()
      ..add([
        _cpuProfiler = _CpuProfiler(
          _timelineController,
          () => _timelineController.timelineData.cpuProfileData,
        )..hidden(true),
        // TODO(kenzie): eventually we should show something in this area that
        // is useful for GPU events as well (tips, links to docs, etc).
        _gpuEventDetails = div(
          text: 'CPU profiling is not available for GPU events.',
          c: 'centered-single-line-message',
        )..hidden(true),
      ]);

    _content = div(c: 'event-details-section section-border')
      ..flex()
      ..add(<CoreElement>[_title, details]);

    _tabNav = CpuProfilerTabNav(
      _cpuProfiler,
      CpuProfilerTabOrder(
        first: CpuProfilerViewType.flameChart,
        second: CpuProfilerViewType.callTree,
        third: CpuProfilerViewType.bottomUp,
      ),
    );
  }

  void _initListeners() {
    _timelineController.onSelectedFrame.listen((_) => reset());

    _timelineController.onSelectedTimelineEvent
        .listen((_) async => await update());

    _timelineController.onLoadOfflineData.listen((_) async {
      // If there is no CPU profile data, there is no reason to show the event
      // details section.
      if (_timelineController.offlineTimelineData.hasCpuProfileData()) {
        titleTextColor = Colors.black;
        titleBackgroundColor = mainUiColor;
        await update();
      }
    });
  }

  Future<void> update({bool hide = false}) async {
    final selectedEvent = _timelineController.timelineData?.selectedEvent;

    _title.text = selectedEvent != null
        ? '${selectedEvent.name} - ${msText(selectedEvent.time.duration)}'
        : _defaultTitleText;
    _title.element.style
      ..backgroundColor = colorToCss(titleBackgroundColor)
      ..color = colorToCss(titleTextColor);

    hidden(hide);
    _gpuEventDetails.hidden(selectedEvent?.isUiEvent ?? true);
    _cpuProfiler.hidden(selectedEvent?.isGpuEvent ?? true);

    if (selectedEvent != null && selectedEvent.isUiEvent) {
      await _cpuProfiler.update();
    }
  }

  void reset({bool hide = false}) {
    titleTextColor = contrastForeground;
    titleBackgroundColor = _defaultTitleBackground;
    update(hide: hide);
  }
}

class _CpuProfiler extends CpuProfiler {
  _CpuProfiler(
    this._timelineController,
    CpuProfileDataProvider profileDataProvider,
  ) : super(
          CpuFlameChart(profileDataProvider),
          CpuCallTree(profileDataProvider),
          CpuBottomUp(profileDataProvider),
        );

  final TimelineController _timelineController;

  @override
  Future<void> prepareCpuProfile() async {
    // Fetch a profile if we are not loading from offline.
    if (!offlineMode || _timelineController.offlineTimelineData == null) {
      await _timelineController.getCpuProfileForSelectedEvent();
    }
  }

  @override
  bool maybeShowMessageOnUpdate() {
    if (offlineMode &&
        !collectionEquals(_timelineController.timelineData.selectedEvent.json,
            _timelineController.offlineTimelineData?.selectedEvent?.json)) {
      final offlineModeMessage = div()
        ..add(span(
            text:
                'CPU profiling is not yet available for snapshots. You can only'
                ' view '));
      if (_timelineController.offlineTimelineData.hasCpuProfileData()) {
        offlineModeMessage
          ..add(span(text: 'the '))
          ..add(span(text: 'CPU profile', c: 'message-action')
            ..click(() {
              // TODO(kenzie): ensure event details title style is restored.
              _timelineController.setOfflineData();
            }))
          ..add(span(text: ' included in the snapshot.'));
      } else {
        offlineModeMessage.add(span(
            text:
                'a CPU profile if it is included in the imported snapshot file.'));
      }
      showMessage(offlineModeMessage);
      return true;
    }

    final cpuProfileData = _timelineController.timelineData.cpuProfileData;
    if (cpuProfileData != null && cpuProfileData.stackFrames.isEmpty) {
      final frameOffset =
          _timelineController.timelineData.selectedFrame.time.start;
      final startTime =
          _timelineController.timelineData.selectedEvent.time.start -
              frameOffset;
      final endTime =
          _timelineController.timelineData.selectedEvent.time.end - frameOffset;
      showMessage(div(
          text: 'CPU profile unavailable for time range'
              ' [${msText(startTime, fractionDigits: 2)} -'
              ' ${msText(endTime, fractionDigits: 2)}]'));
      return true;
    }
    return false;
  }
}
