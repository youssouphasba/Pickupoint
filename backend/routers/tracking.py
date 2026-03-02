"""
Router tracking : endpoints publics (sans authentification).
"""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from core.exceptions import not_found_exception
from database import db
from services.parcel_service import get_parcel_timeline

router = APIRouter()


@router.get("/{tracking_code}", summary="Statut public d'un colis")
async def track_parcel(tracking_code: str):
    parcel = await db.parcels.find_one(
        {"tracking_code": tracking_code},
        {
            "_id": 0,
            "sender_user_id": 0,
            "payment_ref": 0,
            "pickup_code": 0,     # codes de sécurité non exposés publiquement
            "delivery_code": 0,
        },
    )
    if not parcel:
        raise not_found_exception("Colis")

    # Inclure la timeline publique
    parcel_id = parcel.get("parcel_id")
    if parcel_id:
        timeline = await get_parcel_timeline(parcel_id)
        public_timeline = [
            {k: v for k, v in evt.items() if k not in ("actor_id", "metadata")}
            for evt in timeline
        ]
        parcel["events"] = public_timeline

    return parcel


@router.get("/{tracking_code}/events", summary="Historique complet du colis")
async def track_parcel_events(tracking_code: str):
    parcel = await db.parcels.find_one(
        {"tracking_code": tracking_code},
        {"_id": 0, "parcel_id": 1},
    )
    if not parcel:
        raise not_found_exception("Colis")

    timeline = await get_parcel_timeline(parcel["parcel_id"])
    # On retire actor_id des événements publics
    public_timeline = [
        {k: v for k, v in evt.items() if k not in ("actor_id", "metadata")}
        for evt in timeline
    ]
    return {"tracking_code": tracking_code, "events": public_timeline}


@router.get("/view/{tracking_code}", response_class=HTMLResponse, summary="Page de suivi Web (sans app)")
async def view_parcel_web(tracking_code: str):
    """Affiche une page HTML élégante pour le suivi public."""
    parcel = await track_parcel(tracking_code) # Utilise la logique existante
    
    status_map = {
        "CREATED": ("Créé", "📦"),
        "DROPPED_AT_ORIGIN_RELAY": ("Déposé au relais", "🏪"),
        "IN_TRANSIT": ("En transit", "🚚"),
        "AT_DESTINATION_RELAY": ("Arrivé au relais destination", "📍"),
        "AVAILABLE_AT_RELAY": ("Prêt pour retrait", "✅"),
        "OUT_FOR_DELIVERY": ("En cours de livraison", "🚲"),
        "DELIVERED": ("Livré", "🎉"),
        "CANCELLED": ("Annulé", "❌"),
    }
    
    current_status = parcel.get("status", "CREATED")
    status_label, status_emoji = status_map.get(current_status, (current_status, "📦"))
    
    events_html = ""
    for evt in reversed(parcel.get("events", [])):
        ts = evt.get("created_at")
        if isinstance(ts, str):
             # Format simple: "2023-10-27T10:00:00Z" -> "27 Oct 10:00"
             ts = ts.replace("T", " ")[:16]
        
        events_html += f"""
        <div class="event">
            <div class="event-dot"></div>
            <div class="event-content">
                <div class="event-time">{ts}</div>
                <div class="event-title">{evt.get('notes') or evt.get('to_status')}</div>
            </div>
        </div>
        """

    html = f"""
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Suivi PickuPoint - {tracking_code}</title>
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
        <style>
            :root {{
                --primary: #007AFF;
                --bg: #F5F7FA;
                --card: #FFFFFF;
                --text: #1D1D1F;
                --text-muted: #86868B;
            }}
            body {{
                font-family: 'Inter', -apple-system, sans-serif;
                background-color: var(--bg);
                color: var(--text);
                margin: 0;
                display: flex;
                justify-content: center;
                padding: 20px;
            }}
            .container {{
                width: 100%;
                max-width: 500px;
            }}
            .header {{
                text-align: center;
                margin-bottom: 30px;
            }}
            .logo {{
                font-size: 24px;
                font-weight: 800;
                color: var(--primary);
                letter-spacing: -1px;
            }}
            .card {{
                background: var(--card);
                border-radius: 20px;
                padding: 24px;
                box-shadow: 0 10px 30px rgba(0,0,0,0.05);
                margin-bottom: 20px;
            }}
            .status-badge {{
                display: inline-block;
                padding: 6px 12px;
                background: rgba(0,122,255,0.1);
                color: var(--primary);
                border-radius: 100px;
                font-size: 13px;
                font-weight: 600;
                margin-bottom: 15px;
            }}
            .tracking-id {{
                font-size: 28px;
                font-weight: 700;
                margin: 0 0 5px 0;
            }}
            .status-large {{
                font-size: 20px;
                margin-top: 10px;
                display: flex;
                align-items: center;
                gap: 10px;
            }}
            .timeline {{
                margin-top: 30px;
                position: relative;
                padding-left: 30px;
            }}
            .timeline::before {{
                content: '';
                position: absolute;
                left: 10px;
                top: 5px;
                bottom: 5px;
                width: 2px;
                background: #E5E5EA;
            }}
            .event {{
                position: relative;
                margin-bottom: 25px;
            }}
            .event-dot {{
                position: absolute;
                left: -24px;
                top: 6px;
                width: 10px;
                height: 10px;
                background: var(--primary);
                border-radius: 50%;
                border: 3px solid white;
                box-shadow: 0 0 0 2px var(--primary);
            }}
            .event:first-child .event-dot {{
                background: #34C759;
                box-shadow: 0 0 0 2px #34C759;
            }}
            .event-time {{
                font-size: 12px;
                color: var(--text-muted);
                margin-bottom: 4px;
            }}
            .event-title {{
                font-size: 15px;
                font-weight: 600;
            }}
            .footer {{
                text-align: center;
                font-size: 12px;
                color: var(--text-muted);
                margin-top: 40px;
            }}
            .btn-app {{
                display: block;
                text-align: center;
                background: var(--primary);
                color: white;
                text-decoration: none;
                padding: 15px;
                border-radius: 14px;
                font-weight: 600;
                margin-top: 30px;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <div class="logo">PickuPoint</div>
            </div>
            
            <div class="card">
                <div class="status-badge">Suivi en direct</div>
                <h1 class="tracking-id">{tracking_code}</h1>
                <div class="status-large">{status_emoji} {status_label}</div>
            </div>

            <div class="card">
                <div class="timeline">
                    {events_html}
                </div>
            </div>

            <a href="#" class="btn-app">Ouvrir dans l'application</a>

            <div class="footer">
                &copy; 2026 PickuPoint - Logistique Connectée
            </div>
        </div>
    </body>
    </html>
    """
    return html
