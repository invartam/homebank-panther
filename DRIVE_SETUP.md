# Google Drive Direct Sur Panther

Le mode **compte de service**, accepte pour cette edition, ne demande pas de connexion Google dans Safari Panther. Une configuration initiale dans Google Cloud et Drive sur une machine compatible est necessaire. Ensuite les requetes d'authentification, de lecture et d'ecriture partent directement du G3 vers Google, sans relais.

Ce mode accede a un fichier existant explicitement partage au compte de service. Il ne connecte pas votre compte personnel, ne parcourt pas votre Drive et ne cree pas de nouveau fichier. La cle est une autorisation de longue duree : ne pas lui partager d'autres fichiers ou dossiers sensibles.

## 1. Creer Le Compte De Service

Depuis un navigateur compatible avec Google Cloud :

1. Selectionner le projet Google Cloud prevu pour HomeBank.
2. Dans **API et services > Bibliotheque**, activer **Google Drive API**.
3. Ouvrir **IAM et administration > Comptes de service**, puis **Creer un compte de service**.
4. Lui donner un nom, par exemple `homebank-panther`.
5. Ne pas attribuer de role **Proprietaire/Editeur du projet**. L'acces au fichier sera donne dans Drive, pas par les roles IAM du projet.
6. Ne pas activer de delegation a l'echelle du domaine ni d'usurpation d'un compte utilisateur.
7. Copier son adresse, du type `homebank-panther@projet.iam.gserviceaccount.com`.
8. Dans **Cles > Ajouter une cle > Creer une cle**, choisir **JSON**. Certaines organisations interdisent ces cles ; ne pas contourner cette politique.

Ce parcours ne demande ni CLIENT_ID OAuth Desktop ni API_KEY Picker. L'application signe une assertion JWT RS256 avec wolfSSL puis l'echange contre un jeton valable environ une heure. Aucun mot de passe Google n'est demande. [Documentation Google des comptes de service](https://developers.google.com/identity/protocols/oauth2/service-account).

## 2. Partager Un Fichier Existant

1. Dans votre Drive personnel, creer ou choisir une **copie de test** du fichier `.xhb` avant d'utiliser les donnees principales.
2. Partager uniquement ce fichier avec l'adresse du compte de service, avec le role **Editeur**.
3. Relever son identifiant dans l'URL `https://drive.google.com/file/d/IDENTIFIANT/view`.
4. Verifier que le fichier n'est pas a la corbeille et qu'une politique Workspace n'interdit pas le partage.

Un compte de service n'a pas de quota de stockage propre et ne peut pas devenir proprietaire de fichiers. Ce client met a jour le fichier partage existant, sans creer un fichier possede par le compte de service. Les quotas et droits de votre fichier restent applicables. Les cas Drive personnel et Drive partage doivent etre testes avec votre compte avant usage reel. [Restrictions et erreurs Drive](https://developers.google.com/workspace/drive/api/guides/handle-errors).

## 3. Compiler L'Application Dans La VM

Conserver le kit HTTPS qui a passe les tests dans Panther. Depuis les sources de l'application :

```sh
make HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"
make test HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"
make package HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"
```

L'archive `build/HomeBankPanther-0.4.0-ppc.tar.gz` contient l'application et son client curl/CA dans `Contents/Resources/Drive`. wolfSSL est lie statiquement pour les signatures. Aucun composant du systeme, ni Safari ni `/usr/bin/curl`, n'est remplace. Le client HTTPS n'a pas besoin d'etre recompile si le kit valide est deja present.

Apres transfert et installation de l'application sur le G3, ses chemins curl et CA integres sont proposes dans la configuration. Si l'application est deplacee apres configuration, verifier les chemins de nouveau. Le test sur le G3 physique reste necessaire, meme apres une reussite dans la VM.

## 4. Configurer Dans HomeBank Panther

1. Transferer la cle JSON vers la VM/G3 avec un support ou canal prive. Ne pas l'envoyer dans une conversation, la placer dans un depot, ou la laisser sur un partage public.
2. Ouvrir **Drive > Configurer le compte de service**.
3. Renseigner l'identifiant du fichier, pas son URL complete.
4. Verifier les chemins du curl moderne et du bundle CA. Ne pas utiliser le curl systeme de Panther.
5. Choisir **Importer une cle JSON**, puis **Enregistrer**.
6. Autoriser l'acces au trousseau si le systeme le demande. La configuration est refusee si la cle ne peut pas etre conservee dans le trousseau.
7. Choisir **Drive > Ouvrir le fichier Drive**.

La cle JSON est validee, puis conservee comme mot de passe generique dans le trousseau sous le service `HomeBank Panther Drive`. Les preferences ne contiennent que l'identifiant du fichier, les chemins et l'alias de cle. Le fichier JSON original importe n'est pas supprime automatiquement : le conserver uniquement dans une sauvegarde privee ou le retirer du support d'echange apres import. Le trousseau Panther et l'OS ancien ne fournissent pas les garanties de securite d'un systeme maintenu.

