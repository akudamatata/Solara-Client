import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Native remote controls channel for iOS lock screen / Control Center.
const MethodChannel _remoteControlsChannel =
    MethodChannel('solara/remote_controls');

Future<Directory?> _ensureSolaraDirectory({String? child}) async {
  if (!Platform.isIOS) {
    return null;
  }
  try {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/Solara');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    if (child == null || child.isEmpty) {
      return root;
    }
    final directory = Directory('${root.path}/$child');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.solara.mobile.channel.audio',
    androidNotificationChannelName: 'Solara Playback',
    androidNotificationOngoing: true,
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  runApp(const SolaraApp());
}

class SolaraApp extends StatelessWidget {
  const SolaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = SolaraApi();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SolaraNotificationController(),
        ),
        ChangeNotifierProvider(
          create: (_) => SolaraPlayerController(api),
        ),
        ChangeNotifierProxyProvider<SolaraPlayerController, SolaraSearchController>(
          create: (_) => SolaraSearchController(api),
          update: (_, player, search) => (search ?? SolaraSearchController(api))
            ..attachPlayer(player),
        ),
      ],
      child: MaterialApp(
        title: 'Solara',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'SpecialElite',
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF6B5F),
            secondary: Color(0xFF272B34),
            surface: Color(0xFF0E0F13),
            onSurface: Color(0xFFFAFAFA),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'SpecialElite',
                bodyColor: Colors.white,
                displayColor: Colors.white,
              ),
          useMaterial3: true,
        ),
        home: const SolaraHomePage(),
      ),
    );
  }
}

enum SolaraNotificationType { info, success, warning, error }

enum CollectionTransferMode { import, export }

class SolaraNotificationData {
  const SolaraNotificationData({
    required this.id,
    required this.message,
    required this.type,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final int id;
  final String message;
  final SolaraNotificationType type;
  final IconData icon;
  final Color background;
  final Color foreground;
}

class SolaraNotificationController extends ChangeNotifier {
  final Queue<_PendingNotification> _queue = Queue<_PendingNotification>();
  SolaraNotificationData? _current;
  Timer? _timer;
  int _counter = 0;

  SolaraNotificationData? get current => _current;

  void show(
    String message, {
    SolaraNotificationType type = SolaraNotificationType.info,
  }) {
    _queue.add(_PendingNotification(message, type));
    if (_current == null) {
      _displayNext();
    }
  }

  void success(String message) => show(message, type: SolaraNotificationType.success);

  void error(String message) => show(message, type: SolaraNotificationType.error);

  void _displayNext() {
    _timer?.cancel();
    if (_queue.isEmpty) {
      _current = null;
      notifyListeners();
      return;
    }
    final pending = _queue.removeFirst();
    final data = _buildNotification(pending);
    _current = data;
    notifyListeners();
    _timer = Timer(const Duration(milliseconds: 2600), _displayNext);
  }

  SolaraNotificationData _buildNotification(_PendingNotification pending) {
    final theme = pending.type;
    late final Color background;
    late final IconData icon;
    Color foreground = Colors.white;
    switch (theme) {
      case SolaraNotificationType.success:
        background = const Color(0xFF1F3A2C);
        icon = Icons.check_circle_rounded;
        break;
      case SolaraNotificationType.warning:
        background = const Color(0xFF3A2F1F);
        icon = Icons.warning_amber_rounded;
        foreground = const Color(0xFFFFD87A);
        break;
      case SolaraNotificationType.error:
        background = const Color(0xFF3A1F25);
        icon = Icons.error_rounded;
        break;
      case SolaraNotificationType.info:
        background = const Color(0xFF212530);
        icon = Icons.info_rounded;
        break;
    }
    final id = ++_counter;
    return SolaraNotificationData(
      id: id,
      message: pending.message,
      type: pending.type,
      icon: icon,
      background: background,
      foreground: foreground,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _PendingNotification {
  const _PendingNotification(this.message, this.type);

  final String message;
  final SolaraNotificationType type;
}

class SolaraHomePage extends StatefulWidget {
  const SolaraHomePage({super.key});

  @override
  State<SolaraHomePage> createState() => _SolaraHomePageState();
}

class _SolaraHomePageState extends State<SolaraHomePage> {
  bool _showQueue = false;
  bool _showFavorites = false;
  bool _showSearch = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF362125), Color(0xFF050608)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            const _BackgroundHalo(),
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final media = MediaQuery.of(context);
                      final safeHeight =
                          media.size.height - media.padding.top - media.padding.bottom;
                      final double availableHeight = constraints.hasBoundedHeight
                          ? constraints.maxHeight
                          : safeHeight;
                      final bool isCompact = availableHeight < 720;
                      final bool isCupertino =
                          Theme.of(context).platform == TargetPlatform.iOS;
                      final double cupertinoBaseSpacing = isCupertino
                          ? _clampSpacing(availableHeight * 0.02, 8, 32)
                          : 0;
                      final double cupertinoDetailSpacing = isCupertino
                          ? _clampSpacing(availableHeight * 0.015, 6, 18)
                          : 0;
                      final double cupertinoMidSpacing = isCupertino
                          ? _clampSpacing(availableHeight * 0.01, 6, 18)
                          : 0;

                      final bodySectionSpacing = _clampSpacing(
                        availableHeight * 0.018 +
                            cupertinoBaseSpacing * 0.8 +
                            cupertinoMidSpacing,
                        14,
                        isCupertino ? 42 : 24,
                      );

                      final minorSpacing = _clampSpacing(
                        availableHeight * 0.012 +
                            cupertinoDetailSpacing +
                            cupertinoMidSpacing * 0.6,
                        10,
                        isCupertino ? 26 : 16,
                      );
                      // 统一上下边缘留白，让内容在垂直方向更均衡
                      const double topBarSpacing = 8;

                      final topBar = _buildToolbar(context);

                      final compactPlayerSection = _PlayerContentStack(
                        majorSpacing: bodySectionSpacing,
                        minorSpacing: minorSpacing,
                        useFlexibleSpacing: false,
                      );
                      final expandedPlayerSection = _PlayerContentStack(
                        majorSpacing: bodySectionSpacing,
                        minorSpacing: minorSpacing,
                        useFlexibleSpacing: true,
                      );

                      final topSection = <Widget>[
                        topBar,
                        const SizedBox(height: topBarSpacing),
                        if (isCompact)
                          compactPlayerSection
                        else
                          Expanded(child: expandedPlayerSection),
                      ];

                      final controlsSection = SafeArea(
                        top: false,
                        bottom: true,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildControls(context),
                        ),
                      );

                      final controlSpacing = max(minorSpacing, isCupertino ? 24.0 : 18.0);

                      Widget pageContent;

                      if (isCompact) {
                        pageContent = SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          // 调整底部填充，使用较小的固定值，并保留 media.padding.bottom
                          padding:
                              EdgeInsets.only(bottom: 16.0 + media.padding.bottom),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...topSection,
                              SizedBox(height: controlSpacing),
                              controlsSection,
                            ],
                          ),
                        );
                        return SafeArea(
                          top: true,
                          bottom: false,
                          child: pageContent,
                        );
                      }

                      if (isCupertino) {
                        pageContent = SizedBox(
                          height: availableHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...topSection,
                                ],
                              ),
                            ),
                              SizedBox(height: controlSpacing),
                              controlsSection,
                            ],
                          ),
                        );
                        return SafeArea(
                          top: true,
                          bottom: false,
                          child: pageContent,
                        );
                      }

                      pageContent = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...topSection,
                              ],
                            ),
                          ),
                          SizedBox(height: controlSpacing),
                          controlsSection,
                        ],
                      );

                      return SafeArea(
                        top: true,
                        bottom: false,
                        child: pageContent,
                      );
                    },
                  ),
                ),
              ),
            ),
            // 添加底部渐变层
            Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: Builder(
                  builder: (context) {
                    final media = MediaQuery.of(context);
                    return Container(
                      height: media.padding.bottom + 30,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x00050608), Color(0xFF050608)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _QueuePanel(
              visible: _showQueue,
              showFavorites: _showFavorites,
              onClose: () => setState(() => _showQueue = false),
              onToggleTab: (favorites) => setState(() => _showFavorites = favorites),
            ),
            _SearchOverlay(
              visible: _showSearch,
              onClose: () => setState(() => _showSearch = false),
            ),
            const _NotificationOverlay(),
            ],
          ),
      ),
    );
  }

  void _openSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      barrierColor: Colors.black.withOpacity(0.6),
      backgroundColor: Colors.transparent,
      builder: (context) => const _SettingsSheet(),
    );
  }

  double _clampSpacing(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Widget _buildToolbar(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final isCupertino = Theme.of(context).platform == TargetPlatform.iOS;
    if (!isCupertino) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0x33000000),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_note, size: 18),
                  SizedBox(width: 8),
                  Text('Solara'),
                ],
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _showSearch = true),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.queue_music_outlined),
                onPressed: () {
                  setState(() {
                    _showFavorites = false;
                    _showQueue = true;
                  });
                },
              ),
            ],
          ),
        ],
      );
    }

    const double buttonSize = 44;
    return Row(
      children: [
        SizedBox(
          height: buttonSize,
          width: buttonSize,
          child: _ToolbarCircleButton(
            icon: Icons.radar,
            tooltip:
                player.enabledExploreGenres.isEmpty ? '请选择探索流派' : '探索雷达',
            isLoading: player.isExploring,
            onTap: player.isExploring || player.enabledExploreGenres.isEmpty
                ? null
                : () {
                    player.exploreRadar().then((added) {
                      final notifications = context.read<SolaraNotificationController?>();
                      if (notifications == null) {
                        return;
                      }
                      if (added > 0) {
                        notifications.success('为你探索到 $added 首新歌');
                      } else if (added == 0) {
                        notifications.show('没有找到新的歌曲，稍后再试试');
                      } else {
                        notifications.error('探索失败，请稍后重试');
                      }
                    });
                  },
          ),
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () => _openSettingsSheet(context),
              child: Text(
                'Solara',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: buttonSize,
              width: buttonSize,
            child: _ToolbarCircleButton(
              icon: Icons.search,
              tooltip: '搜索',
              onTap: () => setState(() => _showSearch = true),
            ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final isPlaying = player.isPlaying;
    final iconTheme = Theme.of(context).iconTheme.copyWith(color: Colors.white);
    final playMode = player.playMode;
    final playModeData = _PlayModeVisuals.from(playMode);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: playModeData.icon,
          tooltip: playModeData.label,
          onTap: player.hasQueue ? player.cyclePlayMode : null,
          iconTheme: iconTheme,
        ),
        const SizedBox(width: 18),
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: player.hasQueue ? player.playPrevious : null,
          iconTheme: iconTheme,
        ),
        const SizedBox(width: 20),
        _ControlButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 68,
          onTap: player.hasQueue
              ? () => isPlaying ? player.pause() : player.resume()
              : null,
          background: const LinearGradient(
            colors: [Color(0xFFFF6B5F), Color(0xFFFF8C66)],
          ),
          iconTheme: iconTheme,
        ),
        const SizedBox(width: 20),
        _ControlButton(
          icon: Icons.skip_next_rounded,
          onTap: player.hasQueue ? player.playNext : null,
          iconTheme: iconTheme,
        ),
        const SizedBox(width: 18),
        _ControlButton(
          icon: Icons.queue_music,
          tooltip: '播放列表',
          isActive: _showQueue && !_showFavorites,
          onTap: () {
            setState(() {
              _showFavorites = false;
              _showQueue = true;
            });
          },
          iconTheme: iconTheme,
        ),
      ],
    );
  }
}

