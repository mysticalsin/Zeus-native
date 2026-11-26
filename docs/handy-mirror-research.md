# Handy, LinkedIn, and Zeus's on-screen helper

This is the ZGB-70 research note. It lived only in the project store. It is in the repository so a later agent can draft from it without that store. Recommendations only. No feature in this note is merged. The five Linux drafts it names at the end already have open pull requests: candidate pack #450, caption lines #394, guide preview #453, question sort #456, and the offline or online speech gate #481.

Research note for Tony Walteur. Read on 23 November 2026 (Brasília time). Recommendations only. Nothing in this note is a shipped Zeus feature, and no pull request was opened.

Zeus stays the native app it already is. The principles in `/agent/repos/Zeus-native/docs/DESIGN-DIRECTION.md` (updated 9 November 2026) still apply: motion explains a state change and can be interrupted, one primary action is visible, depth is progressive, and Reduce Motion changes geometry immediately. The pointing plan in `/agent/repos/Zeus-native/docs/POINTING-ASSISTANT-PLAN.md` already keeps Zeus’s own marker, ink, rings, and voice. This note does not replace that plan. It names public product behavior worth learning, and it leaves other products’ assets, layouts, names, and prompts out of the app.

Two different “mirrors” already exist in the Zeus sources. This note is about the on-screen helper: the bolt that follows the pointer, the ring on a control, and the short caption. The notification list that reads Notification Center (`notify.mirror` in `/agent/repos/Zeus-native/docs/settings-inventory.md`) is a separate surface and is not the subject below.

## 1. LinkedIn changes that matter for a personal top-bar assistant

People open LinkedIn to find work, keep up with people they already know, and feel current without reading a whole feed. Those are the use cases. Zeus can serve the same jobs from the person’s own calendar, notes, and to-dos, in Zeus’s voice: one to three spoken sentences, dry and precise, as `/agent/repos/Zeus-native/docs/PERSONA.md` already specifies. Zeus does not become a social network, does not send a message for the person, and does not copy LinkedIn’s feed, cards, or wording.

### Say the job in a sentence

LinkedIn’s newsroom, 1 May 2025, described AI-powered job search, hiring insights on a listing, and Premium interview practice in LinkedIn Learning. The reason they gave for search: more than half of candidates in a March 2025 Censuswide survey said they miss postings because they do not know the filter or the title. The person types a sentence. The product matches meaning, and the listing shows whether a company looks active.

