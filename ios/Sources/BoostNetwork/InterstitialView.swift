#if os(iOS)
import UIKit

/**
 * Interstitiel : pub plein écran, dans le rendu de l'app (même style et mêmes couleurs que la bannière), sur le
 * modèle de l'aperçu du back-office (BoostFullscreen.vue) et de l'interstitiel Android (InterstitialView.kt).
 *
 * - standard : fond uni, grande icône, nom, note, description qui alterne, captures qui défilent, bouton plein ;
 * - dynamic : fond travaillé (dégradé, motif, halo), icône avec onde, nom en majuscules, accroche très grasse au mot
 *   surligné, éventail de 3 grandes captures qui tourne, bouton avec reflet ; un pas toutes les 2,6 s.
 *
 * Bouton de fermeture après `closeSeconds` (compte à rebours) ; le glissement vers le bas ne ferme pas. Les captures
 * sont masquées sur un écran bas (paysage) et le contenu défile. « Réduire les animations » : rien ne bouge, les
 * descriptions alternent sans transition.
 */
final class InterstitialViewController: UIViewController {
    /// Fermeture demandée (bouton ✕)
    var onClose: (() -> Void)?
    /// Clic sur la pub : bouton, icône, textes ou captures
    var onAdClick: (() -> Void)?
    /// Animation d'entrée terminée : l'affichage peut commencer à compter
    private(set) var fullyShown = false

    private let ad: Ad
    private let theme: BannerTheme
    private let images: IconLoader
    private var remaining: Int
    private var isDynamic: Bool { return theme.style == "dynamic" }
    private var motion: Bool { return !UIAccessibility.isReduceMotionEnabled }

    private let backgroundLayer = CAGradientLayer()
    private let patternLayer = CALayer()
    private let haloLayer = CAGradientLayer()
    private let scroll = UIScrollView()
    private let column = UIView()
    private let stack = UIStackView()
    private let closeButton = UIButton(type: .custom)
    private let iconBox = UIView()
    private let waveLayer = CAShapeLayer()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let ratingLabel = UILabel()
    private let hook = HookTextView()
    private let topSpacer = UIView()
    private let bottomSpacer = UIView()
    private let media = UIView()
    private let fan = FanView()
    private let marquee = MarqueeView()
    private let ctaButton = UIButton(type: .custom)
    private let shineLayer = CAGradientLayer()

    private var step = 0
    private var stepTimer: Timer?
    private var closeTimer: Timer?
    private var hookHeight: NSLayoutConstraint!

    init(ad: Ad, look: Look, closeSeconds: Int, images: IconLoader) {
        self.ad = ad
        self.theme = BannerTheme(look: look)
        self.images = images
        self.remaining = closeSeconds
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        // Pas de fermeture par glissement : seulement le bouton, après le compte à rebours
        isModalInPresentation = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non pris en charge")
    }

    override var prefersStatusBarHidden: Bool { return true }
    override var preferredStatusBarStyle: UIStatusBarStyle { return isDynamic ? .lightContent : .darkContent }

