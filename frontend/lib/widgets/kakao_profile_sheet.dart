import 'package:flutter/material.dart';

import '../theme.dart';

class KakaoProfileSheet extends StatelessWidget {
  final String fallbackUserName;
  final String? email;
  final String? profileImageUrl;
  final Future<void> Function() onLogout;
  final Future<void> Function() onWithdrawComplete;

  const KakaoProfileSheet({
    super.key,
    required this.fallbackUserName,
    required this.onLogout,
    required this.onWithdrawComplete,
    this.email,
    this.profileImageUrl,
  });

  Future<void> _handleLogout(BuildContext context) async {
    await onLogout();

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleWithdraw(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            '회원 탈퇴',
            style: TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            '카카오 연결을 해제하고 로그아웃할까요?\n이 작업은 되돌릴 수 없습니다.',
            style: TextStyle(
              color: AppColors.muted,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                '탈퇴',
                style: TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await onWithdrawComplete();

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfileImage =
        profileImageUrl != null && profileImageUrl!.isNotEmpty;

    final hasEmail = email != null && email!.isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            const SizedBox(height: 24),

            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.cardAlt,
              backgroundImage: hasProfileImage
                  ? NetworkImage(profileImageUrl!)
                  : null,
              child: hasProfileImage
                  ? null
                  : const Icon(
                      Icons.person,
                      color: AppColors.foreground,
                      size: 42,
                    ),
            ),

            const SizedBox(height: 14),

            Text(
              fallbackUserName,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              hasEmail ? email! : '카카오 계정으로 로그인됨',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 24),

            _SheetButton(
              icon: Icons.logout,
              label: '로그아웃',
              color: AppColors.foreground,
              onTap: () => _handleLogout(context),
            ),

            const SizedBox(height: 10),

            _SheetButton(
              icon: Icons.delete_outline,
              label: '회원 탈퇴',
              color: AppColors.pink,
              onTap: () => _handleWithdraw(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}