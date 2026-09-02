import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/data/object_tracker.dart';
import '../../tracking/domain/camera_lens.dart';
import '../../tracking/domain/tracker_algorithm.dart';
import '../application/settings_controller.dart';
import '../domain/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('Tracker'),
          _AlgorithmTile(
            value: settings.algorithm,
            onChanged: controller.setAlgorithm,
          ),
          const Divider(height: 32),
          const _SectionHeader('Camera'),
          _LensTile(value: settings.lens, onChanged: controller.setLens),
          const Divider(height: 32),
          const _SectionHeader('Performance'),
          _ResolutionTile(
            value: settings.processingScale,
            onChanged: controller.setProcessingScale,
          ),
          const Divider(height: 32),
          const _SectionHeader('Target location estimate'),
          _FovTile(
            value: settings.cameraHorizontalFovDegrees,
            onChanged: controller.setCameraHorizontalFovDegrees,
          ),
          _CameraHeightTile(
            value: settings.assumedCameraHeightMeters,
            onChanged: controller.setAssumedCameraHeightMeters,
          ),
          const Divider(height: 32),
          const _SectionHeader('Appearance'),
          _BoxColorTile(
            color: settings.boxColor,
            onChanged: controller.setBoxColor,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _AlgorithmTile extends StatelessWidget {
  const _AlgorithmTile({required this.value, required this.onChanged});

  final TrackerAlgorithm value;
  final ValueChanged<TrackerAlgorithm> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<TrackerAlgorithm>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final algorithm in TrackerAlgorithm.values)
            RadioListTile<TrackerAlgorithm>(
              value: algorithm,
              // Algorithms without a Dart binding stay visible but inert.
              enabled: TrackerAvailability.isAvailable(algorithm),
              title: Row(
                children: [
                  Text(algorithm.label),
                  if (!TrackerAvailability.isAvailable(algorithm)) ...[
                    const SizedBox(width: 8),
                    const _UnavailableBadge(),
                  ],
                ],
              ),
              subtitle: Text(
                TrackerAvailability.isAvailable(algorithm)
                    ? algorithm.description
                    : TrackerAvailability.unavailableReason(algorithm),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnavailableBadge extends StatelessWidget {
  const _UnavailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'no binding',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _LensTile extends StatelessWidget {
  const _LensTile({required this.value, required this.onChanged});

  final CameraLens value;
  final ValueChanged<CameraLens> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<CameraLens>(
        segments: const [
          ButtonSegment(
            value: CameraLens.back,
            label: Text('Back'),
            icon: Icon(Icons.photo_camera_back_outlined),
          ),
          ButtonSegment(
            value: CameraLens.front,
            label: Text('Front'),
            icon: Icon(Icons.photo_camera_front_outlined),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _ResolutionTile extends StatelessWidget {
  const _ResolutionTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tracking resolution'),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value,
            min: AppSettings.minProcessingScale,
            max: AppSettings.maxProcessingScale,
            divisions: 6,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
          Text(
            'Frames are downscaled by this factor before the tracker sees them. '
            'Lower is faster; small or distant targets need a higher setting.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FovTile extends StatelessWidget {
  const _FovTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Camera field of view'),
              Text(
                '${value.round()}°',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value,
            min: AppSettings.minHorizontalFov,
            max: AppSettings.maxHorizontalFov,
            divisions: 60,
            label: '${value.round()}°',
            onChanged: onChanged,
          ),
          Text(
            "Horizontal field of view of the rear camera. No device database is "
            "available, so this defaults to a typical phone lens - correct it if "
            "you know your device's actual spec, for a more accurate estimate "
            "of the tracked object's real-world location.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CameraHeightTile extends StatelessWidget {
  const _CameraHeightTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Assumed camera height'),
              Text(
                '${value.toStringAsFixed(1)} m',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value,
            min: AppSettings.minCameraHeight,
            max: AppSettings.maxCameraHeight,
            divisions: 17,
            label: '${value.toStringAsFixed(1)} m',
            onChanged: onChanged,
          ),
          Text(
            "How high the camera sits above the ground the target stands on, "
            "while tracking. Used to estimate the target's real-world "
            "location; no sensor measures this directly.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BoxColorTile extends StatelessWidget {
  const _BoxColorTile({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Bounding box colour'),
      subtitle: Text('#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}'),
      trailing: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
        ),
      ),
      onTap: () => _pickColour(context),
    );
  }

  Future<void> _pickColour(BuildContext context) async {
    var draft = color;
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bounding box colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: color,
            enableAlpha: false,
            onColorChanged: (value) => draft = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft),
            child: const Text('Use colour'),
          ),
        ],
      ),
    );

    if (picked != null) onChanged(picked);
  }
}