    // MARK: - Construction

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        view.clipsToBounds = true
        if isDynamic {
            backgroundLayer.colors = [theme.background.cgColor, theme.background2.cgColor]
            backgroundLayer.startPoint = CGPoint(x: 0.5, y: 0)
            backgroundLayer.endPoint = CGPoint(x: 0.5, y: 1)
            view.layer.addSublayer(backgroundLayer)
            patternLayer.backgroundColor = ShowcaseView.patternTile(theme.pattern, color: theme.patternColor)
                .map { UIColor(patternImage: $0).cgColor }
            view.layer.addSublayer(patternLayer)
            haloLayer.type = .radial
            haloLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            haloLayer.endPoint = CGPoint(x: 1, y: 1)
            haloLayer.colors = [theme.button.cgColor, theme.button.withAlphaComponent(0).cgColor]
            haloLayer.opacity = 0.35
            view.layer.addSublayer(haloLayer)
        }

        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.clipsToBounds = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)

        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(stack)

        let bar = topBar()
        stack.addArrangedSubview(bar)
        stack.setCustomSpacing(8, after: bar)
        stack.addArrangedSubview(topSpacer)
        buildHeader()
        stack.addArrangedSubview(bottomSpacer)
        buildMedia()
        buildCta()

        let guide = view.safeAreaLayoutGuide
        let width = stack.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -48)
        width.priority = .defaultHigh
        let fill = column.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor)
        // Hauteur de l'écran de préférence : les captures (ou les espaces) prennent la place restante
        let exact = column.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        exact.priority = .defaultLow
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: guide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            column.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            fill,
            exact,
            stack.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            stack.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor, constant: -48),
            width,
            stack.topAnchor.constraint(equalTo: column.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -24),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            media.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ctaButton.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        showHook(animated: false)
        updateCloseButton()
        loadImages()
    }

    private func topBar() -> UIView {
        let bar = UIView()
        let adLabel = PaddedLabel()
        adLabel.text = "Ad"
        adLabel.font = .systemFont(ofSize: 11)
        adLabel.insets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        adLabel.textColor = theme.text.withAlphaComponent(0.8)
        adLabel.backgroundColor = theme.text.withAlphaComponent(0.12)
        adLabel.layer.cornerRadius = 6
        adLabel.clipsToBounds = true
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(adLabel)

        closeButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        closeButton.setTitleColor(theme.text, for: .normal)
        closeButton.backgroundColor = theme.text.withAlphaComponent(0.12)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(closeButton)

        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 48),
            adLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            adLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        return bar
    }

    private func buildHeader() {
        let iconSize: CGFloat = 96
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = iconSize * 0.22
        iconView.backgroundColor = theme.text.withAlphaComponent(0.1)
        iconView.frame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        iconView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let iconPath = UIBezierPath(roundedRect: iconView.frame, cornerRadius: iconSize * 0.22).cgPath
        if isDynamic {
            waveLayer.frame = iconView.frame
            waveLayer.path = iconPath
            waveLayer.fillColor = UIColor.clear.cgColor
            waveLayer.strokeColor = theme.button.cgColor
            waveLayer.lineWidth = 3
            waveLayer.opacity = 0
            iconBox.layer.addSublayer(waveLayer)
        }
        iconBox.layer.shadowColor = UIColor.black.cgColor
        iconBox.layer.shadowOpacity = 0.25
        iconBox.layer.shadowRadius = 7
        iconBox.layer.shadowOffset = CGSize(width: 0, height: 6)
        iconBox.layer.shadowPath = iconPath
        iconBox.addSubview(iconView)
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        addTap(iconBox)
        stack.addArrangedSubview(iconBox)
        stack.setCustomSpacing(16, after: iconBox)

        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.textColor = theme.title
        if isDynamic {
            let name = ad.name.uppercased(with: Locale(identifier: ad.languageCode))
            nameLabel.attributedText = NSAttributedString(string: name, attributes: [
                .kern: 14 * 0.12, .font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: theme.title
            ])
            nameLabel.alpha = 0.8
        } else {
            nameLabel.text = ad.name
            nameLabel.font = .boldSystemFont(ofSize: 24)
        }
        stack.addArrangedSubview(nameLabel)

        if let rating = ad.rating, rating > 0 {
            stack.setCustomSpacing(4, after: nameLabel)
            ratingLabel.text = String(format: "★ %.1f", locale: Locale(identifier: "en_US"), rating)
            ratingLabel.font = .systemFont(ofSize: 14)
            ratingLabel.textColor = theme.text.withAlphaComponent(0.85)
            stack.addArrangedSubview(ratingLabel)
            stack.setCustomSpacing(16, after: ratingLabel)
        } else {
            stack.setCustomSpacing(16, after: nameLabel)
        }

        // Description : 4 lignes réservées pour que rien ne saute
        hook.configure(font: hookFont(), color: theme.text, mark: theme.button, markText: theme.buttonText, maxLines: 4)
        hook.translatesAutoresizingMaskIntoConstraints = false
        addTap(hook)
        stack.addArrangedSubview(hook)
        hookHeight = hook.heightAnchor.constraint(equalToConstant: ceil(hookFont().lineHeight * (isDynamic ? 1.2 : 1.35) * 4) + 4)

        for spacer in [topSpacer, bottomSpacer] {
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.setContentHuggingPriority(.init(1), for: .vertical)
            spacer.setContentCompressionResistancePriority(.init(1), for: .vertical)
        }
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: iconSize),
            iconBox.heightAnchor.constraint(equalToConstant: iconSize),
            nameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hook.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hookHeight
        ])
    }

    private func hookFont() -> UIFont {
        guard isDynamic else { return .systemFont(ofSize: 18) }
        let base = UIFont.systemFont(ofSize: 26, weight: .heavy)
        let design: UIFontDescriptor.SystemDesign?
        switch theme.font {
        case "serif": design = .serif
        case "rounded": design = .rounded
        default: design = nil
        }
        guard let wanted = design, let descriptor = base.fontDescriptor.withDesign(wanted) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    private func buildMedia() {
        media.translatesAutoresizingMaskIntoConstraints = false
        media.clipsToBounds = false
        media.setContentHuggingPriority(.init(2), for: .vertical)
        media.setContentCompressionResistancePriority(.init(2), for: .vertical)
        addTap(media)
        let shots = Array(ad.screenshots.prefix(3))
        let content: UIView = isDynamic ? fan : marquee
        content.frame = media.bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        media.addSubview(content)
        if isDynamic {
            fan.configure(count: shots.count)
        } else {
            marquee.configure(count: shots.count, background: theme.text.withAlphaComponent(0.08), motion: motion)
        }
        stack.addArrangedSubview(media)
        stack.setCustomSpacing(16, after: hook)
        stack.setCustomSpacing(16, after: media)
        media.heightAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        media.isHidden = shots.isEmpty
        topSpacer.isHidden = !shots.isEmpty
        bottomSpacer.isHidden = !shots.isEmpty
    }

    private func buildCta() {
        ctaButton.setTitle(ad.cta, for: .normal)
        ctaButton.setTitleColor(theme.buttonText, for: .normal)
        ctaButton.titleLabel?.font = .systemFont(ofSize: 17, weight: isDynamic ? .heavy : .bold)
        ctaButton.backgroundColor = theme.button
        ctaButton.layer.cornerRadius = 28
        ctaButton.layer.shadowColor = UIColor.black.cgColor
        ctaButton.layer.shadowOpacity = 0.2
        ctaButton.layer.shadowRadius = 5
        ctaButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        ctaButton.addTarget(self, action: #selector(adTapped), for: .touchUpInside)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        if isDynamic {
            shineLayer.colors = [UIColor.clear.cgColor, UIColor(white: 1, alpha: 0.55).cgColor, UIColor.clear.cgColor]
            shineLayer.locations = [0.3, 0.5, 0.7]
            shineLayer.startPoint = CGPoint(x: 0, y: 0.35)
            shineLayer.endPoint = CGPoint(x: 1, y: 0.65)
            shineLayer.isHidden = true
            let mask = CAShapeLayer()
            shineLayer.mask = mask
            ctaButton.layer.addSublayer(shineLayer)
        }
        stack.addArrangedSubview(ctaButton)
        ctaButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    private func loadImages() {
        if let url = ad.iconUrl {
            images.load(url, maxPixelSize: 288) { [weak self] image in self?.iconView.image = image }
        }
        for (i, url) in ad.screenshots.prefix(3).enumerated() {
            images.load(url, maxPixelSize: 720) { [weak self] image in
                guard let self = self else { return }
                if self.isDynamic { self.fan.setImage(image, at: i) } else { self.marquee.setImage(image, at: i) }
            }
        }
    }

    private func addTap(_ target: UIView) {
        target.isUserInteractionEnabled = true
        target.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(adTapped)))
    }

    // MARK: - Mise en page

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = view.bounds
        patternLayer.frame = view.bounds
        if haloLayer.animation(forKey: "drift") == nil {
            haloLayer.frame = CGRect(x: view.bounds.width * 0.1, y: view.safeAreaInsets.top + 40, width: 300, height: 300)
        }
        shineLayer.frame = ctaButton.bounds
        (shineLayer.mask as? CAShapeLayer)?.path = UIBezierPath(roundedRect: ctaButton.bounds, cornerRadius: 28).cgPath
        ctaButton.layer.shadowPath = UIBezierPath(roundedRect: ctaButton.bounds, cornerRadius: 28).cgPath
        CATransaction.commit()

        // Écran bas (paysage) : pas de captures, le contenu défile
        let showMedia = !ad.screenshots.isEmpty && view.bounds.height >= 560
        if media.isHidden == showMedia {
            media.isHidden = !showMedia
            topSpacer.isHidden = showMedia
            bottomSpacer.isHidden = showMedia
        }
        hook.relayoutMarks()
    }

    // MARK: - Cycle de vie

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard motion else { return }
        stack.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        stack.alpha = 0
        for target in [iconBox, ctaButton] {
            target.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if motion {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
                self.stack.transform = .identity
                self.stack.alpha = 1
            }, completion: { _ in self.fullyShown = true })
            UIView.animate(withDuration: 0.6, delay: 0.15, usingSpringWithDamping: 0.55, initialSpringVelocity: 0,
                           options: [.allowUserInteraction], animations: {
                self.iconBox.transform = .identity
                self.ctaButton.transform = .identity
            }, completion: nil)
            startDrift()
        } else {
            fullyShown = true
        }
        fan.place(step: step, animated: false)
        marquee.start()
        // Réaffiché après une vue présentée par-dessus : pas de minuteries en double
        stepTimer?.invalidate()
        closeTimer?.invalidate()
        let interval = isDynamic ? ShowcaseView.stepInterval : TimeInterval(ad.rotationSeconds)
        stepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.nextStep() }
        if remaining > 0 {
            closeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self = self else { return timer.invalidate() }
                self.remaining -= 1
                self.updateCloseButton()
                if self.remaining <= 0 { timer.invalidate() }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }

    func stop() {
        stepTimer?.invalidate()
        stepTimer = nil
        closeTimer?.invalidate()
        closeTimer = nil
        haloLayer.removeAllAnimations()
        marquee.stop()
    }

    // MARK: - Rythme

    private func nextStep() {
        step += 1
        if ad.descriptions.count > 1 { showHook(animated: true) }
        guard isDynamic, motion else { return }
        playWave()
        if !media.isHidden && ad.screenshots.count > 1 { fan.place(step: step, animated: true) }
        pulseAndShine()
    }

    private func showHook(animated: Bool) {
        let texts = ad.descriptions
        let text = texts.isEmpty ? "" : texts[step % texts.count]
        let marked = isDynamic ? Hooks.parse(text) : Hooks.Marked(text: Hooks.plain(text), marks: [])
        guard animated, motion else {
            hook.set(marked, animated: motion && isDynamic)
            return
        }
        UIView.animate(withDuration: 0.22, animations: {
            self.hook.transform = CGAffineTransform(translationX: 0, y: -16)
            self.hook.alpha = 0
        }, completion: { _ in
            self.hook.set(marked, animated: self.isDynamic)
            self.hook.transform = CGAffineTransform(translationX: 0, y: 16)
            UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut, animations: {
                self.hook.transform = .identity
                self.hook.alpha = 1
            }, completion: nil)
        })
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
        pulse.values = [1, 1.06, 1]
        pulse.duration = 0.5
        ctaButton.layer.add(pulse, forKey: "pulse")

        let width = ctaButton.bounds.width
        shineLayer.isHidden = false
        let shine = CABasicAnimation(keyPath: "transform.translation.x")
        shine.fromValue = -1.2 * width
        shine.toValue = 1.2 * width
        shine.beginTime = CACurrentMediaTime() + 0.1
        shine.duration = 0.8
        shine.fillMode = .both
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.shineLayer.isHidden = true }
        shineLayer.add(shine, forKey: "shine")
        CATransaction.commit()
    }

    private func startDrift() {
        guard isDynamic, haloLayer.animation(forKey: "drift") == nil else { return }
        let drift = CABasicAnimation(keyPath: "transform.translation")
        drift.fromValue = NSValue(cgSize: .zero)
        drift.toValue = NSValue(cgSize: CGSize(width: view.bounds.width * 0.5, height: view.bounds.height * 0.35))
        drift.duration = 9
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        haloLayer.add(drift, forKey: "drift")
    }

    private func updateCloseButton() {
        closeButton.setTitle(remaining > 0 ? "\(remaining)" : "✕", for: .normal)
        closeButton.alpha = remaining > 0 ? 0.6 : 1
        closeButton.accessibilityLabel = remaining > 0 ? nil : "Close"
    }

    @objc private func closeTapped() {
        if remaining <= 0 { onClose?() }
    }

    @objc private func adTapped() {
        onAdClick?()
    }
}

