import 'package:flutter/material.dart';
import '../network/api_client.dart';

/// Turns any relative or misplaced image/avatar path into a valid absolute URL.
/// Handles backslashes, old host IPs, localhost, and relative paths.
String? resolveImageUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  var value = raw.trim().replaceAll('\\', '/');

  // If it's already a data URI or blob URL
  if (value.startsWith('data:') || value.startsWith('blob:')) {
    return value;
  }

  // Base URL normalization
  final base = kBaseUrl.endsWith('/')
      ? kBaseUrl.substring(0, kBaseUrl.length - 1)
      : kBaseUrl;

  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    // If it's an absolute URL pointing to localhost, 127.0.0.1 or an old IP pointing to /uploads/ or /api/
    if (uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.path.startsWith('/uploads') ||
        uri.path.startsWith('uploads')) {
      final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
      return '$base$path${uri.hasQuery ? '?${uri.query}' : ''}';
    }
    return value;
  }

  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

/// Generates 1-2 letter initials from a full name.
String getInitials(String? name) {
  if (name == null || name.trim().isEmpty) return 'D';
  var clean = name.trim();
  final lower = clean.toLowerCase();
  for (final prefix in ['dr.', 'dr ', 'doctor ', 'د.', 'د ']) {
    if (lower.startsWith(prefix)) {
      clean = clean.substring(prefix.length).trim();
      break;
    }
  }
  if (clean.isEmpty) return 'D';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
  return clean.substring(0, clean.length.clamp(0, 2)).toUpperCase();
}

/// A resilient circular avatar that resolves image URLs, loads over network,
/// and falls back smoothly to initials without showing a blank space.
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double radius;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.radius = 20,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveImageUrl(imageUrl);
    final initials = getInitials(name);
    final bg = backgroundColor ?? const Color(0xFFCCFBF1);
    final fg = textColor ?? const Color(0xFF0F766E);
    final fSize = fontSize ?? (radius * 0.75);

    Widget avatarContent;
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: ClipOval(
          child: Image.network(
            resolvedUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: radius * 2,
                height: radius * 2,
                color: bg,
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: fSize,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: radius * 2,
                height: radius * 2,
                color: bg,
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: fSize,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      avatarContent = CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: fSize,
            fontWeight: FontWeight.bold,
            color: fg,
          ),
        ),
      );
    }

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: avatarContent,
      );
    }

    return avatarContent;
  }
}
