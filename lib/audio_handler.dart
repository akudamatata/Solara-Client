import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// 自定义音频处理器：管理 just_audio 播放器并桥接 audio_service。
class SolaraAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  AudioPlayer get player => _player;

  SolaraAudioHandler() {
    // 监听播放事件，向系统广播状态
    _player.playbackEventStream.listen(_broadcastState);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    // 可根据需要扩展队列管理，此例简单处理单曲播放。
    queue.value = [mediaItem];
    await _player.setAudioSource(AudioSource.uri(Uri.parse(mediaItem.id)));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() async {
    // 其他自定义逻辑，如管理队列索引；此例简化处理。
    return;
  }

  @override
  Future<void> skipToPrevious() async {
    return;
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

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
