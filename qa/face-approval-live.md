# Live face-approval check

Tony runs this on his Mac, with his own face, after the Wave 2 face tests exist. An agent does not run it and does not fill the result lines.

The camera permission must already be Tony's own choice. This script does not click a permission prompt.

## Before

- The face-approval setting is off. Confirm an approval still uses Touch ID or the existing card, and the camera stays off.
- Turn the setting on. Confirm the only new prompt is the camera, and that the explanation matches the onboarding sentence.
- Enrol in more than one pose. Confirm no image file appears in the repo, the home folder's Zeus logs, or a screenshot tool.

## Cases

1. Genuine: look at the camera and approve. Expect one approval and no password field.
2. Impostor: another person, or Tony after the template is deleted. Expect a refuse and the Touch ID fallback.
3. Photo or screen: hold a still photo or a playing video up to the camera. Expect a refuse.
4. Low light, then ordinary light.
5. Stand far, then near.
6. Cover the camera. Expect the covered-camera sentence, not a success.
7. Deny the camera permission. Expect the denied sentence and Touch ID.
8. Wait out the timeout. Expect the timeout sentence and Touch ID.
9. Fail until the lockout. Expect no further approval until the lock ends.
10. Turn the kill switch off. Expect the camera to stop and the next face attempt to refuse.

## Write down

For each case: pass or fail, the sentence shown, and whether Touch ID was offered. Do not write a template, a score vector, or a picture.

False-accept and false-reject counts are not filled here. Those come from the fixture run in `specs/004-notch-parity/checklist.md`.

## Result

Not run.