/// Accroche centrée avec passages surlignés : une bande de la couleur d'accent se trace de gauche à droite sous chaque
/// passage, dont le texte passe ensuite à la couleur du texte d'accent (comme la bannière dynamique).
final class HookTextView: UITextView {
    private var marked = Hooks.Marked(text: "", marks: [])
    private var markLayers: [CALayer] = []
    private var hookFont = UIFont.systemFont(ofSize: 18)
    private var color = UIColor.black
    private var markColor = UIColor.black
    private var markTextColor = UIColor.white

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = false
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non pris en charge")
    }

    func configure(font: UIFont, color: UIColor, mark: UIColor, markText: UIColor, maxLines: Int) {
        hookFont = font
        self.color = color
        markColor = mark
        markTextColor = markText
        textContainer.maximumNumberOfLines = maxLines
    }

    func set(_ newMarked: Hooks.Marked, animated: Bool) {
        marked = newMarked
        for band in markLayers { band.removeAllAnimations() }
        setText(highlighted: !animated)
        if animated { animateMarks() }
    }

    func relayoutMarks() {
        layoutMarks(progress: 1)
    }

    private func setText(highlighted: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 1.05
        let text = NSMutableAttributedString(string: marked.text, attributes: [
            .font: hookFont, .foregroundColor: color, .paragraphStyle: paragraph
        ])
        if highlighted {
            for range in marked.marks { text.addAttribute(.foregroundColor, value: markTextColor, range: range) }
        }
        attributedText = text
        textContainer.lineBreakMode = .byTruncatingTail
        layoutIfNeeded()
        layoutMarks(progress: highlighted ? 1 : 0)
    }

    /// Une bande arrondie sous chaque ligne de chaque passage surligné ; le texte est centré verticalement
    private func layoutMarks(progress: CGFloat) {
        layoutManager.ensureLayout(for: textContainer)
        // Centrage vertical dans la hauteur réservée
        let used = layoutManager.usedRect(for: textContainer).height
        let top = max(0, (bounds.height - used) / 2)
        if abs(textContainerInset.top - top) > 0.5 {
            textContainerInset = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            layoutManager.ensureLayout(for: textContainer)
        }
        var rects: [CGRect] = []
        for range in marked.marks {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs,
                                                  withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                                  in: textContainer) { rect, _ in
                rects.append(rect.insetBy(dx: -3, dy: 0).offsetBy(dx: 0, dy: top))
            }
        }
        while markLayers.count < rects.count {
            let band = CALayer()
            band.cornerRadius = 6
            band.anchorPoint = CGPoint(x: 0, y: 0.5)
            layer.insertSublayer(band, at: 0)
            markLayers.append(band)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, band) in markLayers.enumerated() {
            band.isHidden = i >= rects.count
            guard i < rects.count else { continue }
            let rect = rects[i]
            band.backgroundColor = markColor.cgColor
            band.bounds = CGRect(origin: .zero, size: rect.size)
            band.position = CGPoint(x: rect.minX, y: rect.midY)
            if band.animation(forKey: "mark") == nil {
                band.transform = CATransform3DMakeScale(max(progress, 0.0001), 1, 1)
            }
        }
        CATransaction.commit()
    }

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
            UIView.transition(with: self, duration: 0.45, options: .transitionCrossDissolve, animations: {
                self.setText(highlighted: true)
            }, completion: nil)
        }
    }
}

