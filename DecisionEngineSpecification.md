# Decision Engine Specification v1.0

## Product assumptions

- The product optimizes the driver's time, not the battery.
- V1 produces a deterministic Daily-mode recommendation from the current battery, selected destination, arrival reserve, and preferred charge limit.
- V1 does not use live vehicle telemetry, route distance, traffic, weather, charger availability, or pricing.
- A destination's coordinates select one of three deterministic prototype route-consumption bands. This is an explicit temporary proxy for live route data.
- The engine never mutates input and contains no UI or navigation behavior.

## Decision tree

1. Estimate route consumption from the selected destination.
2. Calculate predicted arrival battery as `max(0, battery - consumption)`.
3. Calculate confidence from the predicted-arrival margin above reserve.
4. Select a confidence buffer.
5. Recommend **Charge Now** when predicted arrival is less than or equal to `reserve + confidence buffer`; otherwise recommend **Don't Charge**.
6. Calculate the time that charging toward the preferred charge limit would add.
7. Return the decision, predicted arrival, confidence, ITC, and explanation together.

## Daily mode rules

Daily mode is the only mode that calls `DecisionEngineV1.recommendation(for:)`.

### Route-consumption prototype

- No selected destination: 30 percentage points.
- Destination signature modulo 3 equals 0: 18 percentage points (city band).
- Signature modulo 3 equals 1: 30 percentage points (borderline band).
- Signature modulo 3 equals 2: 55 percentage points (long-trip band).
- Signature is `round(abs(latitude * 100) + abs(longitude * 100))`.

### Reserve battery logic

- The arrival reserve is always preserved in the output.
- Predicted arrival is clamped at 0%; it never becomes negative.
- A low-confidence result adds a 5-point decision buffer, medium adds 2 points, and high adds 0 points.
- Equality is conservative: arrival equal to the reserve plus its buffer is **Charge Now**.

### Preferred charge limit logic

- Preferred charge limit does not change predicted arrival or the charge/no-charge threshold.
- It determines the reference charge delta used for ITC.
- `chargeDelta = max(0, preferredChargeLimit - battery)`.
- `ITC = max(8, round(chargeDelta * 0.45))` minutes.

### Confidence calculation

Confidence is based on `predictedArrival - reserve`:

| Margin | Confidence | Buffer |
| --- | --- | --- |
| 15 points or more | High | 0 points |
| 5–14 points | Medium | 2 points |
| 4 points or less | Low | 5 points |

### Explanation generation

- **Charge Now** explains the predicted arrival, reserve, and preferred charge limit.
- **Don't Charge** explains the predicted arrival, reserve, and avoided charging time.
- Explanations must use only values returned or supplied to the engine, so the UI never invents a reason.

## Journey mode rules

- Journey remains a planning placeholder in v1 and does not call the decision engine.
- V1 does not infer charging stops, route legs, or a journey recommendation.
- A future Journey engine may reuse the same reserve, confidence, explanation, and ITC contracts per route leg.

## Future ITC integration points

The current ITC is a deterministic estimate. A future route-aware implementation should replace the charge-delta estimate with:

1. Route duration and traffic delay.
2. Charger detour, queue, and reliability.
3. Vehicle charge curve, battery temperature, and charger power.
4. Preferred charge limit plus the minimum energy needed for the next leg.
5. Weather, elevation, driving style, and real-time consumption.

The output contract remains unchanged: return the incremental minutes plus a concise explanation of why that time is worthwhile.