class _BackgroundHalo extends StatelessWidget {
  const _BackgroundHalo();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Container(
          width: 460,
          height: 460,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0x44FF6B5F), Color(0x11000000), Colors.transparent],
              stops: [0.1, 0.5, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationOverlay extends StatelessWidget {
  const _NotificationOverlay();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SolaraNotificationController>();
    final notification = controller.current;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final child = notification == null
        ? const SizedBox.shrink()
        : _NotificationChip(notification: notification);
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offsetAnimation = Tween<Offset>(
              begin: const Offset(0, -0.2),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offsetAnimation, child: child),
            );
          },
          child: notification == null
              ? const SizedBox(key: ValueKey('empty'))
              : Padding(
                  key: ValueKey(notification.id),
                  padding: EdgeInsets.fromLTRB(24, topPadding + 56, 24, 0),
                  child: child,
                ),
        ),
      ),
    );
  }
}

class _NotificationChip extends StatelessWidget {
  const _NotificationChip({required this.notification});

  final SolaraNotificationData notification;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: notification.background.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(notification.icon, size: 20, color: notification.foreground),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                notification.message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: notification.foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final cover = player.currentArtwork;
    final isPlaying = player.isPlaying && !player.isLoadingSong;
    final mediaSize = MediaQuery.of(context).size;
    final isCupertino = Theme.of(context).platform == TargetPlatform.iOS;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double baseCoverSize =
            (mediaSize.width * 0.7).clamp(200.0, 320.0).toDouble();
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : baseCoverSize;
        final double coverSize = isCupertino ? availableWidth : baseCoverSize;

        final Widget artwork = cover == null
            ? _ArtworkPlaceholder(size: coverSize)
            : Image.network(
                cover,
                key: ValueKey(cover),
                width: coverSize,
                height: coverSize,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return const _ArtworkLoading();
                },
                errorBuilder: (_, __, ___) => _ArtworkPlaceholder(size: coverSize),
              );

        return Center(
          child: AnimatedScale(
            scale: isPlaying
                ? (isCupertino ? 1.04 : 1.0)
                : (isCupertino ? 0.92 : 0.9),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: Container(
              width: coverSize,
              height: coverSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF201B26), Color(0xFF101118)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: artwork,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveSize = constraints.biggest.shortestSide.isFinite
            ? constraints.biggest.shortestSide
            : size;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF202631), Color(0xFF12151C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.music_note_rounded,
              size: effectiveSize * 0.38,
              color: Colors.white.withOpacity(0.78),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkLoading extends StatelessWidget {
  const _ArtworkLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}

class _SongSummary extends StatelessWidget {
  const _SongSummary();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final song = player.currentSong;
    final title = song?.name ?? '选择一首歌曲开始播放';
    final artist = song?.artist ?? '未知艺术家';
    final theme = Theme.of(context);
    final isCupertino = theme.platform == TargetPlatform.iOS;
    final bool canFavorite = song != null;
    final bool isFavorite = canFavorite && player.isFavorite(song!);
    final favoriteButton = isCupertino
        ? IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: canFavorite ? () => player.toggleFavorite(song!) : null,
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              color: canFavorite
                  ? (isFavorite ? const Color(0xFFFF4D6A) : Colors.white70)
                  : theme.disabledColor,
              size: 24,
            ),
          )
        : Material(
            shape: const CircleBorder(),
            color: isFavorite
                ? const Color(0x1Aff4d6a)
                : Colors.white.withOpacity(0.08),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: canFavorite ? () => player.toggleFavorite(song!) : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  color: canFavorite
                      ? (isFavorite ? const Color(0xFFFF4D6A) : Colors.white70)
                      : theme.disabledColor,
                  size: 22,
                ),
              ),
            ),
          );

    final followButton = OutlinedButton(
      onPressed: song == null ? null : () {},
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withOpacity(0.28), width: 1),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: const Text('关注'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isCupertino ? 0 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.95),
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            artist,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withOpacity(0.62),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        followButton,
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: isCupertino ? 0 : 12),
              favoriteButton,
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _PlayerContentStack extends StatelessWidget {
  const _PlayerContentStack({
    required this.majorSpacing,
    required this.minorSpacing,
    required this.useFlexibleSpacing,
  });

  final double majorSpacing;
  final double minorSpacing;
  final bool useFlexibleSpacing;

  @override
  Widget build(BuildContext context) {
    final isCupertino = Theme.of(context).platform == TargetPlatform.iOS;
    final children = <Widget>[
      if (useFlexibleSpacing) const Spacer(),
      const Align(
        alignment: Alignment.topCenter,
        child: _PlayerArtwork(),
      ),
      SizedBox(height: majorSpacing),
      if (useFlexibleSpacing) const Spacer(),
      const _SongSummary(),
      SizedBox(height: minorSpacing),
      if (useFlexibleSpacing) const Spacer(),
      _ProgressSection(showInlineQuality: isCupertino),
      SizedBox(height: minorSpacing),
      if (useFlexibleSpacing) const Spacer(),
      if (!isCupertino) const _QualityAndActions(),
      if (useFlexibleSpacing) const Spacer(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _QualityAndActions extends StatelessWidget {
  const _QualityAndActions();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final hasSong = player.currentSong != null;
    final isCupertino = Theme.of(context).platform == TargetPlatform.iOS;
    final Color activeColor = Colors.white.withOpacity(0.95);
    final Color inactiveColor = Colors.white.withOpacity(0.75);

    if (isCupertino) {
      return const _CupertinoQualityDropdown();
    }

    final Color borderColor = Colors.white.withOpacity(0.35);
    final Color backgroundColor = Colors.white.withOpacity(hasSong ? 0.18 : 0.08);
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1),
          color: backgroundColor,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: _QualityDropdown(
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
      ),
    );
  }
}

class _CupertinoQualityDropdown extends StatelessWidget {
  const _CupertinoQualityDropdown();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.center,
      child: SizedBox(
        height: 32,
        child: _QualityDropdown(),
      ),
    );
  }
}

