#!/usr/bin/env python3
"""
Envoie un « paquet magique » Wake-on-LAN pour réveiller un PC.

À lancer depuis un AUTRE appareil allumé sur le même réseau
(autre PC, Raspberry Pi, NAS, ou Android via Termux).

Usage :  python3 reveiller.py AA:BB:CC:DD:EE:FF [adresse_broadcast]
"""
import socket
import sys


def reveiller(mac, broadcast="255.255.255.255", port=9):
    hexa = mac.replace(":", "").replace("-", "").strip()
    if len(hexa) != 12:
        raise ValueError(f"Adresse MAC invalide : {mac}")
    paquet = b"\xff" * 6 + bytes.fromhex(hexa) * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(paquet, (broadcast, port))
    print(f"Paquet magique envoyé à {mac} via {broadcast}:{port}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    reveiller(sys.argv[1], *(sys.argv[2:3] or []))
