# Télécommande veille / réveil du PC depuis le téléphone

Deux boutons sur ton téléphone :

| Action | Comment ça marche |
|---|---|
| **Mettre en veille** | Petit serveur sur le PC (`serveur_veille.py`) + page web avec un gros bouton, ajoutée à l'écran d'accueil du téléphone. |
| **Réveiller** | Wake-on-LAN : le téléphone envoie un « paquet magique » à la carte réseau du PC. (Un PC en veille ne fait tourner aucun programme, donc le réveil ne peut pas passer par le serveur.) |

Fonctionne sur Windows, macOS et Linux. Aucune dépendance à part Python 3.8+.

---

## 1. Installer la commande de veille (5 min)

1. Installe Python : <https://www.python.org/downloads/> (Windows : coche **« Add python.exe to PATH »**).
2. Copie le dossier `veille-pc` sur ton PC (ex. `C:\veille-pc`).
3. **Windows** : double-clique `installer-demarrage-windows.bat`.
   → Le serveur démarre maintenant et à chaque ouverture de session.
   → Si le pare-feu Windows demande l'autorisation : coche **Réseaux privés** uniquement.
   **macOS / Linux** : `python3 serveur_veille.py` (démarrage auto : Éléments de connexion sur macOS, `systemd --user` ou crontab `@reboot` sur Linux).
4. La console affiche un lien du type `http://192.168.1.20:8765/?k=XXXX`. Ouvre-le sur ton téléphone (même Wi-Fi).
   Le lien est aussi reconstructible : IP du PC + clé dans `veille-config.json`.
5. Sur le téléphone, ajoute la page à l'écran d'accueil :
   - iPhone (Safari) : Partager → *Sur l'écran d'accueil*
   - Android (Chrome) : ⋮ → *Ajouter à l'écran d'accueil*

**Windows — important :** si l'hibernation est activée, Windows hibernera au lieu de se mettre en veille (et le réveil Wake-on-LAN est moins fiable depuis l'hibernation). Pour l'éviter, dans un terminal **administrateur** :
```
powercfg /hibernate off
```

## 2. Activer le réveil Wake-on-LAN (10 min, une seule fois)

1. **BIOS/UEFI** (touche Suppr/F2 au démarrage) : active *Wake on LAN* / *Power On by PCI-E* / *Resume by LAN* (le nom varie selon la carte mère).
2. **Windows** : Gestionnaire de périphériques → Cartes réseau → ta carte → Propriétés :
   - onglet *Gestion de l'alimentation* : coche « Autoriser ce périphérique à sortir l'ordinateur du mode veille » **et** « N'autoriser que le paquet magique… »
   - onglet *Avancé* : `Wake on Magic Packet` = Activé
3. **Repère l'adresse MAC** de la carte réseau : `ipconfig /all` (Windows) → ligne *Adresse physique* de la carte utilisée (Ethernet de préférence). La page web l'affiche aussi si elle a pu être détectée.
4. **Sur le téléphone**, installe une app « Wake on LAN » (nombreuses gratuites sur App Store / Play Store), crée un appareil avec cette MAC et l'adresse de diffusion de ton réseau (souvent `192.168.1.255`), puis ajoute son raccourci/widget à l'écran d'accueil.
   - Android : l'app *HTTP Shortcuts* permet aussi de créer un raccourci Wake-on-LAN sur l'écran d'accueil (à vérifier dans ta version).
   - iPhone : choisis une app compatible *Raccourcis* si tu veux un bouton ou une commande Siri.

Alternative : `reveiller.py AA:BB:CC:DD:EE:FF` depuis tout autre appareil allumé du réseau (autre PC, Raspberry Pi, Termux sur Android).

## Limites à connaître

- **Ethernet recommandé.** Le réveil par Wi-Fi n'est supporté que par certains portables/cartes ; en Wi-Fi, il échoue souvent.
- **Même réseau uniquement** par défaut. Pour piloter depuis l'extérieur :
  - veille : installe [Tailscale](https://tailscale.com) sur le PC et le téléphone, puis utilise l'IP Tailscale du PC dans le lien ;
  - réveil : il faut un appareil toujours allumé chez toi (box qui sait envoyer du WoL, Raspberry Pi avec `reveiller.py`…), car un PC endormi ne répond pas sur Tailscale.
  - N'ouvre **pas** le port 8765 sur ta box vers Internet (le serveur est en HTTP simple).
- **Sécurité** : le lien contient une clé secrète. Ne le partage pas. Pour la changer, supprime `veille-config.json` et relance le serveur (nouveau lien).
- Portable sur batterie couvercle fermé : le Wake-on-LAN est souvent désactivé par le constructeur.

## Tester sans mettre le PC en veille

```
VEILLE_SIMULATION=1 python3 serveur_veille.py      # macOS/Linux
set VEILLE_SIMULATION=1 && python serveur_veille.py  # Windows
```
