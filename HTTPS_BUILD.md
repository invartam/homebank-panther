# Tentative De Compilation HTTPS Pour Panther

Ce kit reste **experimental** et n'est pas un client Drive. L'utilisateur a confirme le 7 octobre 2026 sa compilation et le test HTTPS Google dans la VM OS X 10.3.9 / PowerPC, avec curl 8.22.0 et wolfSSL 5.9.4. Les tests cryptographiques du profil sans ML-KEM et la verification d'architecture ont reussi. Aucun binaire PPC n'a ete genere sur le Mac recent ; le test sur l'iMac G3 reel reste a faire. La reussite dans cette VM ne certifie pas toutes les configurations GCC 3.3, SDK et materiels Panther.

## Preparation Sur Le Mac Recent

Depuis la racine du projet `homebank-panther`, avec Node.js recent et un curl capable de HTTPS moderne :

```sh
make drive-tools-prepare
```

Le preparateur telecharge uniquement les sources publiques et le bundle de certificats. Il verifie leurs SHA-256 figes avant de creer `build/HomeBankPanther-https-sources.tar.gz` et son fichier `.sha256`. Il ne lit aucune donnee bancaire ni configuration Google. Le Mac recent n'est utilise que pour preparer les sources : **pas de relais pour les futurs transferts Drive**.

Le bundle CA est un instantane Mozilla du 25 septembre 2026 distribue par curl. Si un telechargement ne correspond plus au SHA-256 attendu, arreter : verifier l'origine et mettre a jour le manifeste apres revue, sans accepter automatiquement un nouveau hash.

## Compilation Dans La VM Panther

Transmettre l'archive de sources a la VM, l'extraire dans un chemin sans espaces, puis :

```sh
tar -xzf HomeBankPanther-https-sources.tar.gz
cd homebank-https-sources
sh build.sh
```

Le script utilise `gcc`, une seule tache de compilation et les options G3 sans AltiVec. Il construit les bibliotheques localement dans `out/ppc`, execute les tests cryptographiques wolfSSL, verifie l'architecture du curl obtenu, puis teste une URL publique de Google avec TLS 1.2 minimum et validation des certificats. La compilation peut etre longue sur G3 ou dans une VM emulee.

Le build force desormais **tout l'assembleur wolfSSL desactive** avec `--disable-asm`, en plus de `--disable-sp-asm` : ce dernier ne suffit pas a empecher l'activation de `WOLFSSL_SP_PPC` dans le moteur des grands entiers. Les erreurs de syntaxe de `sp_int.c` observees avec GCC 3.3 proviennent de ce chemin optimise. La correction choisit le backend C fourni par wolfSSL, sans modifier ses sources ni les protocoles TLS.

Les etapes s'executent dans le shell principal et s'arretent au premier echec. Une erreur wolfSSL ne doit plus etre suivie par une configuration curl. L'architecture est verifiee avec `lipo -info` ; le `lipo` de Panther ne prend pas en charge `-verify_arch`.

La validation native Apple est aussi desactivee : `--disable-sys-ca-certs` pour wolfSSL, `--without-apple-sectrust --disable-ca-native` pour curl. La detection des en-tetes Apple par wolfSSL ne garantit pas la presence des API utilisees : Panther ne fournit notamment pas `CFErrorRef` et `SecTrustEvaluateWithError`. La verification TLS reste active, effectuee par wolfSSL avec le bundle Mozilla `share/cacert.pem`, sans dependre du trousseau systeme obsolete. Ces options ne desactivent ni la verification de la chaine de certificats, ni celle du nom du serveur.

Pour wolfSSL uniquement, `-DXSNPRINTF=snprintf` conserve le formatage borne fourni par la libc de Panther. `snprintf` figure dans la [documentation Apple de stdio datee de janvier 2003](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/stdio.3.html). Sinon le mode C89 de wolfSSL remplace `XSNPRINTF` par `sprintf`, sans limite de taille : un diagnostic TLS contenant un chemin de source long peut alors deborder le tampon d'erreur. Le kit ne modifie pas les sources du fournisseur et ne masque pas les erreurs de certificat.

## Profil Cryptographique Panther

Sur la VM PPC, le test ML-KEM de wolfSSL 5.9.4 echoue a la comparaison des secrets issus de l'encapsulation et de la decapsulation (`test.c`, ligne 62861, premier jeu de parametres). La cause exacte n'est pas identifiee : ne pas attribuer automatiquement l'echec au compilateur, a l'endianness ou a l'emulateur, et ne pas utiliser ce module sur cette cible tant qu'il n'est pas valide.