class _QualityDropdown extends StatelessWidget {
  const _QualityDropdown({
    this.activeColor,
    this.inactiveColor,
  });

  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final quality = player.quality;
    final Color resolvedActive = activeColor ?? Colors.white.withOpacity(0.95);
    final Color resolvedInactive = inactiveColor ?? Colors.white.withOpacity(0.75);
    return DropdownButtonHideUnderline(
      child: DropdownButton<SongQuality>(
        value: quality,
        dropdownColor: const Color(0xFF15171D),
        borderRadius: BorderRadius.circular(16),
        icon: Icon(
          Icons.expand_more,
          size: 18,
          color: Colors.white.withOpacity(0.75),
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: resolvedActive,
        ),
        focusColor: Colors.transparent,
        isDense: true,
        onChanged: player.currentSong == null
            ? null
            : (value) {
                if (value != null) {
                  unawaited(player.updateQuality(value));
                  final notifications = context.read<SolaraNotificationController?>();
                  notifications?.success('已切换至${value.label}');
                }
              },
        items: SongQuality.values
            .map(
              (q) => DropdownMenuItem(
                value: q,
                child: Text(
                  q.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: q == quality ? FontWeight.w600 : FontWeight.w400,
                    color: q == quality ? resolvedActive : resolvedInactive,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = context.watch<SolaraPlayerController>();
    final queueCount = player.queue.length;
    final favoritesCount = player.favorites.length;
    final enabledGenres = player.enabledExploreGenres;
    final totalGenres = player.availableExploreGenres.length;
    final exploreSubtitle = enabledGenres.isEmpty
        ? '已关闭所有流派'
        : (enabledGenres.length == totalGenres
            ? '探索所有流派'
            : '探索 ${enabledGenres.length}/$totalGenres 个流派');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF101218).withOpacity(0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '设置',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: '列表管理',
                  children: [
                    _SettingsActionTile(
                      icon: Icons.file_download,
                      label: '导入列表',
                      subtitle: '导入播放列表或收藏列表',
                      onTap: () => _showCollectionTransferSheet(
                        context,
                        player,
                        mode: CollectionTransferMode.import,
                      ),
                    ),
                    _SettingsActionTile(
                      icon: Icons.file_upload,
                      label: '导出列表',
                      subtitle:
                          '播放列表 ${queueCount.toString()} 首 · 收藏列表 ${favoritesCount.toString()} 首',
                      onTap: () => _showCollectionTransferSheet(
                        context,
                        player,
                        mode: CollectionTransferMode.export,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SettingsSection(
                  title: '探索雷达',
                  children: [
                    _SettingsActionTile(
                      icon: Icons.radar,
                      label: '探索雷达',
                      subtitle: exploreSubtitle,
                      onTap: () => _showExplorePreferencesSheet(context, player),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarCircleButton extends StatelessWidget {
  const _ToolbarCircleButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.isLoading = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withOpacity(0.08),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isLoading ? null : onTap,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, size: 22),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({this.showInlineQuality = false});

  final bool showInlineQuality;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final duration = player.duration;
    final position = player.position;
    final isCupertino = Theme.of(context).platform == TargetPlatform.iOS;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.white.withOpacity(0.95),
            inactiveTrackColor: Colors.white.withOpacity(0.24),
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: SliderComponentShape.noOverlay,
            trackShape: const _EdgeToEdgeSliderTrackShape(),
          ),
          child: Slider(
            value: duration.inMilliseconds == 0
                ? 0
                : position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
            min: 0,
            max: duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds.toDouble(),
            onChanged: duration.inMilliseconds == 0
                ? null
                : (value) => player.seek(Duration(milliseconds: value.round())),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment:
              showInlineQuality ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
          children: [
            Text(
              player.positionLabel,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            if (showInlineQuality) ...[
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: isCupertino ? 32 : 30,
                    child: const _QualityDropdown(),
                  ),
                ),
              ),
            ],
            Text(
              player.durationLabel,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.6),
              ),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ],
    );
  }
}

class _EdgeToEdgeSliderTrackShape extends RoundedRectSliderTrackShape {
  const _EdgeToEdgeSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.onTap,
    this.size = 48,
    this.iconTheme,
    this.isActive = false,
    this.background,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final IconThemeData? iconTheme;
  final bool isActive;
  final Gradient? background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: size * 0.45);
    final button = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: background,
          color: background == null
              ? (isActive ? const Color(0x33FF6B5F) : Colors.white.withOpacity(0.05))
              : null,
          shape: BoxShape.circle,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(size),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: IconTheme(
                data: iconTheme ?? Theme.of(context).iconTheme,
                child: iconWidget,
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _PlayModeVisuals {
  const _PlayModeVisuals(this.icon, this.label);

  final IconData icon;
  final String label;

  static _PlayModeVisuals from(PlayMode mode) {
    switch (mode) {
      case PlayMode.list:
        return const _PlayModeVisuals(Icons.repeat_rounded, '列表循环');
      case PlayMode.single:
        return const _PlayModeVisuals(Icons.repeat_one_rounded, '单曲循环');
      case PlayMode.random:
        return const _PlayModeVisuals(Icons.shuffle_rounded, '随机播放');
    }
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.visible,
    required this.showFavorites,
    required this.onClose,
    required this.onToggleTab,
  });

  final bool visible;
  final bool showFavorites;
  final VoidCallback onClose;
  final ValueChanged<bool> onToggleTab;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final songs = showFavorites ? player.favorites : player.queue;

    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final safePadding = mediaQuery.padding;
    return IgnorePointer(
      ignoring: !visible,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              opacity: visible ? 0.6 : 0,
              child: GestureDetector(
                onTap: onClose,
                child: Container(color: Colors.black),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: visible ? 0 : -size.height,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              opacity: visible ? 1 : 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: size.height - safePadding.top,
                    ),
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.primaryDelta != null && details.primaryDelta! > 14) {
                          onClose();
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (details.primaryVelocity != null && details.primaryVelocity! > 400) {
                          onClose();
                        }
                      },
                      child: Material(
                        elevation: 30,
                        color: const Color(0xFF101218).withOpacity(0.96),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(36)),
                        clipBehavior: Clip.antiAlias,
                        child: SafeArea(
                          top: false,
                          bottom: true,
                          minimum: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        showFavorites ? '收藏列表' : '播放列表',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '共 ${songs.length} 首歌曲',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: songs.isEmpty
                                        ? null
                                        : (showFavorites
                                            ? () => _addFavoritesToQueue(
                                                  context,
                                                  player,
                                                )
                                            : () async {
                                                final success = await player
                                                    .playFromCollection(songs, 0);
                                                if (!success) {
                                                  _showSnackBar(
                                                    context,
                                                    '无法播放该歌曲',
                                                    error: true,
                                                  );
                                                  return;
                                                }
                                                onClose();
                                              }),
                                    icon: Icon(
                                      showFavorites
                                          ? Icons.playlist_add_check
                                          : Icons.play_arrow_rounded,
                                    ),
                                    label: Text(
                                      showFavorites ? '全部添加到播放列表' : '播放全部',
                                    ),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                      foregroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      textStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: _QueueTabs(
                                      showFavorites: showFavorites,
                                      onToggle: onToggleTab,
                                      playlistCount: player.queue.length,
                                      favoritesCount: player.favorites.length,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _QueueCircleButton(
                                    icon: Icons.delete_sweep,
                                    tooltip: showFavorites ? '清空收藏列表' : '清空播放列表',
                                    onTap: songs.isEmpty
                                        ? null
                                        : () => _clearCollection(
                                              context,
                                              player,
                                              favorites: showFavorites,
                                            ),
                                  ),
                                  const SizedBox(width: 12),
                                  _QueueCircleButton(
                                    icon: Icons.keyboard_arrow_down_rounded,
                                    tooltip: '收起列表',
                                    onTap: onClose,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                child: _QueueSurface(
                                  padding: EdgeInsets.zero,
                                  child: songs.isEmpty
                                      ? const Center(child: Text('暂无歌曲'))
                                      : ListView.separated(
                                          physics: const BouncingScrollPhysics(),
                                          padding: EdgeInsets.only(
                                            left: 12,
                                            right: 12,
                                            top: 12,
                                            bottom: safePadding.bottom + 20,
                                          ),
                                          itemCount: songs.length,
                                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                                          itemBuilder: (context, index) {
                                            final song = songs[index];
                                            final isActive = player.currentSong == song;
                                            final actions = showFavorites
                                                ? _buildFavoriteActions(
                                                    context,
                                                    player,
                                                    song,
                                                  )
                                                : _buildQueueActions(
                                                    context,
                                                    player,
                                                    song,
                                                  );
                                            return _QueueTile(
                                              song: song,
                                              index: index,
                                              isActive: isActive,
                                              onTap: () async {
                                                final success = await player
                                                    .playFromCollection(songs, index);
                                                if (!success) {
                                                  _showSnackBar(
                                                    context,
                                                    '无法播放该歌曲',
                                                    error: true,
                                                  );
                                                  return;
                                                }
                                                onClose();
                                              },
                                              actions: actions,
                                            );
                                          },
                                        ),
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  void _clearCollection(
    BuildContext context,
    SolaraPlayerController player, {
    required bool favorites,
  }) {
    final removed = favorites ? player.clearFavorites() : player.clearQueue();
    if (removed == 0) {
      _showSnackBar(context, favorites ? '收藏列表为空' : '播放列表为空');
    } else {
      _showSnackBar(
        context,
        favorites ? '收藏列表已清空' : '播放列表已清空',
        success: true,
      );
    }
  }

  Future<void> _addFavoritesToQueue(
    BuildContext context,
    SolaraPlayerController player,
  ) async {
    final added = await player.addFavoritesToQueue();
    if (added == 0) {
      _showSnackBar(context, '收藏歌曲已全部在播放列表中');
    } else {
      _showSnackBar(
        context,
        '已添加 $added 首收藏歌曲到播放列表',
        success: true,
      );
    }
  }

  Future<void> _downloadSong(
    BuildContext context,
    SolaraPlayerController player,
    Song song,
  ) async {
    final url = await player.resolveDownloadUrl(song);
    if (url == null || url.isEmpty) {
      _showSnackBar(context, '暂时无法获取下载链接', error: true);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnackBar(context, '下载链接无效', error: true);
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnackBar(context, '无法打开下载链接', error: true);
    }
  }

  List<_QueueTileAction> _buildQueueActions(
    BuildContext context,
    SolaraPlayerController player,
    Song song,
  ) {
    final isFavorite = player.isFavorite(song);
    return [
      _QueueTileAction(
        icon: isFavorite ? Icons.favorite : Icons.favorite_border,
        tooltip: isFavorite ? '取消收藏' : '收藏',
        color: isFavorite ? Theme.of(context).colorScheme.primary : null,
        onTap: () {
          player.toggleFavorite(song);
          final nowFavorite = player.isFavorite(song);
          _showSnackBar(
            context,
            nowFavorite ? '已添加到收藏' : '已从收藏列表移除',
            success: nowFavorite,
          );
        },
      ),
      _QueueTileAction(
        icon: Icons.download_for_offline_outlined,
        tooltip: '下载',
        onTap: () => _downloadSong(context, player, song),
      ),
      _QueueTileAction(
        icon: Icons.delete_outline,
        tooltip: '从播放列表移除',
        onTap: () {
          final removed = player.removeFromQueue(song);
          if (removed) {
            _showSnackBar(context, '已从播放列表移除', success: true);
          }
        },
      ),
    ];
  }

  List<_QueueTileAction> _buildFavoriteActions(
    BuildContext context,
    SolaraPlayerController player,
    Song song,
  ) {
    return [
      _QueueTileAction(
        icon: Icons.playlist_add,
        tooltip: '添加到播放列表',
        onTap: () async {
          final added = await player.addSongsToQueue([song]);
          _showSnackBar(
            context,
            added > 0 ? '已添加到播放列表' : '歌曲已在播放列表中',
            success: added > 0,
          );
        },
      ),
      _QueueTileAction(
        icon: Icons.download_for_offline_outlined,
        tooltip: '下载',
        onTap: () => _downloadSong(context, player, song),
      ),
      _QueueTileAction(
        icon: Icons.delete_outline,
        tooltip: '移除收藏',
        onTap: () {
          player.toggleFavorite(song);
          _showSnackBar(context, '已从收藏列表移除');
        },
      ),
    ];
  }
}

class _QueueTabs extends StatelessWidget {
  const _QueueTabs({
    required this.showFavorites,
    required this.onToggle,
    required this.playlistCount,
    required this.favoritesCount,
  });

  final bool showFavorites;
  final ValueChanged<bool> onToggle;
  final int playlistCount;
  final int favoritesCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          _QueueTabButton(
            label: '播放列表 ($playlistCount)',
            active: !showFavorites,
            onTap: () => onToggle(false),
          ),
          const SizedBox(width: 6),
          _QueueTabButton(
            label: '收藏列表 ($favoritesCount)',
            active: showFavorites,
            onTap: () => onToggle(true),
          ),
        ],
      ),
    );
  }
}

class _QueueTabButton extends StatelessWidget {
  const _QueueTabButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFFFF6B5F), Color(0xFFFF8C66)],
                  )
                : null,
            color: active ? null : Colors.transparent,
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Colors.white : Colors.white70,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.song,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.actions,
  });

  final Song song;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final List<_QueueTileAction> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(isActive ? 0.14 : 0.06),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              for (final action in actions)
                _QueueTileActionButton(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueTileAction {
  const _QueueTileAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
}

class _QueueTileActionButton extends StatelessWidget {
  const _QueueTileActionButton({required this.action});

  final _QueueTileAction action;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: action.onTap,
      icon: Icon(
        action.icon,
        size: 20,
        color: action.color ?? Theme.of(context).iconTheme.color,
      ),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(10),
        minimumSize: const Size(40, 40),
      ),
    );
    if (action.tooltip == null || action.tooltip!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: button,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(message: action.tooltip!, child: button),
    );
  }
}

