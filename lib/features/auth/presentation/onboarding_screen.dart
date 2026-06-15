import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/tiipee_wordmark.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      emoji: '📵',
      emojiSize: 80,
      bg: Color(0xFF0A0E1A),
      accentColor: AppColors.emerald,
      title: 'Plus tu décroches,\nplus tu gagnes.',
      subtitle:
          'Plus ton enfant pose son téléphone, plus il gagne sa récompense. Simple. Mesurable. Motivant.',
      illustrationEmojis: ['💰', '📵', '⏱️'],
    ),
    _Slide(
      emoji: '🪄',
      emojiSize: 72,
      bg: Color(0xFF0F1729),
      accentColor: AppColors.emerald,
      title: 'Comment ça\nmarche ?',
      subtitle:
          '1️⃣ Tu configures les règles.\n2️⃣ Ton enfant installe Tiipee sur SON téléphone et le connecte avec ton code.\n3️⃣ Tiipee mesure le temps d\'écran et calcule ses gains — tu verses quand tu veux.',
      illustrationEmojis: ['⚙️', '📲', '💸'],
    ),
    _Slide(
      emoji: '🛡️',
      emojiSize: 72,
      bg: Color(0xFF0F1729),
      accentColor: AppColors.amber,
      title: 'Tu décides\ndes règles.',
      subtitle:
          'Socle garanti chaque semaine + bonus screen-free avec plafond journalier. Zéro conflit, zéro frustration.',
      illustrationEmojis: ['⚙️', '📊', '✅'],
    ),
    _Slide(
      emoji: '🔥',
      emojiSize: 72,
      bg: Color(0xFF0D1520),
      accentColor: AppColors.violet,
      title: 'Séries, badges\net vrais euros.',
      subtitle:
          'L\'enfant enchaîne les jours consécutifs, débloque des badges, et reçoit un vrai virement de toi chaque semaine.',
      illustrationEmojis: ['🏆', '🎯', '💎'],
    ),
  ];

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) context.go('/role');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _slides[_page].bg,
      body: Stack(
        children: [
          // Pages
          PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _SlidePage(slide: _slides[i]),
          ),

          // Logotype persistant en haut
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(child: TiipeeWordmark(fontSize: 26)),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i
                              ? _slides[_page].accentColor
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // CTA
                  Row(
                    children: [
                      if (_page > 0)
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white60,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => _controller.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            ),
                            child: const Text('Retour'),
                          ),
                        ),
                      if (_page > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _slides[_page].accentColor,
                                _slides[_page].accentColor.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _slides[_page].accentColor.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                if (_page < _slides.length - 1) {
                                  _controller.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  _done();
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Center(
                                  child: Text(
                                    _page < _slides.length - 1
                                        ? 'Suivant →'
                                        : 'Commencer gratuitement',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Skip
                  if (_page < _slides.length - 1)
                    TextButton(
                      onPressed: _done,
                      child: const Text(
                        'Passer',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  final String emoji;
  final double emojiSize;
  final Color bg;
  final Color accentColor;
  final String title;
  final String subtitle;
  final List<String> illustrationEmojis;

  const _Slide({
    required this.emoji,
    required this.emojiSize,
    required this.bg,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.illustrationEmojis,
  });
}

class _SlidePage extends StatelessWidget {
  final _Slide slide;

  const _SlidePage({required this.slide});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Illustration zone
            Expanded(
              child: Center(
                child: _IllustrationZone(slide: slide),
              ),
            ),

            const SizedBox(height: 32),

            // Title
            Text(
              slide.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),

            const SizedBox(height: 16),

            // Subtitle
            Text(
              slide.subtitle,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 16,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IllustrationZone extends StatelessWidget {
  final _Slide slide;

  const _IllustrationZone({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow circle
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: slide.accentColor.withValues(alpha: 0.08),
          ),
        ),
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: slide.accentColor.withValues(alpha: 0.1),
          ),
        ),

        // Main emoji
        Text(slide.emoji, style: TextStyle(fontSize: slide.emojiSize)),

        // Floating mini emojis
        Positioned(
          top: 20,
          right: 40,
          child: _FloatingEmoji(
            emoji: slide.illustrationEmojis[0],
            delay: 0,
          ),
        ),
        Positioned(
          bottom: 30,
          right: 20,
          child: _FloatingEmoji(
            emoji: slide.illustrationEmojis[1],
            delay: 200,
          ),
        ),
        Positioned(
          bottom: 20,
          left: 30,
          child: _FloatingEmoji(
            emoji: slide.illustrationEmojis[2],
            delay: 400,
          ),
        ),
      ],
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  final String emoji;
  final int delay;

  const _FloatingEmoji({required this.emoji, required this.delay});

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2000 + widget.delay),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(widget.emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
