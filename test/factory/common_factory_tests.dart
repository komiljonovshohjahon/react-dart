@JS()
library react.test.common_factory_tests;

// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:html';
import 'dart:js';
import 'dart:js_util';

import 'package:js/js.dart';
import 'package:react/react_client/js_backed_map.dart';
import 'package:react/react_client/js_interop_helpers.dart';
import 'package:test/test.dart';

import 'package:react/react.dart' as react;
import 'package:react/react_client.dart';
import 'package:react/react_dom.dart' as react_dom;
import 'package:react/react_test_utils.dart' as rtu;
import 'package:react/react_client/react_interop.dart';

import '../shared_type_tester.dart';
import '../util.dart';

/// Runs common tests for [factory].
///
/// [dartComponentVersion] should be specified for all components with Dart render code in order to
/// properly test `props.children`, forwardRef compatibility, etc.
void commonFactoryTests(ReactComponentFactoryProxy factory,
    {String? dartComponentVersion,
    bool skipPropValuesTest = false,
    bool isNonDartComponentWithDartWrapper = false,
    ReactElement Function(dynamic children)? renderWrapper}) {
  _childKeyWarningTests(
    factory,
    renderWithUniqueOwnerName: (ReactElement Function() render) => _renderWithUniqueOwnerName(render, renderWrapper),
  );

  test('renders an instance with the corresponding `type`', () {
    final instance = factory({});

    expect(instance.type, equals(factory.type));
  });

  test('has a type with the expected ReactDartComponentVersion', () {
    // ignore: invalid_use_of_protected_member
    expect(ReactDartComponentVersion.fromType(factory.type), dartComponentVersion);
  });

  void sharedChildrenTests(dynamic Function(ReactElement instance) getChildren,
      {required bool shouldAlwaysBeList, Map props = const {}}) {
    // There are different code paths for 0, 1, 2, 3, 4, 5, 6, and 6+ arguments.
    // Test all of them.
    group('a number of variadic children:', () {
      test('0', () {
        final instance = factory(props);
        expect(getChildren(instance), shouldAlwaysBeList ? [] : isNull);
      });

      test('1', () {
        final instance = factory(props, 1);
        expect(getChildren(instance), shouldAlwaysBeList ? [1] : 1);
      });

      const firstGeneralCaseVariadicChildCount = 2;
      const maxSupportedVariadicChildCount = 40;
      for (var i = firstGeneralCaseVariadicChildCount; i < maxSupportedVariadicChildCount; i++) {
        final childrenCount = i;

        test('$childrenCount', () {
          final expectedChildren = List.generate(childrenCount, (i) => i + 1);
          final arguments = <dynamic>[props, ...expectedChildren];
          final instance = Function.apply(factory, arguments) as ReactElement;
          expect(getChildren(instance), expectedChildren);
        }, tags: i > 5 ? 'dart-2-7-dart2js-variadic-issues' : null);
      }

      test('$maxSupportedVariadicChildCount (and passes static analysis)', () {
        final instance = factory(props, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
            23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40);
        // Generate these instead of hard coding them to ensure the arguments passed into this test match maxSupportedVariadicChildCount
        final expectedChildren = List.generate(maxSupportedVariadicChildCount, (i) => i + 1);
        expect(getChildren(instance), equals(expectedChildren));
      }, tags: 'dart-2-7-dart2js-variadic-issues');
    });

    test('a List', () {
      final instance = factory(props, [
        'one',
        'two',
      ]);
      expect(getChildren(instance), equals(['one', 'two']));
    });

    test('an empty List', () {
      final instance = factory(props, []);
      expect(getChildren(instance), equals([]));
    });

    test('an Iterable', () {
      final instance = factory(props, Iterable.generate(3, (i) => '$i'));
      expect(getChildren(instance), equals(['0', '1', '2']));
    });

    test('an empty Iterable', () {
      final instance = factory(props, Iterable.empty());
      expect(getChildren(instance), equals([]));
    });
  }

  group('passes children to the JS component when specified as', () {
    dynamic getJsChildren(ReactElement instance) => getProperty(instance.props, 'children');

    sharedChildrenTests(getJsChildren,
        // Only Component2 should always get lists.
        // Component, DOM components, etc. should not for compatibility purposes.
        shouldAlwaysBeList: isDartComponent2(factory({})));
  });

  if (isDartComponent(factory({})) && !isNonDartComponentWithDartWrapper) {
    group('passes children to the Dart component when specified as', () {
      final notCalledSentinelValue = Object();
      dynamic childrenFromLastRender;
      void onDartRender(Map props) => childrenFromLastRender = props['children'];

      dynamic getDartChildren(ReactElement instance) {
        // Set to a value that won't ever be equal to children, so we can tell whether it was called.
        childrenFromLastRender = notCalledSentinelValue;
        rtu.renderIntoDocument(instance);
        final children = childrenFromLastRender;
        if (childrenFromLastRender == notCalledSentinelValue) {
          throw StateError('onDartRender was not called when rendering `instance`. '
              'Ensure the `props` argument are being passed to the factory.');
        }
        return children;
      }

      sharedChildrenTests(
        getDartChildren,
        shouldAlwaysBeList: true,
        props: Map.unmodifiable({
          'onDartRender': onDartRender,
        }),
      );
    });

    if (!isDartComponent1(factory({}))) {
      test('passes through props as a JsBackedMap:', () {
        dynamic receivedProps;
        rtu.renderIntoDocument(factory({
          'onDartRender': (Map props) {
            receivedProps = props;
          }
        }));

        expect(receivedProps, isA<JsBackedMap>(), reason: 'props should be a JsBackedMap');
      });
    }

    if (!skipPropValuesTest) {
      group('does not convert/wrap values for interop:', () {
        sharedTypeTests((dynamic testValue) {
          dynamic receivedValue;

          rtu.renderIntoDocument(factory({
            'testValue': testValue,
            'onDartRender': (Map props) {
              receivedValue = props['testValue'];
            }
          }));

          expect(receivedValue, same(testValue));
        });
      });
    }
  }

  if (isDartComponent2(factory({})) && !isNonDartComponentWithDartWrapper) {
    test('executes Dart render code in the component zone', () {
      final oldComponentZone = componentZone;
      addTearDown(() => componentZone = oldComponentZone);
      componentZone = Zone.current.fork();
      expect(componentZone, isNot(Zone.current),
          reason: 'test setup: component zone should be different than the zone used to render it');

      Zone? renderZone;
      rtu.renderIntoDocument(factory({
        'onDartRender': (_) {
          renderZone = Zone.current;
        }
      }));
      expect(renderZone, isNotNull, reason: 'test setup: onDartRender should have been called');
      expect(renderZone, same(componentZone));
    });
  }
}

