import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum NotificationType {
  success,
  error,
  warning,
  info,
}

/// Global Toast and Notification system for Flutter, mirroring Angular's
/// UiService.showSuccess, showError, showWarning, showInfo block toast cards.
class AppNotification {
  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onDismiss,
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Success',
      type: NotificationType.success,
      duration: duration,
      onDismiss: onDismiss,
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 4500),
    VoidCallback? onDismiss,
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Error',
      type: NotificationType.error,
      duration: duration,
      onDismiss: onDismiss,
    );
  }

  static void showWarning(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3800),
    VoidCallback? onDismiss,
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Notice',
      type: NotificationType.warning,
      duration: duration,
      onDismiss: onDismiss,
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onDismiss,
  }) {
    show(
      context,
      message: message,
      title: title ?? 'Information',
      type: NotificationType.info,
      duration: duration,
      onDismiss: onDismiss,
    );
  }

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    required NotificationType type,
    Duration duration = const Duration(milliseconds: 3500),
    VoidCallback? onDismiss,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        padding: EdgeInsets.zero,
        duration: duration,
        content: _ToastCard(
          title: title,
          message: message,
          type: type,
          onClose: () {
            messenger.hideCurrentSnackBar();
            onDismiss?.call();
          },
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  final String? title;
  final String message;
  final NotificationType type;
  final VoidCallback onClose;

  const _ToastCard({
    this.title,
    required this.message,
    required this.type,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getStyleConfig(type);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: config.accentColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Accent Bar (matches Angular's 5px border-left)
            Container(
              width: 5,
              color: config.accentColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon Badge (tinted circle with crisp symbol)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: config.iconBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Icon(
                          config.icon,
                          size: 18,
                          color: config.accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title & Message Body
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null && title!.isNotEmpty) ...[
                            Text(
                              title!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: config.accentColor,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            message,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textMain,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Dismiss Button (✕)
                    GestureDetector(
                      onTap: onClose,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: AppTheme.textMuted.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _NotificationConfig _getStyleConfig(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return _NotificationConfig(
          accentColor: const Color(0xFF059669), // Emerald Green
          iconBg: const Color(0xFFECFDF5),
          icon: Icons.check_circle_rounded,
        );
      case NotificationType.error:
        return _NotificationConfig(
          accentColor: const Color(0xFFDC2626), // Rose Red
          iconBg: const Color(0xFFFEF2F2),
          icon: Icons.error_rounded,
        );
      case NotificationType.warning:
        return _NotificationConfig(
          accentColor: const Color(0xFFD97706), // Amber Orange
          iconBg: const Color(0xFFFFFBEB),
          icon: Icons.warning_rounded,
        );
      case NotificationType.info:
        return _NotificationConfig(
          accentColor: const Color(0xFF0284C7), // Sky Blue
          iconBg: const Color(0xFFF0F9FF),
          icon: Icons.info_rounded,
        );
    }
  }
}

class _NotificationConfig {
  final Color accentColor;
  final Color iconBg;
  final IconData icon;

  _NotificationConfig({
    required this.accentColor,
    required this.iconBg,
    required this.icon,
  });
}

/// Block-style in-page alert banner (equivalent to Angular's .alert .alert-success / .alert-danger)
class AppAlertBlock extends StatelessWidget {
  final String message;
  final String? title;
  final NotificationType type;
  final Widget? action;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry? margin;

  const AppAlertBlock({
    super.key,
    required this.message,
    this.title,
    this.type = NotificationType.info,
    this.action,
    this.onClose,
    this.margin,
  });

  const AppAlertBlock.success({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onClose,
    this.margin,
  }) : type = NotificationType.success;

  const AppAlertBlock.error({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onClose,
    this.margin,
  }) : type = NotificationType.error;

  const AppAlertBlock.warning({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onClose,
    this.margin,
  }) : type = NotificationType.warning;

  const AppAlertBlock.info({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.onClose,
    this.margin,
  }) : type = NotificationType.info;

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(type);

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: config.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: config.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              color: config.accent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(config.icon, size: 20, color: config.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null && title!.isNotEmpty) ...[
                            Text(
                              title!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: config.accent,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            message,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: config.text,
                              height: 1.35,
                            ),
                          ),
                          if (action != null) ...[
                            const SizedBox(height: 8),
                            action!,
                          ],
                        ],
                      ),
                    ),
                    if (onClose != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onClose,
                        child: Icon(Icons.close, size: 16, color: config.accent.withValues(alpha: 0.7)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _AlertBlockConfig _getConfig(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return _AlertBlockConfig(
          bg: const Color(0xFFF0FDF4),
          border: const Color(0xFFBBF7D0),
          accent: const Color(0xFF16A34A),
          text: const Color(0xFF14532D),
          icon: Icons.check_circle_outline_rounded,
        );
      case NotificationType.error:
        return _AlertBlockConfig(
          bg: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          accent: const Color(0xFFDC2626),
          text: const Color(0xFF7F1D1D),
          icon: Icons.error_outline_rounded,
        );
      case NotificationType.warning:
        return _AlertBlockConfig(
          bg: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          accent: const Color(0xFFD97706),
          text: const Color(0xFF78350F),
          icon: Icons.warning_amber_rounded,
        );
      case NotificationType.info:
        return _AlertBlockConfig(
          bg: const Color(0xFFF0F9FF),
          border: const Color(0xFFBAE6FD),
          accent: const Color(0xFF0284C7),
          text: const Color(0xFF0C4A6E),
          icon: Icons.info_outline_rounded,
        );
    }
  }
}

class _AlertBlockConfig {
  final Color bg;
  final Color border;
  final Color accent;
  final Color text;
  final IconData icon;

  _AlertBlockConfig({
    required this.bg,
    required this.border,
    required this.accent,
    required this.text,
    required this.icon,
  });
}
