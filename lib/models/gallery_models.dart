import 'package:photo_manager/photo_manager.dart';

class ImportedImage {
  final String path;
  final String name;
  final DateTime addedAt;

  const ImportedImage({
    required this.path,
    required this.name,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'addedAt': addedAt.toIso8601String(),
  };

  factory ImportedImage.fromJson(Map<String, dynamic> json) {
    return ImportedImage(
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      addedAt:
      DateTime.tryParse((json['addedAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

class MySelection {
  final String id;
  final bool isImported;

  const MySelection({
    required this.id,
    required this.isImported,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MySelection &&
        other.id == id &&
        other.isImported == isImported;
  }

  @override
  int get hashCode => Object.hash(id, isImported);
}

class MyAppImage {
  final String id;
  final String title;
  final AssetEntity? asset;
  final ImportedImage? imported;

  MyAppImage.asset(this.asset)
      : imported = null,
        id = asset!.id,
        title = asset.title ?? 'Item';

  MyAppImage.imported(this.imported)
      : asset = null,
        id = imported!.path,
        title = imported.name;

  bool get isImported => imported != null;

  bool get isVideo {
    if (imported != null) {
      final lower = imported!.path.toLowerCase();
      return lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.3gp') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.m4v');
    }
    return asset?.type == AssetType.video;
  }

  bool get isImage => !isVideo;
}