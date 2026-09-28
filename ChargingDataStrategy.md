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

Google Routes requests a high-quality GeoJSON LineString. Corridor filtering measures distance to every segment, including between vertices. The generic service retains a straight-line fallback for diagnostics, but Daily stop verification requires the real road geometry and will not select a stop without it.

Daily screens candidates using path progress and approximate energy. Up to three are checked with a Google route through the station; its two legs determine travel-to-stop, remaining travel, additional road distance and added driving time. The winner is the lowest estimated added time among this bounded shortlist, not a globally optimal stop. Traffic reflects query time, not a guaranteed forecast after charging. Arrival reserve is required at the stop and destination, and the preferred charge limit is never silently exceeded.

Consumption and charging still use generic estimates (0.18 battery percentage points/km, 70 kWh, capped/tapered charging power). These are not Macan telemetry. Multiple charging stops remain unsupported and are identified as a possible reason a single-stop plan cannot be produced.

## Future operator integrations

Official operator APIs should implement `ChargingDataProvider`, return partial results on per-provider failures, and provide timestamped unit status where available. Their status may only be presented as live when explicitly supplied by that provider.
