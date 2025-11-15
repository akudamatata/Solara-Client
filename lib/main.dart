import 'dart:async';
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
        child: SafeArea(
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
                            ? _clampSpacing(availableHeight * 0.04, 18, 56)
                            : 0;
                        final double cupertinoDetailSpacing = isCupertino
                            ? _clampSpacing(availableHeight * 0.024, 12, 36)
                            : 0;
                        final topSpacing = _clampSpacing(
                          availableHeight * 0.025 + cupertinoBaseSpacing,
                          16,
                          isCupertino ? 72 : 28,
                        );
                        final sectionSpacing = _clampSpacing(
                          availableHeight * 0.032 + cupertinoBaseSpacing,
                          20,
                          isCupertino ? 76 : 36,
                        );
                        final minorSpacing = _clampSpacing(
                          availableHeight * 0.022 + cupertinoDetailSpacing,
                          14,
                          isCupertino ? 48 : 28,
                        );
                        final controlSpacing = sectionSpacing +
                            (isCupertino ? cupertinoDetailSpacing * 0.5 : 0);
                        final bottomSpacing = _clampSpacing(availableHeight * 0.05, 18, 44);

                        final topSection = <Widget>[
                          _buildToolbar(context),
                          SizedBox(height: topSpacing),
                          const Center(child: _PlayerArtwork()),
                          SizedBox(height: sectionSpacing),
                          const _SongSummary(),
                          SizedBox(height: minorSpacing),
                          const _QualityAndActions(),
                          SizedBox(height: minorSpacing),
                          const _ProgressSection(),
                        ];

                        if (isCompact) {
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.only(bottom: bottomSpacing),
                            child: Column(
                              children: [
                                ...topSection,
                                SizedBox(height: controlSpacing),
                                _buildControls(context),
                              ],
                            ),
                          );
                        }

                        if (isCupertino) {
                          return SizedBox(
                            height: availableHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...topSection,
                                SizedBox(height: controlSpacing),
                                _buildControls(context),
                                SizedBox(height: bottomSpacing),
                              ],
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...topSection,
                            SizedBox(height: controlSpacing),
                            _buildControls(context),
                            SizedBox(height: bottomSpacing),
                          ],
                        );
                      },
                    ),
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
            ],
          ),
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
                onPressed:
                    player.isLoading ? null : () => setState(() => _showSearch = true),
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
            tooltip: '探索雷达',
            isLoading: player.isExploring,
            onTap: player.isLoading ? null : () => player.exploreRadar(),
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
                onTap: player.isLoading
                    ? null
                    : () => setState(() => _showSearch = true),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ControlButton(
          icon: playModeData.icon,
          tooltip: playModeData.label,
          onTap: player.hasQueue ? player.cyclePlayMode : null,
          iconTheme: iconTheme,
        ),
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: player.hasQueue ? player.playPrevious : null,
          iconTheme: iconTheme,
        ),
        _ControlButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 64,
          onTap: player.hasQueue
              ? () => isPlaying ? player.pause() : player.resume()
              : null,
          background: const LinearGradient(
            colors: [Color(0xFFFF6B5F), Color(0xFFFF8C66)],
          ),
          iconTheme: iconTheme,
        ),
        _ControlButton(
          icon: Icons.skip_next_rounded,
          onTap: player.hasQueue ? player.playNext : null,
          iconTheme: iconTheme,
        ),
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
        alignment: const Alignment(0, -0.9),
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

class _PlayerArtwork extends StatefulWidget {
  const _PlayerArtwork();

  @override
  State<_PlayerArtwork> createState() => _PlayerArtworkState();
}

