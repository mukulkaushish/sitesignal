import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_signal/features/monitoring/data/http_internet_connectivity_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

void main() {
  test('reports no network without issuing an external probe', () async {
    var requestCount = 0;
    final checker = HttpInternetConnectivityChecker(
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('', 500);
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.none,
      ],
    );

    final assessment = await checker.assess();

    expect(assessment.availability, InternetAvailability.offline);
    expect(assessment.issue, ConnectivityIssue.noNetwork);
    expect(requestCount, 0);
  });

  test(
    'detects Wi-Fi without validated internet or a captive portal',
    () async {
      final checker = HttpInternetConnectivityChecker(
        client: MockClient((request) async => http.Response('Sign in', 200)),
        connectivityProvider: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
      );

      final assessment = await checker.assess();

      expect(assessment.availability, InternetAvailability.offline);
      expect(assessment.issue, ConnectivityIssue.noInternet);
      expect(assessment.transports, <NetworkTransport>[NetworkTransport.wifi]);
    },
  );

  test(
    'accepts internet access when either independent probe validates',
    () async {
      final checker = HttpInternetConnectivityChecker(
        client: MockClient((request) async {
          if (request.url.host == 'www.msftconnecttest.com') {
            return http.Response('Microsoft Connect Test', 200);
          }
          return http.Response('', 503);
        }),
        connectivityProvider: () async => <ConnectivityResult>[
          ConnectivityResult.mobile,
        ],
      );

      final assessment = await checker.assess();

      expect(assessment.availability, InternetAvailability.online);
      expect(assessment.issue, ConnectivityIssue.none);
      expect(assessment.transports, <NetworkTransport>[
        NetworkTransport.mobile,
      ]);
    },
  );
}
