# Charging Data Strategy

## Sources

Daily recommendations currently use the EPDK public catalogue through the project proxy. Seven supported brands are configured: TESLA, TRUGO, ZES, ESARJ, SHARZ, OTOJET and VOLTRUN. This is not a claim of full Turkish coverage. Open Charge Map remains available in diagnostics. Neither Google Places nor catalogue inclusion establishes live availability.

## Refresh contract

- Server cache: 12 hours, per brand, in memory only; refresh is request-driven, not scheduled. Cold starts may refetch data.
- `fetchedAt` is the oldest successful upstream fetch represented by a response; cache hits preserve it. `fetchedAtByBrand` preserves individual fetch times. `servedAt` is response generation only. `sourceUpdatedAt` remains unknown.
- iOS `retrievedAt` is device download time; `catalogueFetchedAt` is server fetch time. Neither populates station/unit `lastUpdated`.
- Device cache: 30 minutes for successful complete responses, with a separate 24-hour catalogue age check. Known catalogue dates older than 24 hours or more than five minutes in the future are rejected. This is a product rule, not a provider SLA.
- Legacy responses without fetch metadata remain low-confidence and display a warning. They are not cached as complete successful responses.
- Timeout, malformed payload and individual invalid station records preserve other usable results and carry a partial-data warning. Unsupported or excessive brand requests fail explicitly rather than silently truncating coverage.
- Persistent storage, scheduled refresh, complete operator discovery and live socket availability are not implemented yet.

## Known limitations

Open Charge Map is not treated as live availability. Connector, power, status, and timestamps can be absent or stale. The app preserves unknown values rather than guessing.

## Freshness and confidence

EPDK stations and units have unknown source freshness and unknown availability, so remain low confidence. Recent catalogue retrieval permits candidate evaluation, not operational verification. The recommendation explains this limitation. Source timestamps for other providers are retained separately; merging does not attach another record's newer timestamp to the selected provider.

## Deduplication

Records with the same normalized operator and approximately the same coordinates are merged. Connector/power pairs are retained once, preferring the most confident record. Conflicting records remain conservative through low confidence.

## Route corridor

The service accepts origin, destination, optional polyline, and radius. A supplied polyline is used directly; otherwise, it samples nine straight-line points. This is replaceable with the true route polyline in a future route provider update.

## Future operator integrations

Official operator APIs should implement `ChargingDataProvider`, return partial results on per-provider failures, and provide timestamped unit status where available. Their status may only be presented as live when explicitly supplied by that provider.
