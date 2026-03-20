from pathlib import Path
import textwrap

from PIL import Image, ImageDraw, ImageFont


WIDTH = 1280
HEIGHT = 720
OUT_DIR = Path(__file__).resolve().parent / "tutorial_video"
SLIDES_DIR = OUT_DIR / "slides"
CONCAT_FILE = OUT_DIR / "ffmpeg_concat.txt"

BG = "#0B1220"
BG_ALT = "#121B2F"
CARD = "#172338"
CARD_ALT = "#1F2F49"
ACCENT = "#2ED1A2"
ACCENT_ALT = "#5EA8FF"
TEXT = "#F7FAFC"
TEXT_SOFT = "#D2DBE8"
TEXT_MUTED = "#9FB0C8"
WARN = "#FFD166"


SCENARIOS = [
    {
        "code": "R2R",
        "title": "Relais vers relais",
        "route": "Relais Medina, Dakar -> Relais Escale, Thies",
        "example": "Fatou depose au relais, Moussa transporte, Mareme remet au destinataire.",
        "codes": "Codes utilises : pickup_code pour la collecte, relay_pin pour le retrait final.",
        "statuses": [
            "CREATED",
            "DROPPED_AT_ORIGIN_RELAY",
            "IN_TRANSIT",
            "AVAILABLE_AT_RELAY",
            "DELIVERED",
        ],
        "steps": [
            {
                "title": "Depot au relais de depart",
                "bullets": [
                    "Expediteur : Fatou Diallo",
                    "Agent relais : Aminata, Relais Medina - Dakar",
                    "Action : Fatou depose le colis au relais",
                    "Controle : Aminata effectue un scan d'entree",
                    "Resultat : le colis est pret pour la collecte du livreur",
                ],
                "status": "CREATED -> DROPPED_AT_ORIGIN_RELAY",
                "screen": "Ce que voit l'utilisateur : colis depose, suivi actif, relais de depart confirme.",
            },
            {
                "title": "Collecte par le livreur",
                "bullets": [
                    "Livreur : Moussa Livreur",
                    "Action : Moussa vient recuperer le colis au relais",
                    "Verification : Aminata lui donne le pickup_code",
                    "Validation : confirm-pickup dans l'application",
                    "Resultat : la mission demarre et le colis passe en transit",
                ],
                "status": "DROPPED_AT_ORIGIN_RELAY -> IN_TRANSIT",
                "screen": "Ce que voit l'utilisateur : livreur assigne, trajet en cours, statut en transit.",
            },
            {
                "title": "Depot au relais d'arrivee",
                "bullets": [
                    "Relais d'arrivee : Mareme, Relais Escale - Thies",
                    "Action : Moussa depose le colis au relais final",
                    "Controle : Mareme effectue un scan d'entree",
                    "Resultat : le colis devient disponible au retrait",
                ],
                "status": "IN_TRANSIT -> AVAILABLE_AT_RELAY",
                "screen": "Ce que voit l'utilisateur : colis disponible au relais avec notification de retrait.",
            },
            {
                "title": "Retrait par le destinataire",
                "bullets": [
                    "Destinataire : Ibrahima Sow",
                    "Action : Ibrahima se presente au relais Escale",
                    "Verification : Mareme effectue le scan_out avec le relay_pin",
                    "Resultat : retrait confirme, preuve de remise enregistree",
                ],
                "status": "AVAILABLE_AT_RELAY -> DELIVERED",
                "screen": "Ce que voit l'utilisateur : colis retire, historique complet, mission terminee.",
            },
        ],
    },
    {
        "code": "R2H",
        "title": "Relais vers domicile",
        "route": "Relais Medina, Dakar -> Domicile Ibrahima, Thies",
        "example": "Fatou depose au relais, Moussa transporte, puis livre a domicile.",
        "codes": "Codes utilises : pickup_code pour la collecte, delivery_code pour la remise finale.",
        "statuses": [
            "CREATED",
            "DROPPED_AT_ORIGIN_RELAY",
            "IN_TRANSIT",
            "OUT_FOR_DELIVERY",
            "DELIVERED",
        ],
        "steps": [
            {
                "title": "Depot au relais de depart",
                "bullets": [
                    "Expediteur : Fatou Diallo",
                    "Agent relais : Aminata, Relais Medina - Dakar",
                    "Action : le colis est depose au relais",
                    "Controle : scan d'entree par le relais",
                    "Resultat : attente de collecte livreur",
                ],
                "status": "CREATED -> DROPPED_AT_ORIGIN_RELAY",
                "screen": "Ce que voit l'utilisateur : depot confirme, relais de depart affiche, suivi lance.",
            },
            {
                "title": "Collecte et depart en mission",
                "bullets": [
                    "Livreur : Moussa Livreur",
                    "Action : le relais remet le colis au livreur",
                    "Verification : pickup_code saisi au moment du depart",
                    "Resultat : la mission de livraison est lancee",
                ],
                "status": "DROPPED_AT_ORIGIN_RELAY -> IN_TRANSIT",
                "screen": "Ce que voit l'utilisateur : livreur en charge, position et statut en transit.",
            },
            {
                "title": "Arrivee a destination",
                "bullets": [
                    "Destination : domicile de Ibrahima Sow, Thies",
                    "Action : Moussa arrive sur place",
                    "Validation : arrive-at-destination dans l'application",
                    "Resultat : le colis passe en remise a domicile",
                ],
                "status": "IN_TRANSIT -> OUT_FOR_DELIVERY",
                "screen": "Ce que voit l'utilisateur : livreur arrive, code de remise pret a etre partage.",
            },
            {
                "title": "Remise au destinataire",
                "bullets": [
                    "Destinataire : Ibrahima Sow",
                    "Action : Ibrahima donne son delivery_code",
                    "Validation : confirm-delivery par le livreur",
                    "Resultat : remise confirmee et historisee",
                ],
                "status": "OUT_FOR_DELIVERY -> DELIVERED",
                "screen": "Ce que voit l'utilisateur : colis livre, preuve de remise et suivi clos.",
            },
        ],
    },
    {
        "code": "H2R",
        "title": "Domicile vers relais",
        "route": "Chez Fatou, Medina -> Relais Plateau, Dakar",
        "example": "Moussa recupere le colis au domicile, puis Cheikh le remet au relais.",
        "codes": "Codes utilises : pickup_code pour la collecte, relay_pin pour le retrait final.",
        "statuses": [
            "CREATED",
            "IN_TRANSIT",
            "AVAILABLE_AT_RELAY",
            "DELIVERED",
        ],
        "steps": [
            {
                "title": "Collecte au domicile de l'expediteur",
                "bullets": [
                    "Expediteur : Fatou Diallo",
                    "Lieu : Chez Fatou, Medina",
                    "Livreur : Moussa Livreur",
                    "Action : Moussa se rend au domicile pour la collecte",
                    "Resultat : la mission de collecte est active",
                ],
                "status": "CREATED",
                "screen": "Ce que voit l'utilisateur : mission assignee, livreur en approche, details de collecte.",
            },
            {
                "title": "Validation de la collecte",
                "bullets": [
                    "Action : Fatou donne le pickup_code au livreur",
                    "Validation : confirm-pickup dans l'application",
                    "Resultat : le colis quitte le domicile et part vers le relais",
                ],
                "status": "CREATED -> IN_TRANSIT",
                "screen": "Ce que voit l'utilisateur : collecte confirmee, colis en transit vers le relais.",
            },
            {
                "title": "Depot au relais de destination",
                "bullets": [
                    "Relais de destination : Cheikh, Relais Plateau - Dakar",
                    "Action : Moussa depose le colis au relais",
                    "Controle : scan d'entree effectue par Cheikh",
                    "Resultat : retrait disponible pour le destinataire",
                ],
                "status": "IN_TRANSIT -> AVAILABLE_AT_RELAY",
                "screen": "Ce que voit l'utilisateur : colis disponible au relais, point de retrait confirme.",
            },
            {
                "title": "Retrait final au relais",
                "bullets": [
                    "Destinataire : Ibrahima Sow",
                    "Action : retrait au Relais Plateau",
                    "Validation : scan_out avec relay_pin",
                    "Resultat : remise terminee et preuve de retrait enregistree",
                ],
                "status": "AVAILABLE_AT_RELAY -> DELIVERED",
                "screen": "Ce que voit l'utilisateur : colis recupere, suivi termine.",
            },
        ],
    },
    {
        "code": "H2H",
        "title": "Domicile vers domicile",
        "route": "Chez Fatou, Medina -> Domicile Ibrahima, Thies",
        "example": "Scenario express : collecte au domicile, transport direct, remise a domicile.",
        "codes": "Codes utilises : pickup_code a la collecte, delivery_code a la remise.",
        "statuses": [
            "CREATED",
            "IN_TRANSIT",
            "OUT_FOR_DELIVERY",
            "DELIVERED",
        ],
        "steps": [
            {
                "title": "Collecte au domicile",
                "bullets": [
                    "Expediteur : Fatou Diallo",
                    "Lieu : Chez Fatou, Medina",
                    "Livreur : Moussa Livreur",
                    "Action : le livreur vient chercher le colis",
                ],
                "status": "CREATED",
                "screen": "Ce que voit l'utilisateur : mission de collecte active, details du livreur visibles.",
            },
            {
                "title": "Depart en transit",
                "bullets": [
                    "Action : Fatou donne le pickup_code au livreur",
                    "Validation : confirm-pickup",
                    "Resultat : le colis part vers le domicile du destinataire",
                ],
                "status": "CREATED -> IN_TRANSIT",
                "screen": "Ce que voit l'utilisateur : collecte confirmee, trajet en cours.",
            },
            {
                "title": "Arrivee chez le destinataire",
                "bullets": [
                    "Destination : domicile de Ibrahima Sow, Thies",
                    "Action : le livreur arrive a destination",
                    "Validation : arrive-at-destination",
                    "Resultat : remise en cours",
                ],
                "status": "IN_TRANSIT -> OUT_FOR_DELIVERY",
                "screen": "Ce que voit l'utilisateur : livreur arrive, livraison imminente.",
            },
            {
                "title": "Remise finale",
                "bullets": [
                    "Destinataire : Ibrahima Sow",
                    "Action : Ibrahima communique le delivery_code",
                    "Validation : confirm-delivery",
                    "Resultat : livraison complete et historisee",
                ],
                "status": "OUT_FOR_DELIVERY -> DELIVERED",
                "screen": "Ce que voit l'utilisateur : colis livre, historique final et preuve de remise.",
            },
        ],
    },
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    font_candidates = []
    if bold:
        font_candidates.extend(
            [
                "C:/Windows/Fonts/arialbd.ttf",
                "C:/Windows/Fonts/segoeuib.ttf",
                "C:/Windows/Fonts/calibrib.ttf",
            ]
        )
    else:
        font_candidates.extend(
            [
                "C:/Windows/Fonts/arial.ttf",
                "C:/Windows/Fonts/segoeui.ttf",
                "C:/Windows/Fonts/calibri.ttf",
            ]
        )
    for candidate in font_candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


TITLE_FONT = load_font(42, bold=True)
SUBTITLE_FONT = load_font(28, bold=True)
BODY_FONT = load_font(26)
BODY_BOLD_FONT = load_font(26, bold=True)
SMALL_FONT = load_font(20)
TINY_FONT = load_font(16)
CONTENT_FONT = load_font(20)
CONTENT_BOLD_FONT = load_font(20, bold=True)
META_FONT = load_font(16)
STEP_FONT = load_font(18)
STEP_BOLD_FONT = load_font(18, bold=True)

STATUS_LABELS = {
    "CREATED": "CREATED",
    "DROPPED_AT_ORIGIN_RELAY": "ORIGIN RELAY",
    "IN_TRANSIT": "TRANSIT",
    "AVAILABLE_AT_RELAY": "AT RELAY",
    "OUT_FOR_DELIVERY": "OUT FOR DELIVERY",
    "DELIVERED": "DELIVERED",
}


def wrap_text(text: str, width: int) -> list[str]:
    return textwrap.wrap(text, width=width, break_long_words=False)


def draw_wrapped(draw: ImageDraw.ImageDraw, text: str, xy: tuple[int, int], font, fill, width: int, line_gap: int = 10):
    x, y = xy
    lines = wrap_text(text, width)
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        bbox = draw.textbbox((x, y), line, font=font)
        y = bbox[3] + line_gap
    return y


def draw_header(draw: ImageDraw.ImageDraw, tag: str, title: str, subtitle: str):
    draw.rounded_rectangle((56, 40, 1224, 164), radius=26, fill=BG_ALT)
    tag_bbox = draw.textbbox((0, 0), tag, font=SUBTITLE_FONT)
    tag_width = max(160, min(380, tag_bbox[2] - tag_bbox[0] + 40))
    draw.rounded_rectangle((76, 62, 76 + tag_width, 108), radius=18, fill=ACCENT_ALT)
    draw.text((96, 71), tag, font=SUBTITLE_FONT, fill=TEXT)
    draw.text((76, 118), title, font=TITLE_FONT, fill=TEXT)
    draw.text((76, 176), subtitle, font=BODY_FONT, fill=TEXT_SOFT)


def draw_status_bar(draw: ImageDraw.ImageDraw, statuses: list[str], current: str):
    left = 64
    top = 626
    width = 1152
    draw.rounded_rectangle((left, top, left + width, top + 66), radius=22, fill=BG_ALT)
    current_index = statuses.index(current.split(" -> ")[-1]) if " -> " in current and current.split(" -> ")[-1] in statuses else None
    slot_width = width / max(1, len(statuses))
    for index, status in enumerate(statuses):
        color = ACCENT if current_index is not None and index <= current_index else TEXT_MUTED
        short = STATUS_LABELS.get(status, status.replace("_", " "))
        x = int(left + 24 + slot_width * index)
        draw.text((x, top + 21), short, font=TINY_FONT, fill=color)
        if index < len(statuses) - 1:
            arrow_x = int(left + slot_width * (index + 1) - 18)
            draw.text((arrow_x, top + 21), "->", font=TINY_FONT, fill=TEXT_MUTED)


def render_intro_slide(slide_no: int, scenario_index: int, scenario: dict):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw_header(
        draw,
        f"Scenario {scenario_index}/4",
        f"{scenario['code']} - {scenario['title']}",
        scenario["route"],
    )

    draw.rounded_rectangle((56, 220, 590, 582), radius=28, fill=CARD)
    draw.rounded_rectangle((620, 220, 1224, 582), radius=28, fill=CARD_ALT)

    draw.text((84, 252), "Exemple reel", font=SUBTITLE_FONT, fill=ACCENT)
    y = draw_wrapped(draw, scenario["example"], (84, 304), CONTENT_FONT, TEXT, 25)
    y += 24
    draw.text((84, y), "Codes utilises", font=SUBTITLE_FONT, fill=ACCENT_ALT)
    draw_wrapped(draw, scenario["codes"], (84, y + 44), CONTENT_FONT, TEXT_SOFT, 25)

    draw.text((648, 252), "Sequence de statuts", font=SUBTITLE_FONT, fill=ACCENT)
    status_y = 308
    for idx, status in enumerate(scenario["statuses"], start=1):
        draw.rounded_rectangle((648, status_y + 8, 662, status_y + 22), radius=7, fill=ACCENT if idx == len(scenario["statuses"]) else ACCENT_ALT)
        draw.text((686, status_y), f"{idx}. {status.replace('_', ' ')}", font=CONTENT_FONT, fill=TEXT)
        status_y += 52

    draw.text((648, 544), "Ensuite :", font=SUBTITLE_FONT, fill=ACCENT_ALT)
    draw_wrapped(
        draw,
        "On suit le trajet complet du colis et ce que voit l'utilisateur a chaque etape.",
        (648, 588),
        META_FONT,
        WARN,
        30,
        line_gap=8,
    )

    slide_path = SLIDES_DIR / f"slide_{slide_no:02d}.png"
    image.save(slide_path)
    return slide_path


def render_step_slide(slide_no: int, scenario_index: int, step_index: int, step: dict, scenario: dict):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw_header(
        draw,
        f"Scenario {scenario_index}/4 - Etape {step_index}/4",
        step["title"],
        scenario["title"],
    )

    draw.rounded_rectangle((56, 220, 760, 596), radius=28, fill=CARD)
    draw.rounded_rectangle((786, 220, 1224, 596), radius=28, fill=CARD_ALT)

    draw.text((84, 252), "Actions et controles", font=SUBTITLE_FONT, fill=ACCENT)
    y = 306
    for bullet in step["bullets"]:
        draw.rounded_rectangle((84, y + 7, 96, y + 19), radius=6, fill=ACCENT_ALT)
        y = draw_wrapped(draw, bullet, (112, y), STEP_FONT, TEXT, 38, line_gap=6) + 12

    draw.text((814, 252), "Impact dans Denkma", font=SUBTITLE_FONT, fill=ACCENT)
    y = draw_wrapped(draw, step["status"], (814, 304), STEP_BOLD_FONT, TEXT, 20, line_gap=8) + 16
    draw.text((814, y), "Ce que voit l'utilisateur", font=SUBTITLE_FONT, fill=ACCENT_ALT)
    screen_text = step["screen"].replace("Ce que voit l'utilisateur : ", "")
    draw_wrapped(draw, screen_text, (814, y + 44), STEP_FONT, TEXT_SOFT, 20, line_gap=8)

    draw_status_bar(draw, scenario["statuses"], step["status"])

    slide_path = SLIDES_DIR / f"slide_{slide_no:02d}.png"
    image.save(slide_path)
    return slide_path


def render_title_slide():
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((56, 72, 1224, 648), radius=36, fill=BG_ALT)
    draw.rounded_rectangle((92, 116, 318, 170), radius=20, fill=ACCENT)
    draw.text((114, 127), "Tutoriel Denkma", font=SUBTITLE_FONT, fill=BG)
    draw.text((92, 214), "Processus complet des livraisons", font=TITLE_FONT, fill=TEXT)
    draw.text((92, 282), "4 scenarios reels, du depot a la remise finale", font=SUBTITLE_FONT, fill=TEXT_SOFT)
    draw.text((92, 364), "Ce tutoriel montre le vrai deroule d'un colis :", font=BODY_BOLD_FONT, fill=ACCENT_ALT)
    bullets = [
        "Relais vers relais",
        "Relais vers domicile",
        "Domicile vers relais",
        "Domicile vers domicile",
    ]
    y = 420
    for bullet in bullets:
        draw.rounded_rectangle((98, y + 7, 110, y + 19), radius=6, fill=ACCENT)
        draw.text((128, y), bullet, font=BODY_FONT, fill=TEXT)
        y += 48
    draw.text((92, 592), "Avec exemples : Fatou, Ibrahima, Moussa, Aminata, Cheikh et Mareme.", font=SMALL_FONT, fill=WARN)

    slide_path = SLIDES_DIR / "slide_01.png"
    image.save(slide_path)
    return slide_path


def render_legend_slide():
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw_header(
        draw,
        "Avant de commencer",
        "Comment lire les scenarios",
        "Les memes codes et les memes acteurs reviennent dans les exemples.",
    )
    draw.rounded_rectangle((56, 220, 590, 644), radius=28, fill=CARD)
    draw.rounded_rectangle((620, 220, 1224, 644), radius=28, fill=CARD_ALT)

    draw.text((84, 252), "Acteurs", font=SUBTITLE_FONT, fill=ACCENT)
    actors = [
        "Fatou Diallo : expediteur",
        "Ibrahima Sow : destinataire",
        "Moussa Livreur : livreur",
        "Aminata : relais Medina - Dakar",
        "Cheikh : relais Plateau - Dakar",
        "Mareme : relais Escale - Thies",
    ]
    y = 304
    for actor in actors:
        draw.rounded_rectangle((84, y + 7, 96, y + 19), radius=6, fill=ACCENT_ALT)
        y = draw_wrapped(draw, actor, (112, y), STEP_FONT, TEXT, 24, line_gap=6) + 10

    draw.text((648, 252), "Codes et validations", font=SUBTITLE_FONT, fill=ACCENT)
    notes = [
        "pickup_code : valide la collecte par le livreur",
        "delivery_code : valide une remise a domicile",
        "relay_pin : valide un retrait au relais",
        "scan_in : enregistrement d'entree au relais",
        "scan_out : enregistrement de sortie au relais",
    ]
    y = 304
    for note in notes:
        draw.rounded_rectangle((648, y + 7, 660, y + 19), radius=6, fill=ACCENT)
        y = draw_wrapped(draw, note, (676, y), STEP_FONT, TEXT, 24, line_gap=6) + 10

    slide_path = SLIDES_DIR / "slide_02.png"
    image.save(slide_path)
    return slide_path


def render_final_slide(last_slide_no: int):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    draw_header(
        draw,
        "Recap",
        "Ce que les utilisateurs doivent retenir",
        "Le processus change selon le mode de livraison, mais les preuves et les statuts restent clairs.",
    )
    draw.rounded_rectangle((56, 220, 1224, 588), radius=28, fill=CARD)
    points = [
        "Relais -> relais : depot relais, transport, disponibilite relais, retrait final.",
        "Relais -> domicile : depot relais, transport, arrivee livreur, remise au code.",
        "Domicile -> relais : collecte a domicile, depot relais, retrait final.",
        "Domicile -> domicile : collecte a domicile, transit direct, remise au code.",
        "A chaque etape, Denkma garde une preuve : scan, code, statut et historique.",
    ]
    y = 260
    for point in points:
        draw.rounded_rectangle((84, y + 9, 98, y + 23), radius=6, fill=ACCENT)
        y = draw_wrapped(draw, point, (118, y), BODY_FONT, TEXT, 62, line_gap=10) + 20
    draw.text((84, 614), "Fin du tutoriel", font=SUBTITLE_FONT, fill=ACCENT_ALT)

    slide_path = SLIDES_DIR / f"slide_{last_slide_no:02d}.png"
    image.save(slide_path)
    return slide_path


def generate_all():
    SLIDES_DIR.mkdir(parents=True, exist_ok=True)
    slide_paths = []
    durations = []

    slide_paths.append(render_title_slide())
    durations.append(5)
    slide_paths.append(render_legend_slide())
    durations.append(6)

    slide_no = 3
    for index, scenario in enumerate(SCENARIOS, start=1):
        slide_paths.append(render_intro_slide(slide_no, index, scenario))
        durations.append(5)
        slide_no += 1
        for step_index, step in enumerate(scenario["steps"], start=1):
            slide_paths.append(render_step_slide(slide_no, index, step_index, step, scenario))
            durations.append(5)
            slide_no += 1

    slide_paths.append(render_final_slide(slide_no))
    durations.append(6)

    lines = []
    for path, duration in zip(slide_paths, durations):
        lines.append(f"file '{path.as_posix()}'")
        lines.append(f"duration {duration}")
    lines.append(f"file '{slide_paths[-1].as_posix()}'")
    CONCAT_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONCAT_FILE.write_text("\n".join(lines), encoding="utf-8")

    print(f"Slides generated: {len(slide_paths)}")
    print(f"Slides dir: {SLIDES_DIR}")
    print(f"Concat file: {CONCAT_FILE}")


if __name__ == "__main__":
    generate_all()
