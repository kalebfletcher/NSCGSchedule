import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

class BadgeDefinition {
  final List<String> ids; // plain ids like "C123456"
  final List<String> hashes; // optional sha256 hex strings
  final String label;
  final String? icon; // material icon name
  final String? imageUrl; // optional image URL
  final int priority;

  BadgeDefinition({
    required this.ids,
    required this.hashes,
    required this.label,
    this.icon,
    this.imageUrl,
    required this.priority,
  });

  factory BadgeDefinition.fromMap(Map<String, dynamic> m) {
    return BadgeDefinition(
      ids:
          (m['ids'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          [],
      hashes:
          (m['hashes'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          [],
      label: m['label'] ?? '',
      icon: m['icon'],
      imageUrl: m['imageUrl'],
      priority: (m['priority'] is int) ? m['priority'] as int : 0,
    );
  }
}

class BadgesService {
  BadgesService._private();
  static final BadgesService instance = BadgesService._private();

  List<BadgeDefinition> _definitions = [];
  Directory? _cacheDir;
  String? remoteUrl;

  Future<void> init({String? remoteJsonUrl}) async {
    // Only set remoteUrl when a value is provided so callers can set the
    // property ahead of time and call init() later without clearing it.
    if (remoteJsonUrl != null) remoteUrl = remoteJsonUrl;
    _cacheDir = await getApplicationSupportDirectory();
    await _loadCached();
    if (remoteUrl != null) {
      await fetchAndCache(remoteUrl!);
    }
  }

  Future<void> _loadCached() async {
    try {
      _cacheDir ??= await getApplicationSupportDirectory();
      final f = File(p.join(_cacheDir!.path, 'badges.json'));
      if (await f.exists()) {
        final s = await f.readAsString();
        _parseAndSet(s);
      }
    } catch (_) {}
  }

  Future<void> fetchAndCache(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = resp.body;
        _parseAndSet(body);
        _cacheDir ??= await getApplicationSupportDirectory();
        final f = File(p.join(_cacheDir!.path, 'badges.json'));
        await f.writeAsString(body);
        // Precache images listed
        for (final d in _definitions) {
          if (d.imageUrl != null && d.imageUrl!.isNotEmpty) {
            _downloadBadgeImage(d.imageUrl!);
          }
        }
      }
    } catch (_) {}
  }

  void _parseAndSet(String jsonText) {
    try {
      final map = json.decode(jsonText) as Map<String, dynamic>;
      final list = (map['badges'] as List?) ?? [];
      _definitions = list
          .map((e) => BadgeDefinition.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _definitions = [];
    }
  }

  List<BadgeDefinition> getBadgesForIds({String? id, String? userId}) {
    final results = <BadgeDefinition>[];
    final candidates = _definitions;
    final idsToCheck = <String>[];
    if (userId != null) idsToCheck.add(userId.toLowerCase());
    if (id != null) idsToCheck.add(id.toLowerCase());

    final hashesToCheck = idsToCheck.map((s) => _sha256Hex(s)).toList();

    for (final d in candidates) {
      bool matched = false;
      for (final plain in d.ids) {
        if (idsToCheck.contains(plain.toLowerCase())) {
          matched = true;
          break;
        }
      }
      if (!matched && d.hashes.isNotEmpty) {
        for (final h in d.hashes) {
          if (hashesToCheck.contains(h.toLowerCase())) {
            matched = true;
            break;
          }
        }
      }
      if (matched) results.add(d);
    }

    results.sort((a, b) => b.priority.compareTo(a.priority));
    return results;
  }

  // convenience that accepts a Friend-like object with `id` and `userId` fields
  List<BadgeDefinition> getBadgesFor(dynamic friend) {
    try {
      return getBadgesForIds(
        id: friend.id as String?,
        userId: friend.userId as String?,
      );
    } catch (_) {
      return [];
    }
  }

  Future<File?> _downloadBadgeImage(String url) async {
    try {
      _cacheDir ??= await getApplicationSupportDirectory();
      final key = _sha256Hex(url);
      final ext = p.extension(Uri.parse(url).path);
      final fn = 'badge_$key$ext';
      final file = File(p.join(_cacheDir!.path, fn));
      if (await file.exists()) return file;
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        await file.writeAsBytes(resp.bodyBytes);
        return file;
      }
    } catch (_) {}
    return null;
  }

  Future<File?> getBadgeImageFile(BadgeDefinition def) async {
    if (def.imageUrl == null || def.imageUrl!.isEmpty) return null;
    try {
      _cacheDir ??= await getApplicationSupportDirectory();
      final key = _sha256Hex(def.imageUrl!);
      final ext = p.extension(Uri.parse(def.imageUrl!).path);
      final fn = 'badge_$key$ext';
      final file = File(p.join(_cacheDir!.path, fn));
      if (await file.exists()) return file;
      return await _downloadBadgeImage(def.imageUrl!);
    } catch (_) {
      return null;
    }
  }

  String _sha256Hex(String input) {
    final normalized = input.toLowerCase();
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Small mapping for common material icon names used in badges
  static const Map<String, IconData> iconMap = {
    'developer_mode': Icons.developer_mode,
    'developer': Icons.developer_mode,
    'verified': Icons.verified,
    'star': Icons.star,
    'beta': Icons.new_releases,
    'shield': Icons.shield,
    'handyman': Icons.handyman,
    'labs': Icons.science,
    'science': Icons.science,
  };
}
