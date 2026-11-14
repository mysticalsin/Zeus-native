#!/usr/bin/env python3
"""One table, two outputs: teardown/glance-settings-inventory.md and Sources/Zeus/App/SettingsCatalog.swift.
the reference app labels come from studying a reference app (its fr/es Localizable.strings keys, Info.plist, binary
strings and settings icon names). Only option names and behaviour are recorded, never code or assets.
Usage: gen-settings-catalog.py <repo> <inventory.md>"""
import sys, json

# section, group, glance option, glance control, glance default, what it does,
# zeus before (has/partial/missing), zeus id, zeus kind, choices, zeus default, state, note
# state: live (wired here), custom (hand-built row already wired), stub (stored + labelled, TODO), excluded
R = []
def o(*a): R.append(a)

S='general'
o(S,'Your defaults','Language','menu','System language','Pins the app language instead of following macOS.','missing','general.language','choice',['System language','English'],'System language','stub','ZEUS copy is English only today. TODO: localize, then honour the pin.')
o(S,'Your defaults','Window appearance (System, Light, Dark)','segmented','System','Theme for Settings and the welcome guide.','missing','general.windowTheme','choice',['System','Light','Dark'],'Dark','stub','Glass is drawn dark only. TODO: light glass palette.')
o(S,'Your defaults','Default agent for new chats','menu','Claude Code','Agent used when you start a new chat from the notch.','missing','general.defaultAgent','choice',['Claude Code','Codex'],'Claude Code','live','Pre-selects the agent in Chat > New chat; falls back to the first offered agent.')
o(S,'Your defaults','Show the notch on (Built-in display, Display with the pointer, All displays)','menu','Built-in display','Which screens carry the notch. Screens without a notch get a slim pill.','missing','notch.displays','choice',['Built-in display','Display with the pointer','All displays'],'Built-in display','live','Rebuilds the notch windows; lock, wake and Space changes re-raise them.')
o(S,'Day to day','Launch at login','toggle','on','Starts the app when you log in.','missing','general.launchAtLogin','toggle',[],'true','live','SMAppService, bundled app only.')
o(S,'Day to day','Keep the Mac awake while agents work','toggle','off','Blocks idle sleep while an agent runs; the screen can still lock.','missing','general.keepAwake','toggle',[],'false','live','Power assertion held only while a session is working.')
o(S,'Day to day','Keep the display awake while music plays','toggle','-','Holds the display on only while Music or Spotify is playing. Stops on low battery or heat.','missing','keepAwake.whileMusic','toggle',[],'false','live','M4. Display assertion with a two minute lease, renewed each minute, held only while a track plays (20 second grace). Uses the Keep awake battery floor and heat rule. Separate from sessions and the Home cup.')
o(S,'Day to day','Welcome back recap (Recap and return)','toggle','on','After 10 minutes or more away, the notch shows what agents finished, failed or are waiting on, and Zeus says one line about it when voice answers are on.','missing','general.welcomeBack','toggle',[],'true','live','Away is system idle time (no keys or mouse). Only agent events since you left are listed; waiting ones only while still waiting.')
o(S,'Day to day','Meeting mode (discreet during calls and screen sharing)','toggle','on','When another app uses the mic or camera, or the display is mirrored: leave captures, mute sounds, hide details.','partial','general.meetingMode','toggle',[],'true','live','Detects the mic in use by another app and mirrored displays. Camera detection TODO.')
o(S,'Day to day','Show in screen sharing','toggle','-','','missing','general.showInScreenSharing','toggle',[],'false','live','N1. Every Zeus window uses the shared sharing helper.')
o(S,'Guided setup','Run setup again','button','-','Replays the first-run guide.','has','general.runSetup','action',[],'','custom','')
o(S,'Updates','Check for updates automatically','toggle','on','','missing','about.autoUpdate','toggle',[],'false','live','N6. Polls the feed URL when set.')
o(S,'Updates','Update feed URL','text','-','','missing','about.updateFeedURL','text',[],'','live','N6. JSON feed with version and downloadURL; empty means off.')
o(S,'Updates','Check for updates','button','-','Checks now.','missing','about.checkNow','action',[],'','stub','Same as above.')

