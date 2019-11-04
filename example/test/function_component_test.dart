import 'dart:html';

import 'package:react/hooks.dart';
import 'package:react/react.dart' as react;
import 'package:react/react_dom.dart' as react_dom;
import 'package:react/react_client.dart';

var useStateTestFunctionComponent = react.registerFunctionComponent(UseStateTestComponent, displayName: 'useStateTest');

UseStateTestComponent(Map props) {
  final count = useState(0);

  useEffect(() {
    print('count changed to ' + count.value.toString());
    return () {
      print('count is about to change');
    };
  });

  return react.div({}, [
    count.value,
    react.button({'onClick': (_) => count.set(0)}, ['Reset']),
    react.button({'onClick': (_) => count.setTx((prev) => prev + 1)}, ['+']),
  ]);
}

void main() {
  setClientConfiguration();

  render() {
    react_dom.render(
        react.Fragment({}, [
          react.h2({'key': 'useStateTestLabel'}, ['useState Hook Test']),
          useStateTestFunctionComponent({'key': 'useStateTest'}, []),
        ]),
        querySelector('#content'));
  }

  render();
}