void domEventHandlerWrappingTests(
  ReactComponentFactoryProxy factory, {
  bool isNonDartComponentWithDartWrapper = false,
}) {
  Element renderAndGetRootNode(ReactElement content) {
    final mountNode = Element.div();
    react_dom.render(content, mountNode);
    return mountNode.children.single;
  }

  setUpAll(() {
    var called = false;

    final nodeWithClickHandler = renderAndGetRootNode(factory({
      'onClick': (_) {
        called = true;
      }
    }));

    rtu.Simulate.click(nodeWithClickHandler);

    expect(called, isTrue,
        reason: 'this set of tests assumes that the factory '
            'renders a single DOM node and passes props.onClick to it');
  });

  group('wraps event handlers properly,', () {
    const dart = EventTestCase.dart('onMouseUp', 'set on component');
    const dartCloned = EventTestCase.dart('onMouseLeave', 'cloned onto component');
    const jsCloned = EventTestCase.js('onClick', 'cloned onto component ');
    const eventCases = {dart, jsCloned, dartCloned};

    late Element node;
    late Map<EventTestCase, dynamic> events;
    late Map propsFromDartRender;

    setUpAll(() {
      expect(eventCases.map((h) => h.eventPropKey).toSet(), hasLength(eventCases.length),
          reason: 'test setup: each helper should have a unique event key');

      events = {};

      var element = factory({
        'onDartRender': (Map p) {
          propsFromDartRender = p;
        },
        dart.eventPropKey: (event) => events[dart] = event,
      });

      // Simulate a JS component cloning a handler onto a ReactElement created by a Dart component.
      element = React.cloneElement(
        element,
        jsifyAndAllowInterop({
          jsCloned.eventPropKey: (event) => events[jsCloned] = event,
        }) as JsMap,
      );

      element = React.cloneElement(
        element,
        // Invoke the factory corresponding to element's type
        // to get the correct version of the handler (converted or non-converted)
        // before passing it straight to the JS.
        factory({
          dartCloned.eventPropKey: (event) => events[dartCloned] = event,
        }).props,
      );

      node = renderAndGetRootNode(element);
    });

    group('passing Dart events to Dart handlers, and JS events to handlers originating from JS:', () {
      for (final eventCase in eventCases) {
        test(eventCase.description, () {
          eventCase.simulate(node);
          expect(events[eventCase], isNotNull, reason: 'handler should have been called');
          expect(events[eventCase], isA<react.SyntheticMouseEvent>());
        });
      }
    });

    if (isDartComponent(factory({})) && !isNonDartComponentWithDartWrapper) {
      group('in a way that the handlers are callable from within the Dart component:', () {
        setUpAll(() {
          expect(propsFromDartRender, isNotNull,
              reason: 'test setup: component must pass props into props.onDartRender');
        });

        late react.SyntheticMouseEvent dummyEvent;
        setUpAll(() {
          final mountNode = DivElement();
          document.body!.append(mountNode);
          addTearDown(() {
            react_dom.unmountComponentAtNode(mountNode);
            mountNode.remove();
          });

          final divRef = react.createRef<DivElement>();
          react_dom.render(
              react.div({
                'ref': divRef,
                'onClick': (react.SyntheticMouseEvent e) => dummyEvent = e,
              }),
              mountNode);
          divRef.current!.click();
        });

        for (final eventCase in eventCases.where((helper) => helper.isDart)) {
          test(eventCase.description, () {
            expect(() => propsFromDartRender[eventCase.eventPropKey](dummyEvent), returnsNormally);
          });
        }
      });
    }
  });

  test('doesn\'t wrap the handler if it is null', () {
    final nodeWithClickHandler = renderAndGetRootNode(factory({'onClick': null}));

    expect(() => rtu.Simulate.click(nodeWithClickHandler), returnsNormally);
  });

  group('calls the handler in the zone the event was dispatched from', () {
    test('(simulated event)', () {
      final testZone = Zone.current;

      late Element nodeWithClickHandler;
      // Run the ReactElement creation and rendering in a separate zone to
      // ensure the component lifecycle isn't run in the testZone, which could
      // create false positives in the `expect`.
      runZoned(() {
        nodeWithClickHandler = renderAndGetRootNode(factory({
          'onClick': (event) {
            expect(Zone.current, same(testZone));
          }
        }));
      });

      rtu.Simulate.click(nodeWithClickHandler);
    });

    test('(native event)', () {
      final testZone = Zone.current;

      late Element nodeWithClickHandler;
      // Run the ReactElement creation and rendering in a separate zone to
      // ensure the component lifecycle isn't run in the testZone, which could
      // create false positives in the `expect`.
      runZoned(() {
        nodeWithClickHandler = renderAndGetRootNode(factory({
          'onClick': (event) {
            expect(Zone.current, same(testZone));
          }
        }));
      });

      nodeWithClickHandler.dispatchEvent(MouseEvent('click'));
    });
  });
}

