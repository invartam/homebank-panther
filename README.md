# HomeBank Panther

## Votre quotidien bancaire, sur votre Mac PowerPC.

Retrouvez vos comptes, suivez vos depenses et preparez les prochaines echeances sans quitter votre ancien Mac. **HomeBank Panther** est une application native de gestion bancaire personnelle, concue pour les Mac PowerPC sous **Mac OS X 10.3.9**, avec une cible iMac G3.

Elle travaille sur votre fichier HomeBank : vous gardez vos donnees localement et choisissez quand les synchroniser.

**Version 0.4.0** | **Application native Cocoa** | **Mac OS X Panther** | **Fichiers HomeBank .xhb**

---

## L'essentiel, Au Meme Endroit

### Une vue claire de vos comptes

Consultez vos comptes ouverts, filtrez entre banque et epargne et retrouvez vos soldes **rapproche, pointe et futur**. Les couleurs tiennent compte du decouvert autorise, et les devises restent distinctes pour ne pas melanger les montants.

### Vos operations au quotidien

Ajoutez des depenses, des revenus et des virements internes. Renseignez separement le tiers, le memo et le numero de paiement, puis classez chaque operation dans ses categories et sous-categories.

Retrouvez une operation par recherche, modifiez-la, pointez-la ou rapprochez-la. Les mouvements futurs apparaissent en gris ; la suppression demande une confirmation.

### Un regard sur les prochaines echeances

Explorez vos operations recurrentes dans un calendrier mensuel ou annuel. Consultez le detail d'un jour ou d'un mois, comparez les revenus et depenses, puis passez de la vue generale a un compte particulier.

Les dates futures associent les previsions aux operations deja inscrites. Les virements entrants et sortants sont presentes separement, et l'historique des comptes clos reste accessible dans le calendrier.

### Un moteur pense pour les anciennes machines

Les editions ne reconstruisent plus tout le fichier XML. Les changements sont conserves dans un petit journal local, en arriere-plan, tandis que les soldes sont mis a jour pour les comptes concernes.

L'objectif : reduire le travail demande au processeur lors de la saisie et du rapprochement. Les performances reelles restent a mesurer sur votre machine.

## Local D'abord, Drive Quand Vous Le Decidez

**Pas de connexion a votre banque.** HomeBank Panther vous aide a consulter et organiser les operations de votre fichier HomeBank ; il n'execute aucun paiement ni virement bancaire.

Vos fichiers locaux restent utilisables sans connexion Internet et sans compte Google.

**Google Drive est une option.** Avec un compte de service configure et un fichier partage, vous pouvez charger votre portefeuille puis cliquer sur **Synchroniser** pour envoyer vos changements dans une nouvelle revision. Les ajouts et modifications ne declenchent pas d'envoi automatique.

La cle du compte de service est conservee dans le trousseau. Cette integration demande une configuration specifique ; ce n'est pas une connexion a votre compte personnel dans Safari. Consultez le [guide Google Drive](DRIVE_SETUP.md).

## Ce Que Vous Pouvez Faire

| Au quotidien | Avec HomeBank Panther |
| --- | --- |
| Consulter vos comptes | Soldes rapproche, pointe et futur ; filtres banque et epargne |
| Suivre vos mouvements | Depenses, revenus et virements internes, y compris entre devises |
| Retrouver une operation | Recherche par tiers, memo, categorie, numero ou montant |
| Verifier vos comptes | Pointage, rapprochement et retrait des statuts |
| Anticiper vos echeances | Consultation des recurrences et calendriers mensuel et annuel |
| Garder votre historique | Comptes clos consultables dans le calendrier |
| Conserver vos changements | Journal local automatique et reprise au chargement |
| Echanger votre portefeuille | Export .xhb et synchronisation Drive manuelle |

## Prendre En Main

1. Preparez l'application PowerPC avec le [guide technique](README_TECHNIQUE.md), puis installez-la sur votre Mac. Xcode n'est pas necessaire sur la machine qui execute une application deja compilee.
2. Commencez par le [portefeuille de demonstration](tests/demo.xhb), puis ouvrez une copie de votre fichier HomeBank.
3. Consultez vos comptes et utilisez **Nouvelle**, **Modifier**, **Pointer** ou **Rapprocher** selon vos besoins.
4. Pour retrouver les dernieres donnees dans HomeBank original, utilisez **Fichier > Consolider le fichier XML** ou **Exporter une copie**. Pour Drive, cliquez sur **Synchroniser**.

### Un point important pour vos fichiers

**Enregistrer confirme le journal local, pas un nouveau XML.** Tant que vous n'avez pas consolide le fichier, gardez le `.xhb` avec son `.panther-journal`. HomeBank original et les anciennes versions ne lisent pas ce journal.

La consolidation integre les changements dans le XML et conserve une sauvegarde de sa version precedente. La synchronisation Drive effectue cette consolidation avant l'envoi. Gardez egalement des sauvegardes independantes et ne modifiez pas le meme fichier dans plusieurs applications en parallele.

## Compatibilite Et Limites

HomeBank Panther est un projet separe de HomeBank Web et un client distinct de l'application HomeBank originale.

- Cible : Mac PowerPC sous OS X 10.3.9. Les essais sur un Mac recent ne remplacent pas une validation dans Panther et sur le materiel cible.
- Fichiers : HomeBank `.xhb` UTF-8 non chiffres, jusqu'au format 1.6 et 8 Mio.
- Planifications : consultation uniquement ; pas de creation, de modification ni de publication automatique des echeances.
- Operations protegees : certaines modifications de montants, dates ou categories sont bloquees sur les operations rapprochees ou ventilees.
- Confidentialite : les fichiers locaux ne sont pas chiffres. Panther n'est plus un systeme maintenu ; cette application ne corrige pas les risques de son systeme d'exploitation.

## Documentation

- **[Guide technique](README_TECHNIQUE.md)** : compilation, installation, tests, performances, journal local et recuperation.
- **[Google Drive](DRIVE_SETUP.md)** : compte de service, partage du fichier, synchronisation et conflits.
- **[Kit HTTPS PowerPC](HTTPS_BUILD.md)** : preparation et compilation des composants reseau.
