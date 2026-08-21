import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../shared/theme/theme_extensions.dart';

/// Unified widget for displaying images loaded from the Lute server or web.
/// Automatically resolves relative paths (e.g. `/userimages/1/pic.jpg`) against
/// the active Lute [serverUrl] and injects [customHeaders] for authentication.
class LuteImage extends ConsumerWidget {
  final String? imageUrl;
  final String? serverUrl;
  final Map<String, String>? customHeaders;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const LuteImage({
    super.key,
    required this.imageUrl,
    this.serverUrl,
    this.customHeaders,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  /// Resolves an image URL (relative or absolute) against [serverUrl].
  static String? resolveImageUrl(String? imageUrl, String? serverUrl) {
    if (imageUrl == null) return null;
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty || trimmed.endsWith('/-')) {
      return null;
    }

    if (trimmed.startsWith('data:image')) {
      return trimmed;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    final base = serverUrl ?? '';
    final cleanBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;

    if (trimmed.startsWith('/')) {
      return '$cleanBase$trimmed';
    }

    return '$cleanBase/$trimmed';
  }

  /// Checks whether a given [url] targets the Lute [serverUrl].
  static bool isLuteServerUrl(String? url, String? serverUrl) {
    if (url == null ||
        url.trim().isEmpty ||
        serverUrl == null ||
        serverUrl.trim().isEmpty) {
      return false;
    }
    try {
      final targetUri = Uri.parse(url.trim());
      final serverUri = Uri.parse(serverUrl.trim());

      // If relative path without scheme/host, it belongs to the Lute server
      if (!targetUri.hasScheme || targetUri.host.isEmpty) {
        return true;
      }

      // Check scheme, host, and port
      final isSameHost =
          targetUri.host.toLowerCase() == serverUri.host.toLowerCase();
      final targetPort = targetUri.hasPort
          ? targetUri.port
          : (targetUri.scheme == 'https' ? 443 : 80);
      final serverPort = serverUri.hasPort
          ? serverUri.port
          : (serverUri.scheme == 'https' ? 443 : 80);

      return isSameHost && targetPort == serverPort;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveServerUrl =
        serverUrl ?? ref.watch(settingsProvider.select((s) => s.serverUrl));
    final effectiveHeaders =
        customHeaders ??
        ref.watch(settingsProvider.select((s) => s.customHeaders));

    final resolvedUrl = resolveImageUrl(imageUrl, effectiveServerUrl);

    Widget content;
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      content = errorWidget ?? _buildDefaultPlaceholder(context);
    } else if (resolvedUrl.startsWith('data:image')) {
      content = _buildBase64Image(context, resolvedUrl);
    } else {
      final isLuteServer = isLuteServerUrl(resolvedUrl, effectiveServerUrl);
      final headersToSend = isLuteServer &&
              effectiveHeaders != null &&
              effectiveHeaders.isNotEmpty
          ? effectiveHeaders
          : null;

      content = CachedNetworkImage(
        imageUrl: resolvedUrl,
        httpHeaders: headersToSend,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) =>
            placeholder ?? _buildLoadingPlaceholder(context),
        errorWidget: (context, url, error) =>
            errorWidget ?? _buildDefaultPlaceholder(context),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildBase64Image(BuildContext context, String dataUri) {
    try {
      final commaIndex = dataUri.indexOf(',');
      if (commaIndex != -1) {
        final base64Str = dataUri.substring(commaIndex + 1);
        final Uint8List bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
              errorWidget ?? _buildDefaultPlaceholder(context),
        );
      }
    } catch (_) {
      // Fall through to error
    }
    return errorWidget ?? _buildDefaultPlaceholder(context);
  }

  Widget _buildLoadingPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: context.appColorScheme.background.surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildDefaultPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: context.appColorScheme.background.surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: context.appColorScheme.text.primary.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