/// Tests that refs work properly with [factory], including [forwardRef2] and [chainRefs] integration tests.
///
/// [verifyRefValue] will be called with the actual ref value, and should contain an `expect`
/// that the value is of the correct type.
///
/// [verifyJsRefValue] is optional, and only necessary when the ref value is wrapped and will be different in Dart vs
/// JS (e.g., react.Component vs ReactComponent for class based-components).
/// If omitted, it defaults to [verifyRefValue].
/// It will be called with the actual ref value for JS refs, (e.g., JS ref objects as opposed to Dart objects)
void refTests<T extends Object>(
  ReactComponentFactoryProxy factory, {
  required void Function(dynamic refValue) verifyRefValue,
  void Function(dynamic refValue)? verifyJsRefValue,
}) {
  if (T == dynamic) {
    throw ArgumentError('Generic parameter T must be specified');
  }

  verifyJsRefValue ??= verifyRefValue;

  //
  // [1] Setting a JS callback ref on a Dart component results in the ref being called with the Dart component,
  //     not the JS one, so these tests will fail.
  //
  //     This is because the callback ref will get treated like a Dart callback when the Dart factory performs its conversion.
  //
  //     We don't need to support that use-case, so we won't test it.
  //

  final factoryIsDartComponent = isDartComponent(factory({}));
  final testCaseCollection = RefTestCaseCollection<T>(
    includeJsCallbackRefCase: !factoryIsDartComponent, // [1]
  );

  group('supports all ref types:', () {
    for (final name in testCaseCollection.allTestCaseNames) {
      test(name, () {
        final testCase = testCaseCollection.createCaseByName(name);
        rtu.renderIntoDocument(factory({
          'ref': testCase.ref,
        }));
        final verifyFunction = testCase.meta.isJs ? verifyJsRefValue! : verifyRefValue;
        verifyFunction(testCase.getCurrent());
      });
    }

    test('string refs', () {
      final renderedInstance = _renderWithStringRefSupportingOwner(() => factory({'ref': 'test'}));

      verifyRefValue(renderedInstance.dartComponent!.ref('test'));
    });
  });

  test('asserts that callback ref arguments are nullable on ReactElement creation', () {
    expect(() => factory({'ref': nonNullableCallbackRef}), throwsNonNullableCallbackRefAssertionError);
  }, tags: 'no-dart2js');

  group('forwardRef2 function passes a ref through a component to one of its children, when the ref is a:', () {
    for (final name in testCaseCollection.allTestCaseNames) {
      test(name, () {
        final testCase = testCaseCollection.createCaseByName(name);
        final ForwardRefTestComponent = forwardRef2((props, ref) {
          return factory({'ref': ref});
        });

        rtu.renderIntoDocument(ForwardRefTestComponent({
          'ref': testCase.ref,
        }));
        final verifyFunction = testCase.meta.isJs ? verifyJsRefValue! : verifyRefValue;
        verifyFunction(testCase.getCurrent());
      });
    }
  });

  group('chainRefList works', () {
    test('with all different types of values, ignoring null', () {
      final testCases = testCaseCollection.createAllCases();

      final refSpy = createRef<T>();
      rtu.renderIntoDocument(factory({
        'ref': chainRefList([
          refSpy,
          null,
          null,
          ...testCases.map((t) => t.ref),
        ]),
      }));

      for (final testCase in testCases) {
        final verifyFunction = testCase.meta.isJs ? verifyJsRefValue! : verifyRefValue;
        final valueToVerify = testCase.meta.isJs ? refSpy.jsRef.current : refSpy.current;

        // Test setup check: verify refValue is correct,
        // which we'll use below to verify refs were updated.
        verifyFunction(valueToVerify);
        testCase.verifyRefWasUpdated(valueToVerify);
      }
    });

    group('when refs come from sources where they have been potentially converted:', () {
      test('ReactElement.ref', () {
        final testCases = testCaseCollection.createAllCases().map((testCase) {
          return RefTestCase(
            ref: factory({'ref': testCase.ref}).ref,
            verifyRefWasUpdated: testCase.verifyRefWasUpdated,
            getCurrent: testCase.getCurrent,
            meta: testCase.meta,
          );
        }).toList();

        final refSpy = createRef<T>();
        rtu.renderIntoDocument(factory({
          'ref': chainRefList([
            refSpy,
            null,
            null,
            ...testCases.map((t) => t.ref),
          ]),
        }));

        for (final testCase in testCases) {
          final verifyFunction = testCase.meta.isJs ? verifyJsRefValue! : verifyRefValue;
          final valueToVerify = testCase.meta.isJs ? refSpy.jsRef.current : refSpy.current;

          // Test setup check: verify refValue is correct,
          // which we'll use below to verify refs were updated.
          verifyFunction(valueToVerify);
          testCase.verifyRefWasUpdated(valueToVerify);
        }
      });

      group('forwardRef2 arg, and the ref is a', () {
        for (final name in testCaseCollection.allTestCaseNames) {
          test(name, () {
            final testCase = testCaseCollection.createCaseByName(name);

            final refSpy = createRef<T>();

            final wrapperFactory = react.forwardRef2((props, ref) {
              return factory({
                ...props,
                'ref': chainRefList([
                  refSpy,
                  ref,
                ]),
              }, props['children']);
            });

            rtu.renderIntoDocument(wrapperFactory({
              'ref': testCase.ref,
            }));

            final verifyFunction = testCase.meta.isJs ? verifyJsRefValue! : verifyRefValue;
            final valueToVerify = testCase.meta.isJs ? refSpy.jsRef.current : refSpy.current;

            // Test setup check: verify refValue is correct,
            // which we'll use below to verify refs were updated.
            verifyFunction(valueToVerify);
            testCase.verifyRefWasUpdated(valueToVerify);
          });
        }
      });
    });

    // Other cases tested in chainRefList's own tests
  });
}

