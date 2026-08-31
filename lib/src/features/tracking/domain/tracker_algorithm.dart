/// Tracking algorithms the app knows about.
///
/// [wireName] is what travels to the backend `tracker_algorithm` column, so it
/// must stay in sync with `MdfTracker.Api.Models.TrackerAlgorithm`.
enum TrackerAlgorithm {
  csrt('csrt', 'CSRT', 'Follows the target\'s size and survives occlusion. '
      'Slowest - lower the tracking resolution if the FPS drops.'),
  kcf('kcf', 'KCF', 'Much faster than CSRT. Keeps the box at its seeded size.'),
  mil('mil', 'MIL', 'Fixed-size box, no scale tracking. Lightest of the three.');

  const TrackerAlgorithm(this.wireName, this.label, this.description);

  final String wireName;
  final String label;
  final String description;

  static TrackerAlgorithm fromWire(String value) => TrackerAlgorithm.values
      .firstWhere((e) => e.wireName == value, orElse: () => TrackerAlgorithm.mil);
}
