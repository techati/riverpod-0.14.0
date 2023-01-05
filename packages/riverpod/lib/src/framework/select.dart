import 'package:meta/meta.dart';

import '../framework.dart';

/// {@template riverpod.SelectorSubscription}
/// A [ProviderSubscription] for [RootProvider.select], that notify its listeners
/// only if the result of the selector changes.
/// {@endtemplate}
@sealed
class SelectorSubscription<Input, Output>
    implements ProviderSubscription<Output> {
  /// {@macro riverpod.SelectorSubscription}
  SelectorSubscription({
    required ProviderContainer container,
    required Output Function(Input) selector,
    required RootProvider<Object?, Input> provider,
    void Function(SelectorSubscription<Input, Output> sub)? mayHaveChanged,
    void Function(SelectorSubscription<Input, Output> sub)? didChange,
  })  : _selector = selector,
        _didChange = didChange {
    _sub = container.listen(
      provider,
      // TODO(rrousselGit) add test
      mayHaveChanged:
          mayHaveChanged == null ? null : (_) => mayHaveChanged(this),
    );
  }

  final void Function(SelectorSubscription<Input, Output> sub)? _didChange;
  bool _isFirstBuild = true;
  late ProviderSubscription<Input> _sub;
  Output? _lastOutput;
  Output Function(Input) _selector;

  /// Updates the selector associated with this [SelectorSubscription], and
  /// immediately recompute the value exposed.
  ///
  /// This does not call `mayHaveChanged` and `didChange`.
  void updateSelector(ProviderListenable<Output> providerListenable) {
    _selector =
        (providerListenable as ProviderSelector<Input, Output>).selector;
    _lastOutput = _selector(_sub.read());
  }

  @override
  bool flush() {
    if (_sub.flush()) {
      final newOutput = _selector(_sub.read());
      if (_isFirstBuild || _lastOutput != newOutput) {
        _lastOutput = newOutput;
        if (!_isFirstBuild) {
          _didChange?.call(this);
        }
        _isFirstBuild = false;
        return true;
      }
    }
    return false;
  }

  @override
  Output read() {
    flush();
    return _lastOutput as Output;
  }

  @override
  void close() => _sub.close();
}
