#if os(iOS)
import UIKit

/**
 * Style dynamique (« vitrine ») de la bannière, sur le modèle de l'aperçu du back-office (BoostStrip.vue) et de la
 * bannière Android (ShowcaseView.kt) :
 *
 * - fond : dégradé vertical, motif éventuel (rayures, grille, points) et halo flou de la couleur d'accent qui dérive ;
 * - icône aux coins arrondis à 22 %, nom en petites majuscules, accroche très grasse (3 lignes au plus) dont le mot
 *   entre étoiles est surligné par une bande de la couleur d'accent tracée de gauche à droite ;
 * - éventail de 3 captures au plus (masqué sous 330 pt de large ou 80 pt de haut), bouton pilule avec reflet.
 *
 * Un pas toutes les 2,6 s : accroche suivante, onde autour de l'icône, éventail qui tourne d'un cran, bouton qui
 * pulse et reflet. « Réduire les animations » activé : tout est figé, les mots restent surlignés.
 */
final class ShowcaseView: UIView {
    static let stepInterval: TimeInterval = 2.6

    private let images: IconLoader
    private let backgroundLayer = CAGradientLayer()
    private let patternLayer = CALayer()
    private let haloLayer = CAGradientLayer()

    private let row = UIStackView()
    private let iconBox = UIView()
    private let waveLayer = CAShapeLayer()
    private let iconView = UIImageView()
    private let texts = UIStackView()
    private let nameLabel = UILabel()
    private let hookView = UITextView()
    private var markLayers: [CALayer] = []
    private let fan = UIView()
    private let shots: [UIView] = (0..<3).map { _ in UIView() }
    private let shotImages: [UIImageView] = (0..<3).map { _ in UIImageView() }
    private let shotDims: [UIView] = (0..<3).map { _ in UIView() }
    private let ctaBox = UIView()
    private let ctaLabel = PaddedLabel()
    private let shineLayer = CAGradientLayer()
    private let adLabel = UILabel()

    private var iconSize: NSLayoutConstraint!
    private var fanHeight: NSLayoutConstraint!

    private var ad: Ad?
    private var theme: BannerTheme?
    private var marked = Hooks.Marked(text: "", marks: [])
    private var step = 0
    private var compact = false
    private var fanAllowed = true
    private var stepWork: DispatchWorkItem?
    private var laidOutSize = CGSize.zero

    /// Positions de l'éventail : 0 devant, droite et nette ; puis inclinée, décalée à droite, réduite et assombrie
    private static let fanSlots: [(angle: CGFloat, x: CGFloat, scale: CGFloat, dim: CGFloat)] = [
        (-8, 0, 1, 0), (3, 9, 0.9, 0.22), (13, 18, 0.8, 0.4)
    ]

    init(images: IconLoader) {
        self.images = images
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non pris en charge")
    }

    private func setUp() {
        clipsToBounds = true
        layer.cornerRadius = 16

        backgroundLayer.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(backgroundLayer)
        layer.addSublayer(patternLayer)
        haloLayer.type = .radial
        haloLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        haloLayer.endPoint = CGPoint(x: 1, y: 1)
        haloLayer.opacity = 0.35
        layer.addSublayer(haloLayer)

        // Icône : onde derrière, ombre sur le conteneur, image découpée
        waveLayer.fillColor = UIColor.clear.cgColor
        waveLayer.lineWidth = 2
        waveLayer.opacity = 0
        iconBox.layer.addSublayer(waveLayer)
        iconBox.layer.shadowColor = UIColor.black.cgColor
        iconBox.layer.shadowOpacity = 0.3
        iconBox.layer.shadowRadius = 5
        iconBox.layer.shadowOffset = CGSize(width: 0, height: 4)
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)

        nameLabel.font = .boldSystemFont(ofSize: 11)
        nameLabel.alpha = 0.75
        nameLabel.lineBreakMode = .byTruncatingTail

        hookView.isEditable = false
        hookView.isSelectable = false
        hookView.isScrollEnabled = false
        hookView.isUserInteractionEnabled = false
        hookView.backgroundColor = .clear
        hookView.textContainerInset = .zero
        hookView.textContainer.lineFragmentPadding = 0
        hookView.textContainer.lineBreakMode = .byTruncatingTail
        hookView.textContainer.maximumNumberOfLines = 3