/// Éventail de 3 grandes captures (style dynamique) : une au centre, nette ; les autres de part et d'autre, inclinées,
/// réduites et assombries. Tourne d'un cran à chaque pas.
final class FanView: UIView {
    private var shots: [UIView] = []
    private var shotImages: [UIImageView] = []
    private var dims: [UIView] = []
    private var step = 0

    /// x en largeurs de capture
    private static let slots: [(angle: CGFloat, x: CGFloat, scale: CGFloat, dim: CGFloat)] = [
        (0, 0, 1, 0), (-8, -0.52, 0.82, 0.28), (8, 0.52, 0.82, 0.28)
    ]

    func configure(count: Int) {
        clipsToBounds = false
        for _ in 0..<count {
            let shot = UIView()
            shot.layer.shadowColor = UIColor.black.cgColor
            shot.layer.shadowOpacity = 0.35
            shot.layer.shadowRadius = 10
            shot.layer.shadowOffset = CGSize(width: 0, height: 8)
            shot.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 14
            image.backgroundColor = UIColor(white: 0, alpha: 0.15)
            image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let dim = UIView()
            dim.backgroundColor = .black
            dim.alpha = 0
            dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            image.addSubview(dim)
            shot.addSubview(image)
            addSubview(shot)
            shots.append(shot)
            shotImages.append(image)
            dims.append(dim)
        }
    }

