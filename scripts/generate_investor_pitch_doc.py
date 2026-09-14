from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


OUT_PATH = Path("docs/DENKMA_PITCH_INVESTISSEUR_FAMILIER.docx")


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
    r = p.add_run("Denkma - Note de presentation investisseur familier")
    set_run_font(r, 24, bold=True, color=RGBColor(11, 37, 69))
    set_spacing(p, after=3)

    p = doc.add_paragraph()
    r = p.add_run(
        "Document court pour presenter l'opportunite, le modele et l'usage des fonds "
        "a un investisseur proche du fondateur."
    )
    set_run_font(r, 11, color=RGBColor(85, 85, 85))
    set_spacing(p, after=10)

    p = doc.add_paragraph()
    r = p.add_run("En une phrase : ")
    set_run_font(r, 11, bold=True)
    r = p.add_run(
        "Denkma veut devenir l'infrastructure de livraison locale pensee pour la realite "
        "senegalaise : des adresses parfois imprecises, beaucoup de coordination manuelle, "
        "peu de confiance, et un besoin croissant de solutions simples pour envoyer ou "
        "recevoir un colis."
    )
    set_run_font(r, 11)
    set_spacing(p, after=6)

    p = doc.add_paragraph()
    r = p.add_run("Positionnement. ")
    set_run_font(r, 11, bold=True)
    r = p.add_run(
        "Denkma combine une application mobile, des livreurs independants et un reseau de "
        "points relais pour rendre la livraison plus simple, plus tracable et plus adaptee "
        "aux usages du quotidien a Dakar puis dans les autres grandes villes du Senegal."
    )
    set_run_font(r, 11)
    set_spacing(p, after=8)

    sections = [
        (
            "Pourquoi maintenant ?",
            [
                "Le e-commerce et le commerce via WhatsApp, Instagram et Facebook progressent rapidement au Senegal.",
                "Le mobile money est deja installe dans les usages, ce qui facilite les paiements, les recharges et les commissions.",
                "Les solutions existantes sont soit informelles, soit generalistes, et repondent mal au probleme d'adressage et de fiabilite.",
                "Un reseau de points relais bien implante cree une vraie barriere terrain, difficile a copier rapidement.",
            ],
        ),
        (
            "Le probleme que Denkma resout",
            [
                "Perte de temps importante pour l'expediteur, le destinataire et le livreur.",
                "Livraisons ratees a cause d'adresses incompletes ou d'une mauvaise coordination.",
                "Manque de visibilite sur ou se trouve le colis et quand il arrive.",
                "Absence de structure locale fiable entre les boutiques, les livreurs et les particuliers.",
            ],
        ),
        (
            "La solution Denkma",
            [
                "Quatre modes de livraison : relais a relais, relais a domicile, domicile a relais, domicile a domicile.",
                "Geolocalisation de precision pour les points de collecte et de livraison.",
                "Dispatch par proximite pour proposer les courses aux livreurs les plus pertinents.",
                "Suivi du colis et de la mission, avec preuves operationnelles et historique.",
                "Reseau de points relais de quartier pour absorber les limites de l'adressage classique.",
            ],
        ),
        (
            "Pourquoi Denkma peut gagner",
            [
                "Le produit est deja developpe et exploitable : l'investissement sert surtout a accelerer l'adoption, pas a lancer une idee sur papier.",
                "Le reseau relais cree une presence physique locale, donc une barriere operationnelle.",
                "Le modele est discipline : la plateforme prend sa commission sur chaque course, tandis que les livreurs et relais gardent une forte incitation economique.",
                "Denkma est pense pour le Senegal, pas comme une copie d'une super-app etrangere.",
            ],
        ),
        (
            "Ce que finance l'investissement",
            [
                "Recrutement et activation de nouveaux points relais dans les quartiers denses.",
                "Acquisition terrain et digitale des premiers utilisateurs recurrents.",
                "Animation du reseau de livreurs et amelioration de la qualite de service.",
                "Support operationnel, communication locale et visibilite de la marque.",
                "Renforcement du fonds de roulement pour absorber la montee en charge.",
            ],
        ),
        (
            "Objectif des 12 prochains mois",
            [
                "Etendre le maillage de points relais a Dakar de maniere disciplinee.",
                "Stabiliser une flotte active de livreurs reellement utilises.",
                "Monter en volume mensuel jusqu'a un niveau permettant une rentabilite operationnelle solide.",
                "Creer assez de traction locale pour preparer une levee plus structuree ensuite, si necessaire.",
            ],
        ),
        (
            "Pourquoi un investisseur familier peut avoir du sens",
            [
                "Le projet est proche du terrain et le fondateur connait personnellement le probleme a resoudre.",
                "Le besoin est simple a comprendre : chaque quartier a besoin d'une logistique locale plus fiable.",
                "Le capital demande sert a accelerer un modele deja construit, pas a financer une idee abstraite.",
                "Un investisseur proche peut apporter a la fois de la confiance, du reseau et de la vitesse d'execution.",
            ],
        ),
    ]

    for title, bullets in sections:
        p = doc.add_paragraph(title, style="Heading 1")
        set_spacing(p, before=16, after=8)
        add_bullets(doc, bullets)

    p = doc.add_paragraph("Modele economique", style="Heading 1")
    set_spacing(p, before=16, after=8)
    for body in [
        "La plateforme preleve une commission d'environ 15 % sur chaque livraison. Les tarifs restent accessibles, avec une base a partir de 700 XOF selon le mode de livraison, puis des ajustements transparents lies a la distance, au poids et a l'urgence.",
        "Le coeur du modele n'est pas de faire payer le client final a tout prix, mais d'organiser un flux plus fiable et plus rentable pour l'ensemble du reseau : client, livreur, relais et plateforme.",
    ]:
        p = doc.add_paragraph()
        r = p.add_run(body)
        set_run_font(r, 11)
        set_spacing(p, after=6)

    p = doc.add_paragraph("Donnees financieres cles", style="Heading 1")
    set_spacing(p, before=16, after=8)
    add_bullets(
        doc,
        [
            "Investissement de depart estime : 10 000 EUR, soit environ 6 550 000 XOF.",
            "Panier moyen estime : 1 200 XOF par livraison.",
            "Commission plateforme : 15 %, soit environ 180 XOF par course sur ce panier moyen.",
            "Objectif 12 mois du plan actuel : 2 500 livraisons mensuelles, 100 relais actifs, 50 livreurs actifs.",
            "Commission plateforme cumulee projetee sur l'annee 1 : 2 205 000 XOF.",
            "Tresorerie de fin d'annee 1 projetee : environ 1 507 000 XOF si le plan est execute selon les hypotheses actuelles.",
        ],
    )

    p = doc.add_paragraph("Utilisation prevue des fonds", style="Heading 1")
    set_spacing(p, before=16, after=8)
    table = doc.add_table(rows=8, cols=3)
    table.style = "Table Grid"
    headers = table.rows[0].cells
    for cell in headers:
        shade_cell(cell, "E8EEF5")
    set_cell_text(headers[0], "Poste", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[1], "Montant XOF", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[2], "Lecture", bold=True, color=RGBColor(11, 37, 69))
    use_of_funds = [
        ("Recrutement points relais", "1 500 000", "Activation terrain, supports et demarrage du maillage local."),
        ("Marketing et reseaux sociaux", "1 200 000", "Acquisition des premiers utilisateurs et visibilite de la marque."),
        ("Offres de lancement", "900 000", "Reduction de friction pour accelerer les premiers usages."),
        ("Parrainage", "1 000 000", "Boucle d'acquisition organique au demarrage."),
        ("Infrastructure cloud 12 mois", "600 000", "Backend, base de donnees, domaine et outils techniques."),
        ("Frais paiement et APIs", "350 000", "Paiement, cartographie et services tiers."),
        ("Fonds de roulement", "1 000 000", "Marge de securite pour absorber les imprevus et la montee en charge."),
    ]
    for row_index, row_data in enumerate(use_of_funds, start=1):
        for col_index, value in enumerate(row_data):
            set_cell_text(table.rows[row_index].cells[col_index], value, bold=(col_index == 0))

    p = doc.add_paragraph("Economie par course", style="Heading 1")
    set_spacing(p, before=16, after=8)
    p = doc.add_paragraph()
    r = p.add_run(
        "Sur une course moyenne estimee a 1 200 XOF, Denkma capte environ 180 XOF de commission brute. "
        "L'interet du modele vient donc du volume, de la recurrence et de la discipline sur les charges. "
        "A ce stade, l'investisseur doit comprendre que le projet n'est pas un business a tres forte marge "
        "unitaire, mais un modele de reseau local qui peut devenir solide si le maillage et l'usage se stabilisent."
    )
    set_run_font(r, 11)
    set_spacing(p, after=6)

    p = doc.add_paragraph("Projection 12 mois", style="Heading 1")
    set_spacing(p, before=16, after=8)
    table = doc.add_table(rows=7, cols=4)
    table.style = "Table Grid"
    headers = table.rows[0].cells
    for cell in headers:
        shade_cell(cell, "E8EEF5")
    set_cell_text(headers[0], "Periode", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[1], "Livraisons / mois", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[2], "Commission / mois (XOF)", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(headers[3], "Lecture", bold=True, color=RGBColor(11, 37, 69))
    monthly_points = [
        ("Mois 1", "100", "18 000", "Demarrage, mise en place terrain."),
        ("Mois 3", "220", "39 600", "Premiers signaux de traction."),
        ("Mois 6", "700", "126 000", "Base locale plus visible, reseau en construction."),
        ("Mois 9", "1 500", "270 000", "Montee en charge plus convaincante."),
        ("Mois 12", "2 500", "450 000", "Objectif de fin d'annee du plan actuel."),
        ("Annee 1 cumulee", "12 250", "2 205 000", "Commission plateforme totale projetee."),
    ]
    for row_index, row_data in enumerate(monthly_points, start=1):
        for col_index, value in enumerate(row_data):
            set_cell_text(table.rows[row_index].cells[col_index], value, bold=(col_index == 0))

    p = doc.add_paragraph("Structure de couts et point mort", style="Heading 1")
    set_spacing(p, before=16, after=8)
    add_bullets(
        doc,
        [
            "Phase 1, fondateur seul : environ 348 000 XOF de charges mensuelles.",
            "Phase 2, fondateur plus 2 employes : environ 860 000 XOF de charges mensuelles.",
            "Point mort estime en phase solo : environ 2 200 livraisons par mois.",
            "Point mort estime avec une petite equipe : environ 5 450 livraisons par mois.",
            "Horizon de rentabilite mensuelle estime dans le business plan actuel : entre le mois 14 et le mois 18.",
        ],
    )

    p = doc.add_paragraph("Comment presenter cela a un investisseur familier", style="Heading 1")
    set_spacing(p, before=16, after=8)
    p = doc.add_paragraph()
    r = p.add_run(
        "Le bon angle n'est pas de promettre une rentabilite immediate. Le bon angle est de montrer qu'avec "
        "un capital relativement raisonnable, le projet peut financer son demarrage commercial, rester en "
        "tresorerie positive sur la premiere annee et construire une base exploitable pour une phase 2 plus "
        "ambitieuse. Pour un investisseur proche, la these est donc : risque encore reel, mais ticket limite, "
        "produit deja construit, et apprentissage terrain a forte valeur."
    )
    set_run_font(r, 11)
    set_spacing(p, after=6)

    p = doc.add_paragraph("Proposition d'offre a presenter", style="Heading 1")
    set_spacing(p, before=16, after=8)
    p = doc.add_paragraph()
    r = p.add_run(
        "Pour un investisseur familier, la presentation doit rester simple. Le plus credible est "
        "de proposer un ticket clair, un usage des fonds precis et une logique de retour "
        "comprehensible. Si tu n'as pas encore fige les termes, presente d'abord le besoin "
        "economique et laisse la structure juridique comme point de discussion."
    )
    set_run_font(r, 11)
    set_spacing(p, after=6)

    p = doc.add_paragraph()
    r = p.add_run("Cadre conseille : ")
    set_run_font(r, 11, bold=True)
    r = p.add_run("Exemple de structure de discussion :")
    set_run_font(r, 11)
    set_spacing(p, after=6)

    table = doc.add_table(rows=5, cols=2)
    table.style = "Table Grid"
    header = table.rows[0].cells
    shade_cell(header[0], "E8EEF5")
    shade_cell(header[1], "E8EEF5")
    set_cell_text(header[0], "Point", bold=True, color=RGBColor(11, 37, 69))
    set_cell_text(header[1], "Proposition", bold=True, color=RGBColor(11, 37, 69))
    rows = [
        ("Montant recherche", "A adapter selon le besoin reel : par exemple 10 000 a 30 000 EUR."),
        ("Usage des fonds", "Relais, acquisition, operations, animation du reseau, tresorerie de demarrage."),
        ("Horizon", "12 a 18 mois pour valider le maillage, le volume et la discipline operationnelle."),
        ("Forme possible", "Pret familial, avance remboursable, ou entree au capital selon la relation et le niveau de risque accepte."),
    ]
    for idx, (left, right) in enumerate(rows, start=1):
        set_cell_text(table.rows[idx].cells[0], left, bold=True)
        set_cell_text(table.rows[idx].cells[1], right)

    doc.add_page_break()

    p = doc.add_paragraph("Pitch oral - version courte", style="Heading 1")
    set_spacing(p, before=16, after=8)
    p = doc.add_paragraph()
    r = p.add_run(
        "Denkma est une solution de livraison pensee pour la realite senegalaise. "
        "Aujourd'hui, envoyer un colis prend trop de temps, depend trop des appels, et reste "
        "peu fiable a cause de l'adressage. Nous avons construit une plateforme qui combine "
        "livreurs, points relais et geolocalisation pour rendre tout cela simple, tracable et "
        "local. L'application existe deja. Le besoin maintenant, c'est surtout d'accelerer le "
        "terrain : recruter les bons relais, activer les livreurs, faire connaitre le service "
        "et atteindre une masse critique de courses. L'opportunite est interessante parce que "
        "le probleme est quotidien, le marche grandit, et notre modele cree une vraie barriere "
        "locale. Je cherche un investissement pour accelerer cette execution, pas pour demarrer de zero."
    )
    set_run_font(r, 11)
    set_spacing(p, after=6)

    p = doc.add_paragraph("Conseils pour la presentation", style="Heading 1")
    set_spacing(p, before=16, after=8)
    add_bullets(
        doc,
        [
            "Parle d'abord du probleme concret vecu tous les jours, avant de parler technologie.",
            "Evite de survendre la taille du marche si l'investisseur est proche : il faut surtout lui montrer pourquoi le modele peut devenir solide.",
            "Insiste sur le fait que le produit existe deja et que l'argent sert a accelerer le deploiement.",
            "Si tu donnes des chiffres, donne seulement ceux que tu peux defendre immediatement.",
        ],
    )

    p = doc.add_paragraph("Elements a personnaliser avant envoi", style="Heading 1")
    set_spacing(p, before=16, after=8)
    add_bullets(
        doc,
        [
            "Le montant exact recherche.",
            "Le format souhaite : pret, avance remboursable ou capital.",
            "Tes chiffres actuels de traction si tu veux les mettre : relais actifs, livreurs actifs, volume mensuel, taux de recurrence.",
            "Le niveau de valorisation envisage si tu pars sur une entree au capital.",
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