        texts.axis = .vertical
        texts.spacing = 2
        texts.addArrangedSubview(nameLabel)
        texts.addArrangedSubview(hookView)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for i in 0..<3 {
            let shot = shots[i]
            shot.layer.shadowColor = UIColor.black.cgColor
            shot.layer.shadowOpacity = 0.35
            shot.layer.shadowRadius = 4
            shot.layer.shadowOffset = CGSize(width: 0, height: 3)
            shot.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            let image = shotImages[i]
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 5
            image.backgroundColor = UIColor(white: 0, alpha: 0.15)
            image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shotDims[i].backgroundColor = .black
            shotDims[i].alpha = 0
            shotDims[i].autoresizingMask = [.flexibleWidth, .flexibleHeight]
            image.addSubview(shotDims[i])
            shot.addSubview(image)
            fan.addSubview(shot)
        }

        ctaLabel.insets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        ctaLabel.font = .systemFont(ofSize: 13, weight: .heavy)
        ctaLabel.textAlignment = .center
        ctaLabel.clipsToBounds = true
        ctaLabel.translatesAutoresizingMaskIntoConstraints = false
        shineLayer.colors = [UIColor.clear.cgColor, UIColor(white: 1, alpha: 0.55).cgColor, UIColor.clear.cgColor]
        shineLayer.locations = [0.3, 0.5, 0.7]
        shineLayer.startPoint = CGPoint(x: 0, y: 0.35)
        shineLayer.endPoint = CGPoint(x: 1, y: 0.65)
        shineLayer.isHidden = true
        ctaLabel.layer.addSublayer(shineLayer)
        ctaBox.layer.shadowColor = UIColor.black.cgColor
        ctaBox.layer.shadowOpacity = 0.25
        ctaBox.layer.shadowRadius = 5
        ctaBox.layer.shadowOffset = CGSize(width: 0, height: 4)
        ctaBox.addSubview(ctaLabel)
        ctaBox.setContentHuggingPriority(.required, for: .horizontal)
        ctaBox.setContentCompressionResistancePriority(.required, for: .horizontal)
        ctaLabel.setContentHuggingPriority(.required, for: .horizontal)
        ctaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        for view in [iconBox, texts, fan, ctaBox] {
            row.addArrangedSubview(view)
        }
        row.setCustomSpacing(12, after: iconBox)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        adLabel.text = "Ad"
        adLabel.font = .systemFont(ofSize: 9)
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(adLabel)

