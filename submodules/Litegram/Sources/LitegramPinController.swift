import Foundation
import UIKit
import LocalAuthentication
import TelegramCore

public final class LitegramPinController: UIViewController {

    public enum Mode {
        case set
        case verify(peerId: Int64)
        case verifyFolder(filterId: Int32)
    }

    public var onPinSet: ((_ pin: String) -> Void)?
    public var onPinVerified: (() -> Void)?
    public var onDismiss: (() -> Void)?

    public var gradientTop: UIColor = UIColor(red: 0.275, green: 0.451, blue: 0.620, alpha: 1.0)
    public var gradientBottom: UIColor = UIColor(red: 0.165, green: 0.349, blue: 0.510, alpha: 1.0)
    public var isDarkTheme = false

    public func applyPasscodeTheme(top: UIColor, bottom: UIColor, button: UIColor, isDark: Bool = false) {
        gradientTop = top
        gradientBottom = bottom
        isDarkTheme = isDark
    }

    public static func passcodeColors(
        wallpaper: TelegramWallpaper,
        isDark: Bool,
        bubbleFallback: UIColor?,
        passcodeTop: UIColor,
        passcodeBottom: UIColor,
        passcodeButton: UIColor
    ) -> (top: UIColor, bottom: UIColor, button: UIColor) {
        switch wallpaper {
        case .color(let cv):
            let color = rgbColor(cv)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            let lightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let base = (lightness < 0.1 || lightness > 0.9) ? (bubbleFallback ?? color) : color
            if isDark {
                return (
                    top: hsbMul(base, h: 1.034, s: 0.819, b: 0.214),
                    bottom: hsbMul(base, h: 1.029, s: 0.77, b: 0.132),
                    button: UIColor(white: 1.0, alpha: 0.12)
                )
            } else {
                return (
                    top: hsbMul(base, h: 1.029, s: 0.312, b: 1.26),
                    bottom: hsbMul(base, h: 1.034, s: 0.729, b: 0.942),
                    button: UIColor(white: 0.0, alpha: 0.2)
                )
            }
        case .gradient(let g):
            if g.colors.count >= 2 {
                return (
                    top: rgbColor(g.colors[0]),
                    bottom: rgbColor(g.colors.last!),
                    button: isDark ? UIColor(white: 1.0, alpha: 0.12) : UIColor(white: 0.0, alpha: 0.2)
                )
            }
            return (top: passcodeTop, bottom: passcodeBottom, button: passcodeButton)
        case .file(let f) where !f.settings.colors.isEmpty:
            return (
                top: rgbColor(f.settings.colors[0]),
                bottom: rgbColor(f.settings.colors.last!),
                button: isDark ? UIColor(white: 1.0, alpha: 0.12) : UIColor(white: 0.0, alpha: 0.2)
            )
        default:
            return (top: passcodeTop, bottom: passcodeBottom, button: passcodeButton)
        }
    }