S='appearance'
o(S,'Find your look','Card style (Classic, Glass, Physical, Liquid Glass, Dashboard, Dashboard B)','picture cards','Glass','Look of the permission, running and finished cards.','partial','appearance.cardStyle','choice',['Liquid Glass','Glass','Classic','Physical','Dashboard','Dashboard B'],'Liquid Glass','live','')
o(S,'Find your look','Home style (Device, Borderless, Borderless colour)','picture cards','Device','Frame of the Home band.','missing','appearance.homeStyle','choice',['Device','Borderless','Borderless colour'],'Device','live','')
o(S,'Find your look','Customize Physical (Home and card finishes)','menus','-','Separate finishes for Home and cards in the Physical theme.','missing','appearance.physicalFinish','choice',['Same all','Separate'],'Same all','live','')
o(S,'Home','Home slot 1','menu','-','The widget in the first Home card.','missing','home.widget.1','choice',['Music', 'Focus', 'Weather', 'Calendar', 'Clock', 'World clock', 'Month', 'Agenda', 'Countdown', 'Note', 'Battery', 'Agents'],'Music','live','Click a card in Customize Home, or pick here. Defaults are today\'s Music, Focus, Weather and Calendar.')
o(S,'Home','Home slot 2','menu','-','The widget in the second Home card.','missing','home.widget.2','choice',['Music', 'Focus', 'Weather', 'Calendar', 'Clock', 'World clock', 'Month', 'Agenda', 'Countdown', 'Note', 'Battery', 'Agents'],'Focus','live','Click a card in Customize Home, or pick here. Defaults are today\'s Music, Focus, Weather and Calendar.')
o(S,'Home','Home slot 3','menu','-','The widget in the third Home card.','missing','home.widget.3','choice',['Music', 'Focus', 'Weather', 'Calendar', 'Clock', 'World clock', 'Month', 'Agenda', 'Countdown', 'Note', 'Battery', 'Agents'],'Weather','live','Click a card in Customize Home, or pick here. Defaults are today\'s Music, Focus, Weather and Calendar.')
o(S,'Home','Home slot 4','menu','-','The widget in the fourth Home card.','missing','home.widget.4','choice',['Music', 'Focus', 'Weather', 'Calendar', 'Clock', 'World clock', 'Month', 'Agenda', 'Countdown', 'Note', 'Battery', 'Agents'],'Calendar','live','Click a card in Customize Home, or pick here. Defaults are today\'s Music, Focus, Weather and Calendar.')
o(S,'Home','Clock style','menu','-','Analog, digital, elastic or blue halo.','missing','home.variant.clock','choice',['Analog','Digital','Elastic','Blue halo'],'Analog','live','Home Clock widget.')
o(S,'Home','Music style','menu','-','Art, disc, cassette, wave or synced lyrics.','missing','home.variant.music','choice',['Art','Disc','Cassette','Wave','Lyrics'],'Art','live','Home Music widget.')
o(S,'Home','Weather style','menu','-','Summary, hourly curve, days, feels like or wind.','missing','home.variant.weather','choice',['Summary','Hourly curve','Days','Feels like','Wind'],'Summary','live','Home Weather widget.')
o(S,'Home','Calendar style','menu','-','Next event, month, week or agenda.','missing','home.variant.calendar','choice',['Next event','Month','Week','Agenda'],'Next event','live','Home Calendar widget.')
o(S,'Home','Home backdrop','picture cards','-','A quiet drawing behind the Home cards. Moves only while Home is open, and holds still with Reduce Motion.','missing','home.backdrop','choice',['None', 'Aurora', 'Fluted glass', 'Halftone', 'Ripple', 'Marble', 'Watercolor', 'Terrazzo', 'Sunset', 'Caustics', 'Cosmos', 'Low-poly', 'Matcha'],'None','live','Twelve procedural backdrops drawn in SwiftUI.')
o(S,'Home','World clock cities','text','-','Time zone names, separated by commas.','missing','home.worldClock.zones','text',[],'Europe/London, America/New_York, Asia/Tokyo','live','Home World clock widget.')
o(S,'Home','Countdown title','text','-','What the Countdown widget counts down to.','missing','home.countdown.title','text',[],'','live','Home Countdown widget.')
o(S,'Home','Countdown date','text','-','A day as 2026-12-25.','missing','home.countdown.date','text',[],'','live','Home Countdown widget.')
o(S,'Agent cards','Running card (Wave, Essentials)','segmented','Wave','Layout of the running-agent preview.','missing','appearance.runningCard','choice',['Wave','Essentials'],'Wave','live','Wave shows activity bars; Essentials keeps the compact status row.')
o(S,'Agents','Agent status icon (Glyphs, Lumi, Lumi Pixel, Creatures)','picture cards','Glyphs','Symbol or a character for each agent state.','partial','avatar.alwaysInNotch','toggle',[],'true','custom','ZEUS answer: the Mini ZEUS mascot (13 states) on General.')
o(S,'Notch behavior','Hide the notch automatically','toggle','on','Closes when the pointer leaves.','partial','notch.autoHide','toggle',[],'true','live','Off: it stays open until the shortcut or a click elsewhere.')
o(S,'Notch behavior','Delay before closing','menu','Short','How long it waits after the pointer leaves.','missing','notch.closeDelay','choice',['Instantly','0.5 s','1 s','2 s'],'0.5 s','live','the reference app closes about 0.53 s after the pointer leaves (private reference notes).')
o(S,'Notch behavior','Show the notch (hover dwell)','menu','On hover','How quickly hovering opens it.','partial','notch.openDelay','choice',['Fast','Normal','Relaxed'],'Normal','live','0.1 s, 0.25 s or 0.6 s.')
o(S,'Notch behavior','Show Zeus next to cursor','toggle','off','When summoned, Zeus anchors beside the mouse pointer instead of the notch.','missing','presence.nearCursor','toggle',[],'true','live','P0 item I. Offset 18 pt right and down from the pointer, clamped and flipped at screen edges, multi-display aware, 60 fps with a light spring; off keeps the notch/top-bar placement. Also in the menu bar menu and `zeus debug presence`.')
o(S,'Halo','Halo style','menu','Classic halo','The closed-notch glow while an agent works or needs you. One setting: the notch, Settings and the welcome guide all read it.','partial','halo.style','choice',['classic', 'pixelated', 'rayons', 'prisme', 'nimbus', 'lumiere', 'volumetric', 'bioluminescent', 'aurora', 'storm', 'off'],'classic','custom','Stable ids; titles come from ZeusCore.HaloStyle. Replaces the old topBar.halo key (migrated at launch).')
o(S,'Halo','Halo entrance','menu','Sweep','Animation as the halo lights up.','partial','halo.entrance','choice',['sweep', 'trace', 'blast', 'whiteFlash', 'hueSlide', 'hybrid', 'deflagration', 'shockwave', 'supernova', 'strobe', 'bigBang', 'ondulation', 'shimmer'],'sweep','custom','Stable ids; titles come from ZeusCore.HaloEntrance. Each has its own choreography.')
o(S,'Halo','Entrance intensity','slider','100 %','Strength of the entrance.','missing','halo.intensity','slider',[50,150,10],'100','live','Controls the halo entrance effects and live preview.')
o(S,'Halo','Entrance speed','slider','100 %','Speed of the entrance.','missing','halo.speed','slider',[50,200,10],'100','live','Scales the closed-notch entrance duration from 50 to 200 %.')
o(S,'Halo','Match the halo colour to the wallpaper','toggle','on','Blends with white on light wallpapers.','partial','halo.wallpaper','toggle',[],'true','live','Samples the wallpaper under the notch and blends the halo toward white as it gets lighter.')
o(S,'Halo','Halo arm width (Narrow, Medium, Wide, Extra wide)','segmented','Medium','76, 130, 220 or 440 pt each side.','missing','halo.armWidth','choice',['Narrow','Medium','Wide','Extra wide'],'Medium','live','Controls the closed-notch halo reach and live preview.')
o(S,'Halo','Light thickness','slider','100 %','100 to 200 %.','missing','halo.thickness','slider',[100,200,10],'100','live','Controls the closed-notch halo and live preview.')
o(S,'Halo','Light wave to the screen edges','toggle','on','A wave of light crosses the screen on agent events.','partial','halo.edgeWave','toggle',[],'true','live','A click-through overlay on every Space, left out of captures; fronts run round the screen edge.')
o(S,'Everyday lights','Light wave while music plays','toggle','on','Artwork-tinted wave on the closed notch.','has','topBar.musicWings','toggle',[],'true','custom','')
o(S,'Everyday lights','Progress outline on the music preview','toggle','on','Outline empties as the track plays.','missing','lights.musicProgress','toggle',[],'true','live','Tracks media progress around the music wings.')
o(S,'Everyday lights','React to real sound (live spectrum)','toggle','off','The music light follows the sound your Mac is playing.','missing','lights.liveSpectrum','toggle',[],'false','live','CoreAudio process tap of system output, listen only. Asks for System Audio Recording once, when this is turned on or the Waves tab opens. Runs only while music plays.')
o(S,'Everyday lights','Waves style (Bars, Wave, Mirror)','segmented','Bars','How the Waves tab draws the spectrum.','missing','waves.style','choice',['Bars','Wave','Mirror'],'Bars','live','Zeus addition. The Waves tab is off by default; add it in Settings > Appearance > Top bar tabs.')
o(S,'Everyday lights','Waves sensitivity','slider','100 %','How strongly the bars react to quiet sound.','missing','waves.sensitivity','slider',[50,200,10],'100','live','Zeus addition. A gain on the live band levels.')
o(S,'Everyday lights','Light sweep on copy','toggle','on','Confirms a copy was caught.','partial','lights.copy','toggle',[],'true','live','Gates the copy cue.')
o(S,'Everyday lights','Intake light when files land','toggle','on','Glow when files land on the shelf.','partial','lights.shelf','toggle',[],'true','live','Gates the shelf cue.')
o(S,'Everyday lights','Case-key lights (Caps Lock and Shift)','toggle','on','Caps Lock flashes the outline.','partial','lights.capsLock','toggle',[],'true','live','Caps Lock flash and the Shift-held-alone crest, both live (Shift needs Accessibility access).')
o(S,'Everyday lights','Shortcut peeks (cut, undo, save, print...)','toggle','on','Shows cards for command shortcuts. Requires Accessibility access.','missing','lights.shortcutPeeks','toggle',[],'false','live','Key monitoring waits until Accessibility access is granted in Settings > Permissions.')
o(S,'Everyday lights','Green gauge when plugged in','toggle','on','Charge level outline on power changes.','partial','lights.battery','toggle',[],'true','live','Gates charging and low-battery cues.')
o(S,'Everyday lights','Volume HUD in the notch','toggle','on','Level glow and wings when output volume changes.','live','lights.hud.volume','toggle',[],'true','live','CoreAudio listener; no permission needed.')
o(S,'Everyday lights','Brightness HUD in the notch','toggle','on','Level glow when built-in brightness changes.','live','lights.hud.brightness','toggle',[],'true','live','DisplayServices polling; keys accelerate when Accessibility is on.')
o(S,'Everyday lights','Keyboard backlight HUD','toggle','on','Level glow when keyboard illumination changes.','live','lights.hud.keyboard','toggle',[],'true','live','Skipped on Macs without a backlight.')
o(S,'Everyday lights','Mute pulse in the notch','toggle','on','Dim slash pulse when output is muted.','live','lights.hud.mute','toggle',[],'true','live','')
o(S,'Everyday lights','Replace macOS volume and brightness HUD','toggle','on','Needs Accessibility in Settings > Permissions. Without it, both HUDs can show.','live','lights.hud.replaceSystem','toggle',[],'true','live','CGEventTap consumes media keys when trusted.')
o(S,'Everyday lights','Screen-edge glow on volume, brightness and keyboard-backlight HUDs','toggle','on','A glow runs around every screen edge and joins the notch, filled to the level.','missing','lights.hud.screenEdge','toggle',[],'true','live','P0 item G. Click-through overlay above the menu bar on every display; fades in 120 ms, holds, fades out after about 1.2 s idle; respects Reduce Motion and Reduce Transparency.')
o(S,'Everyday lights','Ignore mic conflicts (debug)','toggle','-','For QA environments where Core Audio keeps reporting a stale recorder.','has','wake.ignoreMicConflicts','toggle',[],'false','stub','Item 6 (Hey Zeus). Never shown. Read only in DEBUG builds (WakeWordController); release builds always keep the call guard.')
o(S,'Everyday lights','Incoming rain alert','toggle','on','"Rain in X min" pill before a shower.','partial','lights.rain','toggle',[],'true','live','Uses hourly forecast timing; suppresses repeat alerts for three hours after a shower starts.')
o(S,'Everyday lights','Timer light gauge','toggle','on','Outline counts down a focus session.','partial','lights.timer','toggle',[],'true','live','Gates the closed focus wings.')
o(S,'Everyday lights','Purple glow while the mic listens','toggle','on','Glows with your voice during a spoken answer.','partial','lights.micGlow','toggle',[],'true','live','Gates the mic-listening glow while Zeus speaks.')
o(S,'Everyday lights','Glow when a reminder is added','toggle','on','Blue crests after you add a reminder.','missing','lights.reminderGlow','toggle',[],'true','live','Fires when ZEUS saves a reminder.')
o(S,'Everyday lights','Glow when an event is added','toggle','on','Cyan ribbon after you add an event.','partial','lights.eventGlow','toggle',[],'true','live','Fires when ZEUS adds an event: the Calendar page quick-add, or "add lunch with Ana tomorrow at 1 pm".')
o(S,'Everyday lights','Glow when AirDrop arrives','toggle','off','Blue intake glow and drops the file on the shelf.','missing','lights.airDrop','toggle',[],'false','live','Gated by Downloads folder access.')
o(S,'Everyday lights','Screenshot cue','toggle','off','Camera cue and shelf drop for new screenshots.','missing','lights.screenshot','toggle',[],'false','live','Gated by Desktop folder access.')