## 5. Synchronisation Et Reprise

- Ajouter, modifier, supprimer, pointer ou rapprocher une operation ajoute uniquement une commande au journal local `cache.xhb.panther-journal`, en arriere-plan. Le XML n'est pas regenere. Les modifications rapprochees sont regroupees pendant 350 ms ; la file ajoute ensuite les commandes plus recentes sans reecrire le portefeuille complet.
- L'indicateur **Drive : modifications a synchroniser** signale les changements non envoyes. Cliquer sur **Synchroniser**, en bas a droite, ou **Drive > Synchroniser maintenant**. Cette demande attend le journal durable, consolide le XML puis envoie la copie complete dans une nouvelle revision. Le journal correspondant est nettoye uniquement apres consolidation confirmee ; un echec reseau conserve les changements dans le XML local et l'etat Drive en attente. Sans changement local, le bouton charge la version distante.
- Le reseau, l'ecriture du cache telecharge et de sa reference s'executent dans un thread separe. L'interface reste consultable ; les modifications, l'export et le changement de fichier sont temporairement bloques pendant la synchronisation. Une fermeture pendant une sauvegarde locale ou une synchronisation est refusee : recommencer apres la fin. Une erreur locale conserve les modifications en memoire et empeche leur envoi ; utiliser **Enregistrer** pour reessayer.
- Un `PUT` conditionnel utilise l'ETag de reference et demande `newRevision=true`. Le contenu distant est relu et compare aux octets envoyes avant de marquer la synchronisation reussie. [API Drive v2 files.update](https://developers.google.com/workspace/drive/api/reference/rest/v2/files/update).
- Les revisions ne sont pas epinglees indefiniment : Google applique sa politique de retention. Garder des sauvegardes independantes ; les revisions Drive ne les remplacent pas.
- Le jeton d'acces reste en memoire et est renouvele au besoin. Aucune erreur reseau ne declenche une reprise automatique : cliquer de nouveau sur **Synchroniser** apres avoir corrige la connexion.
- Au prochain lancement, la copie du dernier fichier Drive actif est restauree, si aucun fichier local n'a ete ouvert au lancement. Les modifications non envoyees sont reconnues par leur SHA-256 et leur reference distante conservee. Aucun telechargement ni envoi n'est tente au demarrage ; cliquer sur **Synchroniser** pour retrouver la version distante ou envoyer les modifications. Si le cache n'existe plus, le bouton permet de le charger. **Ouvrir le fichier Drive** charge seulement la copie locale existante, ou telecharge le fichier si c'est le premier chargement.
- Le cache et ses sauvegardes sont dans `~/Library/Application Support/HomeBank Panther/`, dossier prive `0700`, fichiers `0600`. Les donnees bancaires locales ne sont pas chiffrees. Les sauvegardes locales ne sont pas purgees automatiquement : surveiller l'espace disque, surtout sur G3.
- Une copie locale sans etat de reference n'est jamais envoyee automatiquement. Elle est conservee et un rechargement explicite est necessaire.

Depuis 0.4.0, **Enregistrer** confirme le journal local. Pour utiliser le fichier dans HomeBank original ou copier seulement le `.xhb`, choisir **Fichier > Consolider le fichier XML** ou **Exporter une copie**. Ne pas effacer le journal ni le recu `.panther-commit.plist` pour forcer une reprise. Le rechargement distant apres confirmation consolide d'abord les changements locaux, de sorte que la sauvegarde XML conserve aussi ces operations. Voir [modele et journal](README.md#modele-metier-et-journal-local-040).

## 6. Conflits Et Fichiers Introuvables

Sous Panther, un message `Synchronisation interrompue` accompagne de `-[NSCFString longLongValue]: selector not recognized` dans Console correspond a une conversion de taille incompatible dans les versions precedentes. Mettre a jour en 0.3.4 et relancer l'application : la taille est maintenant traitee comme un entier borne, sans cette methode NSString. Ne pas effacer le cache, reimporter la cle ou contourner la verification TLS. Ce correctif ne reecrit pas automatiquement les fichiers distants.

La version 0.3.1 corrige un faux conflit possible lors du premier chargement : la version precedente envoyait l'ETag des metadonnees sur le telechargement du contenu, dont la representation peut avoir un validateur different. Le client demande maintenant la revision `headRevisionId` via le parametre `revisionId` de [files.get](https://developers.google.com/workspace/drive/api/reference/rest/v2/files/get), sans envoyer cet ETag sur la lecture du contenu. Il controle ensuite que la revision et les metadonnees n'ont pas change. Les ecritures restent conditionnelles (`If-Match`) ; aucun remplacement force n'est ajoute. Il n'est pas necessaire d'effacer le cache ni de reimporter la cle pour appliquer cette correction.