    private static func rgbColor(_ v: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((v >> 16) & 0xff) / 255.0,
            green: CGFloat((v >> 8) & 0xff) / 255.0,
            blue: CGFloat(v & 0xff) / 255.0,
            alpha: 1.0
        )
    }

    private static func hsbMul(_ c: UIColor, h: CGFloat, s: CGFloat, b: CGFloat) -> UIColor {
        var ch: CGFloat = 0, cs: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
        c.getHue(&ch, saturation: &cs, brightness: &cb, alpha: &ca)
        return UIColor(
            hue: min(1, max(0, ch * h)),
            saturation: min(1, max(0, cs * s)),
            brightness: min(1, max(0, cb * b)),
            alpha: ca
        )
    }

    private let mode: Mode
    private var enteredPin = ""
    private var firstPin: String?
    private var confirmStep = false

    private let gradientLayer = CAGradientLayer()
    private let lockIcon = UIImageView()
    private let titleLabel = UILabel()
    private var dotViews: [UIImageView] = []
    private let dotsContainer = UIView()
    private var keyButtons: [PinKeyButton] = []
    private let deleteBtn = UIButton(type: .system)
    private var bioBtn: UIButton?
    private let cancelBtn = UIButton(type: .system)

    private var dotEmptyImg: UIImage!
    private var dotFilledImg: UIImage!

    private static let dotDiam: CGFloat = 13
    private static let dotGap: CGFloat = 24
    private static let btnSize: CGFloat = 75
    private static let btnGapH: CGFloat = 28
    private static let btnGapV: CGFloat = 16
    private static let subtitles = [" ", "A B C", "D E F", "G H I", "J K L", "M N O", "P Q R S", "T U V", "W X Y Z", ""]

    public init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    public override func viewDidLoad() {
        super.viewDidLoad()
        dotEmptyImg = Self.makeDotImage(filled: false)
        dotFilledImg = Self.makeDotImage(filled: true)
        buildUI()
        refreshTitle()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .set = mode { return }
        tryBiometric()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
        layoutElements()
    }

    // MARK: - Dot Images (matching PasscodeInputFieldNode)

    private static func makeDotImage(filled: Bool) -> UIImage {
        let d = dotDiam
        return UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { ctx in
            let r = CGRect(x: 0, y: 0, width: d, height: d)
            if filled {
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: r)
            } else {
                UIColor.white.setStroke()
                ctx.cgContext.setLineWidth(1.0)
                ctx.cgContext.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
            }
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        gradientLayer.colors = [gradientBottom.cgColor, gradientTop.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)

        let iconCfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .thin)
        lockIcon.image = UIImage(systemName: "lock.fill", withConfiguration: iconCfg)
        lockIcon.tintColor = .white
        lockIcon.contentMode = .scaleAspectFit
        view.addSubview(lockIcon)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .regular)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        dotsContainer.backgroundColor = .clear
        view.addSubview(dotsContainer)
        for _ in 0..<4 {
            let iv = UIImageView(image: dotEmptyImg)
            iv.contentMode = .scaleToFill
            dotsContainer.addSubview(iv)
            dotViews.append(iv)
        }

        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        for (i, d) in digits.enumerated() {
            let btn = PinKeyButton(digit: d, letters: Self.subtitles[i], size: Self.btnSize, isDark: isDarkTheme)
            btn.onTap = { [weak self] ch in self?.digitEntered(ch) }
            view.addSubview(btn)
            keyButtons.append(btn)
        }

        let delCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        deleteBtn.setImage(UIImage(systemName: "delete.left", withConfiguration: delCfg), for: .normal)
        deleteBtn.tintColor = .white
        deleteBtn.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteBtn.alpha = 0
        view.addSubview(deleteBtn)

        if biometricAvailable {
            let b = UIButton(type: .system)
            let bioType = detectBioType()
            let iconName = bioType == .faceID ? "faceid" : "touchid"
            let bCfg = UIImage.SymbolConfiguration(pointSize: 30, weight: .thin)
            b.setImage(UIImage(systemName: iconName, withConfiguration: bCfg), for: .normal)
            b.tintColor = .white
            b.addTarget(self, action: #selector(bioTapped), for: .touchUpInside)
            view.addSubview(b)
            bioBtn = b
        }

        cancelBtn.setTitle("Отмена", for: .normal)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)
    }

    // MARK: - Layout

    private func layoutElements() {
        let w = view.bounds.width
        let topY = min(view.bounds.height * 0.22, 200.0)

        lockIcon.frame = CGRect(x: (w - 35) / 2, y: topY, width: 35, height: 37)
        titleLabel.frame = CGRect(x: 20, y: lockIcon.frame.maxY + 16, width: w - 40, height: 24)

        let dotsW = Self.dotDiam * 4 + Self.dotGap * 3
        dotsContainer.frame = CGRect(x: (w - dotsW) / 2, y: titleLabel.frame.maxY + 24, width: dotsW, height: Self.dotDiam)
        for (i, iv) in dotViews.enumerated() {
            iv.frame = CGRect(x: CGFloat(i) * (Self.dotDiam + Self.dotGap), y: 0, width: Self.dotDiam, height: Self.dotDiam)
        }

        let kbW = Self.btnSize * 3 + Self.btnGapH * 2
        let kbX = (w - kbW) / 2
        let kbY = dotsContainer.frame.maxY + 36

        let grid: [(r: Int, c: Int)] = [(0,0),(0,1),(0,2),(1,0),(1,1),(1,2),(2,0),(2,1),(2,2),(3,1)]
        for (i, btn) in keyButtons.enumerated() {
            let p = grid[i]
            let x = kbX + CGFloat(p.c) * (Self.btnSize + Self.btnGapH)
            let y = kbY + CGFloat(p.r) * (Self.btnSize + Self.btnGapV)
            btn.frame = CGRect(x: x, y: y, width: Self.btnSize, height: Self.btnSize)
        }

        let row4Y = kbY + 3 * (Self.btnSize + Self.btnGapV)
        bioBtn?.frame = CGRect(x: kbX, y: row4Y, width: Self.btnSize, height: Self.btnSize)
        deleteBtn.frame = CGRect(x: kbX + 2 * (Self.btnSize + Self.btnGapH), y: row4Y, width: Self.btnSize, height: Self.btnSize)
        cancelBtn.frame = CGRect(x: kbX, y: row4Y + Self.btnSize + 16, width: 80, height: 30)
    }

    // MARK: - Title

    private func refreshTitle() {
        switch mode {
        case .set:
            titleLabel.text = confirmStep ? "Подтвердите PIN-код" : "Установите PIN-код"
        case .verify, .verifyFolder:
            titleLabel.text = "Введите PIN-код"
        }
    }

    // MARK: - Dot Animations (matching PasscodeEntryDotNode)

    private func setDot(_ index: Int, filled: Bool, animated: Bool, delay: Double = 0) {
        let iv = dotViews[index]
        let target = filled ? dotFilledImg! : dotEmptyImg!
        let prev = iv.layer.contents

        iv.layer.removeAnimation(forKey: "contents")
        iv.image = target

        guard animated, let prev = prev else { return }

        let dur = filled ? 0.05 : 0.25
        let a = CABasicAnimation(keyPath: "contents")
        a.fromValue = prev
        a.toValue = target.cgImage!
        a.duration = dur
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if delay > 0 {
            a.beginTime = CACurrentMediaTime() + delay
            a.fillMode = .backwards
        }
        iv.layer.add(a, forKey: "contents")
    }

    private func refreshDots() {
        for i in 0..<4 {
            setDot(i, filled: i < enteredPin.count, animated: true)
        }
        UIView.animate(withDuration: 0.15) {
            self.deleteBtn.alpha = self.enteredPin.isEmpty ? 0 : 1
        }
    }

    private func resetDotsAnimated() {
        var d: Double = 0
        for i in stride(from: 3, through: 0, by: -1) {
            setDot(i, filled: false, animated: true, delay: d)
            d += 0.05
        }
    }

    private func fillAllDots() {
        var d: Double = 0
        for i in 0..<4 {
            setDot(i, filled: true, animated: true, delay: d)
            d += 0.01
        }
    }

    // MARK: - Input

    private func digitEntered(_ ch: String) {
        guard enteredPin.count < 4 else { return }
        enteredPin.append(ch)
        refreshDots()
        if enteredPin.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.complete()
            }
        }
    }

    @objc private func deleteTapped() {
        guard !enteredPin.isEmpty else { return }
        enteredPin.removeLast()
        refreshDots()
    }

    private func complete() {
        switch mode {
        case .set:
            if confirmStep {
                if enteredPin == firstPin {
                    onPinSet?(enteredPin)
                    dismiss(animated: true)
                } else {
                    shakeError()
                    titleLabel.text = "PIN не совпал"
                    confirmStep = false
                    firstPin = nil
                    enteredPin = ""
                    resetDotsAnimated()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.refreshTitle()
                    }
                }
            } else {
                firstPin = enteredPin
                confirmStep = true
                enteredPin = ""
                resetDotsAnimated()
                refreshTitle()
            }

        case .verify(let pid):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkPin(pid, pin: enteredPin) {
                performUnlock { [weak self] in
                    LitegramChatLocks.shared.markUnlocked(pid)
                    self?.onPinVerified?()
                }
            } else { wrongPin() }

        case .verifyFolder(let fid):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkFolderPin(fid, pin: enteredPin) {
                performUnlock { [weak self] in
                    LitegramChatLocks.shared.markFolderUnlocked(fid)
                    self?.onPinVerified?()
                }
            } else { wrongPin() }
        }
    }

    private func wrongPin() {
        shakeError()
        enteredPin = ""
        resetDotsAnimated()
    }

    // MARK: - Shake (matching Display/ShakeAnimation.swift)

    private func shakeError() {
        Self.addShake(to: dotsContainer.layer, amplitude: -30, duration: 0.5, count: 6)
        Self.addShake(to: lockIcon.layer, amplitude: -8, duration: 0.5, count: 6)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private static func addShake(to layer: CALayer, amplitude: CGFloat, duration: Double, count: Int) {
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        var vals: [CGFloat] = [0]
        for i in 0..<count {
            let sign: CGFloat = (i % 2 == 0) ? 1 : -1
            vals.append(amplitude * sign / CGFloat(i + 1))
        }
        vals.append(0)
        anim.values = vals.map { NSNumber(value: Double($0)) }
        var kt: [NSNumber] = []
        for i in 0..<vals.count {
            if i == 0 { kt.append(0) }
            else if i == vals.count - 1 { kt.append(1) }
            else { kt.append(NSNumber(value: Double(i) / Double(vals.count - 1))) }
        }
        anim.keyTimes = kt
        anim.duration = duration
        anim.isAdditive = true
        layer.add(anim, forKey: "shake")
    }

    // MARK: - Unlock (matching PasscodeEntryControllerNode.animateSuccess + animateOut)

    private func performUnlock(markAndNotify: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        fillAllDots()

        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .thin)
        lockIcon.image = UIImage(systemName: "lock.open.fill", withConfiguration: cfg)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            markAndNotify()
            UIView.animate(withDuration: 0.2, animations: {
                self.view.transform = CGAffineTransform(translationX: 0, y: -self.view.bounds.height)
            }) { _ in
                self.dismiss(animated: false)
            }
        }
    }

    @objc private func cancelTapped() {
        onDismiss?()
        dismiss(animated: true)
    }

    // MARK: - Biometric

    private func detectBioType() -> LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    private var biometricAvailable: Bool {
        guard LitegramChatLocks.shared.isBiometricEnabled else { return false }
        if case .set = mode { return false }
        let ctx = LAContext()
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    @objc private func bioTapped() { tryBiometric() }

    private func tryBiometric() {
        guard biometricAvailable else { return }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Ввести PIN"
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Разблокировать чат") { [weak self] ok, _ in
            guard ok else { return }
            DispatchQueue.main.async {
                self?.enteredPin = "__bio__"
                self?.complete()
            }
        }
    }
}