    func setImage(_ image: UIImage?, at index: Int) {
        guard index < shotImages.count else { return }
        shotImages[index].image = image
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height * 0.92
        let width = min(height * 0.48, bounds.width * 0.46)
        for (i, shot) in shots.enumerated() {
            let transform = shot.transform
            shot.transform = .identity
            shot.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            shot.center = CGPoint(x: bounds.midX, y: bounds.height * 0.96)
            shotImages[i].frame = shot.bounds
            dims[i].frame = shot.bounds
            shot.layer.shadowPath = UIBezierPath(roundedRect: shot.bounds, cornerRadius: 14).cgPath
            shot.transform = transform
        }
        place(step: step, animated: false)
    }

    func place(step newStep: Int, animated: Bool) {
        step = newStep
        let count = shots.count
        guard count > 0 else { return }
        let width = shots[0].bounds.width
        for i in 0..<count {
            shots[i].layer.zPosition = CGFloat(3 - ((i - step) % count + count) % count)
        }
        let apply = {
            for i in 0..<count {
                let slot = FanView.slots[((i - self.step) % count + count) % count]
                self.shots[i].transform = CGAffineTransform(translationX: slot.x * width, y: 0)
                    .rotated(by: slot.angle * .pi / 180)
                    .scaledBy(x: slot.scale, y: slot.scale)
                self.dims[i].alpha = slot.dim
            }
        }
        if animated {
            UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0,
                           options: [.allowUserInteraction], animations: apply, completion: nil)
        } else {
            apply()
        }
    }
}

