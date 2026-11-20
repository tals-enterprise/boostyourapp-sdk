#if os(iOS)
import UIKit

/**
 * Bannière native : icône, nom, accroches qui alternent et bouton, sur le modèle de l'aperçu du
 * tableau de bord (BoostStrip.vue) et de la bannière Android. Construite en code, sans ressource.
 *
 * Deux styles, choisis par le développeur de l'app hôte (`BoostNetwork.setStyle`) avec une palette de couleurs :
 * - standard : carte claire bordée, bouton plein ;
 * - dynamic : vitrine (`ShowcaseView`) : fond travaillé, mot surligné, captures en éventail.
 * Même hauteur pour les deux (`height`). Un style inconnu (ajouté côté serveur après cette version du SDK)
 * s'affiche en standard.
 */
final class BannerView: UIView {
    /// Format prévu : largeur de l'écran limitée à 468 pt
    static let maxWidth: CGFloat = 468
    static let margin: CGFloat = 8
    /// Hauteur : 13 % de celle de l'écran, entre 64 et 100 pt, la même pour les deux styles
    static let minHeight: CGFloat = 64
    static let maxHeight: CGFloat = 100

    static var height: CGFloat {
        return min(maxHeight, max(minHeight, (UIScreen.main.bounds.height * 0.13).rounded(.down)))
    }

    var onTap: (() -> Void)?

    private let icons: IconLoader
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let descriptionClip = UIView()
    private let descriptionLabel = UILabel()
    private let ctaLabel = PaddedLabel()
    private let adLabel = UILabel()
    private var iconSize: NSLayoutConstraint!
    /// Style dynamique, créé au premier besoin
    private var showcase: ShowcaseView?

    private var ad: Ad?
    private var descriptionIndex = 0
    private var rotation: DispatchWorkItem?
    /// Style et couleurs appliqués : évite de tout refaire quand la pub suivante a le même rendu
    private var appliedTheme: BannerTheme?
    /// Bannière haute (80 pt et plus) : icône et textes plus grands, accroche sur 2 lignes
    private var tall: Bool?

    init(icons: IconLoader) {
        self.icons = icons
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non pris en charge")
    }

    private func setUp() {
        // Mêmes couleurs en mode sombre, comme sur Android
        overrideUserInterfaceStyle = .light

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Ad"

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.backgroundColor = BannerView.rgb(244, 244, 245)

        nameLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.lineBreakMode = .byTruncatingTail
        // L'accroche glisse verticalement à chaque changement : on la découpe à sa zone
        descriptionClip.clipsToBounds = true
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionClip.addSubview(descriptionLabel)

        ctaLabel.clipsToBounds = true
        ctaLabel.textAlignment = .center
        ctaLabel.setContentHuggingPriority(.required, for: .horizontal)
        ctaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        adLabel.text = "Ad"
        adLabel.font = .systemFont(ofSize: 9)

        let texts = UIStackView(arrangedSubviews: [nameLabel, descriptionClip])
        texts.axis = .vertical
        texts.spacing = 2
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [iconView, texts, ctaLabel, adLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        iconSize = iconView.widthAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconSize,
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),

            texts.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            texts.trailingAnchor.constraint(equalTo: ctaLabel.leadingAnchor, constant: -8),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),

            descriptionLabel.leadingAnchor.constraint(equalTo: descriptionClip.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: descriptionClip.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: descriptionClip.topAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: descriptionClip.bottomAnchor),

            ctaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            ctaLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Le libellé « Ad » se loge dans le coin, dans la marge intérieure
            adLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            adLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        applySizes(tall: false)
        applyTheme(BannerTheme(look: Look()))
    }

    override func layoutSubviews() {
        let nowTall = bounds.height >= 80
        if nowTall != tall { applySizes(tall: nowTall) }
        super.layoutSubviews()
        iconView.layer.cornerRadius = iconSize.constant * 0.22
        ctaLabel.layer.cornerRadius = ctaLabel.bounds.height / 2
        showcase?.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    /// Tailles du style standard selon la hauteur : même hauteur que le style dynamique, contenu à l'échelle
    private func applySizes(tall: Bool) {
        self.tall = tall
        iconSize.constant = tall ? 56 : 44
        nameLabel.font = .boldSystemFont(ofSize: tall ? 15 : 14)
        descriptionLabel.font = .systemFont(ofSize: tall ? 13 : 12)
        descriptionLabel.numberOfLines = tall ? 2 : 1
        ctaLabel.font = .boldSystemFont(ofSize: tall ? 13 : 12)
        ctaLabel.insets = tall ? UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            : UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        ctaLabel.invalidateIntrinsicContentSize()
    }

    func bind(_ newAd: Ad, look: Look) {
        let changed = ad?.id != newAd.id
        ad = newAd
        descriptionIndex = 0
        let theme = BannerTheme(look: look)
        applyTheme(theme)
        accessibilityLabel = "Ad: \(newAd.name)"
        rotation?.cancel()
        rotation = nil

        if theme.style == "dynamic" {
            let view = showcase ?? {
                let created = ShowcaseView(images: icons)
                created.isUserInteractionEnabled = false
                created.frame = bounds
                insertSubview(created, at: 0)
                showcase = created
                return created
            }()
            view.isHidden = false
            view.bind(newAd, theme: theme)
            return
        }

        nameLabel.text = newAd.name
        descriptionLabel.text = Hooks.plain(newAd.descriptions.first ?? "")
        descriptionLabel.transform = .identity
        descriptionLabel.alpha = 1
        ctaLabel.text = newAd.cta

        if changed || iconView.image == nil {
            iconView.image = nil
            if let url = newAd.iconUrl {
                let id = newAd.id
                icons.load(url) { [weak self] image in
                    guard let self = self, self.ad?.id == id else { return }
                    self.iconView.image = image
                }
            }
        }
        scheduleRotation()
    }

    func clear() {
        ad = nil
        rotation?.cancel()
        rotation = nil
        showcase?.stop()
    }

    /// Entrée par glissement depuis le bord de l'écran ; l'impression ne compte qu'une fois l'opacité pleine.
    func playEnterAnimation(fromTop: Bool) {
        transform = CGAffineTransform(translationX: 0, y: fromTop ? -110 : 110)
        alpha = 0
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
            self.transform = .identity
            self.alpha = 1
        }, completion: nil)
    }

    // MARK: - Styles

    private func applyTheme(_ theme: BannerTheme) {
        guard theme != appliedTheme else { return }
        appliedTheme = theme

        // Style dynamique : la vitrine remplace la ligne classique
        let dynamic = theme.style == "dynamic"
        for view in [iconView, nameLabel, descriptionClip, ctaLabel, adLabel] as [UIView] {
            view.isHidden = dynamic
        }
        if !dynamic, let showcase = showcase {
            showcase.stop()
            showcase.isHidden = true
        }

        if dynamic {
            backgroundColor = .clear
            layer.cornerRadius = 16
            layer.borderWidth = 0
            setShadow(opacity: 0.2, radius: 8, offset: CGSize(width: 0, height: 3))
        } else {
            backgroundColor = theme.background
            layer.cornerRadius = 12
            layer.borderWidth = 1
            layer.borderColor = theme.border.cgColor
            setShadow(opacity: 0.12, radius: 6, offset: CGSize(width: 0, height: 2))
            nameLabel.textColor = theme.title
            descriptionLabel.textColor = theme.text
            ctaLabel.textColor = theme.buttonText
            ctaLabel.backgroundColor = theme.button
            adLabel.textColor = theme.text.withAlphaComponent(0.75)
        }
        setNeedsLayout()
    }

    private func setShadow(opacity: Float, radius: CGFloat, offset: CGSize) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowOffset = offset
    }

    // MARK: - Accroches

    // L'alternance des accroches ne tourne que lorsque la bannière est dans une fenêtre
    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleRotation()
    }

    private func scheduleRotation() {
        rotation?.cancel()
        rotation = nil
        guard let current = ad, window != nil, appliedTheme?.style != "dynamic" else { return }
        let work = DispatchWorkItem { [weak self] in self?.rotateDescription() }
        rotation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(current.rotationSeconds), execute: work)
    }

    private func rotateDescription() {
        guard let current = ad else { return }
        if current.descriptions.count > 1 {
            descriptionIndex = (descriptionIndex + 1) % current.descriptions.count
            slideDescription(to: Hooks.plain(current.descriptions[descriptionIndex]))
        }
        scheduleRotation()
    }

    private func slideDescription(to text: String) {
        let distance = max(descriptionLabel.bounds.height, 16)
        UIView.animate(withDuration: 0.2, animations: {
            self.descriptionLabel.transform = CGAffineTransform(translationX: 0, y: -distance)
            self.descriptionLabel.alpha = 0
        }, completion: { _ in
            self.descriptionLabel.text = text
            self.descriptionLabel.transform = CGAffineTransform(translationX: 0, y: distance)
            UIView.animate(withDuration: 0.2) {
                self.descriptionLabel.transform = .identity
                self.descriptionLabel.alpha = 1
            }
        })
    }

    @objc private func handleTap() {
        onTap?()
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}

/// Style, couleurs, motif et police résolus : ceux du rendu de l'app, à défaut ceux du style.
struct BannerTheme: Equatable {
    let style: String
    let background: UIColor
    let background2: UIColor
    let border: UIColor
    let title: UIColor
    let text: UIColor
    let button: UIColor
    let buttonText: UIColor
    /// Motif du fond (style dynamique) ; à défaut, la couleur du bas du dégradé
    let patternColor: UIColor
    let pattern: String?
    let font: String?

    /// Couleurs par défaut de chaque style (palettes Marine et Stade de nuit)
    private static let defaults: [String: [String: String]] = [
        "standard": ["background": "#FFFFFF", "border": "#E4E4E7", "title": "#18181B", "text": "#71717A",
                     "button": "#193865", "buttonText": "#FFFFFF"],
        "dynamic": ["background": "#0B1D24", "background2": "#10292C", "border": "#0B1D24", "title": "#FFFFFF",
                    "text": "#FFFFFF", "button": "#22C08C", "buttonText": "#06231A"]
    ]

    init(look: Look) {
        let resolved = BannerTheme.defaults[look.style] == nil ? "standard" : look.style
        let fallback = BannerTheme.defaults[resolved] ?? [:]
        let colors = look.colors
        func color(_ key: String) -> UIColor {
            return BannerTheme.parse(colors[key]) ?? BannerTheme.parse(fallback[key]) ?? .white
        }
        style = resolved
        background = color("background")
        // Dégradé sans seconde couleur : uni
        background2 = BannerTheme.parse(colors["background2"]) ?? BannerTheme.parse(fallback["background2"]) ?? color("background")
        border = color("border")
        title = color("title")
        text = color("text")
        button = color("button")
        buttonText = color("buttonText")
        patternColor = BannerTheme.parse(colors["patternColor"]) ?? background2
        pattern = resolved == "dynamic" ? look.pattern : nil
        font = resolved == "dynamic" ? look.font : nil
    }

    private static func parse(_ value: String?) -> UIColor? {
        guard let value = value, ApiJson.isHexColor(value),
              let rgb = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// Libellé avec marges intérieures (bouton en forme de pilule).
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
#endif