S='notifications'
o(S,'Agent notifications','Permission requests','toggle','on','Alert when an agent asks.','has','notify.approvals','toggle',[],'true','custom','')
o(S,'Agent notifications','Finished tasks','toggle','on','Alert when an agent finishes.','has','notify.agentDone','toggle',[],'true','custom','')
o(S,'Agent notifications','Errors and stuck agents','toggle','on','Alert when an agent fails or stalls.','missing','notify.errors','toggle',[],'true','live','Failed (Claude Code StopFailure, Codex error) and stalled agents get a red or amber halo and card; with this on they also send a macOS notification (when macOS allows ZEUS notifications) and a notch cue.')
o(S,'Agent notifications','Call an agent stalled after','menu','5 min','A working agent with no events for this long turns amber.','missing','notify.stallMinutes','choice',['2 min','5 min','10 min','15 min'],'5 min','live','Checked every 20 seconds.')
o(S,'System alerts','Show system notifications (app alerts in macOS)','toggle','on','ZEUS sends focused macOS banners while the notch is closed.','missing','notify.system','toggle',[],'false','live','Permission is requested only when you turn this on.')
o(S,'Other apps','Show notifications from other apps in the notch','toggle','off','Reads the local Notification Center store (Full Disk Access).','missing','notify.mirror','toggle',[],'false','custom','Open question Q4, labelled Coming.')
o(S,'Other apps','Replace system banners','toggle','off','Dismisses the macOS banner once shown in the notch.','missing','notify.replaceBanners','toggle',[],'false','live','Experimental auto-dismiss with Accessibility, gated per app.')
o(S,'Other apps','Auto-dismiss apps','text','','Apps whose system banners are auto-dismissed.','missing','notify.dismissApps','text',[],'','live','Bundle ids, comma separated.')
o(S,'Other apps','Muted apps (Unmute)','list','empty','Apps whose notifications are hidden.','missing','notify.mutedApps','text',[],'','custom','Bundle ids, comma separated; the Settings card lists apps seen in Notification Center with Mute and Unmute.')
o(S,'Other apps','Peek new notifications under the notch','toggle','on','A slim line for about four seconds; click opens the app.','missing','notify.peek','toggle',[],'true','live','Needs the mirror above.')
o(S,'Other apps','Show details in the peek','toggle','on','Off shows only the app name. Meeting mode hides details regardless.','missing','notify.peekDetails','toggle',[],'true','live','')

