import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'main.dart' show SolaraApi, SolaraPlayerController;

/// 自定义音频处理器：管理 just_audio 播放器并桥接 audio_service。
class SolaraAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  AudioPlayer get player => _player;

  SolaraAudioHandler() {
    // 监听播放事件，向系统广播状态
    _player.playbackEventStream.listen(_broadcastState);
  }

  SolaraPlayerController? _controller;

  void attachController(SolaraPlayerController controller) {
    _controller = controller;
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final currentQueue = queue.valueOrNull ?? const <MediaItem>[];
    queue.add([...currentQueue, mediaItem]);
    this.mediaItem.add(mediaItem);
    await _player.setAudioSource(
      AudioSource.uri(
        Uri.parse(mediaItem.id),
        headers: SolaraApi.headers,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _controller?.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _controller?.playPrevious();
  }

  Future<void> clearQueue() async {
    queue.add(const []);
    mediaItem.add(null);
    await _player.stop();
  }

  void _broadcastState(_) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }
}