        iconSize = iconBox.widthAnchor.constraint(equalToConstant: 56)
        fanHeight = fan.heightAnchor.constraint(equalToConstant: 58)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconSize,
            iconBox.heightAnchor.constraint(equalTo: iconBox.widthAnchor),
            iconView.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconBox.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor),
            fan.widthAnchor.constraint(equalToConstant: 58),
            fanHeight,
            ctaLabel.leadingAnchor.constraint(equalTo: ctaBox.leadingAnchor),
            ctaLabel.trailingAnchor.constraint(equalTo: ctaBox.trailingAnchor),
            ctaLabel.topAnchor.constraint(equalTo: ctaBox.topAnchor),
            ctaLabel.bottomAnchor.constraint(equalTo: ctaBox.bottomAnchor),
            // À l'écart du bord et de l'arrondi de la carte
            adLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            adLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    // MARK: - Contenu

    func bind(_ newAd: Ad, theme newTheme: BannerTheme) {
        let changed = ad?.id != newAd.id
        ad = newAd
        if newTheme != theme { apply(theme: newTheme) }
        step = 0

        // Petites majuscules espacées, dans la langue de la pub
        let name = newAd.name.uppercased(with: Locale(identifier: newAd.languageCode))
        nameLabel.attributedText = NSAttributedString(string: name, attributes: [.kern: 11 * 0.08])
        ctaLabel.text = newAd.cta
        showHook(animated: false)

        if changed {
            iconView.image = nil
            let id = newAd.id
            if let url = newAd.iconUrl {
                images.load(url) { [weak self] image in
                    guard let self = self, self.ad?.id == id else { return }
                    self.iconView.image = image
                }
            }
            for i in 0..<3 {
                shotImages[i].image = nil
                guard i < newAd.screenshots.count else { continue }
                images.load(newAd.screenshots[i]) { [weak self] image in
                    guard let self = self, self.ad?.id == id else { return }
                    self.shotImages[i].image = image
                }
            }
            updateFan()
            placeFan(animated: false)
            playAppearance()
        }
        scheduleStep()
    }

    func stop() {
        ad = nil
        stepWork?.cancel()
        stepWork = nil
        haloLayer.removeAllAnimations()
    }

    private func apply(theme newTheme: BannerTheme) {
        theme = newTheme
        backgroundLayer.colors = [newTheme.background.cgColor, newTheme.background2.cgColor]
        patternLayer.backgroundColor = ShowcaseView.patternTile(newTheme.pattern, color: newTheme.patternColor)
            .map { UIColor(patternImage: $0).cgColor }
        haloLayer.colors = [newTheme.button.cgColor, newTheme.button.withAlphaComponent(0).cgColor]
        waveLayer.strokeColor = newTheme.button.cgColor
        nameLabel.textColor = newTheme.title
        ctaLabel.textColor = newTheme.buttonText
        ctaLabel.backgroundColor = newTheme.button
        adLabel.textColor = newTheme.text.withAlphaComponent(0.6)
    }

    private func hookFont() -> UIFont {
        let base = UIFont.systemFont(ofSize: compact ? 13 : 15, weight: .heavy)
        let design: UIFontDescriptor.SystemDesign?
        switch theme?.font {
        case "serif": design = .serif
        case "rounded": design = .rounded
        default: design = nil
        }
        guard let wanted = design, let descriptor = base.fontDescriptor.withDesign(wanted) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    // MARK: - Mise en page

    /// Hauteur réduite (moins de 80 pt) : icône et accroche plus petites, pas d'éventail. Étroite : pas d'éventail.
    override func layoutSubviews() {
        let size = bounds.size
        if size != laidOutSize {
            laidOutSize = size
            compact = size.height < 80
            fanAllowed = !compact && size.width >= 330
            iconSize.constant = compact ? 44 : 56
            fanHeight.constant = min(58, max(0, size.height - 20))
            hookView.textContainer.maximumNumberOfLines = compact ? 2 : 3
            updateFan()
            if ad != nil { showHook(animated: false) }
        }
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = bounds
        patternLayer.frame = bounds
        if haloLayer.animation(forKey: "drift") == nil {
            haloLayer.frame = CGRect(x: bounds.width * 0.12, y: -30, width: 110, height: 110)
        }
        let iconBounds = CGRect(origin: .zero, size: CGSize(width: iconSize.constant, height: iconSize.constant))
        let radius = iconSize.constant * 0.22
        iconView.layer.cornerRadius = radius
        iconBox.layer.shadowPath = UIBezierPath(roundedRect: iconBounds, cornerRadius: radius).cgPath
        waveLayer.frame = iconBounds
        waveLayer.path = UIBezierPath(roundedRect: iconBounds, cornerRadius: radius).cgPath
        ctaLabel.layer.cornerRadius = ctaLabel.bounds.height / 2
        ctaBox.layer.shadowPath = UIBezierPath(roundedRect: ctaLabel.bounds, cornerRadius: ctaLabel.bounds.height / 2).cgPath
        shineLayer.frame = ctaLabel.bounds
        CATransaction.commit()

        layoutShots()
        layoutMarks(progress: 1)
    }

    /// Captures en 9:16 aussi hautes que l'éventail, pivot en bas au centre
    private func layoutShots() {
        let height = fanHeight.constant
        let width = height * 0.56
        for (i, shot) in shots.enumerated() {
            let transform = shot.transform
            shot.transform = .identity
            shot.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            shot.center = CGPoint(x: 4 + width / 2, y: fan.bounds.midY + height / 2)
            shotImages[i].frame = shot.bounds
            shotDims[i].frame = shot.bounds
            shot.layer.shadowPath = UIBezierPath(roundedRect: shot.bounds, cornerRadius: 5).cgPath
            shot.transform = transform
        }
    }

    private func updateFan() {
        let count = min(3, ad?.screenshots.count ?? 0)
        fan.isHidden = !fanAllowed || count == 0
        for (i, shot) in shots.enumerated() { shot.isHidden = i >= count }
    }

    // MARK: - Accroche et surlignage

    private func showHook(animated: Bool) {
        let hooks = ad?.descriptions ?? []
        marked = Hooks.parse(hooks.isEmpty ? "" : hooks[step % hooks.count])
        let motion = !UIAccessibility.isReduceMotionEnabled
        guard animated, motion else {
            hookView.layer.removeAllAnimations()
            hookView.transform = .identity
            hookView.alpha = 1
            setHookText(highlighted: !motion)
            if motion { animateMarks() }
            return
        }
        UIView.animate(withDuration: 0.2, animations: {
            self.hookView.transform = CGAffineTransform(translationX: 0, y: -14)
            self.hookView.alpha = 0
        }, completion: { _ in
            self.setHookText(highlighted: false)
            self.hookView.transform = CGAffineTransform(translationX: 0, y: 14)
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
                self.hookView.transform = .identity
                self.hookView.alpha = 1
            }, completion: nil)
            self.animateMarks()
        })
    }

    /// Texte de l'accroche ; passages surlignés en couleur du texte d'accent une fois la bande tracée
    private func setHookText(highlighted: Bool) {
        guard let theme = theme else { return }
        let text = NSMutableAttributedString(string: marked.text, attributes: [
            .font: hookFont(),
            .foregroundColor: theme.text
        ])
        if highlighted {
            for range in marked.marks { text.addAttribute(.foregroundColor, value: theme.buttonText, range: range) }
        }
        hookView.attributedText = text
        hookView.textContainer.lineBreakMode = .byTruncatingTail
        hookView.invalidateIntrinsicContentSize()
        hookView.setNeedsLayout()
        hookView.layoutIfNeeded()
        layoutMarks(progress: highlighted ? 1 : 0)
    }

    /// Une bande arrondie de la couleur d'accent sous chaque ligne de chaque passage surligné
    private func layoutMarks(progress: CGFloat) {
        guard let theme = theme else { return }
        let manager = hookView.layoutManager
        let container = hookView.textContainer
        manager.ensureLayout(for: container)
        var rects: [CGRect] = []
        for range in marked.marks {
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                            in: container) { rect, _ in
                rects.append(rect.insetBy(dx: -2, dy: 0))
            }
        }
        while markLayers.count < rects.count {
            let band = CALayer()
            band.cornerRadius = 4
            band.anchorPoint = CGPoint(x: 0, y: 0.5)
            hookView.layer.insertSublayer(band, at: 0)
            markLayers.append(band)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, band) in markLayers.enumerated() {
            band.isHidden = i >= rects.count
            guard i < rects.count else { continue }
            let rect = rects[i]
            band.backgroundColor = theme.button.cgColor
            band.bounds = CGRect(origin: .zero, size: rect.size)
            band.position = CGPoint(x: rect.minX, y: rect.midY)
            if band.animation(forKey: "mark") == nil {
                band.transform = CATransform3DMakeScale(max(progress, 0.0001), 1, 1)
            }
        }
        CATransaction.commit()
    }

    /// Bande tracée de gauche à droite en 0,45 s, puis le texte passe en couleur du texte d'accent
    private func animateMarks() {
        guard !marked.marks.isEmpty else { return }
        let start = CACurrentMediaTime() + 0.25
        for band in markLayers where !band.isHidden {
            let grow = CABasicAnimation(keyPath: "transform.scale.x")
            grow.fromValue = 0.0001
            grow.toValue = 1
            grow.beginTime = start
            grow.duration = 0.45
            grow.fillMode = .backwards
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            band.transform = CATransform3DIdentity
            band.add(grow, forKey: "mark")
        }
        let current = marked
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, self.marked == current else { return }
            UIView.transition(with: self.hookView, duration: 0.45, options: .transitionCrossDissolve, animations: {
                self.setHookText(highlighted: true)
            }, completion: nil)
        }
    }

    // MARK: - Rythme : un pas toutes les 2,6 s

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleStep()
    }

    private func scheduleStep() {
        stepWork?.cancel()
        stepWork = nil
        guard ad != nil, window != nil else {
            haloLayer.removeAnimation(forKey: "drift")
            return
        }
        startDrift()
        let work = DispatchWorkItem { [weak self] in
            self?.nextStep()
            self?.scheduleStep()
        }
        stepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ShowcaseView.stepInterval, execute: work)
    }

    private func nextStep() {
        guard let current = ad else { return }
        step += 1
        if current.descriptions.count > 1 { showHook(animated: true) }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        playWave()
        if !fan.isHidden && current.screenshots.count > 1 { placeFan(animated: true) }
        pulseAndShine()
    }

    private func playWave() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.35
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.2
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        waveLayer.add(group, forKey: "wave")
    }

    private func pulseAndShine() {
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.08, 1]
        pulse.duration = 0.5
        ctaBox.layer.add(pulse, forKey: "pulse")

        let width = ctaLabel.bounds.width
        shineLayer.isHidden = false
        let shine = CABasicAnimation(keyPath: "transform.translation.x")
        shine.fromValue = -1.2 * width
        shine.toValue = 1.2 * width
        shine.beginTime = CACurrentMediaTime() + 0.1
        shine.duration = 0.8
        shine.fillMode = .both
        shine.isRemovedOnCompletion = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.shineLayer.isHidden = true }
        shineLayer.add(shine, forKey: "shine")
        CATransaction.commit()
    }

    private func startDrift() {
        guard haloLayer.animation(forKey: "drift") == nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let drift = CABasicAnimation(keyPath: "transform.translation")
        drift.fromValue = NSValue(cgSize: .zero)
        drift.toValue = NSValue(cgSize: CGSize(width: 180, height: 30))
        drift.duration = 9
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        haloLayer.add(drift, forKey: "drift")
    }

    /// Apparition : icône et bouton surgissent avec un rebond, texte depuis la gauche, captures depuis le bas
    private func playAppearance() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        for view in [iconBox, ctaBox] {
            view.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            view.alpha = 0
        }
        texts.transform = CGAffineTransform(translationX: -16, y: 0)
        texts.alpha = 0
        fan.transform = CGAffineTransform(translationX: 0, y: 40)
        fan.alpha = 0
        UIView.animate(withDuration: 0.6, delay: 0.1, usingSpringWithDamping: 0.55, initialSpringVelocity: 0,
                       options: [.allowUserInteraction], animations: {
            self.iconBox.transform = .identity
            self.iconBox.alpha = 1
            self.ctaBox.transform = .identity
            self.ctaBox.alpha = 1
        }, completion: nil)
        UIView.animate(withDuration: 0.5, delay: 0.15, options: [.curveEaseOut, .allowUserInteraction], animations: {
            self.texts.transform = .identity
            self.texts.alpha = 1
        }, completion: nil)
        UIView.animate(withDuration: 0.7, delay: 0.15, usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                       options: [.allowUserInteraction], animations: {
            self.fan.transform = .identity
            self.fan.alpha = 1
        }, completion: nil)
    }

    // MARK: - Éventail

    private func placeFan(animated: Bool) {
        let count = min(3, ad?.screenshots.count ?? 0)
        guard count > 0 else { return }
        let apply = {
            for i in 0..<count {
                let slot = ShowcaseView.fanSlots[((i - self.step) % count + count) % count]
                self.shots[i].transform = CGAffineTransform(translationX: slot.x, y: 0)
                    .rotated(by: slot.angle * .pi / 180)
                    .scaledBy(x: slot.scale, y: slot.scale)
                self.shotDims[i].alpha = slot.dim
            }
        }
        // La capture de devant passe au-dessus des autres dès le début du mouvement
        for i in 0..<count { shots[i].layer.zPosition = CGFloat(3 - ((i - step) % count + count) % count) }
        if animated {
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                           options: [.allowUserInteraction], animations: apply, completion: nil)
        } else {
            apply()
        }
    }

    // MARK: - Motifs

    /// Motif répété du fond : rayures à 45° (6 pt sur 14), grille (traits de 1 pt tous les 14 pt) ou points
    /// (rayon 1,5 pt tous les 10 pt), comme les motifs CSS de l'aperçu
    static func patternTile(_ pattern: String?, color: UIColor) -> UIImage? {
        let side: CGFloat
        switch pattern {
        case "stripes": side = 14 * CGFloat(2).squareRoot()
        case "grid": side = 14
        case "dots": side = 10
        default: return nil
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(color.cgColor)
            switch pattern {
            case "stripes":
                // Bandes entre les droites x + y = c et x + y = c + 6√2, raccordées d'une tuile à l'autre
                let band = 6 * CGFloat(2).squareRoot()
                for c in [0, side] {
                    cg.move(to: CGPoint(x: c, y: 0))
                    cg.addLine(to: CGPoint(x: c + band, y: 0))
                    cg.addLine(to: CGPoint(x: c + band - side, y: side))
                    cg.addLine(to: CGPoint(x: c - side, y: side))
                    cg.closePath()
                }
                cg.fillPath()
            case "grid":
                cg.fill(CGRect(x: 0, y: 0, width: side, height: 1))
                cg.fill(CGRect(x: 0, y: 0, width: 1, height: side))
            default:
                cg.fillEllipse(in: CGRect(x: side / 2 - 1.5, y: side / 2 - 1.5, width: 3, height: 3))
            }
        }
    }
}
#endif