Le kit utilise donc `--disable-mlkem --disable-pqc-hybrids` pour **retirer ces algorithmes de la bibliotheque et de la negociation TLS**, et pas uniquement ignorer leur test. La [documentation wolfSSL des groupes TLS](https://www.wolfssl.com/documentation/manuals/wolfssl/appendix07.html) distingue les groupes classiques et les groupes hybrides ML-KEM. Ce profil conserve TLS 1.2/1.3, les algorithmes classiques et la validation des certificats, mais **n'offre pas de protection post-quantique**. Un serveur imposant un echange ML-KEM ne sera pas compatible.

Les tests cryptographiques restent obligatoires pour tous les algorithmes compiles ; tout autre echec arrete le build avant installation et avant curl. Ne pas supprimer cette etape ni forcer un code de sortie reussi. Ce profil concerne uniquement le kit HTTPS experimental Panther, pas les clients Electron, web ou mobiles. Le build ARM64 de verification utilise le meme profil pour tester la recette.

## Reprise Et Diagnostic

Si curl echoue avec `redefinition of struct timeval` dans `curl_setup.h`, sa configuration n'a pas defini `HAVE_STRUCT_TIMEVAL` et active a tort la structure de secours. Sans le `config.log` de la VM, la raison exacte du test negatif initial reste inconnue. Le kit ajoute une etape `curl-system-types` : le compilateur cible verifie `struct timeval` et ses membres avec `sys/types.h` inclus avant `sys/socket.h` et `sys/time.h`, selon l'ordre BSD classique. **Seulement apres reussite**, `curl_cv_struct_timeval=yes` renseigne le cache de configure. Aucune structure systeme n'est redefinie ou remplacee. Si cette verification echoue, le build s'arrete et conserve son journal ; ne pas forcer le resultat sans ce controle. `CC` doit designer un executable, sans arguments (par exemple `gcc` ou `clang`).

Pour reprendre apres un ancien echec, utiliser le nouveau kit dans un dossier neuf afin de ne pas reutiliser des objets compiles avec l'assembleur ou une installation partielle. Les anciennes sources et journaux peuvent etre conserves a part ; aucun nettoyage de leurs fichiers n'est impose.

Exception pour la correction de `struct timeval` : si wolfSSL a deja passe ses tests avec le profil sans ML-KEM et le formatage borne, ses options sont inchangees. On peut reextraire ce kit au meme emplacement, sans supprimer `src/`, `work/` ou `out/`, puis relancer `sh build.sh`. Cela met notamment a jour `build.sh` et ajoute `check-curl-timeval.c`. Le script reconfigure curl et verifie de nouveau chaque etape ; il ne saute pas les tests cryptographiques.

Il ne remplace **ni `/usr/bin/curl`, ni OpenSSL, ni les frameworks du systeme**. Ne pas utiliser sudo. Les sources restent dans `src/`, les fichiers de compilation dans `work/`, les journaux dans `logs/ppc/`. En cas d'echec, transmettre le nom de l'etape et la fin de son journal. Ne pas masquer les erreurs en activant TLS 1.0, en ignorant les certificats ou en supprimant les tests.

Apres une compilation reussie, depuis le dossier du client Panther :

```sh
CURL_BIN=/chemin/homebank-https-sources/out/ppc/bin/curl make drive-check
```

Le chemin du fichier CA est configure lors de la compilation. Si la sortie est transferee vers l'iMac dans un autre dossier, transporter aussi `share/cacert.pem` et definir les deux chemins explicitement :

```sh
CURL_BIN=/nouveau/chemin/out/ppc/bin/curl CURL_CA_BUNDLE=/nouveau/chemin/out/ppc/share/cacert.pem make drive-check
```

Verifier la date du systeme. Le succes du test HTTPS ne valide pas encore les API Drive ni l'authentification Google.

## Verification Sur Apple Silicon

Dans le kit, pour verifier la recette sur le Mac actuel sans produire de PPC :

```sh
ARCH=arm64 CC=clang JOBS=2 DEPLOYMENT_TARGET=13.0 sh build.sh
```

Les fichiers restent separes dans `out/arm64` et `work/arm64`. Une reussite ARM64 **ne prouve pas** une compilation ou execution sur Panther. Aucun contournement du compilateur historique n'est applique automatiquement.

La recette a ete executee sur Apple Silicon : compilation des deux projets, tests cryptographiques wolfSSL et requete HTTPS Google avec validation des certificats ont reussi. Aucun binaire PowerPC n'a ete produit ou teste.

## Validation Rapportee Dans La VM PPC

Le journal transmis par l'utilisateur le 7 octobre 2026 confirme toutes les etapes, de `wolfssl-configure` a `curl-dependencies`, puis `Connexion HTTPS Google validee avec ce client`. Le binaire s'identifie comme `curl 8.22.0 (powerpc-apple-darwin7.9.0) libcurl/8.22.0 wolfSSL/5.9.4`. Cette validation est rapportee par l'utilisateur, pas une execution de la VM par l'agent. Elle concerne les tests cryptographiques du profil retenu et une URL publique Google ; aucun OAuth, fichier Drive, televersement ou test sur le G3 physique n'a ete valide.

Le navigateur Safari de Panther n'utilise pas ce curl autonome : ce build ne met pas a jour sa pile HTTPS ni son moteur JavaScript. La connexion interactive Google est un prerequis distinct, soumis aux [exigences de navigateur Google](https://support.google.com/accounts/answer/7675428). Le flux pour appareils limites implique aussi une validation dans un navigateur sur un autre appareil ; il ne supprime pas ce prerequis et ne doit pas etre detourne pour un client Desktop.

## Licences Et Maintenance

Les archives conservent les licences des projets. wolfSSL 5.9.4 est distribue sous GPLv3 ou licence commerciale ; la licence curl est incluse dans son archive. Ne pas redistribuer les binaires sans examiner ces licences. Ce kit n'est pas embarque dans le package de l'application Panther.

Ces versions sont figees pour la reproductibilite, pas pour un support indefini. Revoir les avis de securite et mettre a jour les dependances et le bundle CA avant toute utilisation durable. Le systeme Panther reste non maintenu.

References : [compilation de curl](https://curl.se/docs/install.html), [wolfSSL : C89 et options de compilation](https://www.wolfssl.com/documentation/manuals/wolfssl/chapter02.html), [archives et hashes wolfSSL](https://www.wolfssl.com/download/), [certificats CA de curl](https://curl.se/docs/caextract.html).