S='sounds'
o(S,'Sound feedback','Sound feedback','toggle','on','Master switch for every cue.','has','sound.on','toggle',[],'true','custom','')
o(S,'Sound categories','Run start sound (style + preview)','menu + play','Classic','When an agent starts.','missing','sound.startStyle','choice',['Off','Classic','Spaceship Futuristic','Mystery Game','Tap'],'Classic','live','Zeus synthesized sounds (tools/sounds/make_sounds.py).')
o(S,'Sound categories','Requests sound (style + preview)','menu + play','Classic','When an agent needs you.','partial','sound.approvalStyle','choice',['Off','Classic','Notebook','Game Alert','Weard Permission','Weard 2 Permission','Short Warning'],'Classic','live','')
o(S,'Sound categories','Your answer sound (style + preview)','menu + play','Futuristic 1','When you approve or deny.','missing','sound.answerStyle','choice',['Off','Futuristic 1','Futuristic 2'],'Futuristic 1','live','')
o(S,'Sound categories','Completion chime (style + preview)','menu + play','Success','When a task completes.','partial','sound.doneStyle','choice',['Off','Success','Gentle','Spark'],'Success','live','')
o(S,'Sound categories','Dictation sounds','toggle','on','Cue when recording starts and ends.','has','dictation.sounds','toggle',[],'true','custom','')
o(S,'Sound categories','Timer alarms','toggle','on','Sound when a focus round ends.','missing','sound.timer','toggle',[],'true','live','')
o(S,'Sound categories','Ambient loop while an agent works','toggle','off','A quiet looping sound under a running agent.','missing','sound.runningLoop','toggle',[],'false','live','Zeus addition. Plays the bundled running loop at half volume while any agent is working; fades out when none is.')
o(S,'Sound categories','Failure sound','toggle','on','A short sound when an agent turn fails.','missing','sound.failure','toggle',[],'true','live','Plays the Failure sound when a session turns red (rate limit, auth or API error).')

S='voice'
o(S,'Voice answer','Listen for approval keywords','toggle','off','Say a keyword to answer a permission card. The microphone opens only while a card is waiting. Off until you turn it on.','partial','voice.answers','toggle',[],'false','live','Opt-in: it opens the microphone. ZEUS also answers out loud (Answers card).')
o(S,'Voice answer','Speak replies','toggle','-','Zeus reads answers aloud with the Ultron voice.','missing','voice.speakReplies','toggle',[],'true','live','')
o(S,'Your keywords','Approve keywords','text','ok, yes','Comma separated; the last word counts.','missing','voice.approveWords','text',[],'ok, yes, approve, allow','live','')
o(S,'Your keywords','Deny keywords','text','no','Comma separated.','missing','voice.denyWords','text',[],'no, deny, stop','live','')
o(S,'Your keywords','Open the app keywords','text','open','Comma separated.','missing','voice.openWords','text',[],'open, show me','live','')
o(S,'Your keywords','Reset the default words','button','-','Restores the keywords.','missing','voice.resetWords','action',[],'','live','')

S='dictation'
o(S,'Local dictation','Enable local dictation','toggle','off','Dictate into any text field.','has','dictation.enabled','toggle',[],'true','custom','')
o(S,'Local dictation','On-device model (download, repair, status)','status + button','Not installed','630 MB model for private transcription.','partial','dictation.model','status',[],'','live','ZEUS uses Apple on-device speech: no download.')
o(S,'Your shortcut','Dictation shortcut (Fn, modifier, pair)','recorder','Fn','Key to hold or press.','has','dictation.key','choice',[],'','custom','')
o(S,'Your shortcut','Shortcut behavior (Hold to speak, Press to start and stop)','segmented','Hold to speak','How the key works.','partial','dictation.behavior','choice',['Hold to speak','Press to start and stop'],'Hold to speak','live','Press toggles recording when dictation has a dedicated key; the shared talk key keeps hold/double-tap behavior.')
o(S,'Language and feedback','Dictation language (Automatic + list)','menu','Automatic','Language to transcribe.','partial','dictation.language','choice',['Automatic','English (US)','English (UK)','Portuguese (Brazil)','French','Spanish','German','Persian'],'Automatic','live','Selected locale is passed to Apple Speech and Whisper; Parakeet uses a script hint where supported.')
o(S,'Language and feedback','Play dictation sounds','toggle','on','Start and stop cues.','has','dictation.sounds','toggle',[],'true','custom','Same switch as Sounds.')
o(S,'History','Dictation history (search, clear)','list','on','Saved only on this Mac.','has','dictation.keepDays','status',[],'','custom','')
o(S,'History','Copy last dictation','button','-','Copies the last result.','missing','dictation.copyLast','action',[],'','live','')
o(S,'History','Third-party licenses','button','-','Model licences.','missing','dictation.licenses','action',[],'','live','Apple speech: no third-party model. Opens About.')

