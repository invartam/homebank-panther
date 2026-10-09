# Cle Fictive De Test

`drive-rsa-test-key.txt` est une cle RSA 2048 bits generee uniquement pour les tests locaux, sans lien avec un compte Google. Elle est volontairement publique et ne doit JAMAIS etre importee comme cle de production ou servir a proteger des donnees.

Les tests utilisent l'identite fictive `fictional@test-project.iam.gserviceaccount.com` et un transport sans reseau. Aucune cle utilisateur et aucun trousseau ne sont lus. Le JWT de test est genere dans `build/drive-test-jwt.txt` pour une verification independante de sa signature.
