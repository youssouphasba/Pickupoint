from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


OUT_PATH = Path("docs/DENKMA_PITCH_INVESTISSEUR_FAMILIER_V4.docx")


def set_spacing(paragraph, before=0, after=6, line=1.1):
    fmt = paragraph.paragraph_format
    fmt.space_before = Pt(before)
    fmt.space_after = Pt(after)
    fmt.line_spacing = line


def set_run_font(run, size, bold=False, color=None):
    run.font.name = "Calibri"
    run._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    run._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    run.font.size = Pt(size)
    run.font.bold = bold
    if color:
        run.font.color.rgb = color


def add_bullets(doc, items):
    for item in items:
        p = doc.add_paragraph(style="List Bullet")
        r = p.add_run(item)
        set_run_font(r, 11)
        set_spacing(p, after=4, line=1.15)


def shade_cell(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill)
    tc_pr.append(shd)


def set_cell_text(cell, text, bold=False, color=None):
    cell.text = ""
    p = cell.paragraphs[0]
    r = p.add_run(text)
    set_run_font(r, 10.5, bold=bold, color=color)
    set_spacing(p, after=0, line=1.0)


def add_heading(doc, text):
    p = doc.add_paragraph(text, style="Heading 1")
    set_spacing(p, before=16, after=8)


def add_paragraph(doc, text):
    p = doc.add_paragraph()
    r = p.add_run(text)
    set_run_font(r, 11)
    set_spacing(p, after=6)


