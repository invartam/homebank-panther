# HomeBank Panther - Documentation Technique

Pour decouvrir le logiciel et ses usages, consulter le [README principal](README.md).

Client natif **0.4.0**, cible iMac G3 / PowerPC, Mac OS X 10.3.9 et Xcode 1.5.
Ce n'est pas un package Electron : ce client utilise Cocoa / Foundation et Objective-C avec gestion manuelle de la memoire. Aucun npm, navigateur moderne ou service reseau n'est requis.

## Fonctionnalites

- Ouverture locale de fichiers HomeBank XML `.xhb` UTF-8, format jusqu'a 1.6, y compris la version GLib `1.6000000000000001`.
- Comptes ouverts uniquement, filtres Banque / Epargne (types HomeBank 3 et 7).
- Solde rapproche principal, soldes pointe et futur par compte, calculs decimaux et devises separees.
- Couleurs de solde tenant compte du decouvert autorise.
- Operations enregistrees, y compris les operations futures et les deux lignes des virements postes. Les operations annulees restent visibles mais sont exclues des soldes.
- Dates francaises, tiers distinct du memo, categories hierarchisees, operations futures en gris.
- Pagination de 100 operations et rechargement manuel du fichier.
- Recherche, ajout et modification de depenses, revenus et virements internes ; les deux mouvements d'un virement sont lies, y compris entre devises avec un montant explicite pour le compte lie.
- Champs distincts tiers, memo et numero de paiement, categories hierarchisees et modes de paiement HomeBank.
- Pointage, rapprochement, retrait des statuts et suppression avec confirmation. Le pointage est propre a chaque compte ; l'annulation d'un virement concerne ses deux mouvements.
- Sauvegarde locale automatique en arriere-plan, export d'une copie `.xhb`, protection avant fermeture/rechargement pendant une sauvegarde.
- Consultation des recurrences et calendrier mensuel/annuel. Les jours passes et aujourd'hui affichent uniquement les operations inscrites ; les jours futurs combinent les operations inscrites et les previsions. Les mois sont agreges jour par jour, sans supprimer les mouvements deja postes dans le futur.
- Totaux revenus/depenses et virements entrants/sortants distincts, par devise et par compte ; agenda d'un jour ou d'un mois au clic, puis passage d'une annee au mois choisi.
- Comptes clos disponibles sur demande dans le calendrier uniquement ; la liste principale des comptes reste limitee aux comptes ouverts.

**Google Drive direct par compte de service** : fichier partage existant, cle dans le trousseau, synchronisation manuelle en arriere-plan avec revisions, detection de conflits et reprise de la copie locale. Le bouton **Synchroniser** envoie les changements locaux ; aucune operation ne declenche un envoi automatique. Voir le [guide de configuration](DRIVE_SETUP.md) et ses limites de validation PPC. Pas de creation/modification de planifications ni de publication automatique d'echeances : leur consultation suit le perimetre de la version web. Les modeles `<fav>` n'entrent jamais dans les soldes des comptes. Les montants, dates et categories des operations ventilees restent proteges ; leurs textes et statuts sont editables. Les montants d'une operation rapprochee ou d'un virement dont une face est rapprochee sont proteges jusqu'au retrait du rapprochement. Le type d'un virement existant ne peut pas etre converti en depense/revenu. Limite de fichier de 8 Mo, fichiers non chiffres uniquement.

## Compiler Dans La VM Panther

Installer les outils en ligne de commande de Xcode 1.5. Transmettre **tout ce dossier**, ou l'archive des sources, a la VM. Dans son Terminal :

```sh
cd /chemin/vers/homebank-panther
make HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"
make test HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"
make package HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"
```

- Application : `build/ppc/HomeBankPanther.app`.
- Archive : `build/HomeBankPanther-0.4.0-ppc.tar.gz`.
- Fichier fictif de test : `tests/demo.xhb`.

Le Makefile cible `ppc`, le processeur 750/G3 sans AltiVec, et fixe `MACOSX_DEPLOYMENT_TARGET=10.3`, valeur acceptee par l'ancien linker. Le minimum de l'application dans `Info.plist` reste **10.3.9**. Compiler directement dans Panther avec son compilateur et ses frameworks ; ne pas remplacer ce compilateur par le Xcode actuel. Le Makefile ne produit pas un binaire universel Intel / Apple Silicon.

