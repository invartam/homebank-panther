# Captures du guide utilisateur

Ces images sont des captures de l’écran de la **VM QEMU Panther sous Mac OS X 10.3.9, build 7W98**, prises le **14 novembre 2026** à une résolution de **1024 × 768 pixels**.

L’application et les vues ont été compilées dans cette VM avec son compilateur GCC et ses frameworks Cocoa. Les écrans utilisent les contrôles Aqua de Panther ; ce ne sont ni des maquettes ni des rendus d’un macOS récent.

Un pilote documentaire temporaire affiche les vues existantes avec un portefeuille entièrement fictif, construit en mémoire, et sélectionne les écrans à capturer. Il utilise un identifiant d’application distinct (`local.homebank.documentation`). La capture du framebuffer est effectuée par la commande QMP `screendump` de QEMU, au format PNG, sans retouche du contenu.

| Fichier | Écran |
| --- | --- |
| `01-compte.png` | Compte courant, opérations et prévision avant salaire. |
| `02-prevision-date.png` | Prévision à date choisie. |
| `03-depense.png` | Formulaire de nouvelle dépense, non validé. |
| `04-virement.png` | Formulaire de virement interne, non validé. |
| `05-calendrier-mensuel.png` | Calendrier mensuel. |
| `06-calendrier-annuel.png` | Calendrier annuel. |
| `07-recurrences.png` | Consultation des récurrences. |
| `08-agenda.png` | Détail d’une journée future. |
| `09-graphique.png` | Rapport de solde avec les contrôles natifs. |
| `10-configuration-drive.png` | Configuration Drive avec identifiant et chemins de démonstration. |
| `11-graphique-previsions.png` | Vue Tout du graphique avec historique et prévisions sur un an. |

Les noms de comptes, tiers, montants et opérations sont fictifs. L’écran Drive ne contient aucune clé et n’illustre pas une connexion authentifiée ; aucune requête vers Drive ni lecture de portefeuille réel n’est nécessaire à ces captures.

Le pilote est exécuté depuis `/Users/builder/homebank-guide-060` dans la VM, séparément des sources de travail habituelles. La validation visuelle de ces écrans dans QEMU ne mesure pas les performances d’un iMac G3 physique et ne constitue pas un test complet de synchronisation Drive.

Consulter le [guide utilisateur](../../../GUIDE_UTILISATEUR.md) pour les procédures associées.