// MARK: - PinKeyButton (matching PasscodeEntryButtonNode with NavigationBackgroundNode blur)

private final class PinKeyButton: UIControl {
    var onTap: ((String) -> Void)?
    private let digit: String
    private let hasSubtitle: Bool

    private let blurView: UIVisualEffectView
    private let tintView = UIView()
    private let highlightView = UIView()
    private let digitLabel = UILabel()
    private let lettersLabel = UILabel()

    init(digit: String, letters: String, size: CGFloat, isDark: Bool) {
        self.digit = digit
        self.hasSubtitle = !letters.isEmpty

        let style: UIBlurEffect.Style = isDark ? .dark : .light
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: style))

        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))

        let r = size / 2

        blurView.layer.cornerRadius = r
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        tintView.backgroundColor = isDark
            ? UIColor(white: 1.0, alpha: 0.05)
            : UIColor(white: 0.0, alpha: 0.15)
        tintView.layer.cornerRadius = r
        tintView.clipsToBounds = true
        tintView.isUserInteractionEnabled = false
        addSubview(tintView)

        highlightView.backgroundColor = UIColor(white: 1.0, alpha: 0.65)
        highlightView.layer.cornerRadius = r
        highlightView.clipsToBounds = true
        highlightView.isUserInteractionEnabled = false
        highlightView.alpha = 0
        addSubview(highlightView)

        digitLabel.text = digit
        digitLabel.font = .systemFont(ofSize: 36, weight: .regular)
        digitLabel.textColor = .white
        digitLabel.textAlignment = .center
        addSubview(digitLabel)

        let trimmed = letters.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor.white,
                .kern: 2.0 as NSNumber
            ]
            lettersLabel.attributedText = NSAttributedString(string: letters, attributes: attrs)
            lettersLabel.textAlignment = .center
            addSubview(lettersLabel)
        }

        addTarget(self, action: #selector(fired), for: .touchDown)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        tintView.frame = bounds
        highlightView.frame = bounds

        let dSize = digitLabel.intrinsicContentSize
        if hasSubtitle {
            let lH = ceil(UIFont.systemFont(ofSize: 10, weight: .bold).lineHeight)
            let totalH = ceil(dSize.height) + 3.0 + lH
            let topY = floor((bounds.height - totalH) / 2.0)
            digitLabel.frame = CGRect(x: 0, y: topY, width: bounds.width, height: ceil(dSize.height))
            if lettersLabel.superview != nil {
                lettersLabel.frame = CGRect(x: 0, y: topY + ceil(dSize.height) + 3.0, width: bounds.width, height: lH)
            }
        } else {
            digitLabel.frame = CGRect(
                x: 0,
                y: floor((bounds.height - dSize.height) / 2.0),
                width: bounds.width,
                height: ceil(dSize.height)
            )
        }
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                UIView.animate(withDuration: 0.05) { self.highlightView.alpha = 1 }
            } else {
                UIView.animate(withDuration: 0.45) { self.highlightView.alpha = 0 }
            }
        }
    }

    @objc private func fired() { onTap?(digit) }
}
