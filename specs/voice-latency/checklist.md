# Checklist: Voice latency

- [x] The log line has durations only. No audio. No transcript. No command text.
- [ ] Mic hot is under 50 ms on the hosted run, or the miss is reported as a miss.
- [ ] A short phrase finals in under 300 ms after release with the model already warm.
- [ ] Insertion is under 30 ms.
- [ ] A listed command acts in under 100 ms from the final transcript and does not wait for the language model.
- [ ] A sentence that is not a listed intent still reaches the language model.
- [ ] The second hold in one run still receives audio.
- [ ] The installed talk cue still plays on start and end.
- [ ] A solo right-Command tap still toggles. A hold with another key does not.
- [ ] The baseline table is filled from the hosted log, or it still says unmeasured.
- [ ] No Package.swift, workflow, or timeout edit.