S='shortcuts'
o(S,'Global shortcut','Open the agent picker (Control Option Space)','toggle','on','Arrows pick a session, Return opens, Esc closes.','partial','shortcut.openNotch','choice',[],'','custom','ZEUS: a preset menu for opening the notch.')
o(S,'Answer from the keyboard','Answer permissions from the keyboard (Control Option Y, N, O)','toggle','on','Approve, deny or open, live only while a request waits.','missing','shortcut.answerKeys','toggle',[],'true','live','Registered only while a card is waiting.')

S='integrations'
o(S,'Available apps','Offer Claude Code for new chats','toggle','on','Shows it in New chat.','missing','integrations.offerClaude','toggle',[],'true','live','Chat > New chat lists Claude Code only when on.')
o(S,'Available apps','Offer Codex for new chats','toggle','on','Shows it in New chat.','missing','integrations.offerCodex','toggle',[],'true','live','Chat > New chat lists Codex only when on.')
o(S,'Connections','Claude Code connection (connect, repair, check again)','status + buttons','auto','Hooks for activity and approvals.','has','integrations.claude','status',[],'','custom','')
o(S,'Connections','Codex connection (connect, validate, repair)','status + buttons','-','Activity follows local logs; the hook adds immediate approvals.','missing','integrations.codex','status',[],'','live','Hook installation is managed under General > Other agents.')
o(S,'Connections','Antigravity (event-driven plugin)','status','auto','Native plugin, no polling.','missing','integrations.antigravity','status',[],'','live','Detects the app. TODO: plugin.')

S='permissions'
o(S,'Access status','Accessibility','status + button','-','Shortcuts, keys and agent actions.','has','perm.accessibility','status',[],'','custom','')
o(S,'Access status','Location','status + button','-','Local weather and rain alerts.','missing','perm.location','status',[],'','live','ZEUS uses a typed city, so this stays optional.')
o(S,'Access status','Calendar','status + button','-','Events and video calls.','partial','perm.calendar','status',[],'','live','')
o(S,'Access status','Reminders','status + button','-','Read, create and complete tasks.','partial','perm.reminders','status',[],'','live','')
o(S,'Access status','Notifications (app alerts)','status + button','-','Agent banners.','missing','perm.notifications','status',[],'','live','')
o(S,'Access status','Full Disk Access','status + button','-','Notifications from other apps.','missing','perm.fullDisk','status',[],'','live','Only needed for the mirror (Q4).')
o(S,'Access status','Mic and speech recognition','status + button','-','Voice answers and interview.','has','perm.mic','status',[],'','custom','')
o(S,'Access status','Screen and system audio','status + button','-','Interview transcription.','has','perm.screen','status',[],'','custom','')
o(S,'Access status','Media control (automation per app)','status','asked when needed','Music, Spotify and browsers ask on first use.','missing','perm.automation','status',[],'','live','')
o(S,'Trusted chats','Trusted chats (stop trusting, clear all)','list + buttons','none','Chats auto-approved except sensitive commands, cleared on quit.','missing','perm.trustedChats','status',[],'','custom','Allow this whole chat on an approval card; high-risk commands still ask. Memory only.')

S='privacy'
o(S,'Notification details','Show project and command details','toggle','on','Off hides commands and project names outside the notch.','missing','privacy.details','toggle',[],'true','live','Off, or Meeting mode active: approval cards hide the command.')
o(S,'Usage data','Help improve (anonymous usage counts)','toggle','on','Daily anonymous counts.','has','privacy.analytics','status',[],'','live','ZEUS sends nothing; shown as a fact, not a switch.')
o(S,'Music metadata','Synced lyrics (LRCLIB)','toggle','off','Sends title and artist to lrclib.net.','missing','privacy.lyrics','toggle',[],'false','live','Fetches time-synced lyrics from lrclib.net (title, artist, album, duration; no key), cached on disk. Lyrics button on the Music page and a Lyrics Home music style. Off by default as it sends data.')
o(S,'Access','Open Accessibility settings','button','-','Jumps to System Settings.','has','privacy.openAccessibility','action',[],'','live','')

S='interview'
o(S,'AI provider','Provider and model','menus','-','Which AI writes the suggestions.','missing','interview.provider','choice',['Claude (local CLI)','None'],'Claude (local CLI)','stub','Copilot is Q3. No keys stored by ZEUS.')
o(S,'AI provider','API key (save, delete, test the connection)','field + buttons','-','Key in the keychain.','missing','interview.key','status',[],'','stub','ZEUS needs no key: it uses the CLIs on this Mac.')
o(S,'Candidate context','Candidate context','text','empty','CV, role, strengths for tailored answers.','missing','interview.context','text',[],'','stub','Stored locally for Q3.')
o(S,'Candidate context','Offer a suggestion automatically','toggle','off','Suggests without asking.','missing','interview.autoSuggest','toggle',[],'false','stub','Q3.')
o(S,"Interviewer's voice",'Capture and transcribe system audio (Deepgram)','toggle + key','off','Cloud transcription of the other person.','missing','interview.systemAudio','toggle',[],'false','stub','Q3. Would be on-device in ZEUS.')
o(S,'Screen sharing','Hide from screen sharing','toggle','auto in meetings','Leaves shares and recordings.','has','interview.hide','toggle',[],'false','custom','')

