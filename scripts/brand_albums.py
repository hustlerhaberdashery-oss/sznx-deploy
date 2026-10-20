import os
from mutagen.easyid3 import EasyID3
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TCOP, COMM

# CONFIGURATION
TARGET_DIR = "/Volumes/NFT TV/Users/theloci/Downloads/AUTHENTICATED COMBINED"
CONTRACT_ADDRESS = "0xFb683A41845eD71a15cce8C2bC0c4A608d5112FB" # SZNX Contract (Deployer)
LEDGER_REF = "MF-AUTHOR-2026-001 | CUSIP 0207361455"

print(f"[*] TARGET LOCKED: {TARGET_DIR}")
print(f"[*] BRANDING IRON HEATED: {CONTRACT_ADDRESS}")

def brand_file(filepath):
    try:
        audio = MP3(filepath, ID3=ID3)
        
        # 1. Inscribe the Copyright (TCOP) - The Legal Claim
        audio.tags.add(TCOP(encoding=3, text=f"SZNX Sovereign Estate | {CONTRACT_ADDRESS}"))
        
        # 2. Inscribe the Comment (COMM) - The Ledger Ref
        audio.tags.add(COMM(encoding=3, lang='eng', desc='SovereignStatus', text=f"Asset of the $60B Master Ledger. {LEDGER_REF}"))
        
        audio.save()
        print(f"[+] BRANDED: {os.path.basename(filepath)}")
    except Exception as e:
        print(f"[!] SKIPPED (Format/Error): {os.path.basename(filepath)} - {e}")

# Execute Sweep
for root, dirs, files in os.walk(TARGET_DIR):
    for file in files:
        if file.lower().endswith(".mp3"):
            brand_file(os.path.join(root, file))

print("\n[*] INSCRIPTION COMPLETE. THE ALBUMS ARE NOW CONTRACT ASSETS.")