Construire d'abord le [kit HTTPS](HTTPS_BUILD.md), ou reutiliser celui valide dans la VM. Le bundle inclut curl et les CA, et wolfSSL est lie statiquement pour les signatures du compte de service. Copier l'archive vers l'iMac, la decompresser (`tar -xzf HomeBankPanther-0.4.0-ppc.tar.gz`) puis placer l'application dans Applications. Utiliser **Fichier > Ouvrir** pour un `.xhb` local, ou le menu **Drive** pour le fichier partage. Une operation est editable au double-clic ou avec **Modifier**. Ne pas installer Xcode sur l'iMac pour simplement executer l'application.

### Modele Metier Et Journal Local (0.4.0)

**Les editions ne regenerent plus le XML.** L'import cree des `HBOperation` et `HBAccount` types, avec identifiants internes stables, dates ordinales, statuts numeriques et montants decimaux. `HBWalletStore` produit des instantanes immuables : les objets inchanges restent partages, les operations modifiees sont remplacees et seuls les index et soldes des comptes concernes sont mis a jour. Les listes copient encore des references ; ce n'est pas une garantie de cout constant, mais il n'y a plus de parseur XML dans le parcours d'edition. Les adapters dictionnaires maintiennent la compatibilite des vues et calendriers existants.

Les adapters implementent les quatre primitives du [contrat NSDictionary d'Apple](https://developer.apple.com/documentation/foundation/nsdictionary?language=objc), avec types de collection adaptes aux anciens SDK. Les constructeurs et la copie vers un dictionnaire ordinaire sont testes.

La sauvegarde automatique ajoute de petites commandes a `nom.xhb.panther-journal`, avec ecritures serialisees et `fsync`. Un virement et ses deux mouvements forment une seule commande. Le journal binaire versionne est lie au SHA-256 du XML de reference ; chaque trame a une longueur bornee et une empreinte d'integrite. Il est prive (`0600`), sans chiffrement, limite a 16 Mio, 256 Kio par commande et 10 000 commandes. A la limite du nombre de commandes, consolider le XML avant de reprendre les editions. Le premier import et le rejeu restent proportionnels a la taille du portefeuille et du journal.

**Enregistrer / Commande-S confirme le journal, pas un nouveau fichier XML.** Pour ouvrir les dernieres donnees dans HomeBank original ou transmettre un `.xhb` seul, choisir **Fichier > Consolider le fichier XML** ou **Exporter une copie**. La synchronisation manuelle Drive consolide automatiquement avant l'envoi. Une exportation vers un autre nom laisse le journal du document courant intact. Le XML genere reste limite a 8 Mio ; un export refuse ne supprime pas le journal.

Consolidation et export se font en arriere-plan, avec edition et changement de document temporairement bloques. Le serializeur applique les changements a une copie du XML de reference et preserve les attributs non edites, extensions, commentaires, ventilations et planifications. La consolidation conserve la sauvegarde XML precedente, puis nettoie uniquement le journal correspondant exactement a l'instantane. Un recu prive `nom.xhb.panther-commit.plist` permet de reconnaitre une interruption entre remplacement XML et nettoyage du journal. Un echec reseau apres consolidation conserve le fichier XML local et l'indicateur Drive en attente ; le journal peut alors deja etre nettoye puisque ses donnees sont dans le XML.

Au prochain chargement, Panther rejoue les commandes completes. Une derniere trame incomplete reste ignoree et est nettoyee sous verrou lors d'une ecriture ou consolidation explicite. Une trame complete corrompue, une version d'operation incorrecte ou un XML modifie independamment bloque la reprise plutot que d'imposer une fusion. Aucun journal inconnu n'est efface automatiquement. Exporter le portefeuille encore en memoire pour recuperer des modifications si un fichier externe a change.

**Ne pas separer le `.xhb` de son `.panther-journal` tant que le XML n'est pas consolide.** Les anciennes versions et HomeBank original ne lisent pas ce journal. Ne pas reutiliser le meme fichier simultanement dans plusieurs applications ; les conflits externes au XML sont controles a la consolidation et a la reprise, pas a chaque edition. Un verrou residuel `.panther-journal.lock` doit etre retire uniquement apres avoir confirme qu'aucun client n'ecrit. Ne pas retirer un recu ou un journal pour contourner une erreur de reprise.

Mesures indicatives sur le Mac recent, 3 000 operations fictives / environ 263 Ko : changement de statut **environ 0,8 ms**, ajout durable au journal **environ 0,25 ms / 257 octets**, contre environ 30 ms pour l'ancien changement de statut avec XML. La generation XML explicite reste plus couteuse. Ces chiffres ne certifient pas les performances sur G3 ; utiliser `make benchmark HTTPS_PREFIX="$HOME/homebank-https-sources/out/ppc"` dans la VM.

### Optimisations Initiales (0.3.7)

La version 0.3.7 reduit le travail effectue, sans retirer les controles d'integrite :

- Une sauvegarde revalide toujours le portefeuille a ecrire. Les deux controles du fichier existant comparent ses octets a la reference deja chargee, au lieu de reconstruire deux fois comptes, soldes et operations. La comparaison est bornee, par blocs de 64 Kio, sur un fichier regulier avec verification d'identite et refus des liens symboliques. Verrou, copie precedente, `fsync` et remplacement atomique restent actifs.
- Sans recherche, la liste reprend les operations deja triees du compte. Elle ne parcourt plus chaque operation pour formater son montant. Une recherche explicite conserve tiers, memo, categorie, numero et montant francais.
- Les formateurs monetaires sont reutilises par devise et proteges par un verrou. Les precisions et separateurs ne passent pas d'une devise a l'autre.
- Le compte selectionne est restaure avant un seul rafraichissement des operations, au lieu de rafraichir d'abord un autre compte puis celui choisi. Un calendrier masque ne recalcule ses projections qu'a sa prochaine ouverture.
- L'import evite certaines allocations temporaires et ne reformate plus les entiers qui sont deja canoniques ; les identifiants avec zeros initiaux restent normalises.

Mesures indicatives sur le Mac recent, donnees fictives de 3 000 operations / environ 263 Ko : remplacement local **84 ms avant / 23 ms apres**, formatage de tous les montants **116 ms avant / 7 ms apres**. Ce formatage global n'est plus necessaire en l'absence de recherche. Ce ne sont ni des mesures G3, ni des temps complets d'edition ; disque, taille du portefeuille et systeme font varier les resultats.

Pour mesurer dans la VM sans utiliser le portefeuille reel, apres compilation :

```sh
make benchmark
HB_BENCH_RECORDS=10000 make benchmark
```

Le benchmark actuel genere uniquement un portefeuille fictif dans un dossier temporaire prive, mesure import, changement de statut sans XML, journal durable, remplacement XML explicite et affichage, puis supprime ses fichiers. Il ne contacte pas Drive et ne lit pas le trousseau. Il requiert le kit HTTPS deja utilise par l'application pour les empreintes du journal. Verifier les gains sur PPC et conserver les sauvegardes.

### Sauvegarde Asynchrone Et Drive Manuel

Depuis 0.3.6, la persistance locale s'effectue dans un thread separe. Depuis 0.4.0, les editions alimentent le journal plutot que de reecrire le XML. Les actions rapprochees sont regroupees pendant 350 ms. Une seule ecriture s'execute a la fois ; une edition plus recente ajoute ensuite uniquement ses nouvelles commandes au prefixe confirme.

Cliquer sur **Synchroniser** ou **Drive > Synchroniser maintenant** pour envoyer les changements. Le bouton attend d'abord la fin des sauvegardes locales. Sans changement local, il charge la version distante. Le demarrage et la reouverture d'une copie existante ne declenchent aucune requete Drive ; le premier chargement sans cache reste une action explicite. Les erreurs reseau ne programment plus de reprise automatique.

La validation metier en memoire reste synchrone, sans XML. La consolidation XML, l'export, le reseau et l'enregistrement du cache/reference Drive sont hors du thread de l'interface. Cela ne supprime pas tout cout des formulaires ou calendriers sur G3. Les tests modernes couvrent editions pendant une ecriture, envoi avant sauvegarde, reprise du journal et interruptions de consolidation ; la nouvelle version reste a valider dans la VM PPC.

### Crash XML Lors Du Rapprochement

La version 0.3.5 corrige la copie du gestionnaire `xmlSAXHandler` sur la pile. Un SDK ancien peut declarer seulement la partie SAX1 tandis que la bibliotheque chargee attend aussi les callbacks SAX2. Copier la structure selon la taille des en-tetes perd alors ces champs : le parseur peut appeler une adresse invalide. Le crash transmis dans `xmlParseElement` pendant `walletByChangingStatus` est coherent avec ce probleme, reproduit sur le Mac recent avec des en-tetes 2.5.4 et le runtime systeme plus recent.

Le lecteur conserve maintenant la table privee allouee par le runtime, sans en tronquer la taille ni modifier son indicateur SAX2. Seuls les callbacks communs de refus DTD/entites et de diagnostics sont remplaces. Les callbacks de construction du DOM et des namespaces restent intacts. Un gestionnaire global partage est refuse plutot que modifie. Les protections contre les entites externes sont maintenues et les tests couvrent des creations/destructions repetees.

La cible optionnelle `make mixed-xml-test` demande `LEGACY_XML_CFLAGS` vers les anciens en-tetes et teste avec `XML_LIBS` du runtime choisi. `make test` indique egalement versions d'en-tetes et de runtime. Les tests mixtes et la compilation restent effectues sur Apple Silicon : ils ne remplacent pas un nouvel essai de rapprochement dans la VM PPC. Aucun portefeuille reel ni fichier Drive n'est modifie par l'agent.

### Correction De La Lecture Drive Sous Panther

Le journal de la VM a confirme `-[NSCFString longLongValue]: selector not recognized`. La version 0.3.4 lit la taille Drive avec le parseur d'entiers borne a 8 Mio, sans ce selecteur NSString absent sur Panther. Les tests simulent une chaine qui refuse ce selecteur, en lecture et en verification d'envoi. Les identifiants de virements et categories passent egalement par le parseur d'entiers pour conserver leur precision 32 bits.

Les erreurs inattendues indiquent desormais une categorie fixe (API/argument, limites, fichier ou memoire), jamais le contenu de l'exception ni sa raison, qui peuvent contenir des secrets. Les appels avec pointeur d'erreur sont hors du bloc `@try` pour eviter les qualifications implicites de GCC ; le nettoyage temporaire utilise une representation de chemin stable. La cible du linker est `10.3`, sans abaisser le minimum requis `10.3.9`. Ces changements ne demandent ni nouvelle cle ni reconstruction du kit HTTPS.

### Correctif GCC Et Libxml2 Panther

La version 0.3.3 active `-fobjc-exceptions` pour les fichiers Objective-C, y compris si `OBJCFLAGS` est personnalise. Les fichiers C du parseur et de cJSON sont compiles separement, sans cette option. Les declarations des methodes internes sont presentes avant leurs appels pour GCC 3.3 : cela garantit notamment le type `double` des delais de synchronisation et les retours `BOOL` des controles de sauvegarde.

L'edition XML utilise `xmlCreateMemoryParserCtxt` et `xmlParseDocument`, disponibles dans la [version historique libxml2 2.5.4](https://download.gnome.org/sources/libxml2/2.5/), au lieu de `xmlReadMemory` et `XML_PARSE_*`. Elle verifie la croissance du tampon plutot que le retour de `xmlBufferAdd`, qui etait `void` dans cette version. Les attributs racine utilisent l'echappement libxml historique et des references numeriques pour les retours de ligne/tabulations, sans appeler `xmlNodeDump` sur un attribut isole. Le contexte et ses callbacks sont prives : refus des DTD, des entites externes et des entites parametre, sans changer le chargeur global. Les tests XML exercent aussi des reglages globaux hostiles pour verifier ce refus. Aucune mise a jour de libxml2 systeme n'est demandee.

Les archives utilisent `ustar`, sans metadonnees Apple, pour eviter les entrees `PaxHeader` sur les anciens outils. Pour reprendre, extraire les nouvelles sources dans un dossier neuf, conserver le kit HTTPS existant dans son dossier separe, puis relancer les trois commandes ci-dessus. Il n'est pas necessaire d'effacer les caches bancaires ni le trousseau.

L'application complete et les tests sont compiles avec les en-tetes et une bibliotheque libxml2 2.5.4 isolee sur le Mac recent. Cette bibliotheque ancienne n'est pas distribuee dans le bundle ; le client PPC utilise celle de Panther. Cela ne constitue pas une compilation avec le GCC de la VM ni une validation PPC. Des avertissements de pragmas ignores dans cJSON peuvent subsister avec GCC 3.3 ; ne pas confondre ces avertissements avec une erreur fatale.

## Preparer Les Sources Depuis Le Mac Actuel

Depuis la racine du projet `homebank-panther` :

```sh
make source-package
```

L'archive `build/HomeBankPanther-0.4.0-sources.tar.gz` contient le code, les licences, la documentation et les donnees fictives. Elle ne contient aucun portefeuille utilisateur ni cle Google de production. La cle RSA dans `tests/fixtures/drive-rsa-test-key.txt` est une cle de test volontairement publique, jamais utilisable en production.

## Validation Sur Un Mac Moderne

Pour controler la logique et ouvrir l'interface sur Apple Silicon, dans ce dossier :

```sh
make CC=clang ARCH=arm64 DEPLOYMENT_TARGET=13.0 HTTPS_PREFIX=/chemin/kit-https/out/arm64
make test CC=clang ARCH=arm64 DEPLOYMENT_TARGET=13.0 HTTPS_PREFIX=/chemin/kit-https/out/arm64
open build/arm64/HomeBankPanther.app
```

Ces commandes produisent un **binaire de verification ARM64**, pas un binaire PPC. Les sorties ARM64 et PPC sont separees et `make package` verifie l'architecture avec `lipo -info`, compatible Panther, avant de creer l'archive. Apres un changement de compilateur ou d'options pour une meme architecture, executer `make clean` avant de reconstruire.

La validation moderne ne certifie ni la compilation avec GCC 3.3 / SDK Panther, ni l'execution sur G3. Avant utilisation : compiler et executer `make test` dans la VM, ouvrir une copie du fichier fictif sur l'iMac, verifier les soldes, la saisie, les deux faces d'un virement, le pointage, l'enregistrement/rechargement, les sauvegardes et les calendriers. Verifier l'architecture avec `file build/ppc/HomeBankPanther.app/Contents/MacOS/HomeBankPanther` : le resultat doit indiquer PowerPC. Tester ensuite seulement sur une copie du portefeuille reel. Les modifications de fichiers bancaires reels ne sont pas couvertes par les essais modernes.

## Enregistrement Et Recuperation

**Valider**, pointer, rapprocher ou supprimer met a jour le modele en memoire puis programme l'ajout de commandes au journal local. **Enregistrer** ou `Commande-S` lance immediatement cette sauvegarde en arriere-plan, sans envoyer sur Drive ni reecrire le XML. L'indicateur **Journal local en cours d'enregistrement** disparait uniquement une fois l'ecriture confirmee. La saisie reste possible pendant cette ecriture ; fermer, changer de fichier, recharger ou exporter attend sa fin (recliquer apres la fin). Les changements deja sauvegardes mais non synchronises peuvent etre conserves en quittant normalement.

En cas d'echec, les modifications restent en memoire et **Enregistrer** permet de reessayer ; la fermeture propose alors Enregistrer, Annuler ou Abandonner. Choisir Enregistrer lance l'ecriture et annule cette tentative de fermeture : la refaire apres confirmation. Abandonner revient a l'instantane confirme en memoire, sans effacer un journal dont une ecriture pourrait avoir reussi sans confirmation ; la reprise peut donc retrouver ces commandes. Pour recuperer le modele courant, **Exporter** produit une copie XML sans envoyer sur Drive. Une coupure de courant ou fermeture forcee avant la confirmation du journal peut perdre des changements encore en memoire ; les trames completes deja ecrites sont rejouees au prochain chargement.

La validation des modifications est metier et incrementale. Lors d'une consolidation ou export, l'arbre XML de reference est edite avec libxml2 fourni par le systeme puis le document complet est revalide avant ecriture. Les noeuds et attributs non edites, commentaires, planifications et ventilations sont conserves semantiquement ; indentation et guillemets peuvent changer.

Chaque remplacement conserve d'abord une copie exacte de l'ancien fichier sous `nom.xhb.backup-XXXXXX`, dans le meme dossier. Les sauvegardes ne sont pas purges automatiquement. Pour recuperer une version, conserver le fichier actuel a part puis donner l'extension `.xhb` a une copie de la sauvegarde souhaitee et l'ouvrir. Les fichiers ecrits et les sauvegardes sont prives (permissions `0600`).

L'ecriture utilise un fichier temporaire adjacent, `fsync`, puis un remplacement atomique. Le contenu sur disque doit correspondre a la version chargee/enregistree ; un changement externe bloque l'enregistrement et laisse les modifications en memoire. Un verrou `nom.xhb.panther-lock` protege contre un autre client Panther. Apres une interruption brutale, verifier qu'aucun autre client n'ecrit avant de retirer un verrou residuel.

**Ne pas modifier le meme fichier simultanement dans HomeBank, Panther ou un outil de synchronisation.** HomeBank et les autres outils ne respectent pas le verrou Panther ; le controle du contenu ne supprime pas toute course entre applications. Les liens symboliques ne sont pas remplaces.

## Previsions

Les recurrences journalieres, hebdomadaires, mensuelles, annuelles et relatives dans le mois, les limites d'occurrences, les reports de week-end et le rattrapage de fin de mois suivent les regles consultees dans HomeBank et la version web. Une recurrence invalide, un compte lie manquant ou une limite de calcul atteinte produit un avertissement de projection incomplete ; les operations inscrites restent disponibles. Les projections sont limitees a 10 000 pas par recurrence et 50 000 pas au total pour ne pas bloquer indefiniment le G3 sur des echeances tres anciennes.

Les cellules trop chargees indiquent des lignes supplementaires et leur info-bulle conserve le detail ; le clic ouvre l'agenda. Les devises ne sont jamais additionnees entre elles et les virements sont presentes comme flux entrants et sortants, pas comme une somme nette nulle. Consulter le calendrier ne poste aucune operation et ne modifie pas les dates des modeles.

## Securite Et Distribution

### Compatibilite Avec HomeBank Original

La version 0.3.2 corrige la declaration XML ajoutee lors des mutations : HomeBank 5.10.3 cherche `<homebank v=` seulement dans les 50 premiers octets (`src/hb-xml.c`, fonction `hb_xml_get_version`). Les sorties utilisent maintenant le marqueur `v` en premier, puis `d` s'il existe, avant les namespaces et autres attributs ; aucune declaration XML n'est ajoutee. Les textes UTF-8, valeurs numeriques, donnees inconnues, commentaires, ventilations et modeles restent conserves.

**Fichier > Exporter une copie** produit aussi ce format. Pour un fichier deja sauvegarde par une version precedente, ouvrir celui-ci dans Panther, puis **Fichier > Reparer la compatibilite HomeBank**. La confirmation ne change pas les operations : elle ajoute une demande de normalisation au journal. Choisir ensuite **Consolider le fichier XML**, **Exporter une copie**, ou **Synchroniser** pour produire le XML compatible. Voir le [guide de recuperation](DRIVE_SETUP.md#7-reparer-un-fichier-refuse-par-homebank-original).

L'export refuse les fichiers sans version plutot que d'inventer leur format, ainsi qu'un prologue qui empeche la detection HomeBank, plutot que d'en supprimer les commentaires. La lecture seule reste possible dans Panther. Les tests couvrent l'en-tete natif et la conservation des valeurs. `make original-compat-test` fournit une verification optionnelle avec GLib sur le Mac recent ; cette bibliotheque n'est pas une dependance du client PPC. Ce controle ne remplace pas un essai du fichier reel dans HomeBank original.

### Google Drive Direct : Compte De Service

La connexion directe sur G3 utilise le kit curl/wolfSSL et un compte de service. Aucun relais ni connexion Google dans Safari ne sont ajoutes. La synchronisation ne s'active qu'apres configuration et ouverture du fichier partage. Le SDK Apple 10.3.9 expose TLS 1.0 et OpenSSL 0.9.7b ; ces composants systeme ne sont pas utilises pour les requetes Drive. Le kit HTTPS est valide dans la VM, mais le nouveau client et l'authentification reelle restent a tester sur PPC.

Avant de choisir les dependances de cette pile, dans la VM Panther :

```sh
make drive-check
openssl version
```

Si un client curl recent est deja installe ailleurs :

```sh
CURL_BIN=/chemin/vers/curl make drive-check
```

Le diagnostic utilise une requete publique vers la configuration OpenID de Google, avec TLS 1.2 minimum, verification normale des certificats et sans lire la configuration personnelle de curl. Il ne lit aucun fichier bancaire, identifiant OAuth ou jeton. Corriger la date de la VM si necessaire ; ne pas utiliser `-k`/`--insecure` pour contourner une erreur. Une reponse HTTPS correcte ne suffit pas a valider OAuth ou l'acces au fichier Drive.

curl 7.10.2 peut afficher sa version correctement puis retourner le code `2`. Le script traite ce retour comme un avertissement et poursuit avec la date et le test HTTPS. Un curl ancien peut ensuite refuser `--proto` ou `--tlsv1.2` : le diagnostic se termine alors avec un message explicite et le code `1`. Corriger cet arret premature ne rend pas la pile TLS de Panther compatible avec l'integration prevue.

Le curl systeme `7.10.2 / OpenSSL 0.9.7b` reste incompatible. L'utilisateur a confirme le 7 octobre 2026 la reussite du [kit isole curl + wolfSSL](HTTPS_BUILD.md) dans la VM Panther/PPC : compilation, tests cryptographiques du profil sans ML-KEM, architecture et HTTPS Google avec certificats verifies. Ce kit n'installe rien dans le systeme et n'ajoute pas de relais. Le test sur le G3 physique et l'acces aux API Drive restent a valider.

L'utilisateur souhaite uniquement Safari sous Panther, sans navigateur sur un autre appareil. Le curl autonome ne modernise ni Safari ni ses API HTTPS/JavaScript : l'authentification Google interactive reste un obstacle distinct. Le flux Desktop standard utilise le navigateur systeme et PKCE ; le flux TV/appareils limites ne doit pas etre choisi simplement parce que l'application est ancienne et exige lui aussi une validation dans un navigateur compatible sur un autre appareil. Voir les [exigences de navigateur Google](https://support.google.com/accounts/answer/7675428).

Le mode [compte de service](https://developers.google.com/identity/protocols/oauth2/service-account) accepte par l'utilisateur est implemente. Il demande une configuration initiale Google Cloud sur une machine compatible, un fichier explicitement partage en modification et une cle dans le trousseau. Il ne connecte pas directement le compte personnel. Aucune cle de production ne doit etre ajoutee aux sources, aux archives ou aux journaux. Le [guide Drive](DRIVE_SETUP.md) detaille configuration, reprise, conflits, revisions et revocation.

References : [recommandations TLS de Google](https://developers.google.com/public-key-infrastructure/faq/tls-client-requirements), [OAuth pour applications Desktop](https://developers.google.com/identity/protocols/oauth2/native-app), [conditions du flux pour appareils limites](https://developers.google.com/identity/protocols/oauth2/limited-input-device), [verification des certificats avec curl](https://curl.se/docs/sslcerts.html). Les [prerequis de Mbed TLS](https://github.com/Mbed-TLS/mbedtls/blob/mbedtls-3.6.5/README.md) ne certifient pas sa compilation avec le GCC 3.3 de Xcode 1.5 : un portage ne peut pas etre annonce comme fonctionnel sans test sur cette chaine.

Les fichiers locaux restent utilisables hors ligne. Drive effectue des requetes HTTPS uniquement lorsque sa synchronisation est active ; il n'y a ni telemetrie ni demande de mot de passe Google. Une copie locale et un etat de reference sont conserves pour la reprise. Les fichiers XML non UTF-8, les DTD, les valeurs invalides et les formats plus recents sont refuses. Le portefeuille precedent reste affiche si un autre import echoue. Les montants utilisent NSDecimalNumber, pas les flottants binaires. libxml2 est utilise sans chargement de DTD, sans substitution d'entites et avec son acces reseau desactive.

Panther n'est pas un systeme maintenu : reserver cette machine a un usage local et garder les sauvegardes sur un systeme maintenu. Cette edition n'ajoute aucun chiffrement et ne resout pas les risques du systeme d'exploitation.

La pipeline GitHub moderne n'inclut pas cette cible. Une release PPC necessite le build et les tests dans la VM Panther ; ne pas renommer un package ARM64 en PPC. La version du prototype est independante des releases web / Electron.

References : [compilation et anciennes architectures Apple](https://developer.apple.com/library/archive/documentation/Porting/Conceptual/PortingUnix/compiling/compiling.html), [refus des entites XML externes](https://developer.apple.com/documentation/foundation/xmlparser/shouldresolveexternalentities).

Les options du processeur sont documentees dans [GCC 3.3 : PowerPC](https://gcc.gnu.org/onlinedocs/gcc-3.3.6/gcc/RS_002f6000-and-PowerPC-Options.html). Les declarations des API utilisees ont ete controlees dans les en-tetes Apple du SDK 10.3.9 ; cela ne remplace pas l'execution dans la VM.