class _PlayerArtworkState extends State<_PlayerArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation(bool isPlaying) {
    if (isPlaying) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop(canceled: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final song = player.currentSong;
    final cover = player.currentArtwork;
    final isPlaying = player.isPlaying && !player.isLoadingSong;
    _syncAnimation(isPlaying);

    final mediaSize = MediaQuery.of(context).size;
    final double maxDiameter = min(mediaSize.width * 0.7, 260);
    final double diameter = max(180.0, maxDiameter);
    final double framePadding = diameter * 0.12;
    final double innerPadding = diameter * 0.06;
    final double artworkSize = max(0.0, diameter - framePadding * 2 - innerPadding * 2);

    final artwork = ClipOval(
      child: SizedBox.square(
        dimension: artworkSize,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1F2A38), Color(0xFF151820)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: cover == null
              ? _ArtworkPlaceholder(size: artworkSize)
              : Image.network(
                  cover,
                  width: artworkSize,
                  height: artworkSize,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      return child;
                    }
                    return const _ArtworkLoading();
                  },
                  errorBuilder: (_, __, ___) => _ArtworkPlaceholder(size: artworkSize),
                ),
        ),
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Color(0x55202932), Color(0xFF0F1118)],
          radius: 0.88,
          center: Alignment(-0.1, -0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      padding: EdgeInsets.all(framePadding),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0C0F15),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1.6,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 26,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(innerPadding),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * pi * 2,
                child: child,
              );
            },
            child: artwork,
          ),
        ),
      ),
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
    final bool canFavorite = song != null;
    final bool isFavorite = canFavorite && player.isFavorite(song!);
    final favoriteButton = IconButton(
      onPressed: canFavorite ? () => player.toggleFavorite(song!) : null,
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: canFavorite
            ? (isFavorite ? theme.colorScheme.primary : theme.iconTheme.color)
            : theme.disabledColor,
      ),
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      tooltip: canFavorite
          ? (isFavorite ? '取消收藏' : '收藏')
          : '暂无可收藏的歌曲',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              favoriteButton,
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          artist,
          style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _QualityAndActions extends StatelessWidget {
  const _QualityAndActions();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final quality = player.quality;
    final theme = Theme.of(context);
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<SongQuality>(
            value: quality,
            dropdownColor: const Color(0xFF15171D),
            borderRadius: BorderRadius.circular(16),
            icon: const Icon(Icons.expand_more, size: 20),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            focusColor: Colors.transparent,
            isDense: true,
            onChanged: player.currentSong == null
                ? null
                : (value) {
                    if (value != null) {
                      player.updateQuality(value);
                    }
                  },
            items: SongQuality.values
                .map(
                  (q) => DropdownMenuItem(
                    value: q,
                    child: Text(q.label, style: theme.textTheme.bodyMedium),
                  ),
                )
                .toList(),
          ),
        ),
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
                  title: '播放列表',
                  children: [
                    _SettingsActionTile(
                      icon: Icons.file_download,
                      label: '导入播放列表',
                      subtitle: '支持 JSON 格式文件',
                      onTap: () => _importCollection(
                        context,
                        player,
                        favorites: false,
                      ),
                    ),
                    _SettingsActionTile(
                      icon: Icons.file_upload,
                      label: '导出播放列表',
                      subtitle: '当前 ${queueCount.toString()} 首歌曲',
                      onTap: () => _exportCollection(
                        context,
                        player,
                        favorites: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SettingsSection(
                  title: '收藏列表',
                  children: [
                    _SettingsActionTile(
                      icon: Icons.favorite_border,
                      label: '导入收藏列表',
                      subtitle: '支持 JSON 格式文件',
                      onTap: () => _importCollection(
                        context,
                        player,
                        favorites: true,
                      ),
                    ),
                    _SettingsActionTile(
                      icon: Icons.favorite,
                      label: '导出收藏列表',
                      subtitle: '当前 ${favoritesCount.toString()} 首歌曲',
                      onTap: () => _exportCollection(
                        context,
                        player,
                        favorites: true,
                      ),
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
  const _ProgressSection();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<SolaraPlayerController>();
    final duration = player.duration;
    final position = player.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFFFF6B5F),
            inactiveTrackColor: Colors.white10,
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              player.positionLabel,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              player.durationLabel,
              style: Theme.of(context).textTheme.labelSmall,
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
                      color: const Color(0xFF101218).withOpacity(0.96),
                      elevation: 30,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(36)),
                      child: SafeArea(
                        top: true,
                        bottom: true,
                        minimum: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                  showFavorites ? '收藏列表' : '播放列表',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  onPressed: songs.isEmpty
                                      ? null
                                      : () =>
                                          player.playFromCollection(songs, 0),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: onClose,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _QueueTabs(
                              showFavorites: showFavorites,
                              onToggle: onToggleTab,
                              playlistCount: player.queue.length,
                              favoritesCount: player.favorites.length,
                            ),
                            const SizedBox(height: 16),
                            _QueueActionsBar(
                              showFavorites: showFavorites,
                              onImport: () => _importCollection(
                                context,
                                player,
                                favorites: showFavorites,
                              ),
                              onExport: () => _exportCollection(
                                context,
                                player,
                                favorites: showFavorites,
                              ),
                              onClear: () => _clearCollection(
                                context,
                                player,
                                favorites: showFavorites,
                              ),
                              onAddAll: showFavorites
                                  ? () => _addFavoritesToQueue(context, player)
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: songs.isEmpty
                                  ? const Center(child: Text('暂无歌曲'))
                                  : ListView.separated(
                                      physics: const BouncingScrollPhysics(),
                                      padding: EdgeInsets.only(
                                        top: 4,
                                        bottom: safePadding.bottom + 16,
                                      ),
                                      itemCount: songs.length,
                                      separatorBuilder: (_, __) => const Divider(
                                        height: 16,
                                        thickness: 0.2,
                                      ),
                                      itemBuilder: (context, index) {
                                        final song = songs[index];
                                        final isActive =
                                            player.currentSong == song;
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
                                          onTap: () => player.playFromCollection(
                                            songs,
                                            index,
                                          ),
                                          actions: actions,
                                        );
                                      },
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

  void _addFavoritesToQueue(BuildContext context, SolaraPlayerController player) {
    final added = player.addFavoritesToQueue();
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
        onTap: () {
          final added = player.addSongsToQueue([song]);
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

class _QueueActionsBar extends StatelessWidget {
  const _QueueActionsBar({
    required this.showFavorites,
    required this.onImport,
    required this.onExport,
    required this.onClear,
    this.onAddAll,
  });

  final bool showFavorites;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onClear;
  final VoidCallback? onAddAll;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    final isCupertino = Theme.of(context).platform == TargetPlatform.iOS;
    if (showFavorites && onAddAll != null) {
      buttons.add(
        _QueueActionButton(
          icon: Icons.playlist_add_check,
          label: '全部添加到播放列表',
          onTap: onAddAll,
        ),
      );
    }
    if (!isCupertino) {
      buttons.addAll([
        _QueueActionButton(icon: Icons.file_download, label: '导入', onTap: onImport),
        _QueueActionButton(icon: Icons.file_upload, label: '导出', onTap: onExport),
      ]);
    }
    buttons.add(
      _QueueActionButton(icon: Icons.delete_sweep, label: '清空', onTap: onClear),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: buttons,
    );
  }
}

class _QueueActionButton extends StatelessWidget {
  const _QueueActionButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
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
        borderRadius: BorderRadius.circular(32),
        color: Colors.white.withOpacity(0.04),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          _QueueTabButton(
            label: '播放列表 ($playlistCount)',
            active: !showFavorites,
            onTap: () => onToggle(false),
          ),
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
            borderRadius: BorderRadius.circular(24),
            color: active ? const Color(0xFFFF6B5F) : Colors.transparent,
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text('${index + 1}'.padLeft(2, '0'), style: Theme.of(context).textTheme.bodySmall),
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
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
                ],
              ),
            ),
            for (final action in actions)
              _QueueTileActionButton(action: action),
          ],
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
      icon: Icon(action.icon, size: 20, color: action.color),
      onPressed: action.onTap,
    );
    if (action.tooltip == null || action.tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: action.tooltip!, child: button);
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
        : player.addSongsToQueue(songs);
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
      final savePath = await FilePicker.platform.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (savePath == null) {
        return;
      }
      final file = File(savePath);
      await file.create(recursive: true);
      await file.writeAsString(json);
      _showSnackBar(
        context,
        '已保存 ${songs.length} 首歌曲',
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
  final theme = Theme.of(context);
  Color? background;
  if (error) {
    background = Colors.redAccent;
  } else if (success) {
    background = theme.colorScheme.primary;
  }
  final textStyle = error || success
      ? const TextStyle(color: Colors.white)
      : null;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: textStyle),
      backgroundColor: background,
      duration: const Duration(seconds: 2),
    ),
  );
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

  @override
  void initState() {
    super.initState();
    final search = context.read<SolaraSearchController>();
    _controller = TextEditingController(text: search.query);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SolaraSearchController>();
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: widget.visible ? 0 : -MediaQuery.of(context).size.height,
      height: MediaQuery.of(context).size.height,
      child: Material(
        color: const Color(0xFF0E0F13).withOpacity(0.98),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) => search.search(value),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.07),
                          prefixIcon: const Icon(Icons.search),
                          hintText: '搜索歌曲或歌手',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SearchSourceSelector(
                  selected: search.source,
                  onSelected: search.changeSource,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: search.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : search.results.isEmpty
                          ? const Center(child: Text('暂无搜索结果'))
                          : ListView.separated(
                              itemCount: search.results.length,
                              separatorBuilder: (_, __) => const Divider(height: 18, thickness: 0.2),
                              itemBuilder: (context, index) {
                                final song = search.results[index];
                                final isSelected = search.isSelected(song);
                                return _SearchResultTile(
                                  song: song,
                                  isSelected: isSelected,
                                  onSelect: () => search.toggleSelection(song),
                                );
                              },
                            ),
                ),
                const SizedBox(height: 12),
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
    );
  }
}

