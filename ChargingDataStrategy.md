# Charging Data Strategy

## Sources

Sprint 8 uses Open Charge Map as a third-party foundation. The data layer is provider-based so official operator APIs can be added without changing recommendation views. Google Places is not used as charging availability data.

## Known limitations

Open Charge Map is not treated as live availability. Connector, power, status, and timestamps can be absent or stale. The app preserves unknown values rather than guessing.

## Freshness and confidence

Data less than seven days old is recent. High confidence needs a recent official/operator source plus complete connector and power data. Medium confidence is recent third-party data with complete technical fields. Old, incomplete, unknown-status, or conflicting records are low confidence.

## Deduplication

Records with the same normalized operator and approximately the same coordinates are merged. Connector/power pairs are retained once, preferring the most confident record. Conflicting records remain conservative through low confidence.

## Route corridor

The service accepts origin, destination, optional polyline, and radius. A supplied polyline is used directly; otherwise, it samples nine straight-line points. This is replaceable with the true route polyline in a future route provider update.

## Future operator integrations

Official operator APIs should implement `ChargingDataProvider`, return partial results on per-provider failures, and provide timestamped unit status where available. Their status may only be presented as live when explicitly supplied by that provider.
