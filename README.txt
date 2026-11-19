Oghoule's Warpath - guide de leveling Horde 1-60 pour WoW Forever
==================================================================
Version 1.40. Toutes les races Horde. Guides ecrits a la main de 1 a 60, optimises pour
l'XP par heure, avec arrets en ville aux changements de zone.

Installation
------------
Copie le dossier OghoulesWarpath dans
  World of Warcraft\_forever_\Interface\AddOns\
puis relance le jeu (ou /reload).

Ce que fait l'addon
-------------------
- Une fenetre te dit quoi faire maintenant, une fleche indique ou aller.
- Les etapes se valident toutes seules (quetes acceptees, objectifs, remises).
- Boutons de ciblage (sous la fenetre) : donneur de quete, cible, maitre de vol, etc.
- Conseils de pierre de foyer, rappels d'achat (marchands), alerte journal plein.
- Detours automatiques quand une quete en demande une autre avant.
- Guides de donjon : /warpath donjon [nom].
- Quetes de metier : coche tes metiers dans les options (onglet Metiers).

Commandes
---------
/warpath (afficher/cacher), /warpath options, /warpath bug [note],
/warpath partage [on|off], /warpath donjon [nom], /warpath guide [nom|auto],
/warpath temps (temps de jeu actif et XP/h ; AFK, metiers et inactivite exclus),
/warpath pvp (victoires et morts face a l'Alliance, marquees sur la carte ; bouton
"Trophees de guerre" en bas a gauche de la carte pour les afficher ou les cacher).

Conseil : desactive la fleche d'un autre addon (ex. FojjiCore) si tu en vois deux ;
l'addon cache deja celle de FojjiCore.

Signaler un probleme
--------------------
Tape /warpath bug suivi d'une courte note a l'endroit du probleme. L'addon enregistre
le guide, l'etape, ta position et ton niveau. Envoie ensuite le fichier
  WTF\Account\<ton compte>\SavedVariables\OghoulesWarpath.lua
au createur de l'addon.

Partage des taux de drop
------------------------
L'addon mesure combien de fois les objets de quete tombent. Ces chiffres (anonymes :
objet, nombre de monstres tues, nombre d'objets obtenus) sont echanges avec les
autres joueurs de l'addon de ton groupe et de ta guilde. Desactivable dans les options
(onglet Itineraire) ou avec /warpath partage off.

Credits et licence
------------------
Createur : Oghoule.
Les donnees de quetes, de PNJ et d'objets sont derivees de la base de donnees de
Questie (https://github.com/Questie/Questie), par l'equipe de Questie et ses
contributeurs. Merci a eux. L'equipe de Questie accepte la copie de son travail selon
les termes de la GPLv3 ; Oghoule's Warpath est donc distribue sous la licence
GNU GPL version 3 (texte complet dans LICENSE.txt). Le code source de l'addon est le
contenu de ce dossier. Cet addon n'est ni affilie a Questie ni approuve par son equipe,
et n'utilise ni son nom ni son logo comme marque.
