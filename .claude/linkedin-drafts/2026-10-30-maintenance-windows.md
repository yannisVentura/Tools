# Brouillon LinkedIn : maintenance Windows silencieuse (SFC + winget)

Date : 2026-10-30
Sujet : `Windows/Maintenance/` (commits d025e05 à 385dc10)
Illustration : `2026-10-30-maintenance-windows.svg` (1200×627)

---

## Post (FR)

Un PC Windows 10 qu'on vous donne, c'est surtout un PC qu'il faut maintenir. Qui s'en charge quand on n'est pas à côté ?

Un proche peinait à garder le sien à jour. J'en ai fait un outil PowerShell de maintenance silencieuse.

🔧 La démarche
- 38 exigences rédigées en EARS, critères d'acceptation Gherkin et matrice de traçabilité
- Tests sur une VM Windows 10 neuve, puis sur le poste réel, puis sur mon Windows 11
- Chaque retour diagnostiqué depuis le journal et les codes retour : winget absent, 0xC0000135 sous SYSTEM, alias winget inexécutable par SYSTEM… et la spec mise à jour à chaque correction
- Des sous-agents IA spécialisés (spécifications, recommandations Microsoft Learn, commits git) que j'ai pilotés et validés

✅ Le résultat
Une tâche planifiée hebdomadaire sous SYSTEM : SFC, puis winget application par application. Aucune fenêtre pour l'utilisateur, un dossier protégé par ACL, une ligne de journal par application.

💡 Ce que j'en retiens
Le choix décisif était produit, pas technique : viser « un poste globalement maintenu » plutôt que « tout mettre à jour ». Une application en échec ne masque plus les autres succès : elle apparaît en ERREUR, à traiter à la main.

Et vous, comment maintenez-vous les PC de vos proches ?

#PowerShell #Windows #Automatisation #Workplace #Infrastructure

---

## Variante d'accroche

« Un échec sur une application faisait échouer toute la maintenance. Le correctif n'était pas technique, c'était une décision produit. »

(Remplace la première ligne ; la suite du post reste identique.)

---

## Hashtags

#PowerShell #Windows #Automatisation #Workplace #Infrastructure

Alternatives possibles : #winget #ModernWorkplace #EndpointManagement

---

## Texte alternatif de l'illustration

Schéma du fonctionnement de l'outil de maintenance Windows. Quatre étapes reliées par des flèches : une tâche planifiée exécutée chaque semaine sous le compte SYSTEM, la vérification des fichiers système avec SFC (et DISM en option), la mise à jour des applications par winget une application à la fois, puis un journal d'une ligne par application. En dessous, un extrait de journal : une ligne OK pour une application mise à jour, une ligne ERREUR avec code retour pour une autre, et la tâche qui reste en succès. Mention : aucune fenêtre pour l'utilisateur, un échec isolé n'arrête pas les autres.

---

## Suggestion de premier commentaire

Le code, les spécifications (exigences EARS + traçabilité) et le guide de dépannage sont en accès libre ici :
https://github.com/yannisVentura/Tools/tree/master/Windows/Maintenance

Retours bienvenus, notamment sur l'exécution de winget sous SYSTEM.

---

## Notes de relecture (non publiées)

- Chiffres vérifiés : 38 exigences (REQ-MAINT-001 à 038) dans `docs/SPECIFICATIONS.md` ; 6 commits sur `Windows/Maintenance`.
- Codes cités issus des commits et du dépannage : 0xC0000135 (runtime VC++ manquant sous SYSTEM), alias winget (point d'analyse utilisateur) inexécutable sous SYSTEM.
- Format retenu : celui de la définition de rôle (120 à 220 mots, 3 emojis, 5 hashtags), plus strict que le skill (250 à 400 mots, 6 à 10 hashtags).
- Lien GitHub placé en premier commentaire, pas dans le post (portée).
