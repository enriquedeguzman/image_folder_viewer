import 'package:path/path.dart' as p;

class OrganizerUtils {
  static bool isImageFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.bmp'].contains(ext);
  }

  static bool isVideoFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.mov', '.mkv', '.avi', '.3gp', '.webm', '.m4v']
        .contains(ext);
  }

  static bool isAllowedDocumentFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp',
      '.pdf',
      '.json',
      '.txt',
      '.mp4',
      '.mov',
      '.mkv',
      '.avi',
      '.3gp',
      '.webm',
      '.m4v',
    ].contains(ext);
  }
}