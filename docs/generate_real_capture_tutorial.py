from pathlib import Path
import textwrap

from PIL import Image, ImageDraw, ImageFont


WIDTH = 1280
HEIGHT = 720
BASE_DIR = Path(__file__).resolve().parent / "tutorial_video_real"
CAPTURES_DIR = BASE_DIR / "captures"
SLIDES_DIR = BASE_DIR / "slides"
CONCAT_FILE = BASE_DIR / "ffmpeg_concat_real.txt"

BG = "#0B1220"
PANEL = "#162238"
PANEL_ALT = "#223452"
TEXT = "#F7FAFC"
TEXT_SOFT = "#D2DBE8"
ACCENT = "#33D7AA"
ACCENT_ALT = "#66A8FF"
WARN = "#FFD166"


SCENARIOS = [
    {
        "tag": "Scénario 1/4",
        "mode": "Relais vers relais",
        "parcel": "PKP-375-7398",
        "capture": "r2r_detail.png",
        "view_title": "Ce que le client voit au départ",
        "view_points": [
            "Code suivi partageable",
            "Destinataire visible",
            "Relais de départ visible",
            "Relais de retrait visible",
        ],
        "flow_title": "Processus réel",
        "steps": [
            "Fatou dépose le colis au Relais Medina.",
            "Aminata enregistre l'entrée du colis.",
            "Moussa collecte avec le pickup_code.",
            "Le colis arrive au Relais Escale.",
            "Ibrahima retire le colis avec le relay_pin.",
        ],
        "proof": "Preuve finale : scan_out au relais de retrait.",
    },
    {
        "tag": "Scénario 2/4",
        "mode": "Relais vers domicile",
        "parcel": "PKP-712-9746",
        "capture": "r2h_detail.png",
        "view_title": "Ce que le client voit au départ",
        "view_points": [
            "Code suivi du colis",
            "Destinataire et téléphone",
            "Relais de départ visible",
            "Historique disponible plus bas",
        ],
        "flow_title": "Processus réel",
        "steps": [
            "Fatou dépose le colis au Relais Medina.",
            "Le relais remet le colis à Moussa.",
            "Moussa valide la collecte avec le pickup_code.",
            "Moussa arrive chez Ibrahima.",
            "La remise finale se fait avec le delivery_code.",
        ],
        "proof": "Preuve finale : confirm-delivery à domicile.",
    },
    {
        "tag": "Scénario 3/4",
        "mode": "Domicile vers relais",
        "parcel": "PKP-979-6839",
        "capture": "h2r_detail.png",
        "view_title": "Ce que le client voit au départ",
        "view_points": [
            "Code de collecte livreur en orange",
            "QR de collecte partageable",
            "Destinataire visible",
            "Relais de retrait visible",
        ],
        "flow_title": "Processus réel",
        "steps": [
            "Moussa vient collecter le colis chez Fatou.",
            "Fatou lui donne le pickup_code visible ici.",
            "Le colis part vers le Relais Plateau.",
            "Cheikh enregistre l'entrée au relais.",
            "Ibrahima retire avec le relay_pin.",
        ],
        "proof": "Preuve finale : entrée relais puis retrait scanné.",
    },
    {
        "tag": "Scénario 4/4",
        "mode": "Domicile vers domicile",
        "parcel": "PKP-195-9762",
        "capture": "h2h_detail.png",
        "view_title": "Ce que le client voit au départ",
        "view_points": [
            "Code de collecte livreur en orange",
            "QR de collecte partageable",
            "Adresse de destination visible",
            "Suivi client déjà disponible",
        ],
        "flow_title": "Processus réel",
        "steps": [
            "Moussa collecte le colis chez Fatou.",
            "Fatou communique le pickup_code.",
            "Le colis part directement vers Ibrahima.",
            "Moussa arrive à destination.",
            "La remise se valide avec le delivery_code.",
        ],
        "proof": "Preuve finale : confirm-delivery au domicile.",
    },
]