void _childKeyWarningTests(ReactComponentFactoryProxy factory,
    {required Function(ReactElement Function()) renderWithUniqueOwnerName}) {
  group('key/children validation', () {
    late bool consoleErrorCalled;
    var consoleErrorMessage;
    late JsFunction originalConsoleError;

    setUp(() {
      consoleErrorCalled = false;
      consoleErrorMessage = null;

      originalConsoleError = context['console']['error'] as JsFunction;
      context['console']['error'] = JsFunction.withThis((self, message, arg1, arg2, arg3) {
        consoleErrorCalled = true;
        consoleErrorMessage = message;

        originalConsoleError.apply([message], thisArg: self);
      });
    });

    tearDown(() {
      context['console']['error'] = originalConsoleError;
    });

    test('warns when a single child is passed as a list', () {
      renderWithUniqueOwnerName(() => factory({}, [react.span({})]));

      expect(consoleErrorCalled, isTrue, reason: 'should have outputted a warning');
      expect(consoleErrorMessage, contains('Each child in a list should have a unique "key" prop.'));
    });

    test('warns when multiple children are passed as a list', () {
      renderWithUniqueOwnerName(() => factory({}, [react.span({}), react.span({}), react.span({})]));

      expect(consoleErrorCalled, isTrue, reason: 'should have outputted a warning');
    });

    test('does not warn when multiple children are passed as variadic args', () {
      renderWithUniqueOwnerName(() => factory({}, react.span({}), react.span({}), react.span({})));

      expect(consoleErrorCalled, isFalse, reason: 'should not have outputted a warning');
    });

    test('when rendering custom Dart components', () {
      renderWithUniqueOwnerName(() => factory({}, react.span({})));

      expect(consoleErrorCalled, isFalse, reason: 'should not have outputted a warning');
    });
  });
}

