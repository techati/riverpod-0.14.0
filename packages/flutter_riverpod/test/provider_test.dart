import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('.read(context)', (tester) async {
    final futureProvider = FutureProvider((_) async => 42);
    final streamProvider = StreamProvider((_) async* {
      yield 42;
    });
    final provider = Provider((_) => 42);
    final changeNotifierProvider = ChangeNotifierProvider((_) {
      return ValueNotifier(0);
    });

    Builder(builder: (context) {
      // ignore: omit_local_variable_types, unused_local_variable, prefer_final_locals
      int providerValue = context.read(provider);
      // ignore: omit_local_variable_types, unused_local_variable, prefer_final_locals
      AsyncValue<int> futureProviderValue = context.read(futureProvider);
      // ignore: omit_local_variable_types, unused_local_variable, prefer_final_locals
      AsyncValue<int> streamProviderValue = context.read(streamProvider);
      // ignore: omit_local_variable_types, unused_local_variable, prefer_final_locals
      ValueNotifier<int> changeNotifierProviderValue =
          context.read(changeNotifierProvider);

      return Container();
    });
  });

  testWidgets('mounted', (tester) async {
    late ProviderReference providerState;
    bool? mountedOnDispose;
    final provider = Provider<int>((ref) {
      providerState = ref;
      ref.onDispose(() => mountedOnDispose = ref.mounted);
      return 42;
    });

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(provider).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('42'), findsOneWidget);
    expect(providerState.mounted, isTrue);

    await tester.pumpWidget(Container());

    expect(mountedOnDispose, isFalse);
    expect(providerState.mounted, isFalse);
  });

  testWidgets('no onDispose does not crash', (tester) async {
    final provider = Provider<int>((ref) => 42);

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(provider).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('42'), findsOneWidget);

    await tester.pumpWidget(Container());
  });

  testWidgets('onDispose calls all callbacks in order', (tester) async {
    final dispose1 = OnDisposeMock();

    final dispose2 = OnDisposeMock();
    final error2 = Error();
    when(dispose2()).thenThrow(error2);

    final dispose3 = OnDisposeMock();

    final provider = Provider<int>((ref) {
      ref..onDispose(dispose1)..onDispose(dispose2)..onDispose(dispose3);
      return 42;
    });

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(provider).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('42'), findsOneWidget);
    verifyZeroInteractions(dispose1);
    verifyZeroInteractions(dispose2);
    verifyZeroInteractions(dispose3);

    final errors = <Object>[];
    await runZonedGuarded(
      () => tester.pumpWidget(Container()),
      (err, _) => errors.add(err),
    );

    verifyInOrder([
      dispose1(),
      dispose2(),
      dispose3(),
    ]);
    verifyNoMoreInteractions(dispose1);
    verifyNoMoreInteractions(dispose2);
    verifyNoMoreInteractions(dispose3);

    expect(errors, [error2]);
  });

  testWidgets('expose value as is', (tester) async {
    var callCount = 0;
    final provider = Provider((ref) {
      callCount++;
      return 42;
    });

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(provider).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(callCount, 1);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('override updates rebuild dependents with new value',
      (tester) async {
    final provider = Provider((_) => 0);
    final child = Consumer(builder: (c, watch, _) {
      return Text(
        watch(provider).toString(),
        textDirection: TextDirection.ltr,
      );
    });

    var callCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(
            Provider((ref) {
              callCount++;
              return 42;
            }),
          ),
        ],
        child: child,
      ),
    );

    expect(callCount, 1);
    expect(find.text('42'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(
            Provider((ref) {
              callCount++;
              throw Error();
            }),
          ),
        ],
        child: child,
      ),
    );

    expect(callCount, 1);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('provider1 as override of normal provider', (tester) async {
    final provider = Provider((_) => 42);
    final provider2 = Provider((_) => 42);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider2.overrideWithProvider(
            Provider<int>((ref) {
              return ref.watch(provider) * 2;
            }),
          ),
        ],
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(provider2).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('84'), findsOneWidget);
  });

  testWidgets('provider1 uses override if the override is at root',
      (tester) async {
    final provider = Provider((_) => 0);

    final provider1 = Provider((ref) {
      return ref.watch(provider).toString();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          provider.overrideWithProvider(Provider((_) => 1)),
        ],
        child: Consumer(builder: (c, watch, _) {
          return Text(watch(provider1), textDirection: TextDirection.ltr);
        }),
      ),
    );

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('provider1 chain', (tester) async {
    final first = Provider((_) => 1);
    final second = Provider<int>((ref) {
      return ref.watch(first) + 1;
    });
    final third = Provider<int>((ref) {
      return ref.watch(second) + 1;
    });
    final forth = Provider<int>((ref) {
      return ref.watch(third) + 1;
    });

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(forth).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('overriden provider1 chain', (tester) async {
    final first = Provider((_) => 1);
    final second = Provider<int>((ref) {
      return ref.watch(first) + 1;
    });
    final third = Provider<int>((ref) {
      return ref.watch(second) + 1;
    });
    final forth = Provider<int>((ref) {
      return ref.watch(third) + 1;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          first.overrideWithProvider(Provider((_) => 42)),
        ],
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(forth).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('45'), findsOneWidget);
  });

  testWidgets('partial override provider1 chain', (tester) async {
    final first = Provider((_) => 1);
    final second = Provider<int>((ref) {
      return ref.watch(first) + 1;
    });
    final third = Provider<int>((ref) {
      return ref.watch(second) + 1;
    });
    final forth = Provider<int>((ref) {
      return ref.watch(third) + 1;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          second.overrideWithProvider(Provider((_) => 0)),
        ],
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(forth).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('ProviderBuilder1', (tester) async {
    final provider = Provider((_) => 42);

    // These check the type safety
    ProviderReference? ref;

    // ignore: omit_local_variable_types
    final Provider<int> provider1 = Provider<int>((r) {
      final first = r.watch(provider);
      ref = r;
      return first * 2;
    });

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (c, watch, _) {
          return Text(
            watch(provider1).toString(),
            textDirection: TextDirection.ltr,
          );
        }),
      ),
    );

    expect(ref, isNotNull);
    expect(find.text('84'), findsOneWidget);
  });
}

class OnDisposeMock extends Mock {
  void call();
}