class _SearchSourceSelector extends StatelessWidget {
  const _SearchSourceSelector({required this.selected, required this.onSelected});

  final SongSource selected;
  final ValueChanged<SongSource> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final source = SongSource.values[index];
          final active = selected == source;
          return ChoiceChip(
            selected: active,
            onSelected: (_) => onSelected(source),
            label: Text(source.label),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: SongSource.values.length,
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.song,
    required this.isSelected,
    required this.onSelect,
  });

  final Song song;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFFFF6B5F) : Colors.white54,
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
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => context.read<SolaraPlayerController>().playFromCollection([song], 0),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text('导入已选 ($selectedCount)'),
          const Spacer(),
          ElevatedButton(
            onPressed: onImport,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B5F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('添加到播放列表'),
          ),
        ],
      ),
    );
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
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode >= 400) {
      throw SolaraApiException('请求失败: ${response.statusCode}');
    }
    final body = response.body;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
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

enum SongSource { netease, tencent, kugou, migu }

extension on SongSource {
  String get label {
    switch (this) {
      case SongSource.netease:
        return '网易云音乐';
      case SongSource.tencent:
        return 'QQ音乐';
      case SongSource.kugou:
        return '酷狗音乐';
      case SongSource.migu:
        return '咪咕音乐';
    }
  }