def main():
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    doc = Document()

    section = doc.sections[0]
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)
    section.header_distance = Inches(0.49)
    section.footer_distance = Inches(0.49)

    normal = doc.styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(11)
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")

    heading_colors = {
        "Heading 1": RGBColor(46, 116, 181),
        "Heading 2": RGBColor(46, 116, 181),
        "Heading 3": RGBColor(31, 77, 120),
    }
    heading_sizes = {"Heading 1": 16, "Heading 2": 13, "Heading 3": 12}
    for style_name in heading_sizes:
        style = doc.styles[style_name]
        style.font.name = "Calibri"
        style.font.size = Pt(heading_sizes[style_name])
        style.font.bold = True
        style.font.color.rgb = heading_colors[style_name]
        style._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")

    p = doc.add_paragraph()
    r = p.add_run("Denkma - Note de présentation investisseur familier")
    set_run_font(r, 24, bold=True, color=RGBColor(11, 37, 69))
    set_spacing(p, after=3)

    p = doc.add_paragraph()
    r = p.add_run(
        "Document court pour présenter l'opportunité, le modèle, les besoins de financement "
        "et le potentiel économique de Denkma à un investisseur proche du fondateur."
    )
    set_run_font(r, 11, color=RGBColor(85, 85, 85))
    set_spacing(p, after=10)

    p = doc.add_paragraph()
    r = p.add_run("En une phrase : ")
    set_run_font(r, 11, bold=True)
    r = p.add_run(
        "Denkma veut devenir l'infrastructure de livraison locale pensée pour la réalité "
        "sénégalaise : des adresses parfois imprécises, beaucoup de coordination manuelle, "
        "peu de confiance, et un besoin croissant de solutions simples pour envoyer ou "
        "recevoir un colis."
    )
    set_run_font(r, 11)
    set_spacing(p, after=6)

    p = doc.add_paragraph()
    r = p.add_run("Positionnement. ")
    set_run_font(r, 11, bold=True)
    r = p.add_run(
        "Denkma combine une application mobile, des livreurs indépendants et un réseau de "
        "points relais pour rendre la livraison plus simple, plus traçable et plus adaptée "
        "aux usages du quotidien à Dakar puis dans les autres grandes villes du Sénégal."
    )
    set_run_font(r, 11)
    set_spacing(p, after=8)

    add_heading(doc, "Pourquoi maintenant ?")
    add_bullets(
        doc,
        [
            "Le e-commerce et le commerce via WhatsApp, Instagram et Facebook progressent rapidement au Sénégal.",
            "Le mobile money est déjà installé dans les usages, ce qui facilite les paiements, les recharges et les commissions.",
            "Les solutions existantes sont soit informelles, soit généralistes, et répondent mal au problème d'adressage et de fiabilité.",
            "Un réseau de points relais bien implanté crée une vraie barrière terrain, difficile à copier rapidement.",
        ],
    )

    add_heading(doc, "Le problème que Denkma résout")
    add_bullets(
        doc,
        [
            "Perte de temps importante pour l'expéditeur, le destinataire et le livreur.",
            "Livraisons ratées à cause d'adresses incomplètes ou d'une mauvaise coordination.",
            "Manque de visibilité sur où se trouve le colis et quand il arrive.",
            "Absence de structure locale fiable entre les boutiques, les livreurs et les particuliers.",
        ],
    )

    add_heading(doc, "La solution Denkma")
    add_bullets(
        doc,
        [
            "Quatre modes de livraison : relais à relais, relais à domicile, domicile à relais, domicile à domicile.",
            "Géolocalisation de précision pour les points de collecte et de livraison.",
            "Dispatch par proximité pour proposer les courses aux livreurs les plus pertinents.",
            "Suivi du colis et de la mission, avec preuves opérationnelles et historique.",
            "Réseau de points relais de quartier pour absorber les limites de l'adressage classique.",
        ],
    )

    add_heading(doc, "Pourquoi Denkma peut gagner")
    add_bullets(
        doc,
        [
            "Le produit est déjà développé et exploitable : l'investissement sert surtout à accélérer l'adoption, pas à lancer une idée sur papier.",
            "Le réseau relais crée une présence physique locale, donc une barrière opérationnelle.",
            "Le modèle est discipliné : la plateforme prend sa commission sur chaque course, tandis que les livreurs et relais gardent une forte incitation économique.",
            "Denkma est pensé pour le Sénégal, pas comme une copie d'une super-app étrangère.",
        ],
    )

    add_heading(doc, "Données financières clés")
    add_bullets(
        doc,
        [
            "Montant recherché : 20 000 EUR, soit environ 13 100 000 XOF.",
            "Panier moyen retenu : 2 000 XOF par livraison.",
            "Commission plateforme : 15 %, soit environ 300 XOF par course sur ce panier moyen.",
            "Objectif 12 mois : 2 500 livraisons mensuelles, 100 relais actifs et 50 livreurs actifs.",
            "Commission mensuelle à l'objectif 12 mois : environ 750 000 XOF.",
            "Commission plateforme cumulée année 1, sur cette base : environ 3 062 500 XOF pour 12 250 livraisons.",
        ],
    )

    add_heading(doc, "Utilisation prévue des fonds")
    table = doc.add_table(rows=8, cols=3)
    table.style = "Table Grid"
    headers = table.rows[0].cells
    for cell in headers:
        shade_cell(cell, "E8EEF5")
    set_cell_text(headers[0], "Poste", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[1], "Montant XOF", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[2], "Lecture", bold=True, color=RGBColor(11, 37, 69))
    rows = [
        ("Recrutement points relais", "3 000 000", "Accélérer le maillage quartier par quartier et sécuriser les meilleurs emplacements."),
        ("Marketing et acquisition", "2 500 000", "Créer du volume plus vite côté clients et e-commerçants."),
        ("Offres de lancement et parrainage", "2 000 000", "Réduire la friction au démarrage et stimuler la recommandation."),
        ("Animation réseau livreurs et relais", "1 500 000", "Bonus, formation, support et fidélisation."),
        ("Infrastructure et outils 12 à 18 mois", "1 200 000", "Backend, base de données, services tiers, monitoring et cartographie."),
        ("Support opérationnel", "1 400 000", "Présence terrain, déplacements, assistance et gestion des incidents."),
        ("Fonds de roulement", "1 500 000", "Marge de sécurité pour imprévus et montée en charge."),
    ]
    for row_index, row_data in enumerate(rows, start=1):
        for col_index, value in enumerate(row_data):
            set_cell_text(table.rows[row_index].cells[col_index], value, bold=(col_index == 0))

    add_heading(doc, "Économie par course")
    add_paragraph(
        doc,
        "Avec un panier moyen de 2 000 XOF, Denkma capte environ 300 XOF de commission brute par livraison. "
        "Le projet reste donc un modèle de volume et de récurrence : plus le réseau local est dense, plus la "
        "fréquence d'usage et l'effet de bouche-à-oreille peuvent améliorer la qualité économique de la plateforme."
    )

    add_heading(doc, "Projection 12 mois")
    table = doc.add_table(rows=7, cols=4)
    table.style = "Table Grid"
    headers = table.rows[0].cells
    for cell in headers:
        shade_cell(cell, "E8EEF5")
    set_cell_text(headers[0], "Période", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[1], "Livraisons / mois", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[2], "Commission / mois (XOF)", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[3], "Lecture", bold=True, color=RGBColor(11, 37, 69))
    monthly_points = [
        ("Mois 1", "100", "30 000", "Démarrage et premiers usages réels."),
        ("Mois 3", "220", "66 000", "Premiers signaux de traction."),
        ("Mois 6", "700", "210 000", "Le réseau commence à devenir visible."),
        ("Mois 9", "1 500", "450 000", "Montée en charge crédible."),
        ("Mois 12", "2 500", "750 000", "Objectif annuel du plan."),
        ("Année 1 cumulée", "12 250", "3 675 000", "Commission plateforme totale sur l'année si le panier moyen tient."),
    ]
    for row_index, row_data in enumerate(monthly_points, start=1):
        for col_index, value in enumerate(row_data):
            set_cell_text(table.rows[row_index].cells[col_index], value, bold=(col_index == 0))

    add_heading(doc, "Structure de coûts et point mort")
    add_bullets(
        doc,
        [
            "Phase 1, fondateur seul : environ 348 000 XOF de charges mensuelles dans le plan initial.",
            "Phase 2, petite équipe : environ 860 000 XOF de charges mensuelles dans le plan initial.",
            "Avec 300 XOF de commission par course, le point mort solo se situe autour de 1 160 livraisons par mois.",
            "Avec 300 XOF de commission par course, le point mort avec petite équipe se situe autour de 2 870 livraisons par mois.",
            "À 2 500 livraisons mensuelles, Denkma approche déjà une zone où le modèle devient beaucoup plus défendable économiquement.",
        ],
    )

    add_heading(doc, "Lecture investisseur")
    add_paragraph(
        doc,
        "Le bon angle n'est pas de promettre une rentabilité immédiate. Le bon angle est de montrer "
        "qu'avec 20 000 EUR, Denkma peut accélérer beaucoup plus vite son maillage, absorber sa phase "
        "de lancement avec davantage de confort, et se rapprocher nettement plus vite d'un niveau "
        "d'activité où l'économie du modèle devient convaincante."
    )

    add_heading(doc, "Proposition d'offre à présenter")
    add_paragraph(
        doc,
        "Pour un investisseur familier, la présentation doit rester simple. Le plus crédible est de "
        "proposer un ticket clair, un usage des fonds précis et une logique de retour compréhensible. "
        "Si les termes ne sont pas encore figés, il vaut mieux présenter d'abord le besoin économique "
        "et ouvrir ensuite la discussion sur la forme juridique."
    )

    table = doc.add_table(rows=5, cols=2)
    table.style = "Table Grid"
    headers = table.rows[0].cells
    shade_cell(headers[0], "E8EEF5")
    shade_cell(headers[1], "E8EEF5")
    set_cell_text(headers[0], "Point", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[1], "Proposition", bold=True, color=RGBColor(11, 37, 69))
    rows = [
        ("Montant recherché", "20 000 EUR."),
        ("Usage des fonds", "Croissance terrain, acquisition, animation réseau et sécurité de trésorerie."),
        ("Horizon", "12 à 18 mois pour consolider le réseau et monter vers une vraie densité d'usage."),
        ("Forme possible", "Prêt familial, avance remboursable ou entrée au capital selon le niveau de confiance et de risque accepté."),
    ]
    for row_index, row_data in enumerate(rows, start=1):
        for col_index, value in enumerate(row_data):
            set_cell_text(table.rows[row_index].cells[col_index], value, bold=(col_index == 0))

    doc.add_page_break()

    add_heading(doc, "Pitch oral - version courte")
    add_paragraph(
        doc,
        "Denkma est une solution de livraison pensée pour la réalité sénégalaise. Aujourd'hui, "
        "envoyer un colis prend trop de temps, dépend trop des appels, et reste peu fiable à cause "
        "de l'adressage. Nous avons construit une plateforme qui combine livreurs, points relais et "
        "géolocalisation pour rendre tout cela simple, traçable et local. L'application existe déjà. "
        "Le besoin maintenant, c'est surtout d'accélérer le terrain : recruter les bons relais, activer "
        "les livreurs, faire connaître le service et atteindre une masse critique de courses. Je cherche "
        "20 000 EUR pour accélérer cette exécution, pas pour démarrer de zéro."
    )

    add_heading(doc, "Conseils pour la présentation")
    add_bullets(
        doc,
        [
            "Parler d'abord du problème concret vécu tous les jours avant de parler technologie.",
            "Ne pas survendre la taille du marché : montrer surtout pourquoi le modèle peut devenir solide.",
            "Insister sur le fait que le produit existe déjà et que l'argent sert à accélérer le déploiement.",
            "Donner uniquement des chiffres que tu peux défendre immédiatement à l'oral.",
        ],
    )

    add_heading(doc, "Éléments à personnaliser avant envoi")
    add_bullets(
        doc,
        [
            "Le format souhaité : prêt, avance remboursable ou capital.",
            "Tes chiffres réels de traction du moment si tu veux les afficher.",
            "Le retour attendu par l'investisseur et le calendrier de discussion.",
            "La version courte email ou WhatsApp qui accompagne le document.",
        ],
    )

    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    r = footer.add_run("Denkma - Note investisseur")
    set_run_font(r, 9, color=RGBColor(120, 120, 120))

    doc.save(OUT_PATH)
    print(OUT_PATH)


if __name__ == "__main__":
    main()
