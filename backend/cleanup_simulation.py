import asyncio
import os
import sys

# Configuration pour pouvoir importer les modules du backend
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db

async def cleanup_test_data():
    """
    Supprime les données créées par le script de simulation.
    Recherche les colis et événements marqués comme 'test' ou créés par le script.
    """
    await connect_db()
    print("\n--- NETTOYAGE DES DONNÉES DE TEST ---")
    
    # On supprime les colis qui ont "Test" dans le nom du destinataire (cas de notre simulateur)
    result = await db.parcels.delete_many({"recipient_name": "Destinataire Test"})
    print(f"🗑️  {result.deleted_count} colis de test supprimés de la collection 'parcels'.")

    # On peut aussi nettoyer les événements orphelins (optionnel mais propre)
    # Dans un vrai système, on marquerait les objets avec un tag 'is_test: true'
    
    print("\n✨ Nettoyage terminé.")

if __name__ == "__main__":
    asyncio.run(cleanup_test_data())
