import 'package:flutter_test/flutter_test.dart';
import 'package:simple_lyrics/services/playback_clock.dart';

void main() {
  late int nowUs;
  late PlaybackClock clock;

  setUp(() {
    nowUs = 0;
    clock = PlaybackClock(nowUs: () => nowUs, nativeLag: Duration.zero);
  });

  Duration pos(int ms) => Duration(milliseconds: ms);

  void sync({
    required int ms,
    required bool playing,
    double rate = 1.0,
    bool songChanged = false,
  }) {
    clock.sync(
      position: pos(ms),
      isPlaying: playing,
      duration: pos(180000),
      playbackRate: rate,
      songChanged: songChanged,
    );
  }

  test('playing advances with the stopwatch between native samples', () {
    sync(ms: 1000, playing: true);
    nowUs += 200 * 1000;
    expect(clock.position, pos(1200));
  });

  test('pause freezes on the derived position, not a stale native sample', () {
    sync(ms: 1000, playing: true);
    nowUs += 400 * 1000;
    expect(clock.position, pos(1400));

    // Native is still reporting the pre-pause snapshot.
    sync(ms: 1000, playing: false);
    expect(clock.position, pos(1400));

    nowUs += 500 * 1000;
    expect(clock.position, pos(1400));
  });

  test('resume continues from the freeze point', () {
    sync(ms: 1000, playing: true);
    nowUs += 300 * 1000;
    sync(ms: 1000, playing: false);
    expect(clock.position, pos(1300));

    nowUs += 2000 * 1000;
    sync(ms: 1300, playing: true);
    nowUs += 200 * 1000;
    expect(clock.position, pos(1500));
  });

  test('in-app seek jumps immediately and ignores stale reports', () {
    sync(ms: 1000, playing: true);
    nowUs += 100 * 1000;
    clock.beginSeek(pos(8000));
    expect(clock.position, pos(8000));

    nowUs += 200 * 1000;
    sync(ms: 1100, playing: true);
    expect(clock.position.inMilliseconds, closeTo(8200, 5));

    nowUs += 50 * 1000;
    sync(ms: 8050, playing: true);
    expect(clock.position.inMilliseconds, closeTo(8050, 5));
  });

  test('external seek larger than noise is adopted', () {
    sync(ms: 1000, playing: true);
    nowUs += 100 * 1000;
    sync(ms: 5000, playing: true);
    expect(clock.position, pos(5000));
  });

  test('small native jitter is not painted', () {
    sync(ms: 1000, playing: true);
    nowUs += 250 * 1000;
    sync(ms: 1240, playing: true);
    expect(clock.position, pos(1250));
  });

  test('playback rate scales the derived clock', () {
    sync(ms: 0, playing: true, rate: 2.0);
    nowUs += 500 * 1000;
    expect(clock.position, pos(1000));
  });

  test('song change adopts the new sample instead of resetting to zero', () {
    sync(ms: 40000, playing: true);
    nowUs += 100 * 1000;
    sync(ms: 15000, playing: true, songChanged: true);
    expect(clock.position, pos(15000));
  });

  test('seek rejected by the source is eventually adopted', () {
    sync(ms: 1000, playing: true);
    clock.beginSeek(pos(8000));
    nowUs += 1000 * 1000;
    sync(ms: 1200, playing: true);
    sync(ms: 1250, playing: true);
    expect(clock.position.inMilliseconds, closeTo(1250, 5));
  });

  test('resume ignores a stale native sample that is still at the pause point',
      () {
    sync(ms: 1000, playing: true);
    nowUs += 400 * 1000;
    sync(ms: 1000, playing: false);
    expect(clock.position, pos(1400));

    nowUs += 300 * 1000;
    // Native is still advertising the pre-pause snapshot.
    sync(ms: 1050, playing: true);
    expect(clock.position, pos(1400));
    nowUs += 200 * 1000;
    expect(clock.position, pos(1600));
  });

  test('local pause freezes immediately even if native still says playing', () {
    sync(ms: 1000, playing: true);
    nowUs += 200 * 1000;
    clock.setAdvancing(false);
    expect(clock.position, pos(1200));

    nowUs += 300 * 1000;
    sync(ms: 1500, playing: true);
    expect(clock.position, pos(1200));
    nowUs += 200 * 1000;
    expect(clock.position, pos(1200));
  });

  test('local play resumes immediately even if native still says paused', () {
    sync(ms: 1000, playing: true);
    nowUs += 200 * 1000;
    clock.setAdvancing(false);
    nowUs += 500 * 1000;
    clock.setAdvancing(true);
    nowUs += 200 * 1000;
    expect(clock.position, pos(1400));

    sync(ms: 1000, playing: false);
    nowUs += 100 * 1000;
    expect(clock.position, pos(1500));
  });

  test('preview starts from the derived position, not the last native snap',
      () {
    sync(ms: 1000, playing: true);
    nowUs += 400 * 1000;
    clock.beginPreview();
    expect(clock.position, pos(1400));
  });

  test('small drift is eased in rather than snapped', () {
    sync(ms: 1000, playing: true);
    nowUs += 250 * 1000;
    // Derived is 1250; native is 1450 (200ms ahead, inside the soft window).
    sync(ms: 1450, playing: true);
    expect(clock.position.inMilliseconds, closeTo(1290, 5));
  });
}