S='iPhone'
o(S,'Pairing','Connect an iPhone (pairing code, new code, disconnect)','QR + buttons','-','End-to-end encrypted pairing.','missing','iphone.pair','status',[],'','custom','Stub with design note: needs the iPhone app (Q6).')
o(S,'While agents work','Keep the Mac from sleeping','toggle','off','Same as General.','missing','general.keepAwake','toggle',[],'false','custom','Shares the General switch.')
o(S,'Local connection','Restart the local connection','button','-','Restarts the relay.','missing','iphone.restart','action',[],'','stub','Q6.')

S='diagnostics'
o(S,'Status','Connection status (Connected, Offline)','status','-','Daemon reachable.','has','diag.socket','status',[],'','custom','')
o(S,'Status','Tracked agents','list','-','Agents that sent events.','missing','diag.agents','status',[],'','live','')
o(S,'Logs','Flight recorder: the last 2,000 app events','list','-','Voice steps, notch cues, agent events and errors, kept in memory with secrets removed.','missing','diag.logs','status',[],'','custom','Zeus addition. Filter by kind, copy the log.')
o(S,'Logs','Export diagnostics','button','-','A zip of the logs, a settings snapshot with secrets masked and the app version, saved to the Desktop or a chosen folder.','missing','diag.export','action',[],'','custom','Written by ZeusCore.DiagnosticsExporter (ditto).')
o(S,'Recovery','Restart the daemon','button','-','Running tasks stay in their apps.','missing','diag.restart','action',[],'','live','Restarts the agent socket.')

S='license'
o(S,'License','Activate a license, key, buy, trial status','field + buttons','trial','Paid licence.','missing','license','status',[],'','custom','Trial countdown, offline Ed25519 key check, Keychain, deactivate to move Macs. No payment provider; gating off (Entitlements).')

S='assistant'
o(S,'Visual explanation','Enable visual explanations','toggle','off','Explain and edit diagrams in Chat with optional on-device narration. No capture starts automatically.','missing','explanation.enabled','toggle',[],'false','live','Native opt-in Chat surface; requires an explicitly configured Any LLM endpoint. Physical-device acceptance remains pending.')
o(S,'Visual explanation','Spoken request shortcut','menu','Command-Shift-Space','Active only inside the visual explanation window. Hold the native Speak control for push-to-talk.','missing','explanation.shortcut','choice',['Command-Shift-Space','Command-Shift-V'],'Command-Shift-Space','live','No global keyboard monitoring or Accessibility permission is required for this shortcut.')
o(S,'Desktop pointing','Enable desktop pointing','toggle','on','Hold the pointing keys, ask about what is under your pointer, and Zeus rings it and answers aloud. Nothing is captured until you hold the keys.','missing','pointing.enabled','toggle',[],'true','live','On by default (owner decision, docs/FIRST-RUN-DEFAULTS.md). Needs your own Input Monitoring or Accessibility grant to see the keys, and Screen Recording to place marks. Zeus never prompts for these.')
o(S,'Desktop pointing','Pointing keys','menu','Control-Option','Control-Option is also the Talk to Zeus key: one hold is one Zeus turn that speaks in the Zeus voice and can point at the screen. Pick Right Option or Fn for a separate pointing turn that draws while held.','missing','pointing.shortcut','choice',['Control-Option','Right Option','Fn (Globe)'],'Control-Option','live','One hold, one turn (docs/VOICE-KEY.md). Control and Option is VoiceOver\'s modifier: while VoiceOver is on, Talk to Zeus moves to Option + Command and pointing on Control-Option pauses.')
o(S,'Desktop pointing','Draw while held','toggle','on','While you hold the pointing keys, your pointer leaves a trail on the screen and Zeus sees it. Clicks always reach your apps. Off: no trail is drawn; Zeus still follows the pointer.','missing','pointing.drawWhileHeld','toggle',[],'true','live','Owner decision 2026-11-10. Drawing needs no Screen Recording permission; the ink is a Zeus overlay that is removed when you let go.')
o(S,'Desktop pointing','Send a screenshot with each question','toggle','off','Off: Zeus asks the model using only what is under your pointer. On: the display under your pointer is sent to the provider you picked, once per question, and never saved.','missing','pointing.sendScreenshot','toggle',[],'false','live','Separate consent from the macOS Screen Recording permission.')
o(S,'Desktop pointing','Provider','menu','Auto','Auto uses the first provider with a saved key that responds, preferring the fastest it has measured this session.','missing','pointing.provider','choice',['Auto','Anthropic + ElevenLabs','OpenAI','Zeus setup'],'Auto','live','Keys come from the Keychain only. Latency numbers stay in memory.')
o(S,'Desktop pointing','Double-tap Control to type a question','toggle','off','Two quick taps on Control open a small box to type a question about what is under your pointer. Off by default.','missing','pointing.textEntry','toggle',[],'false','live','macOS Dictation can also use "Press Control key twice" (System Settings, Keyboard). If both are on, both fire. Turn one off.')
o(S,'Desktop pointing','Use Fn+Control for dictation','toggle','off','Sets the dictation key to Fn+Control. Turning it off puts your previous dictation key back.','missing','pointing.dictationFnControl','toggle',[],'false','live','Off by default. Fn (Globe) alone is used by macOS for emoji and Dictation; check System Settings, Keyboard.')
o(S,'Account','ChatGPT account, model, reasoning effort, speed','sign-in + menus','-','Assistant on your ChatGPT plan.','missing','assistant.provider','choice',['Claude CLI','OpenAI','Anthropic'],'Claude CLI','custom','Bring your own key (OpenAI, Anthropic, ElevenLabs) in the Keychain, model picker. ChatGPT sign-in is Coming: needs an OAuth backend.')
o(S,'Model','Model','menu','-','Selected chat model for the chosen provider.','missing','assistant.model','choice',[],'Claude Code default','custom','Provider-specific model picker on the Assistant settings page.')
o(S,'Behaviour','Double Command replies, Right Command hold to speak','toggles','-','Drafts a reply from the conversation.','partial','assistant.doubleCommand','toggle',[],'false','stub','Hold-to-speak is the ZEUS talk key. Reply drafting TODO with the chat on devon/claude.')