class _StringRefOwnerOwnerHelperComponent extends react.Component {
  @override
  render() => props['render']();
}

/// Renders the provided [render] function with a Component owner that supports string refs,
/// for string ref tests.
ReactComponent _renderWithStringRefSupportingOwner(ReactElement Function() render) {
  final factory =
      react.registerComponent(() => _StringRefOwnerOwnerHelperComponent()) as ReactDartComponentFactoryProxy;

  return rtu.renderIntoDocument(factory({'render': render})) as ReactComponent;
}

int _nextFactoryId = 0;

/// Renders the provided [render] function with a Component2 owner that will have a unique name.
///
/// This prevents React JS from not printing key warnings it deems as "duplicates".
void _renderWithUniqueOwnerName(ReactElement Function() render, [ReactElement Function(dynamic)? wrapper]) {
  final factory = react.registerComponent2(() => _UniqueOwnerHelperComponent());
  factory.reactClass.displayName = 'OwnerHelperComponent_$_nextFactoryId';
  _nextFactoryId++;

  rtu.renderIntoDocument(factory({'render': wrapper != null ? () => wrapper(render()) : render}));
}

class _UniqueOwnerHelperComponent extends react.Component2 {
  @override
  render() => props['render']();
}

class EventTestCase {
  /// The prop key for an arbitrary event handler that will be used to test this case.
  final String eventPropKey;

  /// A description of this test case.
  final String description;

  /// Whether the tested event handler is a Dart function expecting a Dart synthetic event,
  /// as opposed to a JS function expecting a JS synthetic event.
  final bool isDart;

  const EventTestCase.dart(this.eventPropKey, String description)
      : isDart = true,
        description = 'Dart handler $description';

  const EventTestCase.js(this.eventPropKey, String description)
      : isDart = false,
        description = 'JS handler $description';

  String get _camelCaseEventName {
    return eventPropKey.replaceFirst(RegExp(r'^on'), '').capitalize();
  }

  void simulate(Element node) => callMethod(_Simulate, _camelCaseEventName, [node]);

  @override
  toString() => 'EventHelper: ($eventPropKey) $description';
}

extension on String {
  String capitalize() => substring(0, 1).toLowerCase() + substring(1);
}

@JS('React.addons.TestUtils.Simulate')
external Object get _Simulate;
