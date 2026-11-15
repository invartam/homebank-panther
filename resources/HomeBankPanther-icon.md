# Icône HomeBank Panther

Créée le 15 novembre 2026 avec l’outil intégré `image_gen`.

- `HomeBankPanther-icon.png` : image originale 1254 × 1254 pixels, fond transparent.
- `HomeBankPanther.icns` : déclinaisons classiques 16, 32, 48 et 128 pixels, avec masques alpha ; blocs `is32/s8mk`, `il32/l8mk`, `ih32/h8mk` et `it32/t8mk`.

Les petites tailles sont redimensionnées depuis le PNG. Le fichier ICNS utilise les blocs classiques plutôt que les blocs PNG modernes produits par défaut par `iconutil`. Depuis la version 0.6.1, le Makefile copie ce fichier dans le bundle et `CFBundleIconFile` le déclare comme icône de l’application.

Validation : décodage par `sips` et `iconutil` sur le Mac récent, puis chargement et génération d’une représentation TIFF avec Cocoa dans la VM OS X 10.3.9 : `Panther ICNS decode: OK; size 128x128`.

## Prompt de génération

```text
Use case: stylized-concept. Asset type: production desktop application icon for HomeBank Panther, a native personal-finance application for Mac OS X 10.3 PowerPC. Create ONE square icon with a genuinely transparent background. Subject: an elegant small classical bank building, strong triangular pediment, three chunky ivory-white columns, deep sapphire and aqua-blue glass architecture, a subtle warm gold coin integrated near the base to suggest personal budgeting. Early-2000s Mac OS X Aqua icon aesthetic: carefully rendered dimensional object, softly beveled edges, translucent blue glass, restrained glossy highlights and soft contact shadow contained near the object. Frontal slight elevated three-quarter perspective, centered, isolated object filling roughly 82 percent of the square canvas with comfortable transparent margins. Crisp simple silhouette readable at 32 and 128 pixels, professional and welcoming. No enclosing rounded-square app tile, no background scene, no floor plane, no text, no letters, no Apple logo, no watermark, no mockup, no multiple variants. Deliver a polished high-resolution standalone app icon with real alpha transparency.
```