S='integrations'
o(S,'Beamer','Beamer: start when Zeus starts','toggle','-','Opens Beamer hidden in the menu bar when Zeus starts.','missing','beamer.autoStart','toggle',[],'false','live','Zeus addition. Beamer\'s own start-at-login switch is inside Beamer.')
o(S,'Beamer','Beamer: light the notch when control crosses','toggle','-','A Zeus cue when your keyboard and mouse move to another machine.','missing','beamer.cue','toggle',[],'true','live','Zeus addition. Reads Beamer\'s menu bar status (Accessibility).')

S='voice'
o(S,'Fast path','Fast path (instant commands)','toggle','-','Simple commands run the moment you finish speaking; off sends everything to the AI.','missing','fastPath.enabled','toggle',[],'true','live','Zeus addition. Jev is on the Engine page.')
o(S,'Hey Zeus','Listen for "Hey Zeus"','toggle','-','Say it, then your request. Off until you turn it on.','missing','voice.heyZeus','toggle',[],'false','custom','Zeus addition. Hand-built card on Voice. Stored under wake.enabled (default off).')
o(S,'Talk to Zeus','Talk shortcut','recorder','-','Hold Control + Option to talk, let go to send. Point at something while you hold and Zeus sees what you mean.','missing','voice.talkKey','choice',[],'','custom','Zeus addition. Recorder on Shortcuts. Earlier auto-written defaults move to Control + Option once; a key you record is kept.')
o(S,'Voice','Personality (Ultron or Plain) and Design voice','menu','-','How Zeus sounds and what it calls itself.','missing','voice.personality','choice',['Ultron','Plain'],'Ultron','custom','Zeus addition. Voice page.')
o(S,'Dictation','Murmure speech engines','menu','-','Which speech recognition writes your words.','missing','dictation.engine','choice',[],'','custom','Zeus addition. Murmure page.')

S='keepAwake'
o(S,'Insomnia','Insomnia (lid-closed mode)','toggle','-','Keep agents working with the lid closed.','missing','insomnia.lidClosed','toggle',[],'false','custom','Zeus addition. Insomnia page.')

S='teleprompter'
o(S,'Teleprompter','Follow my presentation','toggle','-','Opens the prompter when a slideshow starts.','missing','prompter.followPresentation','toggle',[],'false','custom','Zeus addition. Features page; stored under the prompter key.')
o(S,'Teleprompter','Advance slides when I finish their notes','toggle','-','Voice-follow moves to the next slide.','missing','prompter.followAdvances','toggle',[],'false','custom','Zeus addition. Features page.')
o(S,'Teleprompter','Hide the prompter from screen sharing','toggle','-','You see it; shares do not.','missing','prompterWindow.private','toggle',[],'true','custom','Zeus addition. Features page.')

S='agents'
o(S,'Browser agent','Let Zeus work in Chrome','toggle','-','Web tasks, step by step, with a card you can stop.','missing','browserAgent.enabled','toggle',[],'true','live','Zeus addition.')
o(S,'Browser agent','Most steps per task','menu','-','Where a web task stops and tells you.','missing','browserAgent.maxSteps','choice',['10','15','25','40','60'],'25','live','Zeus addition.')
o(S,'Browser agent','Always ask before','text','-','Extra words that always show an approval card.','missing','browserAgent.alwaysAsk','text',[],'','live','Zeus addition. Added to the built-in list (buy, send, delete, post...).')
o(S,'Browser agent','Browser for the agent','menu','-','Your own Chrome through the ZEUS extension, or a separate browser (browser-use) with its own profile.','missing','browserAgent.backend','choice',['Your Chrome','Separate browser (browser-use)'],'Your Chrome','live','Zeus addition. The separate one needs the Set up button once; `zeus browse --separate` forces it for one task.')
o(S,'Browser agent','Allowed sites (separate browser)','text','-','Sites the separate browser may open, separated by commas. Empty means any site.','missing','browserAgent.allowedDomains','text',[],'','live','Zeus addition. Passed to browser-use as BROWSER_USE_ALLOWED_DOMAINS and checked before every open.')
o(S,'Scribe','When a meeting starts','menu','-','Off, ask first, or start notes on its own when a call or calendar meeting begins.','missing','scribe.autoStart','choice',['Off','Ask me','Start automatically'],'Ask me','live','Zeus addition. Settings > Features > Scribe. Start automatically needs Microphone to be allowed already; otherwise Zeus asks. Never prompts for permission.')
o(S,'Coding','Default coding agent','menu','-','Claude Code, Codex, Gemini or Cursor Agent.','missing','code.tool','choice',['Claude Code','Codex','Gemini','Cursor Agent'],'Claude Code','custom','Zeus addition. Stored under the code.tool key.')
o(S,'Coding','Terminal app','menu','-','Automatic, Ghostty, iTerm, Warp or Terminal.','missing','code.terminal','choice',['Automatic','Ghostty','iTerm','Warp','Terminal'],'Automatic','custom','Zeus addition. Stored under the code.terminal key.')
o(S,'Research','Research depth','menu','-','Quick or Deep when you do not say deep research.','missing','research.depth','choice',['Quick','Deep'],'Quick','live','Zeus addition.')
o(S,'Research','Save reports in','text','-','A folder for research reports.','missing','research.folder','text',[],'','live','Zeus addition. Empty keeps the second brain, else Documents/Zeus Research.')
o(S,'Models','Models Zeus uses (read-only)','status','-','Which model each engine uses, never above Haiku or Sonnet.','missing','models.caps','status',[],'','custom','Zeus addition. Read-only display of ModelCap.')
o(S,'Drive','When Zeus may drive your Mac','menu','-','How much Zeus may do on its own on your Mac.','missing','privacy.driveAutonomy','choice',['Always ask','Safe steps alone','Trusted'],'Safe steps alone','custom','Zeus addition. Privacy page; stored under drive.autonomy.')
o(S,'Drive','Move the system pointer','toggle','-','Drive mode may glide and click with CGEvent when Accessibility cannot.','missing','present.physicalPointer','toggle',[],'false','live','L5. Off by default. Key present.physicalPointer.')

