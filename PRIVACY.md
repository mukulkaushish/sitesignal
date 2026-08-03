# SiteSignal privacy information

SiteSignal works without a SiteSignal account or hosted backend. It contains no
analytics, advertising, cloud synchronization, or crash-reporting service.

## Data stored on the device

SiteSignal stores this information in its local application data:

- site names, base URLs, and discovered same-origin health-probe URLs;
- enabled, paused, interval, appearance, color, and notification-sound settings;
  and
- a bounded history of baseline and health changes, including time, response
  duration, HTTP status, and a short failure classification.

The data is stored in a local SQLite database. SiteSignal cannot upload it to a
SiteSignal service because no such service exists.

## Network requests

SiteSignal makes three kinds of outbound request:

1. Health requests to websites you explicitly configure.
2. Bounded discovery requests to conventional health paths and favicon files on
   the same origin as a configured website.
3. Small requests to Google's Android connectivity endpoint and Microsoft's
   NCSI endpoint to confirm internet access before treating a failure as a
   website outage.

Favicon discovery runs only in the foreground. It follows only same-origin HTTP
or HTTPS links, limits candidate count, redirects, response bytes, image size,
animation frames, and total time, then normalizes the result to at most 64×64
pixels. Favicon URLs and image bytes are held only in foreground memory. They
are never persisted to SQLite or included in background-isolate messages.

Connectivity requests do not contain configured URLs or monitor history. As
with any internet request, the destination can observe normal connection data
such as the device's public IP address and user agent.

Use HTTPS for monitored websites. Unencrypted HTTP traffic can be observed or
changed by networks between the device and the website. SiteSignal rejects URLs
that contain usernames or passwords.

## Operating-system services and permissions

Depending on the platform and enabled features, SiteSignal may use:

- network access for health, discovery, and connectivity checks;
- notification permission for outage, recovery, connectivity, and test alerts;
- an Android foreground service and persistent status notification for
  continuous background monitoring;
- Android restart-after-boot support when monitoring was enabled; and
- optional desktop launch-at-login registration.

The operating system may retain delivered notifications according to the device
owner's settings.

## Retention and deletion

Each site keeps at most 100 baseline or state-change records. Repeated checks in
the same state update the latest observation without adding another history
entry.

Removing a monitor deletes its configuration and history from SiteSignal.
Clearing the application's data or uninstalling it removes the remaining local
database, subject to backups managed separately by the device owner or operating
system.

## Reporting problems safely

Before opening an issue, remove real URLs, private hostnames, credentials,
response bodies, notification contents, database files, and signing information.
Follow [SECURITY.md](SECURITY.md) when a report could expose a vulnerability or
sensitive data.

Any material change to these data flows should update this document in the same
pull request.
