# SiteSignal privacy information

SiteSignal is designed to operate without a SiteSignal account or hosted
backend. It does not include analytics, advertising, cloud synchronization, or
crash-reporting services.

## Data stored on the device

SiteSignal stores the following information in its local application data:

- configured site names and base URLs;
- discovered same-origin probe and favicon URLs;
- enabled, paused, interval, appearance, color, and notification-sound
  preferences; and
- a bounded history of baseline and health-transition records, including time,
  status, response duration, HTTP status, and concise failure classification.

The data is stored in a local SQLite database. SiteSignal does not upload that
database to a SiteSignal service because no such service exists.

## Network requests

SiteSignal makes three categories of outbound request:

1. Health requests to websites explicitly configured by the user.
2. Bounded discovery requests to conventional paths and favicon resources on
   the same origin as a configured website.
3. Small reachability requests to Google's Android connectivity endpoint and
   Microsoft's NCSI endpoint. These confirm that the device has working
   internet access before a network failure can be treated as a website
   outage.

Reachability requests do not contain configured monitor URLs or monitor
history. Like ordinary internet requests, the receiving service can observe
standard connection metadata such as the device's public IP address and the
SiteSignal user agent.

HTTPS is strongly recommended for monitored websites. HTTP URLs are supported,
but unencrypted traffic can be observed or altered by networks between the
device and the website. SiteSignal rejects URLs containing embedded
credentials.

## Operating-system services and permissions

Depending on the platform and enabled features, SiteSignal may use:

- network access for health and reachability checks;
- notification permission for outage, recovery, and connectivity alerts;
- an Android foreground service and persistent status notification for
  continuous background monitoring;
- Android restart-after-boot support when monitoring was enabled;
- iOS background refresh, scheduled at the operating system's discretion; and
- optional desktop launch-at-login registration.

Notifications are delivered and may be retained by the operating system under
the device owner's notification settings.

## Retention and deletion

Each site keeps at most 100 baseline or status-transition records. Repeated
checks in the same state update the latest observation without adding another
history entry.

Removing a monitor deletes its configuration and history from SiteSignal.
Clearing the application's data or uninstalling it removes the remaining local
database, subject to any device backups managed separately by the operating
system or device owner.

## Privacy when reporting problems

Before opening an issue, remove real monitor URLs, private hostnames,
credentials, response bodies, notification contents, database files, and
signing information. Follow [SECURITY.md](SECURITY.md) when a report could
expose a vulnerability or sensitive data.

Material changes to these data flows should update this document in the same
pull request.
