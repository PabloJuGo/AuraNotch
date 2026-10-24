<div align="center">

<img src="Docs/images/icon.png" width="112" alt="Icône d’Aura Notch">

# Aura Notch

**Transformez l’encoche du MacBook en un panneau utile et discret.**
Contrôles de lecture, étagère temporaire de fichiers, vos prochains événements, minuteur, volume, batterie et historique du presse-papiers, à portée de survol.

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License MIT](https://img.shields.io/badge/license-MIT-blue)
![Status beta](https://img.shields.io/badge/status-beta-yellow)

<img src="Docs/images/closed.png" width="420" alt="Encoche réduite pendant la lecture d’un morceau">

</div>

Aura Notch est une app macOS native écrite en Swift (SwiftUI + AppKit), sans dépendance tierce. Elle se loge dans l’encoche, reste discrète et s’ouvre en panneau quand vous la pointez. Tout fonctionne en local : pas de compte, pas d’analyse d’usage, pas de télémétrie.

<div align="center">
<img src="Docs/images/home.png" width="720" alt="Panneau Accueil avec lecture en cours, aujourd’hui, presse-papiers et étagère">
</div>

## Fonctionnalités

- **Encoche réduite avec activité en direct.** Un égaliseur animé et le titre du morceau apparaissent à côté de l’encoche pendant une lecture, un minuteur affiche son compte à rebours, et de courtes alertes (réunion imminente, chargeur branché, minuteur terminé) glissent à l’écran. La forme réduite a une largeur fixe et symétrique : elle ne grandit jamais avec le titre du morceau et masque le moins possible votre barre des menus.
- **Accueil.** La date du jour et la batterie, la lecture en cours avec pochette et commandes de lecture, les événements du jour, les derniers éléments du presse-papiers et votre étagère, d’un seul coup d’œil.
- **Multimédia.** Musique et Spotify : titre, artiste, progression et déplacement dans le morceau, lecture/pause/suivant/précédent dans le style macOS. Balayez à deux doigts sur l’encoche réduite pour changer de morceau. La pochette Spotify est facultative et c’est la seule chose que l’app télécharge.
- **Étagère.** Faites glisser des fichiers ou des liens vers l’encoche : elle s’ouvre pour les recevoir. L’étagère conserve des références, sans jamais déplacer ni supprimer vos originaux. Ouvrir, afficher dans le Finder, copier le chemin, partager ou envoyer par AirDrop, et faire ressortir les éléments par glisser-déposer. La conservation d’une session à l’autre est à activer.
- **Calendrier.** Vos prochains événements, en lecture seule, via EventKit et avec autorisation explicite.
- **Widgets.** Minuteur, volume, batterie, date et actions rapides, disposés sur une grille ordonnée à deux colonnes.
- **Historique du presse-papiers (optionnel).** Texte, liens et images, conservés en mémoire uniquement. Il ignore les éléments marqués comme confidentiels ou temporaires (comme ceux des gestionnaires de mots de passe) et reste désactivé tant que vous ne l’activez pas.
- **Thèmes et langues.** Choisissez une couleur d’accentuation et la taille de l’encoche réduite. L’interface est disponible en anglais, espagnol, français, allemand, portugais du Brésil et chinois simplifié.
- **Bon citoyen.** Panneau non activant qui ne vole jamais le focus, raccourci global (`⌃⌥N`), icône dans la barre des menus, ouverture à la connexion, respect de l’option *Réduire les animations*, masquage au-dessus des apps en plein écran (configurable) et environ 0 % de CPU au repos.
- **Fonctionne sans encoche.** Sur les Mac et écrans sans encoche, il devient une petite pastille flottante en haut au centre de l’écran.

<div align="center">
<img src="Docs/images/media.png" width="360" alt="Panneau Multimédia"> <img src="Docs/images/clipboard.png" width="360" alt="Panneau Presse-papiers">
</div>

## Installation

1. Téléchargez `AuraNotch.zip` depuis la [dernière version](https://github.com/PabloJuGo/AuraNotch/releases/latest) et décompressez-le.
2. Faites glisser **AuraNotch.app** dans votre dossier Applications.
3. La première fois, **faites un clic droit sur l’app, choisissez Ouvrir** (clic droit > Ouvrir), puis confirmez. L’app est signée ad hoc mais pas notarisée (la notarisation nécessite un compte développeur Apple payant) : macOS vous demande donc de l’approuver une fois. Si macOS refuse encore, exécutez :
   ```sh
   xattr -dr com.apple.quarantine /Applications/AuraNotch.app
   ```
4. Repérez la bande de l’encoche en haut de l’écran (et l’icône dans la barre des menus). Survolez-la ou cliquez dessus, ou appuyez sur `⌃⌥N`.

**Prérequis :** macOS 14 ou ultérieur. Elle a été développée et testée sur un MacBook avec encoche sous macOS 27 ; les autres configurations devraient fonctionner, mais ont été moins testées.

## Réglages

Ouvrez les **Réglages** depuis l’engrenage de l’en-tête du panneau ou l’icône de la barre des menus.

| Section | Ce que vous pouvez modifier |
|---|---|
| Général | Ouverture à la connexion, mode d’affichage, **langue de l’interface**, couleur d’accentuation, taille de l’encoche réduite |
| Interaction | Ouvrir au survol, au clic ou avec le raccourci global ; délai de survol ; comportement en plein écran ; titre dans l’encoche réduite ; balayage pour changer de morceau ; alertes |
| Animations | Mouvement (suivre le système, réduit ou aucun) |
| Modules | Activer, désactiver et réordonner Accueil, Multimédia, Étagère, Calendrier, Widgets et Presse-papiers |
| Confidentialité | Conserver l’étagère entre les sessions, limite de l’historique, pochettes Spotify, effacer toutes les données |

Le changement de langue prend effet après un redémarrage ; l’app propose un bouton **Redémarrer maintenant**.

## Confidentialité et autorisations

- Pas de compte, pas d’analyse d’usage, pas de télémétrie, pas de vérification des mises à jour.
- **Réseau :** la seule requête est celle de la pochette Spotify, à l’adresse que Spotify expose lui-même. Vous pouvez la désactiver dans Réglages → Confidentialité.
- **Les autorisations ne sont demandées qu’au moment où vous utilisez la fonctionnalité qui en a besoin :** *Automatisation* pour contrôler Music et Spotify (voir ce qui est en cours de lecture n’exige aucune autorisation), et *Calendriers* pour lister vos événements (lecture seule).
- L’étagère conserve des références vers vos fichiers, l’historique du presse-papiers reste uniquement en mémoire, et **Réglages → Confidentialité → Effacer toutes les données** supprime tout.

Plus de détails dans [PRIVACY.md](PRIVACY.md) et [SECURITY.md](SECURITY.md) (tous deux en espagnol pour l’instant).

## Compiler depuis les sources

Il vous suffit de la chaîne d’outils Swift 6 (les Xcode Command Line Tools suffisent).

```sh
git clone https://github.com/PabloJuGo/AuraNotch.git
cd AuraNotch
swift build
swift run AuraSelfTests            # test suite with detailed failures
swift run AuraNotch                # run without packaging (no Calendar/Automation prompts)
Scripts/package-app.sh             # builds dist/AuraNotch.app (release, ad-hoc signed)
```

Options utiles : `--skip-onboarding`, `--start-module=<home|media|shelf|calendar|widgets|clipboard>`.

Les notes d’architecture se trouvent dans [ARCHITECTURE.md](ARCHITECTURE.md), les décisions de conception dans [Docs/decisions](Docs/decisions) (en espagnol).

## État et limitations connues

Aura Notch est en **bêta**. À savoir :

- Non notarisée (voir Installation). Il n’y a pas de mise à jour automatique.
- Les parcours Calendrier et AirDrop reposent sur des autorisations et des boîtes de dialogue système, et ont été peu testés sur du matériel réel.
- Les écrans externes, les configurations multi-écrans et VoiceOver ont été peu testés en pratique.
- La demande d’autorisation d’Automatisation pour Spotify peut tarder à s’afficher sur les versions récentes de macOS ; macOS la demande alors la première fois que vous appuyez sur une commande.
- Les traductions autres que l’anglais et l’espagnol ont été réalisées avec une assistance automatique et n’ont pas été relues par des locuteurs natifs. Les corrections sont les bienvenues.
- Certains documents du projet (notes d’architecture, décisions, confidentialité) sont encore en espagnol.

## Contribuer

Les issues et pull requests sont les bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md). Pour corriger ou ajouter une traduction, modifiez `Resources/<language>.lproj/Localizable.strings` et lancez `Scripts/check-localizations.py`.

## Licence

[MIT](LICENSE). Aura Notch est un projet indépendant et n’est affilié ni à Apple, ni à Spotify, ni à aucune autre app mentionnée ici.
