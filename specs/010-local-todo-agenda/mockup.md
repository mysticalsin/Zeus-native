# Mock-up: tasks and agenda inside the notch

Open `mockup.html` in a browser. It is a static drawing of the open notch. It is not the app, and this branch does not show it in Zeus.

The panel is the existing top bar: 870 pt wide, the tab row, then the tall page (236 pt). To-do and Agenda sit in that page. There is no second window, no title bar, and no new tab.

The names in the populated state are made up: oat milk, notes, a standup, an offsite. They are not anyone's tasks.

## States

| State | What the page says |
| --- | --- |
| Off | Zeus's own list stays. A quiet line says Microsoft tasks are off. Agenda says to turn the setting on. |
| Permission needed | macOS will ask to read Calendars and Reminders. The drawing has no button that grants access. |
| Denied | The lists stay closed. The way back is System Settings. Zeus does not ask again from the page. |
| Loading | The word Loading. A thin bar moves only when Reduce Motion is off. |
| Empty | Nothing due, and nothing on today's agenda. |
| Populated | Two tasks and two events, with due and time in the same type size as the existing rows. |
| Error | The read failed. The lists already on the Mac are unchanged. |
| App missing | Two readings of the same phase: neither Microsoft app is installed, or Outlook is installed but its account is not in the Mac's calendars. |

## Type and colour

The drawing uses Palatino and Georgia, and the notch colours already in Zeus: `#0E1116`, `#E9EDF2`, `#A3ADB8`, `#8B5CF6`, `#FF8A3D`, `#3CCB7F`. Times are tabular. The app itself keeps its licensed text styles. This file does not embed them.

## Reduce Motion

The loading bar is the only motion. Under `prefers-reduced-motion: reduce` the bar holds still and the word Loading remains. Nothing slides, scales, or fades between states. In the app, a state change replaces the text immediately.

## VoiceOver

Each drawing is a group whose label is the state name plus "To-do and Agenda". Task rows are a list. Event rows are a list. The permission drawing is text, not a control, so it is not announced as a button. Status is in the text, not in colour alone: Overdue is the word Overdue, and a failed read says it failed.

When this is wired, focus stays in the open notch. Turning the feature on moves VoiceOver to the new status line. A denied or missing state does not trap focus. The system permission sheet is macOS's, and Zeus does not speak over it.

## Not in this branch

No SwiftUI view reads these states. The follow-up is in `spec.md`.
