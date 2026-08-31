/// Which physical camera the session runs against.
///
/// [wireName] maps onto the backend `camera_type` enum ('front' | 'back').
enum CameraLens {
  back('back', 'Back'),
  front('front', 'Front');

  const CameraLens(this.wireName, this.label);

  final String wireName;
  final String label;

  static CameraLens fromWire(String value) => CameraLens.values
      .firstWhere((e) => e.wireName == value, orElse: () => CameraLens.back);
}