/// Captures en bande (style standard) : centrées si elles tiennent, sinon elles défilent en continu d'un bord de
/// l'écran à l'autre (doublées pour boucler sans trou).
final class MarqueeView: UIView {
    private let strip = UIView()
    private var images: [[UIImageView]] = []
    private var count = 0
    private var background = UIColor.clear
    private var motion = true
    private var period: CGFloat = 0

    func configure(count: Int, background: UIColor, motion: Bool) {
        self.count = count
        self.background = background
        self.motion = motion
        clipsToBounds = false
        addSubview(strip)
    }

    func setImage(_ image: UIImage?, at index: Int) {
        for set in images where index < set.count { set[index].image = image }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard count > 0, bounds.height > 0 else { return }
        let height = bounds.height
        let width = height * 0.48
        let gap: CGFloat = 12
        let perSet = CGFloat(count) * (width + gap)
        let fits = perSet - gap <= bounds.width
        // Copies : assez pour couvrir deux fois la largeur de l'écran
        let screen = window?.bounds.width ?? bounds.width
        let sets = fits || !motion ? 1 : max(2, 2 * Int(ceil(screen / perSet)))
        if images.count != sets {
            let loaded = images.first?.map { $0.image } ?? []
            strip.subviews.forEach { $0.removeFromSuperview() }
            images = (0..<sets).map { _ in
                (0..<count).map { i in
                    let view = UIImageView()
                    view.contentMode = .scaleAspectFill
                    view.clipsToBounds = true
                    view.layer.cornerRadius = 12
                    view.backgroundColor = background
                    view.image = i < loaded.count ? loaded[i] : nil
                    strip.addSubview(view)
                    return view
                }
            }
        }
        var x: CGFloat = 0
        for set in images {
            for view in set {
                view.frame = CGRect(x: x, y: 0, width: width, height: height)
                x += width + gap
            }
        }
        let total = fits ? perSet - gap : perSet * CGFloat(sets)
        // Défilement d'un bord de l'écran à l'autre : la bande part du bord gauche de l'écran
        let left = fits ? (bounds.width - total) / 2 : -convert(CGPoint.zero, to: window).x
        let frame = CGRect(x: left, y: 0, width: total, height: height)
        guard frame != strip.frame else { return }
        // Nouvelle taille (rotation de l'écran) : le défilement repart du début
        let wasRunning = strip.layer.animation(forKey: "marquee") != nil
        strip.layer.removeAnimation(forKey: "marquee")
        strip.frame = frame
        period = fits ? 0 : perSet
        if wasRunning { start() }
    }

    func start() {
        guard motion, period > 0, strip.layer.animation(forKey: "marquee") == nil else { return }
        let scroll = CABasicAnimation(keyPath: "transform.translation.x")
        scroll.fromValue = 0
        scroll.toValue = -period
        scroll.duration = CFTimeInterval(count) * 6
        scroll.repeatCount = .infinity
        strip.layer.add(scroll, forKey: "marquee")
    }

    func stop() {
        strip.layer.removeAllAnimations()
    }
}
#endif
