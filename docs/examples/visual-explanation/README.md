# Visual explanation protocol examples

These files contain complete version-1 `ExplanationEvent` records, one JSON object per line, including the final newline. Decode model output with `ExplanationWire` or `ExplanationEventStream`, then project it with `ExplanationSceneReducer`. A successful projection validates future work; only the actual playback scheduler admits cues into the canonical scene.

The fixed UUIDs are app-issued **fixture identities**, not IDs a model may choose in a live request. Replace them with the current app-issued identities when constructing a real request, and use the revision supplied after the app reserves that turn. Do not replay these fixture revisions into an existing conversation. No example includes executable code, a URL, an asset reference, capture authority or model-issued audio timing.

| File | Initial scene | Turn | Revision progression |
| --- | --- | --- | --- |
| `diagram.ndjson` | Empty diagram scene, revision 0, canvas 1024 × 768 | `30000000-0000-4000-8000-000000000001` | 0 → 1 → 2 |
| `follow-up.ndjson` | Completed diagram after the app reserves a new turn at revision 3 | `30000000-0000-4000-8000-000000000002` | 3 → 4 |
| `world.ndjson` | Separate empty world scene, revision 0 | `30000000-0000-4000-8000-000000000003` | 0 → 1 → 2 |

All examples share session `10000000-0000-4000-8000-000000000001`. The diagram and follow-up use scene `20000000-0000-4000-8000-000000000001`; the world example uses scene `20000000-0000-4000-8000-000000000002`. Each new turn starts at sequence 0. Beat and speech chunk IDs are unique within each turn.

`diagram.ndjson` creates the `input` and `answer` cards, then the `flow` connector. The connector starts at reveal 0; its second beat reveals it when that cue is admitted. Reduced Motion must preserve the hidden state until that cue, then snap the admitted transition. Canvas coordinates are logical points with a top-left origin; rectangle/card geometry begins at the object's transformed local origin.

`follow-up.ndjson` patches the existing `flow` style and moves `answer`, preserving their IDs and the `input` object. For a reducer-only fixture, first apply both diagram events, then restore that snapshot at revision 3 to represent the app-owned new-turn reservation. The application normally makes this reservation through its history/coordinator API. Applying the follow-up directly to revision 2 must fail with a revision conflict. Manual edits require the app to provide their newer revision and scene in the next request.

`world.ndjson` uses a right-handed, Y-up illustrative world, a group with two visible geometric subjects, material presets, a bounded rotation and a world-space label. Its dimensions have no measurement claim. Groups inherit transforms, opacity and reveal. A group used as a connector subject is bounded by its non-connector geometric descendants; a group with no such descendants is only an origin anchor. Avoid using empty groups as visible diagram subjects.

All objects use the default `proceduralIllustration` provenance and empty source IDs. This is not factual evidence, a photograph or a verified reconstruction. The empty app asset/source registry is sufficient for these fixtures. Images in other requests require IDs already approved by the app; arbitrary asset URLs and file paths are never accepted.

The only times in these records are bounded **relative animation durations**. Start/end cue anchors bind to real synthesized playback boundaries. The app issues audio references, actual duration, sample rate and any verified word alignment separately. Actual remaining audio time bounds each transition; caption mode advances explicitly. No estimated word timings or model-generated audio references are needed.

`ev-drivetrain.ndjson` is the slice S3 acceptance fixture: session `10000000-0000-4000-8000-000000000001`, scene `20000000-0000-4000-8000-000000000003`. Turn `...0004` builds the generic electric drivetrain in five beats (revision 0 to 5): vehicle and floor battery, inverter, motor and reduction drive, torque to the wheels, regenerative braking. Four one-beat follow-up turns (`...0005` to `...0008`, bases 6, 8, 10, 12; the app reserves one revision before each) rotate the view, make the body transparent, make the rear wheels transparent and slow the animation, each editing the same scene by id. It is a generic, explanatory animation and not an engineering simulation.