def load_font(size: int, bold: bool = False):
    candidates = [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


TITLE_FONT = load_font(40, bold=True)
SUBTITLE_FONT = load_font(28, bold=True)
BODY_FONT = load_font(22)
BODY_BOLD_FONT = load_font(22, bold=True)
SMALL_FONT = load_font(18)


def wrap(text: str, width: int) -> list[str]:
    return textwrap.wrap(text, width=width, break_long_words=False)


def draw_lines(draw: ImageDraw.ImageDraw, text: str, x: int, y: int, font, fill: str, width: int, gap: int = 8):
    for line in wrap(text, width):
        draw.text((x, y), line, font=font, fill=fill)
        box = draw.textbbox((x, y), line, font=font)
        y = box[3] + gap
    return y


def add_capture(image: Image.Image, capture_name: str):
    capture = Image.open(CAPTURES_DIR / capture_name).convert("RGB")
    capture.thumbnail((300, 650))
    framed = Image.new("RGB", (capture.width + 22, capture.height + 22), "#E6EDF8")
    framed.paste(capture, (11, 11))
    image.paste(framed, (72, 46 + (HEIGHT - 92 - framed.height) // 2))


def draw_header(draw: ImageDraw.ImageDraw, tag: str, title: str, subtitle: str):
    tag_box = draw.textbbox((0, 0), tag, font=SUBTITLE_FONT)
    tag_width = max(180, min(380, tag_box[2] - tag_box[0] + 42))
    draw.rounded_rectangle((420, 48, 1188, 662), radius=28, fill=PANEL)
    draw.rounded_rectangle((456, 82, 456 + tag_width, 132), radius=18, fill=ACCENT_ALT)
    draw.text((476, 91), tag, font=SUBTITLE_FONT, fill=TEXT)
    draw.text((456, 164), title, font=TITLE_FONT, fill=TEXT)
    draw.text((456, 222), subtitle, font=BODY_FONT, fill=TEXT_SOFT)


def render_intro():
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    add_capture(image, "current_denkma.png")
    draw_header(
        draw,
        "Tutoriel réel",
        "Vrai parcours client dans Denkma",
        "Captures réelles de l'application pour illustrer les 4 scénarios de livraison.",
    )
    y = 300
    bullets = [
        "Les 4 modes sont visibles dans l'écran Mes colis.",
        "Chaque scénario ci-dessous part d'un vrai colis de test.",
        "Le tutoriel explique ce que voit le client et ce qui se passe vraiment ensuite.",
    ]
    for bullet in bullets:
        draw.rounded_rectangle((462, y + 7, 474, y + 19), radius=6, fill=ACCENT)
        y = draw_lines(draw, bullet, 492, y, BODY_FONT, TEXT, 42, gap=8) + 16
    draw.text((456, 580), "Base visuelle : écrans réels du téléphone Samsung connecté.", font=SMALL_FONT, fill=WARN)
    path = SLIDES_DIR / "real_slide_01.png"
    image.save(path)
    return path


def render_view_slide(slide_no: int, scenario: dict):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    add_capture(image, scenario["capture"])
    draw_header(
        draw,
        scenario["tag"],
        f"{scenario['mode']} - {scenario['parcel']}",
        scenario["view_title"],
    )
    y = 300
    for point in scenario["view_points"]:
        draw.rounded_rectangle((462, y + 7, 474, y + 19), radius=6, fill=ACCENT_ALT)
        y = draw_lines(draw, point, 492, y, BODY_FONT, TEXT, 42, gap=8) + 16
    draw.text((456, 594), "Ce visuel vient directement de l'application ouverte sur le téléphone.", font=SMALL_FONT, fill=WARN)
    path = SLIDES_DIR / f"real_slide_{slide_no:02d}.png"
    image.save(path)
    return path


def render_flow_slide(slide_no: int, scenario: dict):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    add_capture(image, scenario["capture"])
    draw_header(
        draw,
        scenario["tag"],
        scenario["flow_title"],
        f"Exemple réel : {scenario['mode']}",
    )
    y = 286
    for idx, step in enumerate(scenario["steps"], start=1):
        draw.rounded_rectangle((456, y + 6, 488, y + 38), radius=16, fill=ACCENT)
        draw.text((467, y + 6), str(idx), font=BODY_BOLD_FONT, fill=BG)
        y = draw_lines(draw, step, 506, y, BODY_FONT, TEXT, 40, gap=8) + 12
    draw.text((456, 598), scenario["proof"], font=SMALL_FONT, fill=WARN)
    path = SLIDES_DIR / f"real_slide_{slide_no:02d}.png"
    image.save(path)
    return path


def render_final(slide_no: int):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    add_capture(image, "current_denkma.png")
    draw_header(
        draw,
        "Récapitulatif",
        "Ce que retient l'utilisateur",
        "Le mode change, mais chaque colis garde un code, une preuve et un historique.",
    )
    y = 304
    points = [
        "Relais -> relais : dépôt, transport, disponibilité relais, retrait.",
        "Relais -> domicile : dépôt relais, transport, livraison au code.",
        "Domicile -> relais : collecte au code, dépôt relais, retrait final.",
        "Domicile -> domicile : collecte au code, remise finale au code.",
    ]
    for point in points:
        draw.rounded_rectangle((462, y + 7, 474, y + 19), radius=6, fill=ACCENT_ALT)
        y = draw_lines(draw, point, 492, y, BODY_FONT, TEXT, 42, gap=8) + 16
    draw.text((456, 606), "Version basée sur les captures réelles de l'app.", font=SMALL_FONT, fill=WARN)
    path = SLIDES_DIR / f"real_slide_{slide_no:02d}.png"
    image.save(path)
    return path


def generate():
    SLIDES_DIR.mkdir(parents=True, exist_ok=True)
    slides = [render_intro()]
    durations = [5]
    slide_no = 2
    for scenario in SCENARIOS:
        slides.append(render_view_slide(slide_no, scenario))
        durations.append(6)
        slide_no += 1
        slides.append(render_flow_slide(slide_no, scenario))
        durations.append(7)
        slide_no += 1
    slides.append(render_final(slide_no))
    durations.append(6)

    lines = []
    for slide, duration in zip(slides, durations):
        lines.append(f"file '{slide.as_posix()}'")
        lines.append(f"duration {duration}")
    lines.append(f"file '{slides[-1].as_posix()}'")
    CONCAT_FILE.write_text("\n".join(lines), encoding="utf-8")
    print(f"Slides generated: {len(slides)}")
    print(f"Concat file: {CONCAT_FILE}")


if __name__ == "__main__":
    generate()
