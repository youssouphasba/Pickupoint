import re

def mask_phone(phone: str) -> str:
    """
    Masque un numéro de téléphone en ne laissant que l'indicatif (si présent) 
    et les 2 derniers chiffres.
    Format type: +221 77 123 45 67 -> +221 ••• •• 67
    """
    if not phone:
        return ""
    
    # On nettoie les espaces pour le traitement
    clean_phone = phone.replace(" ", "")
    
    # Si le numéro est très court, on ne fait rien ou on masque tout
    if len(clean_phone) <= 4:
        return "••••"

    # On essaie de garder l'indicatif (+ suivi de 1-3 chiffres)
    match = re.match(r"^(\+\d{1,3})", clean_phone)
    prefix = match.group(1) if match else ""
    
    # Les 2 derniers chiffres
    suffix = clean_phone[-2:]
    
    # Le milieu à masquer
    return f"{prefix} ••• •• {suffix}" if prefix else f"••• •• {suffix}"
