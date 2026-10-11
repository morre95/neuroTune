# neuroTune app icon

The user selected concept 1, **Resonance**: a mint sound wave within two circular
arcs on a dark teal background.

- `resonance.png`: approved original, used for legacy launcher icons.
- `resonance-foreground.png`: transparent foreground extracted with built-in
  imagegen for adaptive and themed icons.
- `prompts.json`: generation and background-extraction prompts.
- `preview.png`: legacy, circular adaptive, and themed previews.

Regenerate all five Android density variants with ImageMagick 7:

```bash
bash scripts/generate-app-icons.sh
```

Adaptive layers are 108 dp. The foreground source occupies the central 80 dp,
keeping the visible mark inside the 66 dp safe area. The background is `#183A3B`.
Android 26+ uses adaptive icons; Android 33+ also receives a monochrome layer
whose alpha silhouette is tinted by the launcher. Earlier devices use legacy
PNGs. The manifest continues to reference `@mipmap/ic_launcher`.

Sizing follows the [Android adaptive icon documentation](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).