Source: [New Tools and Insights for Job Seekers and Professionals](https://news.linkedin.com/2025/navigating-your-career-in-the-ai-era), published 1 May 2025.

LinkedIn Help, fetched 23 November 2026, says the same search is available to every member worldwide and that classic keyword search is being retired starting in September. The help page’s own stamp is “Last updated: 2 months ago,” so the September it names is the page’s September, not a second announcement. Filters that remain include date, company, experience, employment type, remote, Easy Apply, “in my network,” and “under 10 applicants.” Suggested chips appear under the query in English, German, French, Spanish, and Portuguese.

Source: [Discover new opportunities with AI-powered job search](https://www.linkedin.com/help/linkedin/answer/a6889044), fetched 23 November 2026.

**Zeus use case.** A spoken line such as “roles like mine, closer to home, posted this week” filters the person’s own saved notes, reminders, and calendar. The top bar shows the current scope as a removable chip, the count, and one next action, which is the filter pattern already in the design direction. Zeus speaks one sentence of what matched. The list stays in the to-do and calendar surfaces that already exist. Zeus does not query LinkedIn, does not rank strangers, and does not draft an application.

### A reason to talk to someone you already know

On 6 February 2024 TechCrunch reported a My Network split. Catch Up lists a connection’s new job, a work anniversary, or a hiring post, with a one-tap reaction or a suggested opener. Grow holds connection requests and suggestions. Premium members could start from an AI draft of a first message, which they were expected to edit before sending. People used Catch Up because those moments were buried in the general notification stream, and a cold hello works better with a reason.

Source: [LinkedIn’s new feature nudges users to reach out](https://techcrunch.com/2024/02/06/linkedins-new-feature-nudges-users-to-reach-out-to-people-in-their-network/), Ivan Mehta, 6 February 2024.

On 15 October 2026 LinkedIn’s newsroom described the current form of the same job. A Network feed of posts from connections and follows is in test in the United States, India, the United Kingdom, and Australia. A digital business card is rolling out globally. Premium profile notes, available globally, are private notes on a profile: how you met, what you discussed, when to reconnect. LinkedIn’s stated reason: more than half of Gen Z in their research were unsure what to do after connecting. The same post also announces creator dashboards, in-stream ads, and paid Advice Sessions. Those are marketplace features. They are not a personal-assistant job.

Source: [New Ways to Build Meaningful Connections](https://news.linkedin.com/2026/new-ways-to-build-meaningful-connections), published 15 October 2026.

**Zeus use case.** The top bar names a person who is already on today’s calendar, plus the note the person typed last time (“met at the review, send the diagram”). Zeus speaks the fact and stops. The person writes the message. Zeus does not invent a congratulations, does not read a social profile, and does not store a scraped bio. A note the person typed can be inspected and deleted. That matches the memory rule already written in the pointing plan: screen text does not become memory by itself.

### A short briefing, then stop

On 12 March 2026 LinkedIn said the feed ranker was moving to larger sequence models plus language models, that automated comments and engagement pods were being suppressed, that recycled and bait posts were being reduced, and that new members could pick topics at sign-up. People stay because the feed is how they hear from other professionals. The change exists because a popularity contest stopped being useful.

Source: [How LinkedIn Is Improving the Feed](https://news.linkedin.com/2026/ImprovingTheFeed), published 12 March 2026.

LinkedIn Help describes the Daily Rundown as an editor-chosen set of the day’s professional stories. Opening a story shows a short overview plus member posts. The person can turn the notification on or off. The help page’s stamp, fetched 23 November 2026, is “Last updated: 4 weeks ago.”

Source: [News on LinkedIn](https://www.linkedin.com/help/linkedin/answer/a523356/news-on-linkedin), fetched 23 November 2026.

**Zeus use case.** The top bar holds a few lines the person already has a reason to see: the next meeting, a reminder that is due, and one note they pinned. Zeus speaks the next fact. There is no ranked feed, no interest picker, and no engagement score. If a line needs the network, it is an explicit fetch the person turned on for that question, and the host is named before anything leaves the machine. The design direction already asks for this shape: benefit, then the concrete item, then one action.

### What LinkedIn shipped that Zeus should leave alone

Hiring Assistant and recruiter InMail are employer tools. Advice Sessions and in-stream ads are a marketplace. A top-bar assistant that drafts outreach, posts for the person, or ranks a social graph is a different product. The useful lesson from the 12 March feed note is the opposite of building a ranker: show less, and show something the person can act on.

## 2. Open-source repositories

Checked against each repository’s public license and description on 23 November 2026. “Leave out” is a Zeus rule from this task and from `/agent/repos/Zeus-native/AGENTS.md`: no private vault, no microphone capture without the person’s own OS consent, no copy of another product’s interface.

| Repository | License, as published | What it actually does | What stays out of Zeus |
| --- | --- | --- | --- |
| [satvikxbansal/Handy](https://github.com/satvikxbansal/Handy) | No `LICENSE` file in the tree. The README ends with “Bansal Labs®”, which is not a grant. Created 12 April 2026, 08:36 BRT. V2 workflow commit `c93f705` on 23 April 2026, 07:10 BRT. Latest commit seen, `8622c9a`, on 29 May 2026, 03:52 BRT. | A macOS menu-bar assistant. It captures displays, keeps a local chat per front app, points with a companion mark, and can walk a short on-screen task after one model plan. Section 3 is this repository. | Do not copy source, prompts, colors, the hand menu, the pill, the triangle, or the name. No vendoring until a real license exists. |
| [farzaa/clicky](https://github.com/farzaa/clicky) | MIT, copyright 2026 Farza. Pushed 28 October 2026, 18:41 BRT. README update dated 27 April 2026: the newer HeyClicky app is private; this tree is the older open code. | An open point-and-talk desktop buddy. A full-screen click-through overlay draws its own mark. A model appends a coordinate tag. The person’s pointer keeps working underneath. | The MIT grant allows reuse of that code. Zeus still does not take the mark, the prompt, the product layout, or the product name. Zeus already draws its own bolt on a click-through overlay. |
| [cjpais/Handy](https://github.com/cjpais/Handy) | MIT, copyright 2025 CJ Pais. Pushed 21 November 2026, 03:54 BRT. | A different program with the same name: an offline speech-to-text application. | Not the pointing Handy. Do not import the application window. A Linux draft that needs local speech uses a library and a fixture transcript. It does not open a microphone. |
| [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) | MIT, copyright 2023–2026 The ggml authors. Pushed 23 November 2026, 14:51 BRT. | Local Whisper inference in C++. | Useful only as an engine behind a transcript Zeus already has. It does not see the screen. Do not add a capture path for this research. |
| [microsoft/OmniParser](https://github.com/microsoft/OmniParser) | CC-BY-4.0. Pushed 14 November 2026, 19:53 BRT. | A vision model that parses a screenshot into GUI elements for a computer-use agent. | The useful idea is a short list of controls. Zeus should get that list from the platform accessibility API, with the person’s permission. Bundling the weights would require attribution and would make a screenshot the default. The screenshot stays off unless the person has turned that consent on. |
| [OpenAdaptAI/OpenAdapt](https://github.com/OpenAdaptAI/OpenAdapt) | MIT. Pushed 23 November 2026, 15:11 BRT. Public lead: “Give your agent a program, not a mouse.” | A local execution layer that turns a demonstrated task into a program an agent can run. | A recording of clicks and screens is a private vault. Zeus does not store one. The person still makes every click. Zeus does not synthesize a click. |
| [screenpipe/screenpipe](https://github.com/screenpipe/screenpipe) | Screenpipe Commercial License, copyright 2024–2026 Negentropy Labs, Inc. Root `LICENSE` was absent; `LICENSE.md` is the grant. Pushed 21 November 2026, 06:20 BRT. | Continuous local recording of computer work, then a search for workflows to automate. | Continuous capture, a commercial grant, and a vault of work history. Leave the project out. |
| [GNOME/at-spi2-core](https://github.com/GNOME/at-spi2-core) | LGPL-2.1. Pushed 22 November 2026, 13:45 BRT. Read-only mirror of the GNOME project. | The Linux accessibility bus: names, roles, and bounds of on-screen controls, after the person has allowed it. | Do not vendor the library into Zeus. A later Linux draft defines a candidate record in portable code and feeds it fixtures. A future process may call the system library under the person’s own grant. |
| [e2b-dev/desktop](https://github.com/e2b-dev/desktop) | Apache-2.0. Pushed 22 November 2026, 21:12 BRT. | A remote desktop sandbox an outside model can drive. | The desktop leaves the machine. Leave it out. |

The repositories worth studying are Handy’s public behavior (section 3), the accessibility idea in at-spi2, and the “program, not a mouse” sentence from OpenAdapt. The engines and the remote desktops do not make the on-screen helper cheaper.

## 3. Handy, and what Zeus should learn

Public tree: [github.com/satvikxbansal/Handy](https://github.com/satvikxbansal/Handy). Facts below are either from the README or from source files read on 23 November 2026. The README names `AccessibilityMarksProvider.swift` and `GuideCapturePolicy.swift`. Those two files were not in the public tree that day. Treat “a safe list of labels” and “capture only the focused window” as README claims. The click watcher, the workflow runner, the point parser, and the companion cursor were in the tree and were read.

Handy is a menu-bar app for macOS 14 or later. A question can include a screenshot of the displays. Speech defaults to Apple’s recognizer. The model key stays in the Keychain. Chat history is JSON on disk, one file per frontmost app, and a browser is keyed by the site when accessibility can read the address bar. A request sends the recent slice of that thread, not the whole history. Web search is optional and, in the README, stays off for “where is this button.”

### What a hover does

Hover commits nothing.

- The companion mark follows the real pointer on a 16 ms timer, drawn about 35 by 25 points away, and only while it is in the following state. It does not press anything.
- If the person moves the pointer more than about 100 points while the mark is flying back, the flight cancels and following resumes.
- The optional edge pill highlights while the pointer is inside. A drag past about 6 points moves the pill and hides the mark. A press that did not drag opens the chat panel.
- In the chat title, hovering the status dot shows one short rotating phrase, then dismisses it. That phrase is not the answer.
- During a guided task, a “preview” points at the next control and can say a short line (“after you’re done, click Send”). The preview is not success. If that preview sits unused, the runner stops it after 45 seconds. A wait or a typing pause reveals the preview. The clock does not mark the step done.

### What a click does

The click is the person’s. Handy watches it and does not invent one.

`ClickDetector.swift` installs a listen-only global monitor for left and right mouse-down. The runner arms a rectangle. A down inside that rectangle, expanded by 12 points, fires once. A second down within 0.35 seconds is ignored. A down outside does nothing. The detector disarms before the callback, so the next step can arm a new rectangle.

`WorkflowRunner.swift` then continues locally. The model planned a path of 2 to 5 steps once (`WorkflowContinuationPolicy.swift`). A click on the armed control moves to the next step. Immediate steps arm the next rectangle. Steps that look like typing or waiting reveal a preview instead. The next rectangle comes from a local accessibility lookup, with retries inside a 4 second budget (8 seconds for a delayed preview). Two unresolved steps in a row stop the flow. The whole flow dies at 120 seconds, if the app changes, if the person asks a new question, or if they stop it. Voice (`Control+Z` in Handy) pauses the flow. Letting go without a real question resumes it.

That is the efficiency. The model is not called again because the person clicked.

### What a detail does

There is no control named Detail in the files that were read.

Detail is the written thread. `PointParser.swift` splits a voice reply into a spoken span and the rest. Spoken text for the voice is capped at 420 characters. The short overlay line is capped at 110. Coordinate tags are stripped before the chat shows the text. The README and `DEMO_SCRIPT.md` call the panel the full answer: shortcuts, alternatives, and the longer explanation. The mark keeps the one-line version. If the answer is really a paragraph, the short line points the person at the thread.

The companion’s own motion, which Zeus does not take, is a blue triangle on a one-second-scale Bézier arc, a random dwell of 3 to 5 seconds, then a flight back, with separate colored bubbles for the label, the transcript, and the reply (`CompanionCursorManager.swift`).

### Zeus’s own animation stays

The bolt already has the states the helper needs. `/agent/repos/Zeus-native/Sources/Zeus/Overlay/BuddyModel.swift` lists following, listening, thinking, flying, pointing, and returning. `/agent/repos/Zeus-native/Sources/Zeus/Overlay/BuddyOverlayView.swift` draws the Zeus avatar, a bolt-colored ring, an arrival stroke, a listening waveform, a thinking spinner, a short bubble, and a caption plate. The overlay does not take hits. Reduce Motion is already a flag on the pointing label in `/agent/repos/Zeus-native/Sources/Zeus/Overlay/BuddyController.swift`. The design direction’s shared motion (a short press, an interruptible spring, immediate geometry when Reduce Motion is on) stays the motion. Handy’s triangle, pill, hand glyph, bubble colors, and random catchphrases stay out.

Spoken length already has a Zeus rule. `/agent/repos/Zeus-native/Sources/ZeusCore/PersonaReplyClamp.swift` keeps a spoken reply to a few sentences, and treats “explain,” “in detail,” and “walk me through” as the case that may use the longer spoken budget. The longer words still belong in the thread the person can read.

### Translation into Zeus behavior

**Hover.** The bolt stays in follow mode, beside the pointer, in Zeus’s existing offset and spring. Hover captures nothing, calls no model, and advances no step. A preview of the next ring may appear only after the person has clicked the current one and the local plan says the next control is a type or a wait. The preview uses the same bolt ring. With Reduce Motion the ring is simply there. The caption is the control’s own short label, or one Zeus sentence. It is not a canned “click this.”

**Click.** The person’s real click is the only advance. A click inside the ring moves the local plan to the next step and looks up the next rectangle on the machine. A click outside leaves the step where it is. A double click does not run the step twice. A secure field never arms. Sleep, a display change, a different app, Escape, or a new question drops the plan. The bolt, the ring, and the caption update to the new step. Speech, if any, stays inside the existing sentence clamp.

The current session type is the expensive shape. In `/agent/repos/Zeus-native/Sources/ZeusCore/Pointing/PointingSession.swift`, a `clickInTarget` while guiding returns to `processing` and bumps the generation. The file’s own comment says the guided path is stubbed. The pointing plan’s later phase also recaptures and starts a follow-up turn. The recommendation is to revise that recommendation: resolve the next rectangle locally, and call the model again only when the plan is finished, the control cannot be found, or the person asks something new.

**Detail.** The bubble and the caption stay one line. The full note is the existing chat thread for that turn, opened because the person asked, or because the spoken line said there is more to read. Zeus’s type roles and palette draw it. The thread does not appear because the pointer rested on the bolt. Screen text is not written into the notes vault unless the person saves it. Point tags, if a model emits them, never show as raw text. Zeus keeps its own scene messages. It does not adopt Handy’s tag spelling.

**Efficiency, with that animation left alone.** One model plan. Local steps after that. A candidate list of at most a handful of controls (role, a short label, a rectangle, a secure flag), for the display under the pointer. Screenshot bytes only when the person has already opted in, which the settings inventory already records as off by default (`pointing.sendScreenshot`). Web lookup stays off when the question is “what do I click.” The bolt’s flight is not the cost. The second model call is.

## Later Linux draft

Pure logic, fixtures, and tests. No device, no signing, no microphone, no screenshot bytes, no private vault. The animation files stay untouched. Highest value first.

1. **A guiding reducer with a local plan.** States: armed, preview, done, cancelled. A plan has 2 to 5 steps. A point inside the armed rectangle plus a small tolerance emits “advance” and the next rectangle. A point outside emits nothing. A second point inside a short grace window emits nothing. A clock firing never emits “done.” An app-identity change emits “cancel.” Intermediate advances do not emit “call the model.” This replaces, in the test, the current `clickInTarget` → `processing` hop.
2. **Three strings from one reply.** Spoken text goes through the existing sentence clamp. The on-screen label is a short control name. The detail string is withheld from the overlay input. A fixture with a long answer shows the label and the spoken line only.
3. **A candidate pack.** Each candidate has a role, a truncated label, a rectangle, and a secure flag. Secure values are absent. The pack names one display. A `sendScreenshot` flag defaults to false, and the fixture then contains no image bytes.
4. **A question sort.** “Where is the button” and “walk me through this” set a guide flag and leave web search off. A question that needs a fact from after the model’s knowledge may set web search on. The test performs no network call.
5. **Preview is not success.** After a click whose next step is “type” or “wait,” the reducer enters preview and stays there until a click lands in the next rectangle, or until the idle budget cancels it. The test injects the clock.

Those five are the draft. The bolt, the ring, the waveform, and the caption stay Zeus’s, and they are not part of the draft.
