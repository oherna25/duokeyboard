# duokeyboard

A one-handed keyboard for the iPhone Duo's 5.4″ outer screen. That screen is 77 × 112 mm, about 12 mm wider than an iPhone 18 Pro. So a thumb on one edge can't reach keys on the far edge of the stock keyboard.

This repo holds only a throwaway prototype for now. The real keyboard will be a Swift keyboard extension.

## Prototype

`prototype/index.html` is one HTML file with no build step. Open it in a browser.

It compares four layouts against a model of thumb reach:

| Layout | What it does |
| --- | --- |
| Stock width | The full-width keyboard, as a baseline. |
| Reachability | Slides the whole screen sideways, like Apple's iOS 27.3 beta feature. |
| Slide to thumb | A narrower QWERTY that you drag toward your thumb. |
| Thumb arc | QWERTY rows bent around the base of the thumb. |

On a screen 600 points wide or narrower, such as the folded Duo, the page opens at real size, 6.04 points per mm. On wider screens it shows a scaled model with controls for grip height, thumb reach and keyboard position. Each layout keeps its own typing trials, recording words per minute and corrections.

## Current findings

The reach model assumes a 72 mm thumb reach. It is a model, not a measurement of real hands.

- Stock width reaches 24 of 31 keys.
- Reachability never does better than stock. Sliding the screen brings far keys into reach and pushes near keys off the edge.
- Slide to thumb reaches all 31 keys at 59 mm wide, 7 mm in from the edge and lifted 9 mm, with 5.1 mm letter keys.
- Thumb arc reaches every key but covers 89% of the outer screen, so it hides the text you type.

Slide to thumb is the direction for the Swift build, pending typing trials on a real device.