Si le fichier distant a change, le client n'impose pas le remplacement. Exporter la copie locale, consulter la version distante puis fusionner manuellement les operations. **Recharger depuis Drive** demande une confirmation s'il reste des modifications locales et conserve une sauvegarde avant remplacement. Il n'y a pas de fusion automatique.

Si une reponse d'envoi a ete perdue, la reprise compare le contenu distant avec la copie envoyee. Un contenu deja identique est reconnu sans creer une revision supplementaire.

Un fichier absent ou inaccessible (HTTP 404/410) propose de configurer un autre fichier. Une erreur de droits (403) ne declenche pas une boucle de reconnexion : verifier l'identifiant, le partage Editeur, l'activation de l'API et le quota. Ne pas creer automatiquement un fichier de remplacement et ne pas reutiliser une autre cle sans verifier les droits.

**Desactiver la synchronisation** conserve la cle et les copies locales. **Oublier la configuration et la cle** retire la cle du trousseau et conserve les copies. Pour revoquer vraiment l'acces, retirer le partage dans Drive et/ou supprimer la cle dans Google Cloud. Ne pas desactiver la verification des certificats ou modifier le User-Agent de Safari pour contourner Google.

## 7. Reparer Un Fichier Refuse Par HomeBank Original

Le XML pouvait etre valide pour Panther mais refuse par HomeBank original : la declaration `<?xml ... encoding="UTF-8"?>` ajoutait 39 octets avant `<homebank v=`, tandis que le controle original limite sa recherche a 50 octets. La version 0.3.2 n'ajoute plus cette declaration et place `v`, puis `d`, avant les autres attributs et namespaces, en conservant leurs valeurs.

Mettre a jour l'application, sans effacer le cache ni reimporter la cle et sans recompiler le kit HTTPS. Le fichier deja enregistre doit etre repare explicitement : une mise a jour du logiciel seule ne reecrit pas les donnees Drive.

1. Ouvrir le fichier Drive concerne dans Panther et verifier les comptes et operations affiches.
2. Choisir **Fichier > Exporter une copie** vers un fichier local de secours, hors du dossier synchronise, avant de continuer. Cet export est deja compatible avec HomeBank original.
3. Choisir **Fichier > Reparer la compatibilite HomeBank**, puis confirmer.
4. Attendre la fin de la sauvegarde locale, cliquer sur **Synchroniser**, puis attendre **Drive : synchronise**. Une sauvegarde locale conserve la version precedente, et l'envoi demande une nouvelle revision Drive. Si le fichier distant a change, la synchronisation reste bloquee pour eviter l'ecrasement.
5. Attendre la mise a jour du fichier par le client Google Drive du Mac recent, puis l'ouvrir dans HomeBank original.

Pour une copie locale non liee a Drive, utiliser **Fichier > Ouvrir**, puis la commande de reparation et **Enregistrer**, ou simplement **Exporter une copie** sous un nouveau nom. Aucun compte, montant, tiers, categorie, statut ou modele planifie n'est volontairement modifie par cette reparation de format.

## Validation Et Limites

Le kit HTTPS a ete valide par l'utilisateur dans la VM Panther/PPC. Le nouveau client Drive est teste sur Apple Silicon avec une cle RSA fictive publique, un transport simule, des conflits, des erreurs et des interruptions. La signature JWT est aussi verifiee independamment avec Node/OpenSSL sur le Mac recent.

L'utilisateur a confirme le 8 octobre 2026 le fonctionnement de la synchronisation par compte de service ; la plateforme exacte de ce test n'est pas precisee. Le correctif XML 0.3.2 est verifie sur des donnees fictives avec le controle de signature HomeBank et GLib GMarkup. **La nouvelle build, son fonctionnement dans Panther/PPC et la reouverture du fichier bancaire reel restent a confirmer par l'utilisateur.** Aucune cle reelle, aucun compte Google et aucune donnee bancaire n'ont ete utilises par l'agent pour ces tests. Commencer par une copie de test et conserver des sauvegardes.

L'application utilise l'API Drive v2 pour sa reference ETag explicite ; ce choix ne change pas le fichier, qui reste utilisable avec les clients modernes. Le profil HTTPS reste sans ML-KEM et n'offre pas de protection post-quantique. Panther reste un systeme non maintenu : cette fonctionnalite ne rend pas la machine sure pour des donnees financieres sensibles.

Les licences curl, cJSON et wolfSSL sont conservees avec les sources et le bundle. Le lien statique wolfSSL est soumis a GPLv3 ou licence commerciale : verifier les obligations avant toute redistribution, notamment la disponibilite des sources correspondantes. Cette integration n'accorde pas de licence commerciale.