SECTION_TITLES={'general':'General','appearance':'Appearance','notifications':'Notifications','sounds':'Sounds','voice':'Voice','dictation':'Dictation','shortcuts':'Shortcut','topBar':'Top Bar','integrations':'Integrations','permissions':'Permissions','privacy':'Privacy','interview':'Interview','iPhone':'iPhone','diagnostics':'Diagnostics','about':'About','license':'License','assistant':'Assistant','keepAwake':'Keep awake','teleprompter':'Prompter','agents':'Agents'}

def swift_str(s): return json.dumps(s, ensure_ascii=False)

def validate_table():
    """Generation must not turn passive settings into implicit capture or input."""
    by_id = {}
    for row in R:
        if row[11] != 'excluded':
            by_id.setdefault(row[7], row)  # Same first-row-wins rule as write_swift.
    opt_in = ('voice.answers', 'voice.heyZeus', 'wake.ignoreMicConflicts',
              'lights.liveSpectrum', 'general.showInScreenSharing',
              'present.physicalPointer', 'explanation.enabled',
              'pointing.sendScreenshot', 'pointing.textEntry', 'pointing.dictationFnControl')
    for key in opt_in:
        row = by_id.get(key)
        if row is None or row[8] != 'toggle' or row[10] != 'false':
            raise ValueError(f'{key} must remain an explicit opt-in with a false default')
    if by_id['wake.ignoreMicConflicts'][11] != 'stub':
        raise ValueError('wake.ignoreMicConflicts must remain hidden from release settings')

def write_swift(path):
    validate_table()
    lines=['// Generated by scripts/gen-settings-catalog.py. Edit the table there, then run it again.','// Option names follow a reference app settings (studied, not copied); behaviour is ours.','','enum SettingsCatalog {','    static let all: [SettingOption] = [']
    seen=set()
    for (sec,grp,gl,gc,gd,does,before,zid,kind,choices,zdef,state,note) in R:
        if state=='excluded' or zid in seen: continue
        seen.add(zid)
        rng='nil'; ch='[]'
        if kind=='slider': rng=f'SettingOption.Range(min: {choices[0]}, max: {choices[1]}, step: {choices[2]})'
        elif choices: ch='['+', '.join(swift_str(c) for c in choices)+']'
        title=gl.split(' (')[0] if kind!='choice' or '(' not in gl else gl.split(' (')[0]
        lines.append(f'        SettingOption(id: {swift_str(zid)}, section: .{sec}, group: {swift_str(grp)}, title: {swift_str(title)}, note: {swift_str(does)}, kind: .{kind}, choices: {ch}, range: {rng}, defaultValue: {swift_str(zdef)}, state: .{state}, todo: {swift_str(note)}),')
    lines += ['    ]','}','']
    with open(path, 'w', encoding='utf-8') as output:
        output.write('\n'.join(lines))

def write_md(path):
    validate_table()
    n=len(R); exc=sum(1 for r in R if r[11]=='excluded')
    matched=sum(1 for r in R if r[11] in ('live','custom','stub'))
    live=sum(1 for r in R if r[11] in ('live','custom'))
    before={k:sum(1 for r in R if r[6]==k) for k in ('has','partial','missing')}
    out=['# a reference app settings inventory','',
         'Source: a reference app (build 26) from app-71mb.dmg, studied on the box: the fr and es `Localizable.strings` (1,644 keys; the en table is intentionally empty because the English copy lives in code), `Info.plist` usage strings, `strings` on the binary (defaults keys such as `notchpilot.lyrics.enabled`, `notchpilot.notifications.replaceSystem`, `notchpilot.notifications.mutedApps`, `haloStyle`, `cardStyle`, `avatarStyle`, `haloThickness`, `armWidthSetting`, `rainAlertEnabledKey`, `focusMinutes`, `keepAwake`, `inMeeting`) and the 14 `settings-glass-*` sidebar icon names. No code or assets were copied; Zeus draws its own UI and uses macOS system sounds.','',
         'Sidebar (the reference app order): General, Appearance, Notifications, Sounds, Voice, Dictation, Shortcut, Integrations, Permissions, Privacy, Interview, iPhone, Diagnostics, License. The Assistant (ChatGPT sign-in) strings exist but have no sidebar icon in 0.3.1.','',
         f'**Coverage:** {matched} of {n} the reference app options are in Zeus Settings with a matching control ({matched*100//n}% of all, {matched*100//(n-exc)}% of the {n-exc} in scope). {live} are wired to real behaviour ({live*100//n}%). {matched-live} are labelled stubs with a TODO. {exc} are excluded.','',
         f'**Before this round:** has {before["has"]}, partial {before["partial"]}, missing {before["missing"]}.','',
         'Status key: **live** wired this round, **custom** an existing hand-built Zeus row, **stub** stored, exported and labelled "Coming" with a TODO, **excluded** not built on purpose.','']
    cur=None
    for (sec,grp,gl,gc,gd,does,before_,zid,kind,choices,zdef,state,note) in R:
        if sec!=cur:
            cur=sec; out += ['',f'## {SECTION_TITLES[sec]}','','| Group | Reference option | Control | Reference default | What it does | Zeus before | Zeus now | Zeus id | Note |','|---|---|---|---|---|---|---|---|---|']
        out.append(f'| {grp} | {gl} | {gc} | {gd} | {does} | {before_} | {state} | `{zid}` | {note} |')
    out += ['','## Zeus additions beyond the reference app','','- Search box in the Settings sidebar (every option, section titles and notes; Return opens the first hit).','- Live preview card on Appearance (halo style, arm width, thickness and cues drawn as you change them).','- Reset this section to defaults (header button on every page).','- Export and import all settings as JSON (General).','- Keyboard navigation: Up and Down move between sections, Command F focuses search, Escape clears it.','- Sections the reference app does not have: Top Bar (tab order, weather city and units), the To-do quick-add shortcut, second-brain rows.','']
    with open(path, 'w', encoding='utf-8') as output:
        output.write('\n'.join(out))
    print(f'options {n} matched {matched} live {live} stub {matched-live} excluded {exc}')

if __name__=='__main__':
    write_swift(sys.argv[1]+'/Sources/Zeus/App/SettingsCatalog.swift')
    write_md(sys.argv[2])