class _QueueCircleButton extends StatelessWidget {
  const _QueueCircleButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = primary
        ? theme.colorScheme.primary.withOpacity(0.2)
        : Colors.white.withOpacity(0.08);
    final foreground = primary
        ? theme.colorScheme.primary
        : theme.iconTheme.color ?? Colors.white;
    final button = IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: foreground),
      style: IconButton.styleFrom(
        backgroundColor: background,
        shape: const CircleBorder(),
        fixedSize: const Size(44, 44),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _QueueSurface extends StatelessWidget {
  const _QueueSurface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: Colors.white.withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}

Future<void> _importCollection(
  BuildContext context,
  SolaraPlayerController player, {
  required bool favorites,
}) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final path = result.files.single.path;
    if (path == null) {
      _showSnackBar(context, '未选择有效的文件', error: true);
      return;
    }
    final content = await File(path).readAsString();
    final songs = player.parseImportedSongs(content);
    if (songs.isEmpty) {
      _showSnackBar(context, '未找到可导入的歌曲', error: true);
      return;
    }
    final added = favorites
        ? player.addSongsToFavorites(songs)
        : await player.addSongsToQueue(songs);
    final duplicates = songs.length - added;
    if (added == 0) {
      _showSnackBar(
        context,
        favorites ? '文件中的歌曲已在收藏列表中' : '文件中的歌曲已在播放列表中',
      );
    } else {
      final duplicateHint = duplicates > 0 ? '，$duplicates 首已存在' : '';
      _showSnackBar(
        context,
        '成功导入 $added 首歌曲$duplicateHint',
        success: true,
      );
    }
  } catch (_) {
    _showSnackBar(context, '导入失败，请确认文件格式', error: true);
  }
}

Future<void> _exportCollection(
  BuildContext context,
  SolaraPlayerController player, {
  required bool favorites,
}) async {
  final songs = favorites ? player.favorites : player.queue;
  if (songs.isEmpty) {
    _showSnackBar(
      context,
      favorites ? '收藏列表为空，无法导出' : '播放列表为空，无法导出',
    );
    return;
  }
  try {
    final json = player.buildCollectionExportPayload(songs, favorites: favorites);
    final now = DateTime.now();
    final formatted =
        "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    final label = favorites ? 'favorites' : 'playlist';
    final fileName = 'solara-$label-$formatted.json';
    if (Platform.isIOS) {
      try {
        final savePath = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (savePath != null) {
          final file = File(savePath);
          await file.create(recursive: true);
          await file.writeAsString(json);
          _showSnackBar(
            context,
            '已保存 ${songs.length} 首歌曲',
            success: true,
          );
          return;
        }
      } catch (_) {
        // Ignore and fallback to share sheet.
      }
      final directory = await getTemporaryDirectory();
      final tempFile = File('${directory.path}/$fileName');
      await tempFile.writeAsString(json);
      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'application/json', name: fileName)],
        text: '导出的 Solara ${favorites ? '收藏列表' : '播放列表'}',
      );
      _showSnackBar(
        context,
        '已生成导出文件，可通过系统分享保存',
        success: true,
      );
    } else {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json', name: fileName)],
        text: '导出的 Solara ${favorites ? '收藏列表' : '播放列表'}',
      );
      _showSnackBar(
        context,
        '已导出 ${songs.length} 首歌曲',
        success: true,
      );
    }
  } catch (_) {
    _showSnackBar(context, '导出失败，请稍后重试', error: true);
  }
}

void _showSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
  bool error = false,
}) {
  final notificationController = context.read<SolaraNotificationController?>();
  if (notificationController != null) {
    if (error) {
      notificationController.error(message);
    } else if (success) {
      notificationController.success(message);
    } else {
      notificationController.show(message);
    }
  }
}