  String get param {
    switch (this) {
      case SongSource.netease:
        return 'netease';
      case SongSource.tencent:
        return 'tencent';
      case SongSource.kugou:
        return 'kugou';
      case SongSource.migu:
        return 'migu';
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
    return Song(
      id: id.toString(),
      source: _parseSource(json['source'] as String?),
      name: name.toString(),
      artist: artists.isEmpty ? '未知艺术家' : artists,
      album: json['album']?.toString(),
      picId: json['pic_id']?.toString(),
      urlId: json['url_id']?.toString(),
      lyricId: json['lyric_id']?.toString(),
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
  }

  static const MethodChannel _remoteChannel = MethodChannel('solara/remote_controls');

  final SolaraApi _api;
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _queue = [];
  final Map<String, Song> _favorites = {};
  final Map<String, String> _artworkCache = {};
  final Map<String, List<LyricLine>> _lyricsCache = {};
  final Random _random = Random();

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
    SongSource.tencent,
    SongSource.kugou,
    SongSource.migu,
  ];

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _remoteConfigured = false;

  bool _isLoading = false;
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
    _remoteChannel.setMethodCallHandler(_handleRemoteCommand);
    await _configureRemote();
    _positionSub = _player.positionStream.listen((value) {
      _position = value;
      notifyListeners();
    });
    _durationSub = _player.durationStream.listen((value) {
      _duration = value ?? Duration.zero;
      notifyListeners();
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(playNext());
      }
      notifyListeners();
    });
    unawaited(_loadInitialQueue());
  }

  Future<void> _loadInitialQueue() async {
    _isLoading = true;
    notifyListeners();
    try {
      final songs = await _api.fetchPlaylist(limit: 30);
      _queue
        ..clear()
        ..addAll(songs);
      if (_queue.isNotEmpty) {
        await playSong(_queue.first);
      }
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
      unawaited(_updateRemoteCommands());
    }
  }

  Future<void> _configureRemote() async {
    try {
      await _remoteChannel.invokeMethod('configure');
      _remoteConfigured = true;
    } catch (_) {
      _remoteConfigured = false;
    }
  }

  Future<void> _handleRemoteCommand(MethodCall call) async {
    switch (call.method) {
      case 'skipNext':
        if (hasQueue) {
          unawaited(playNext());
        }
        break;
      case 'skipPrevious':
        if (hasQueue) {
          unawaited(playPrevious());
        }
        break;
    }
  }

  Future<void> _updateRemoteCommands() async {
    if (!_remoteConfigured) {
      await _configureRemote();
      if (!_remoteConfigured) {
        return;
      }
    }
    final bool hasPrevious = _hasPreviousForRemote;
    final bool hasNext = _hasNextForRemote;
    try {
      await _remoteChannel.invokeMethod('updateState', {
        'hasPrevious': hasPrevious,
        'hasNext': hasNext,
      });
    } catch (_) {
      _remoteConfigured = false;
    }
  }

  bool get _hasPreviousForRemote => _queue.isNotEmpty;

  bool get _hasNextForRemote => _queue.isNotEmpty;

  List<Song> get queue => List.unmodifiable(_queue);
  List<Song> get favorites => _favorites.values.toList(growable: false);
  bool get hasQueue => _queue.isNotEmpty;
  bool get isPlaying => _player.playing;
  bool get isLoading => _isLoading;
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

  Future<void> playSong(Song song) async {
    if (song.id.isEmpty) {
      return;
    }
    _isLoadingSong = true;
    notifyListeners();
    try {
      final audioFuture = _api.resolveSongUrl(song, _quality);
      final artworkFuture = _loadArtwork(song);
      final lyricsFuture = _loadLyrics(song);
      final audio = await audioFuture;
      final artwork = await artworkFuture;
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
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(audio.url),
          tag: mediaItem,
        ),
      );
      await _player.play();
      _currentSong = song;
      _currentArtwork = artwork;
      _currentLyrics = await lyricsFuture;
      unawaited(_updateRemoteCommands());
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    } finally {
      _isLoadingSong = false;
      notifyListeners();
    }
  }

  Future<void> playFromCollection(List<Song> songs, int index) async {
    if (songs.isEmpty || index < 0 || index >= songs.length) {
      return;
    }
    final song = songs[index];
    if (!_queue.contains(song)) {
      addSongsToQueue(songs);
    }
    await playSong(song);
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    if (_currentSong == null) {
      await playSong(_queue.first);
      return;
    }
    switch (_playMode) {
      case PlayMode.single:
        await _player.seek(Duration.zero);
        await _player.play();
        unawaited(_updateRemoteCommands());
        return;
      case PlayMode.random:
        final options = _queue.where((song) => song != _currentSong).toList();
        final Song nextSong;
        if (options.isEmpty) {
          nextSong = _currentSong!;
        } else {
          nextSong = options[_random.nextInt(options.length)];
        }
        await playSong(nextSong);
        return;
      case PlayMode.list:
        final currentIndex = _queue.indexOf(_currentSong!);
        final nextIndex = currentIndex >= 0 && currentIndex + 1 < _queue.length
            ? currentIndex + 1
            : 0;
        await playSong(_queue[nextIndex]);
        return;
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    if (_currentSong == null) {
      await playSong(_queue.first);
      return;
    }
    switch (_playMode) {
      case PlayMode.single:
        await _player.seek(Duration.zero);
        await _player.play();
        unawaited(_updateRemoteCommands());
        return;
      case PlayMode.random:
        final options = _queue.where((song) => song != _currentSong).toList();
        final Song previousSong;
        if (options.isEmpty) {
          previousSong = _currentSong!;
        } else {
          previousSong = options[_random.nextInt(options.length)];
        }
        await playSong(previousSong);
        return;
      case PlayMode.list:
        final currentIndex = _queue.indexOf(_currentSong!);
        final previousIndex = currentIndex <= 0 ? _queue.length - 1 : currentIndex - 1;
        await playSong(_queue[previousIndex]);
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
    unawaited(_updateRemoteCommands());
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    await _player.play();
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

  int addSongsToQueue(List<Song> songs) {
    var added = 0;
    for (final song in songs) {
      if (song.id.isEmpty) continue;
      if (_queue.contains(song)) continue;
      _queue.add(song);
      added++;
    }
    if (added > 0) {
      notifyListeners();
      unawaited(_updateRemoteCommands());
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
    }
    notifyListeners();
    unawaited(_updateRemoteCommands());
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
    unawaited(_player.stop());
    notifyListeners();
    unawaited(_updateRemoteCommands());
    return removed;
  }

  void toggleFavorite(Song song) {
    if (_favorites.containsKey(song.identity)) {
      _favorites.remove(song.identity);
    } else {
      _favorites[song.identity] = song;
    }
    notifyListeners();
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
    return removed;
  }

  int addFavoritesToQueue() {
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
    notifyListeners();
    if (_currentSong != null) {
      await playSong(_currentSong!);
    }
  }

  Future<void> exploreRadar() async {
    if (_isExploring) {
      return;
    }
    _isExploring = true;
    notifyListeners();
    try {
      final genre = _exploreGenres[_random.nextInt(_exploreGenres.length)];
      final source = _exploreSources[_random.nextInt(_exploreSources.length)];
      final results = await _api.search(genre, source: source, limit: 30, page: 1);
      if (results.isEmpty) {
        return;
      }
      final newSongs = <Song>[];
      for (final song in results) {
        if (!_queue.contains(song)) {
          newSongs.add(song);
        }
      }
      if (newSongs.isEmpty) {
        return;
      }
      final wasEmpty = _queue.isEmpty;
      addSongsToQueue(newSongs);
      if (wasEmpty && _queue.isNotEmpty) {
        await playSong(_queue.first);
      }
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
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

  Future<void> importSelection() async {
    if (_player == null || _selection.isEmpty) {
      return;
    }
    final songs = _results.where((song) => _selection.contains(song.identity)).toList();
    _player!.addSongsToQueue(songs);
    _selection.clear();
    notifyListeners();
  }
}