Future<void> _showCollectionTransferSheet(
  BuildContext context,
  SolaraPlayerController player, {
  required CollectionTransferMode mode,
}) async {
  final rootContext = context;
  final title = mode == CollectionTransferMode.import ? '导入列表' : '导出列表';
  final helperText =
      mode == CollectionTransferMode.import ? '请选择要导入的列表' : '请选择要导出的列表';
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101218).withOpacity(0.96),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    helperText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  _SettingsActionTile(
                    icon: Icons.queue_music,
                    label: '播放列表',
                    subtitle: '当前 ${player.queue.length} 首',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (mode == CollectionTransferMode.import) {
                        _importCollection(
                          rootContext,
                          player,
                          favorites: false,
                        );
                      } else {
                        _exportCollection(
                          rootContext,
                          player,
                          favorites: false,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingsActionTile(
                    icon: Icons.favorite,
                    label: '收藏列表',
                    subtitle: '当前 ${player.favorites.length} 首',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (mode == CollectionTransferMode.import) {
                        _importCollection(
                          rootContext,
                          player,
                          favorites: true,
                        );
                      } else {
                        _exportCollection(
                          rootContext,
                          player,
                          favorites: true,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _showExplorePreferencesSheet(
  BuildContext context,
  SolaraPlayerController player,
) async {
  final genres = player.availableExploreGenres;
  final initial = player.enabledExploreGenres;
  final updated = await showModalBottomSheet<Set<String>>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (sheetContext) {
      return _ExplorePreferencesSheet(
        genres: genres,
        initialSelection: initial,
      );
    },
  );
  if (updated != null) {
    await player.updateExploreGenreSelection(updated);
    final notifications = context.read<SolaraNotificationController?>();
    notifications?.success('探索雷达偏好已更新');
  }
}

class _ExplorePreferencesSheet extends StatefulWidget {
  const _ExplorePreferencesSheet({
    required this.genres,
    required this.initialSelection,
  });

  final List<String> genres;
  final Set<String> initialSelection;

  @override
  State<_ExplorePreferencesSheet> createState() => _ExplorePreferencesSheetState();
}

class _ExplorePreferencesSheetState extends State<_ExplorePreferencesSheet> {
  late Set<String> _selection = {...widget.initialSelection};

  void _toggleGenre(String genre) {
    setState(() {
      if (_selection.contains(genre)) {
        _selection.remove(genre);
      } else {
        _selection.add(genre);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selection = {...widget.genres};
    });
  }

  void _clearAll() {
    setState(() {
      _selection.clear();
    });
  }

  void _closeSheet() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = min(MediaQuery.of(context).size.height * 0.65, 460.0);
    final totalGenres = widget.genres.length;
    final bool hasSelection = _selection.isNotEmpty;
    final bool hasChanges =
        !const SetEquality<String>().equals(_selection, widget.initialSelection);
    final summary = hasSelection
        ? '探索 ${_selection.length}/$totalGenres 个流派'
        : '未选择任何流派';
    final bool canApply = hasSelection && hasChanges;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF171C25), Color(0xFF090B11)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 28,
                offset: Offset(0, -12),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.radar, size: 20, color: Color(0xFFFF6B5F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '探索雷达',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '选择喜爱的流派作为探索范围，Solara 会定向挖掘。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _closeSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _selectAll,
                      icon: const Icon(Icons.select_all_rounded),
                      label: const Text('全选'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.clear_rounded),
                      label: const Text('清空'),
                    ),
                    const Spacer(),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final genre in widget.genres)
                          _GenreToggleChip(
                            label: genre,
                            selected: _selection.contains(genre),
                            onTap: () => _toggleGenre(genre),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击应用后探索雷达将按此偏好匹配推荐。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: canApply
                            ? () => Navigator.of(context)
                                .pop<Set<String>>({..._selection})
                            : null,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('应用'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreToggleChip extends StatelessWidget {
  const _GenreToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: selected ? color : Colors.white54,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchOverlay extends StatefulWidget {
  const _SearchOverlay({required this.visible, required this.onClose});

  final bool visible;
  final VoidCallback onClose;

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  late final TextEditingController _controller;

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  void initState() {
    super.initState();
    final search = context.read<SolaraSearchController>();
    _controller = TextEditingController(text: search.query);
    _controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    setState(() {});
  }

  void _submitSearch(SolaraSearchController search) {
    _dismissKeyboard();
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      search.reset();
      return;
    }
    search.search(keyword);
  }

  Future<void> _playFromResult(Song song) async {
    _dismissKeyboard();
    final player = context.read<SolaraPlayerController>();
    final notifications = context.read<SolaraNotificationController?>();
    final success = await player.playFromCollection([song], 0);
    if (success) {
      widget.onClose();
    } else {
      notifications?.error('无法播放该歌曲');
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SolaraSearchController>();
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: widget.visible ? 0 : -size.height,
      height: size.height,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Material(
          color: Colors.transparent,
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF16181F), Color(0xFF0B0D12)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: true,
              minimum: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '全网搜索',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '从网易云、酷我、JOOX 捕捉灵感',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down_rounded),
                              tooltip: '收起搜索',
                              onPressed: () {
                                _dismissKeyboard();
                                widget.onClose();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        textAlignVertical: TextAlignVertical.center,
                        onSubmitted: (_) => _submitSearch(search),
                        decoration: InputDecoration(
                          hintText: '搜索歌曲或歌手',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white60,
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIconConstraints:
                              const BoxConstraints(minHeight: 0, minWidth: 0),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_controller.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: '清除',
                                  onPressed: () {
                                    _controller.clear();
                                    search.reset();
                                    _dismissKeyboard();
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.arrow_outward_rounded),
                                tooltip: '搜索',
                                onPressed: () => _submitSearch(search),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SearchSourceSelector(
                      selected: search.source,
                      onSelected: search.changeSource,
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _buildResultsPane(context, search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ImportBar(
                      selectedCount: search.selectedCount,
                      onImport: search.selectedCount == 0
                          ? null
                          : () async {
                              await search.importSelection();
                              widget.onClose();
                            },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsPane(BuildContext context, SolaraSearchController search) {
    if (search.isLoading) {
      return const _SearchStateCard(
        icon: Icons.radar_rounded,
        title: '正在搜索',
        subtitle: '正在向音源请求歌曲…',
        child: Padding(
          padding: EdgeInsets.only(top: 16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (search.query.isEmpty) {
      return const _SearchStateCard(
        icon: Icons.travel_explore,
        title: '开始探索',
        subtitle: '输入关键字，或切换音源获取不同灵感',
      );
    }
    if (search.results.isEmpty) {
      return const _SearchStateCard(
        icon: Icons.sentiment_dissatisfied_rounded,
        title: '没有找到匹配的歌曲',
        subtitle: '尝试更换关键词或切换音源',
      );
    }
    return ScrollConfiguration(
      behavior: const _SearchScrollBehavior(),
      child: ListView.separated(
        key: ValueKey('${search.source.param}-${search.results.length}-${search.selectedCount}'),
        padding: const EdgeInsets.only(bottom: 12),
        physics: const BouncingScrollPhysics(),
        itemCount: search.results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final song = search.results[index];
          final isSelected = search.isSelected(song);
          return _SearchResultTile(
            song: song,
            isSelected: isSelected,
            onSelect: () => search.toggleSelection(song),
            onPlay: () => _playFromResult(song),
          );
        },
      ),
    );
  }
}

class _SearchScrollBehavior extends ScrollBehavior {
  const _SearchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _SearchSourceSelector extends StatelessWidget {
  const _SearchSourceSelector({required this.selected, required this.onSelected});

  final SongSource selected;
  final ValueChanged<SongSource> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final source in SongSource.values)
          GestureDetector(
            onTap: () => onSelected(source),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected == source
                      ? theme.colorScheme.primary
                      : Colors.white24,
                  width: 1.2,
                ),
                color: selected == source
                    ? theme.colorScheme.primary.withOpacity(0.18)
                    : Colors.white.withOpacity(0.03),
                boxShadow: selected == source
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForSource(source),
                    size: 16,
                    color: selected == source
                        ? theme.colorScheme.primary
                        : Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    source.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconForSource(SongSource source) {
    switch (source) {
      case SongSource.netease:
        return Icons.cloud_queue_rounded;
      case SongSource.kuwo:
        return Icons.graphic_eq_rounded;
      case SongSource.joox:
        return Icons.waves_rounded;
    }
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.song,
    required this.isSelected,
    required this.onSelect,
    required this.onPlay,
  });

  final Song song;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAlbum = song.album?.isNotEmpty == true;
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withOpacity(0.03),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.white12,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.2)
                    : Colors.white.withOpacity(0.03),
                border: Border.all(
                  color: isSelected ? theme.colorScheme.primary : Colors.white24,
                ),
              ),
              child: Icon(
                isSelected ? Icons.check_rounded : Icons.add_rounded,
                size: 16,
                color: isSelected ? theme.colorScheme.primary : Colors.white60,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  if (hasAlbum) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.album_outlined,
                          size: 14,
                          color: Colors.white60,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            song.album!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                color: Colors.white,
                onPressed: onPlay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportBar extends StatelessWidget {
  const _ImportBar({required this.selectedCount, required this.onImport});

  final int selectedCount;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool enabled = onImport != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已选 $selectedCount 首歌曲',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '可多选后一次导入到播放列表',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('导入'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchStateCard extends StatelessWidget {
  const _SearchStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.white.withOpacity(0.03),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

class SolaraLogRecorder {
  SolaraLogRecorder._();

  static final SolaraLogRecorder instance = SolaraLogRecorder._();

  Directory? _directory;

  Future<Directory?> _ensureDirectory() async {
    _directory ??= await _ensureSolaraDirectory(child: 'Logs');
    return _directory;
  }

  Future<void> record({
    required Uri uri,
    int? statusCode,
    String? responseBody,
    Object? error,
  }) async {
    try {
      final directory = await _ensureDirectory();
      if (directory == null) {
        return;
      }
      final now = DateTime.now();
      final file = File('${directory.path}/solara-${_dateLabel(now)}.log');
      final timestamp = now.toIso8601String();
      final buffer = StringBuffer()
        ..writeln('[$timestamp]')
        ..writeln('URL: ${uri.toString()}');
      if (statusCode != null) {
        buffer.writeln('Status: $statusCode');
      }
      if (error != null) {
        buffer.writeln('Error: $error');
      }
      if (responseBody != null && responseBody.isNotEmpty) {
        const maxLength = 4000;
        final body = responseBody.length > maxLength
            ? '${responseBody.substring(0, maxLength)}…'
            : responseBody;
        buffer.writeln('Response: $body');
      }
      buffer.writeln();
      await file.writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
    } catch (_) {
      // Ignore logging failures.
    }
  }

  String _dateLabel(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}$month$day';
  }
}

class SolaraApi {
  SolaraApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://music-api.gdstudio.xyz/api.php';
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
    'Referer': 'https://music-api.gdstudio.xyz/',
    'Origin': 'https://music-api.gdstudio.xyz',
    'Accept': 'application/json',
  };

  final Random _rng = Random();

  String _signature() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  Future<dynamic> _get(Map<String, String> params) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      ...params,
      's': params['s'] ?? _signature(),
    });
    String? body;
    int? status;
    var logged = false;
    try {
      final response = await _client.get(uri, headers: _headers);
      status = response.statusCode;
      body = response.body;
      if (status >= 400) {
        throw SolaraApiException('请求失败: $status');
      }
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    } on SolaraApiException catch (error) {
      await SolaraLogRecorder.instance.record(
        uri: uri,
        statusCode: status,
        responseBody: body,
        error: error,
      );
      logged = true;
      rethrow;
    } catch (error) {
      await SolaraLogRecorder.instance.record(
        uri: uri,
        statusCode: status,
        responseBody: body,
        error: error,
      );
      logged = true;
      rethrow;
    } finally {
      if (!logged) {
        await SolaraLogRecorder.instance.record(
          uri: uri,
          statusCode: status,
          responseBody: body,
        );
      }
    }
  }

  Future<List<Song>> fetchPlaylist({String playlistId = '3778678', int limit = 50}) async {
    final data = await _get({
      'types': 'playlist',
      'id': playlistId,
      'limit': '$limit',
    });
    if (data is! Map<String, dynamic>) {
      throw SolaraApiException('播放列表数据格式错误');
    }
    final tracks = (data['playlist']?['tracks'] as List<dynamic>? ?? [])
        .map((raw) => Song.fromPlaylist(raw as Map<String, dynamic>))
        .whereNotNull()
        .toList();
    if (tracks.isEmpty) {
      throw SolaraApiException('未获取到播放列表数据');
    }
    return tracks.take(limit).toList();
  }

  Future<List<Song>> search(String keyword, {SongSource source = SongSource.netease, int limit = 20, int page = 1}) async {
    if (keyword.trim().isEmpty) {
      return const [];
    }
    final data = await _get({
      'types': 'search',
      'source': source.param,
      'name': keyword,
      'count': '$limit',
      'pages': '$page',
    });
    if (data is! List) {
      throw SolaraApiException('搜索数据格式错误');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(Song.fromSearch)
        .whereNotNull()
        .toList();
  }

  Future<SongAudio> resolveSongUrl(Song song, SongQuality quality) async {
    final data = await _get({
      'types': 'url',
      'id': song.urlId ?? song.id,
      'source': song.source.param,
      'br': quality.br,
    });
    if (data is Map<String, dynamic> && data['url'] is String) {
      return SongAudio(url: data['url'] as String, quality: quality);
    }
    throw SolaraApiException('无法获取歌曲播放地址');
  }

  Future<String?> resolveArtwork(Song song, {int size = 320}) async {
    final picId = song.picId;
    if (picId == null || picId.isEmpty) {
      return null;
    }
    final data = await _get({
      'types': 'pic',
      'id': picId,
      'source': song.source.param,
      'size': '$size',
    });
    if (data is Map<String, dynamic> && data['url'] is String) {
      return data['url'] as String;
    }
    return null;
  }

  Future<List<LyricLine>> fetchLyrics(Song song) async {
    final data = await _get({
      'types': 'lyric',
      'id': song.lyricId ?? song.id,
      'source': song.source.param,
    });
    final lyricRaw = data is Map<String, dynamic> ? data['lyric'] as String? : null;
    if (lyricRaw == null || lyricRaw.isEmpty) {
      return const [];
    }
    return LyricLine.parse(lyricRaw);
  }

  void dispose() {
    _client.close();
  }
}

class SolaraApiException implements Exception {
  SolaraApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum SongSource { netease, kuwo, joox }

extension on SongSource {
  String get label {
    switch (this) {
      case SongSource.netease:
        return '网易云音乐';
      case SongSource.kuwo:
        return '酷我音乐';
      case SongSource.joox:
        return 'JOOX音乐';
    }
  }

  String get param {
    switch (this) {
      case SongSource.netease:
        return 'netease';
      case SongSource.kuwo:
        return 'kuwo';
      case SongSource.joox:
        return 'joox';
    }
  }
}

enum SongQuality { standard, high, extreme, lossless }

extension SongQualityExt on SongQuality {
  String get label {
    switch (this) {
      case SongQuality.standard:
        return '标准音质 (128k)';
      case SongQuality.high:
        return '高品音质 (192k)';
      case SongQuality.extreme:
        return '极高音质 (320k)';
      case SongQuality.lossless:
        return '无损音质 (FLAC)';
    }
  }

  String get br {
    switch (this) {
      case SongQuality.standard:
        return '128';
      case SongQuality.high:
        return '192';
      case SongQuality.extreme:
        return '320';
      case SongQuality.lossless:
        return 'flac';
    }
  }
}

enum PlayMode { list, single, random }

class Song {
  const Song({
    required this.id,
    required this.source,
    required this.name,
    required this.artist,
    this.album,
    this.picId,
    this.urlId,
    this.lyricId,
  });

  static SongSource _parseSource(String? value) {
    if (value == null) {
      return SongSource.netease;
    }
    return SongSource.values.firstWhere(
      (source) => source.param == value,
      orElse: () => SongSource.netease,
    );
  }

  static Song? fromSearch(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id == null || name == null) {
      return null;
    }
    final artistField = json['artist'];
    final artists = artistField is List
        ? artistField.whereType<String>().join(' / ')
        : artistField?.toString() ?? '未知艺术家';
    final picId = json['pic_id'] ??
        json['picId'] ??
        json['pic'] ??
        json['picStr'] ??
        json['picUrl'] ??
        json['cover'] ??
        json['coverImgId'] ??
        json['albummid'] ??
        json['image'];
    final urlId = json['url_id'] ??
        json['urlId'] ??
        json['rid'] ??
        json['sid'] ??
        json['hash'] ??
        json['songId'] ??
        id;
    final lyricId = json['lyric_id'] ?? json['lyricId'] ?? json['lrc'] ?? id;
    return Song(
      id: id.toString(),
      source: _parseSource(json['source'] as String?),
      name: name.toString(),
      artist: artists.isEmpty ? '未知艺术家' : artists,
      album: json['album']?.toString(),
      picId: picId?.toString(),
      urlId: urlId?.toString(),
      lyricId: lyricId?.toString(),
    );
  }

  static Song? fromPlaylist(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id == null || name == null) {
      return null;
    }
    final artists = (json['ar'] as List<dynamic>? ?? [])
        .map((item) => (item as Map<String, dynamic>)['name'])
        .whereType<String>()
        .join(' / ');
    final album = json['al'] as Map<String, dynamic>?;
    final picId = album?['pic_str'] ?? album?['pic'] ?? album?['picUrl'];
    return Song(
      id: id.toString(),
      source: SongSource.netease,
      name: name.toString(),
      artist: artists.isEmpty ? '未知艺术家' : artists,
      album: album?['name']?.toString(),
      picId: picId?.toString(),
      urlId: id.toString(),
      lyricId: id.toString(),
    );
  }

  static Song? fromSerialized(Map<String, dynamic> json) {
    final nameValue = json['name'];
    final String name = nameValue is String ? nameValue.trim() : nameValue?.toString() ?? '';
    if (name.isEmpty) {
      return null;
    }
    final id = _resolveSongId(json);
    if (id == null || id.isEmpty) {
      return null;
    }
    final sourceCandidate = json['source'] ?? json['platform'] ?? json['provider'] ?? json['vendor'];
    final SongSource source = _parseSource(sourceCandidate?.toString());
    final artistValue = json['artist'] ?? json['artists'] ?? json['singers'] ?? json['singer'];
    final artist = _normalizeArtist(artistValue);
    final albumValue = json['album'];
    final album = albumValue is Map<String, dynamic>
        ? albumValue['name']?.toString()
        : albumValue?.toString();
    final picId = json['picId'] ??
        json['pic_id'] ??
        json['pic'] ??
        json['picStr'] ??
        json['picUrl'] ??
        json['cover'] ??
        json['coverImgId'] ??
        json['albummid'] ??
        json['image'];
    final urlId = json['urlId'] ?? json['url_id'] ?? json['rid'] ?? json['sid'] ?? id;
    final lyricId = json['lyricId'] ?? json['lyric_id'] ?? json['lrc'] ?? id;
    return Song(
      id: id,
      source: source,
      name: name,
      artist: artist.isEmpty ? '未知艺术家' : artist,
      album: album?.toString(),
      picId: picId?.toString(),
      urlId: urlId?.toString(),
      lyricId: lyricId?.toString(),
    );
  }

  static String? _resolveSongId(Map<String, dynamic> json) {
    const candidates = [
      'id',
      'songId',
      'songid',
      'songmid',
      'mid',
      'hash',
      'sid',
      'rid',
      'trackId',
    ];
    for (final key in candidates) {
      if (!json.containsKey(key)) continue;
      final value = json[key];
      if (value == null) continue;
      if (value is num) {
        return value.toString();
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static String _normalizeArtist(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    if (value is List) {
      final names = value
          .map((entry) {
            if (entry is String) return entry.trim();
            if (entry is Map && entry['name'] is String) return (entry['name'] as String).trim();
            return '';
          })
          .where((name) => name.isNotEmpty)
          .toList();
      return names.join(' / ');
    }
    if (value is Map && value['name'] is String) {
      return (value['name'] as String).trim();
    }
    return '';
  }

  final String id;
  final SongSource source;
  final String name;
  final String artist;
  final String? album;
  final String? picId;
  final String? urlId;
  final String? lyricId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.param,
        'name': name,
        'artist': artist,
        if (album != null) 'album': album,
        if (picId != null) 'pic_id': picId,
        if (urlId != null) 'url_id': urlId,
        if (lyricId != null) 'lyric_id': lyricId,
      };

  String get identity => '${source.param}:$id';

  @override
  bool operator ==(Object other) =>
      other is Song && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

class SongAudio {
  const SongAudio({required this.url, required this.quality});

  final String url;
  final SongQuality quality;
}

class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;

  static final RegExp _lineRegExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})]');

  static List<LyricLine> parse(String raw) {
    final List<LyricLine> lines = [];
    for (final entry in raw.split('\n')) {
      final matches = _lineRegExp.allMatches(entry);
      if (matches.isEmpty) continue;
      final text = entry.replaceAll(_lineRegExp, '').trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final hundredths = match.group(3);
        final millis = hundredths == null
            ? 0
            : (hundredths.length == 3
                ? int.tryParse(hundredths) ?? 0
                : (int.tryParse(hundredths) ?? 0) * 10);
        final time = Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
        lines.add(LyricLine(time: time, text: text));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}

class SolaraPlayerController extends ChangeNotifier {
  SolaraPlayerController(this._api) {
    _init();
    _initRemoteControls();
  }

  final SolaraApi _api;
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true,
  );
  final List<Song> _queue = [];
  final Map<String, Song> _favorites = {};
  final Map<String, String> _artworkCache = {};
  final Map<String, List<LyricLine>> _lyricsCache = {};
  final Map<String, String> _audioUrlCache = {};
  final Random _random = Random();
  bool _remoteControlsConfigured = false;

  static const List<String> _exploreGenres = [
    '流行',
    '摇滚',
    '古典音乐',
    '民谣',
    '电子',
    '爵士',
    '说唱',
    '乡村',
    '蓝调',
    'R&B',
    '金属',
    '嘻哈',
    '轻音乐',
  ];

  static const List<SongSource> _exploreSources = [
    SongSource.netease,
    SongSource.kuwo,
    SongSource.joox,
  ];

  static const String _explorePrefsFile = 'explore_genres.json';
  static const String _playerStateFile = 'player_state.json';

  final Set<String> _disabledExploreGenres = <String>{};

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int?>? _currentIndexSub;
  Timer? _saveDebounce;

  bool _isLoadingSong = false;
  bool _isExploring = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Song? _currentSong;
  SongQuality _quality = SongQuality.extreme;
  PlayMode _playMode = PlayMode.list;
  String? _currentArtwork;
  List<LyricLine> _currentLyrics = const [];
  String? _errorMessage;

  Future<void> _init() async {
    _positionSub = _player.positionStream.listen((value) {
      _position = value;
      _scheduleStateSave();
      notifyListeners();
    });
    _durationSub = _player.durationStream.listen((value) {
      _duration = value ?? Duration.zero;
      _scheduleStateSave();
      notifyListeners();
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(playNext());
      }
      notifyListeners();
    });
    _currentIndexSub = _player.currentIndexStream.listen((index) async {
      if (index == null || index < 0 || index >= _queue.length) {
        return;
      }
      final song = _queue[index];
      if (_currentSong == song) {
        return;
      }
      await _applyCurrentSongState(song);
    });
    await _player.setAudioSource(_playlist);
    await _loadPersistentState();
    await _loadExplorePreferences();
    await _syncPlaylistWithQueue();
  }

  Future<void> _initRemoteControls() async {
    // Only configure once on iOS.
    if (!Platform.isIOS || _remoteControlsConfigured) return;
    _remoteControlsConfigured = true;

    try {
      await _remoteControlsChannel.invokeMethod('configure');
    } catch (_) {
      // Ignore to avoid impacting other platforms
    }

    _remoteControlsChannel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'skipPrevious':
          await playPrevious();
          await _updateRemoteControlsState();
          break;
        case 'skipNext':
          await playNext();
          await _updateRemoteControlsState();
          break;
        default:
          break;
      }
    });

    await _updateRemoteControlsState();
  }

  Future<void> _updateRemoteControlsState() async {
    if (!Platform.isIOS || !_remoteControlsConfigured) return;

    try {
      await _remoteControlsChannel.invokeMethod('updateState', {
        'hasPrevious': hasPrevious,
        'hasNext': hasNext,
      });
    } catch (_) {
      // Ignore iOS channel errors
    }
  }

  Future<void> _loadExplorePreferences() async {
    try {
      final directory = await _ensureSolaraDirectory();
      File? file = directory != null ? File('${directory.path}/$_explorePrefsFile') : null;
      if (file == null || !await file.exists()) {
        final legacyDir = await getApplicationDocumentsDirectory();
        final legacyFile = File('${legacyDir.path}/$_explorePrefsFile');
        if (!await legacyFile.exists()) {
          return;
        }
        file = legacyFile;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return;
      }
      final dynamic payload = jsonDecode(raw);
      Iterable<dynamic>? enabledRaw;
      if (payload is Map<String, dynamic>) {
        enabledRaw = payload['enabled'] as Iterable<dynamic>?;
      } else if (payload is List) {
        enabledRaw = payload;
      }
      if (enabledRaw == null) {
        return;
      }
      final enabled =
          enabledRaw.whereType<String>().where(_exploreGenres.contains).toSet();
      final newDisabled = _exploreGenres
          .where((genre) => !enabled.contains(genre))
          .toSet();
      final unchanged = newDisabled.length == _disabledExploreGenres.length &&
          _disabledExploreGenres.containsAll(newDisabled);
      if (unchanged) {
        return;
      }
      _disabledExploreGenres
        ..clear()
        ..addAll(newDisabled);
      notifyListeners();
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<void> _saveExplorePreferences() async {
    try {
      final directory = await _ensureSolaraDirectory();
      if (directory == null) {
        return;
      }
      final file = File('${directory.path}/$_explorePrefsFile');
      await file.create(recursive: true);
      final enabled = enabledExploreGenres.toList();
      await file.writeAsString(jsonEncode({'enabled': enabled}));
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<File?> _resolvePlayerStateFile() async {
    final directory = await _ensureSolaraDirectory();
    if (directory == null) {
      return null;
    }
    return File('${directory.path}/$_playerStateFile');
  }

  Future<void> _loadPersistentState() async {
    try {
      final file = await _resolvePlayerStateFile();
      if (file == null || !await file.exists()) {
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return;
      }
      final dynamic payload = jsonDecode(raw);
      if (payload is! Map<String, dynamic>) {
        return;
      }
      final queueRaw = payload['queue'] as List<dynamic>? ?? const [];
      _queue
        ..clear()
        ..addAll(queueRaw
            .whereType<Map<String, dynamic>>()
            .map(Song.fromSerialized)
            .whereNotNull());
      final favoritesRaw = payload['favorites'] as List<dynamic>? ?? const [];
      _favorites
        ..clear()
        ..addEntries(favoritesRaw.whereType<Map<String, dynamic>>().map((raw) {
          final song = Song.fromSerialized(raw);
          if (song == null) return null;
          return MapEntry(song.identity, song);
        }).whereType<MapEntry<String, Song>>());
      final currentId = payload['current'] as String?;
      final currentSerialized =
          payload['currentSong'] as Map<String, dynamic>?;
      _currentSong =
          _queue.firstWhereOrNull((song) => song.identity == currentId) ??
              Song.fromSerialized(currentSerialized ?? const {});
      _currentArtwork = payload['artwork'] as String? ?? _currentArtwork;
      if (_currentSong != null && _currentArtwork != null) {
        _artworkCache[_currentSong!.identity] = _currentArtwork!;
      }
      final quality = payload['quality'] as String?;
      if (quality != null) {
        _quality = SongQuality.values
            .firstWhereOrNull((candidate) => candidate.name == quality) ??
            _quality;
      }
      final playMode = payload['playMode'] as String?;
      if (playMode != null) {
        _playMode =
            PlayMode.values.firstWhereOrNull((mode) => mode.name == playMode) ??
                _playMode;
      }
      final positionMs = payload['positionMs'] as int?;
      if (positionMs != null) {
        _position = Duration(milliseconds: max(0, positionMs));
      }
      final durationMs = payload['durationMs'] as int?;
      if (durationMs != null) {
        _duration = Duration(milliseconds: max(0, durationMs));
      }
      notifyListeners();
      await _updateRemoteControlsState();
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  Future<void> _savePersistentState() async {
    try {
      final file = await _resolvePlayerStateFile();
      if (file == null) {
        return;
      }
      await file.create(recursive: true);
      final payload = {
        'queue': _queue.map((song) => song.toJson()).toList(),
        'favorites': _favorites.values.map((song) => song.toJson()).toList(),
        'current': _currentSong?.identity,
        'currentSong': _currentSong?.toJson(),
        'playMode': _playMode.name,
        'quality': _quality.name,
        'positionMs': _position.inMilliseconds,
        'durationMs': _duration.inMilliseconds,
        'artwork': _currentArtwork,
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  void _scheduleStateSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      _saveDebounce = null;
      unawaited(_savePersistentState());
    });
  }

  Future<AudioSource?> _buildAudioSourceForSong(Song song) async {
    if (song.id.isEmpty) return null;
    try {
      final audioUrl = _audioUrlCache[song.identity] ??
          (await _api.resolveSongUrl(song, _quality)).url;
      _audioUrlCache[song.identity] = audioUrl;
      String? artwork = _artworkCache[song.identity] ??
          _normalizeArtworkUrl(song.picId);
      artwork ??= await _api.resolveArtwork(song);
      if (artwork != null) {
        _artworkCache[song.identity] = artwork;
      }
      final mediaItem = MediaItem(
        id: song.identity,
        title: song.name,
        artist: song.artist,
        album: song.album?.isNotEmpty == true ? song.album : null,
        artUri: artwork != null ? Uri.tryParse(artwork) : null,
        extras: {
          'source': song.source.param,
          'quality': _quality.label,
        },
      );
      return AudioSource.uri(Uri.parse(audioUrl), tag: mediaItem);
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncPlaylistWithQueue() async {
    await _playlist.clear();
    for (final song in _queue) {
      final source = await _buildAudioSourceForSong(song);
      if (source != null) {
        await _playlist.add(source);
      }
    }
  }

  Future<void> _appendSongsToPlaylist(List<Song> songs) async {
    for (final song in songs) {
      final source = await _buildAudioSourceForSong(song);
      if (source != null) {
        await _playlist.add(source);
      }
    }
  }

  Future<void> _ensurePlaylistReady() async {
    if (_playlist.length == _queue.length) {
      return;
    }
    await _syncPlaylistWithQueue();
  }

  Future<void> _playFromQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    await _player.seek(Duration.zero, index: index);
    unawaited(_player.play());
    await _applyCurrentSongState(song);
  }

  Future<void> _applyCurrentSongState(Song song) async {
    _currentSong = song;
    _currentArtwork =
        _artworkCache[song.identity] ?? _normalizeArtworkUrl(song.picId);
    _currentLyrics = const [];
    _errorMessage = null;
    await _updateRemoteControlsState();
    unawaited(_savePersistentState());
    notifyListeners();

    unawaited(_loadArtwork(song).catchError((_) => null).then((artwork) {
      final resolvedArtwork = artwork ?? _normalizeArtworkUrl(song.picId);
      if (resolvedArtwork != null) {
        _artworkCache[song.identity] = resolvedArtwork;
        if (_currentSong == song) {
          _currentArtwork = resolvedArtwork;
          notifyListeners();
        }
      }
    }));

    unawaited(
      _loadLyrics(song).catchError((_) => const <LyricLine>[]).then((lyrics) {
        if (_currentSong == song) {
          _currentLyrics = lyrics;
          notifyListeners();
        }
      }),
    );
  }

  List<Song> get queue => List.unmodifiable(_queue);
  List<Song> get favorites => _favorites.values.toList(growable: false);
  bool get hasQueue => _queue.isNotEmpty;
  bool get hasPrevious {
    if (!hasQueue || _currentSong == null) return false;
    final index = _queue.indexOf(_currentSong!);
    return index > 0;
  }

  bool get hasNext {
    if (!hasQueue || _currentSong == null) return false;
    final index = _queue.indexOf(_currentSong!);
    if (index < 0) return false;
    return index < _queue.length - 1;
  }
  bool get isPlaying => _player.playing;
  bool get isBuffering => _player.playerState.processingState == ProcessingState.buffering;
  bool get isLoadingSong => _isLoadingSong;
  bool get isExploring => _isExploring;
  Song? get currentSong => _currentSong;
  SongQuality get quality => _quality;
  PlayMode get playMode => _playMode;
  Duration get position => _position;
  Duration get duration => _duration;
  String get positionLabel => _formatDuration(_position);
  String get durationLabel => _formatDuration(_duration);
  String? get currentArtwork => _currentArtwork;
  List<LyricLine> get currentLyrics => _currentLyrics;
  String? get errorMessage => _errorMessage;

  List<String> get availableExploreGenres => List.unmodifiable(_exploreGenres);

  Set<String> get enabledExploreGenres => _exploreGenres
      .where((genre) => !_disabledExploreGenres.contains(genre))
      .toSet();

  Future<void> playSong(Song song) async {
    if (song.id.isEmpty) {
      return;
    }
    _isLoadingSong = true;
    _currentSong = song;
    final initialArtwork =
        _artworkCache[song.identity] ?? _normalizeArtworkUrl(song.picId);
    if (initialArtwork != null) {
      _artworkCache[song.identity] = initialArtwork;
    }
    _currentArtwork = initialArtwork;
    notifyListeners();
    try {
      await _syncPlaylistWithQueue();
      final index = _queue.indexOf(song);
      if (index < 0) {
        _errorMessage = '歌曲未在播放列表中';
        return;
      }
      await _playFromQueueIndex(index);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    } finally {
      _isLoadingSong = false;
      notifyListeners();
    }
  }

  Future<bool> playFromCollection(List<Song> songs, int index) async {
    if (songs.isEmpty || index < 0 || index >= songs.length) {
      return false;
    }
    final song = songs[index];
    if (!_queue.contains(song)) {
      await addSongsToQueue(songs);
    }
    await playSong(song);
    return _currentSong == song;
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    await _ensurePlaylistReady();
    if (_currentSong == null) {
      await playSong(_queue.first);
      await _updateRemoteControlsState();
      return;
    }
    switch (_playMode) {
      case PlayMode.single:
        await _player.seek(Duration.zero);
        unawaited(_player.play());
        await _updateRemoteControlsState();
        return;
      case PlayMode.random:
        final options = _queue.where((song) => song != _currentSong).toList();
        final Song nextSong;
        if (options.isEmpty) {
          nextSong = _currentSong!;
        } else {
          nextSong = options[_random.nextInt(options.length)];
        }
        final nextIndex = _queue.indexOf(nextSong);
        await _playFromQueueIndex(nextIndex);
        return;
      case PlayMode.list:
        final currentIndex = _queue.indexOf(_currentSong!);
        final nextIndex = currentIndex >= 0 && currentIndex + 1 < _queue.length
            ? currentIndex + 1
            : 0;
        await _playFromQueueIndex(nextIndex);
        return;
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    await _ensurePlaylistReady();
    if (_currentSong == null) {
      await playSong(_queue.first);
      await _updateRemoteControlsState();
      return;
    }
    switch (_playMode) {
      case PlayMode.single:
        await _player.seek(Duration.zero);
        unawaited(_player.play());
        await _updateRemoteControlsState();
        return;
      case PlayMode.random:
        final options = _queue.where((song) => song != _currentSong).toList();
        final Song previousSong;
        if (options.isEmpty) {
          previousSong = _currentSong!;
        } else {
          previousSong = options[_random.nextInt(options.length)];
        }
        final previousIndex = _queue.indexOf(previousSong);
        await _playFromQueueIndex(previousIndex);
        return;
      case PlayMode.list:
        final currentIndex = _queue.indexOf(_currentSong!);
        final previousIndex = currentIndex <= 0 ? _queue.length - 1 : currentIndex - 1;
        await _playFromQueueIndex(previousIndex);
        return;
    }
  }

  void cyclePlayMode() {
    switch (_playMode) {
      case PlayMode.list:
        _playMode = PlayMode.single;
        break;
      case PlayMode.single:
        _playMode = PlayMode.random;
        break;
      case PlayMode.random:
        _playMode = PlayMode.list;
        break;
    }
    notifyListeners();
    unawaited(_updateRemoteControlsState());
    _scheduleStateSave();
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    unawaited(_player.play());
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<String?> resolveDownloadUrl(Song song) async {
    try {
      final audio = await _api.resolveSongUrl(song, _quality);
      return audio.url;
    } catch (_) {
      return null;
    }
  }

  Future<int> addSongsToQueue(List<Song> songs) async {
    var added = 0;
    final List<Song> addedSongs = [];
    for (final song in songs) {
      if (song.id.isEmpty) continue;
      if (_queue.contains(song)) continue;
      _queue.add(song);
      addedSongs.add(song);
      added++;
    }
    if (added > 0) {
      notifyListeners();
      await _appendSongsToPlaylist(addedSongs);
      await _updateRemoteControlsState();
      _scheduleStateSave();
    }
    return added;
  }

  bool removeFromQueue(Song song) {
    final removed = _queue.remove(song);
    if (!removed) {
      return false;
    }
    final wasCurrent = song == _currentSong;
    if (wasCurrent) {
      if (_queue.isNotEmpty) {
        unawaited(playSong(_queue.first));
      } else {
        _currentSong = null;
        _currentArtwork = null;
        _currentLyrics = const [];
        unawaited(_player.stop());
      }
    } else {
      unawaited(_syncPlaylistWithQueue());
    }
    notifyListeners();
    unawaited(_updateRemoteControlsState());
    _scheduleStateSave();
    return true;
  }

  int clearQueue() {
    if (_queue.isEmpty) {
      return 0;
    }
    final removed = _queue.length;
    _queue.clear();
    _currentSong = null;
    _currentArtwork = null;
    _currentLyrics = const [];
    _audioUrlCache.clear();
    unawaited(_playlist.clear());
    unawaited(_player.stop());
    notifyListeners();
    unawaited(_updateRemoteControlsState());
    _scheduleStateSave();
    return removed;
  }

  void toggleFavorite(Song song) {
    if (_favorites.containsKey(song.identity)) {
      _favorites.remove(song.identity);
    } else {
      _favorites[song.identity] = song;
    }
    notifyListeners();
    _scheduleStateSave();
  }

  int addSongsToFavorites(List<Song> songs) {
    var added = 0;
    for (final song in songs) {
      if (_favorites.containsKey(song.identity)) continue;
      _favorites[song.identity] = song;
      added++;
    }
    if (added > 0) {
      notifyListeners();
      _scheduleStateSave();
    }
    return added;
  }

  int clearFavorites() {
    if (_favorites.isEmpty) {
      return 0;
    }
    final removed = _favorites.length;
    _favorites.clear();
    notifyListeners();
    _scheduleStateSave();
    return removed;
  }

  Future<int> addFavoritesToQueue() async {
    final favorites = this.favorites;
    if (favorites.isEmpty) {
      return 0;
    }
    return addSongsToQueue(favorites);
  }

  bool isFavorite(Song song) => _favorites.containsKey(song.identity);

  Future<void> updateQuality(SongQuality quality) async {
    if (_quality == quality) return;
    _quality = quality;
    _audioUrlCache.clear();
    await _syncPlaylistWithQueue();
    notifyListeners();
    _scheduleStateSave();
    if (_currentSong != null) {
      await playSong(_currentSong!);
    }
  }

  Future<void> updateExploreGenreSelection(Set<String> enabled) async {
    final normalized = enabled.where(_exploreGenres.contains).toSet();
    final newDisabled = _exploreGenres
        .where((genre) => !normalized.contains(genre))
        .toSet();
    final unchanged =
        newDisabled.length == _disabledExploreGenres.length &&
            _disabledExploreGenres.containsAll(newDisabled);
    if (unchanged) {
      return;
    }
    _disabledExploreGenres
      ..clear()
      ..addAll(newDisabled);
    notifyListeners();
    await _saveExplorePreferences();
  }

  Future<int> exploreRadar() async {
    if (_isExploring) {
      return 0;
    }
    final enabledGenres = enabledExploreGenres.toList();
    if (enabledGenres.isEmpty) {
      return 0;
    }
    _isExploring = true;
    notifyListeners();
    try {
      final genre = enabledGenres[_random.nextInt(enabledGenres.length)];
      final source = _exploreSources[_random.nextInt(_exploreSources.length)];
      final results = await _api
          .search(genre, source: source, limit: 30, page: 1)
          .timeout(const Duration(seconds: 12));
      if (results.isEmpty) {
        return 0;
      }
      final newSongs = <Song>[];
      for (final song in results) {
        if (!_queue.contains(song)) {
          newSongs.add(song);
        }
      }
      if (newSongs.isEmpty) {
        return 0;
      }
      final wasEmpty = _queue.isEmpty;
      final added = await addSongsToQueue(newSongs);
      if (wasEmpty && _queue.isNotEmpty) {
        await playSong(_queue.first);
      }
      return added;
    } on TimeoutException {
      _errorMessage = '探索雷达超时，请检查网络或稍后重试';
      notifyListeners();
      return -1;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return -1;
    } finally {
      _isExploring = false;
      notifyListeners();
    }
  }

  String buildCollectionExportPayload(List<Song> songs, {required bool favorites}) {
    final payload = {
      'meta': {
        'app': 'Solara',
        'version': 1,
        'type': favorites ? 'favorites' : 'playlist',
        'exportedAt': DateTime.now().toIso8601String(),
        'itemCount': songs.length,
      },
      'items': songs.map((song) => song.toJson()).toList(),
    };
    return jsonEncode(payload);
  }

  List<Song> parseImportedSongs(String raw) {
    if (raw.trim().isEmpty) {
      return const [];
    }
    final dynamic payload = jsonDecode(raw);
    final Iterable<dynamic> items = _extractCollectionItems(payload);
    return items
        .whereType<Map<String, dynamic>>()
        .map(Song.fromSerialized)
        .whereNotNull()
        .toList();
  }

  Iterable<dynamic> _extractCollectionItems(dynamic payload) {
    if (payload is List) {
      return payload;
    }
    if (payload is Map<String, dynamic>) {
      for (final key in const ['items', 'songs', 'playlist', 'tracks', 'data']) {
        final value = payload[key];
        if (value is List) {
          return value;
        }
      }
    }
    return const [];
  }

  Future<String?> _loadArtwork(Song song) async {
    final key = song.identity;
    if (_artworkCache.containsKey(key)) {
      return _artworkCache[key];
    }
    final url = await _api.resolveArtwork(song);
    if (url != null) {
      _artworkCache[key] = url;
    }
    return url;
  }

  String? _normalizeArtworkUrl(String? candidate) {
    if (candidate == null) {
      return null;
    }
    final value = candidate.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return null;
  }

  Future<List<LyricLine>> _loadLyrics(Song song) async {
    final key = song.identity;
    if (_lyricsCache.containsKey(key)) {
      return _lyricsCache[key]!;
    }
    final lyrics = await _api.fetchLyrics(song);
    _lyricsCache[key] = lyrics;
    return lyrics;
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) {
      return '00:00';
    }
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _currentIndexSub?.cancel();
    _saveDebounce?.cancel();
    _player.dispose();
    _api.dispose();
    super.dispose();
  }
}

class SolaraSearchController extends ChangeNotifier {
  SolaraSearchController(this._api);

  final SolaraApi _api;
  SolaraPlayerController? _player;

  List<Song> _results = const [];
  final Set<String> _selection = <String>{};
  String _query = '';
  SongSource _source = SongSource.netease;
  bool _isLoading = false;

  void attachPlayer(SolaraPlayerController player) {
    _player = player;
  }

  List<Song> get results => _results;
  String get query => _query;
  SongSource get source => _source;
  bool get isLoading => _isLoading;
  int get selectedCount => _selection.length;

  Future<void> search(String keyword) async {
    _query = keyword;
    _isLoading = true;
    _selection.clear();
    notifyListeners();
    try {
      _results = await _api.search(keyword, source: _source, limit: 40);
    } catch (error) {
      _results = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void changeSource(SongSource source) {
    if (_source == source) return;
    _source = source;
    notifyListeners();
    if (_query.isNotEmpty) {
      unawaited(search(_query));
    }
  }

  bool isSelected(Song song) => _selection.contains(song.identity);

  void toggleSelection(Song song) {
    if (_selection.contains(song.identity)) {
      _selection.remove(song.identity);
    } else {
      _selection.add(song.identity);
    }
    notifyListeners();
  }

  void reset() {
    if (_results.isEmpty && _selection.isEmpty && _query.isEmpty && !_isLoading) {
      return;
    }
    _results = const [];
    _selection.clear();
    _query = '';
    _isLoading = false;
    notifyListeners();
  }

  Future<void> importSelection() async {
    if (_player == null || _selection.isEmpty) {
      return;
    }
    final songs = _results.where((song) => _selection.contains(song.identity)).toList();
    await _player!.addSongsToQueue(songs);
    _selection.clear();
    notifyListeners();
  }
}
