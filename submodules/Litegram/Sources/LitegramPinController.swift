import Foundation
import UIKit
import LocalAuthentication

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
    public var keyButtonColor: UIColor = UIColor(white: 1.0, alpha: 0.5)

    public func applyPasscodeTheme(top: UIColor, bottom: UIColor, button: UIColor) {
        gradientTop = top
        gradientBottom = bottom
        keyButtonColor = button == .clear ? UIColor(white: 1.0, alpha: 0.5) : button
    }

    private let mode: Mode
    private var enteredPin = ""
    private var firstPin: String?
    private var confirmStep = false

    private let gradient = CAGradientLayer()
    private let lockIcon = UIImageView()
    private let titleLabel = UILabel()
    private var dots: [CAShapeLayer] = []
    private let dotsContainer = UIView()
    private var keys: [PinKey] = []
    private let deleteBtn = UIButton(type: .system)
    private var bioBtn: UIButton?
    private let cancelBtn = UIButton(type: .system)

    private static let dotSize: CGFloat = 13
    private static let dotGap: CGFloat = 24
    private static let btnSize: CGFloat = 75
    private static let btnGapH: CGFloat = 28
    private static let btnGapV: CGFloat = 16
    private static let letters = ["", "A B C", "D E F", "G H I", "J K L", "M N O", "P Q R S", "T U V", "W X Y Z", ""]

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
        gradient.frame = view.bounds
        layout()
    }

    // MARK: - Build

    private func buildUI() {
        gradient.colors = [gradientTop.cgColor, gradientBottom.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(gradient, at: 0)

        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .thin)
        lockIcon.image = UIImage(systemName: "lock.fill", withConfiguration: cfg)
        lockIcon.tintColor = .white
        lockIcon.contentMode = .scaleAspectFit
        view.addSubview(lockIcon)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        dotsContainer.backgroundColor = .clear
        view.addSubview(dotsContainer)
        for _ in 0..<4 {
            let s = CAShapeLayer()
            s.strokeColor = UIColor.white.cgColor
            s.lineWidth = 1.5
            s.fillColor = UIColor.clear.cgColor
            let r = Self.dotSize / 2
            s.path = UIBezierPath(arcCenter: CGPoint(x: r, y: r), radius: r - 0.75, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            dotsContainer.layer.addSublayer(s)
            dots.append(s)
        }

        let digits = ["1","2","3","4","5","6","7","8","9","0"]
        for (i, d) in digits.enumerated() {
            let k = PinKey(digit: d, letters: Self.letters[i], size: Self.btnSize, buttonColor: keyButtonColor)
            k.onTap = { [weak self] ch in self?.digitIn(ch) }
            view.addSubview(k)
            keys.append(k)
        }

        let delCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        deleteBtn.setImage(UIImage(systemName: "delete.left", withConfiguration: delCfg), for: .normal)
        deleteBtn.tintColor = .white
        deleteBtn.addTarget(self, action: #selector(delTap), for: .touchUpInside)
        deleteBtn.alpha = 0
        view.addSubview(deleteBtn)

        if biometricAvailable {
            let b = UIButton(type: .system)
            let type = detectBioType()
            let icon = type == .faceID ? "faceid" : "touchid"
            let bCfg = UIImage.SymbolConfiguration(pointSize: 30, weight: .thin)
            b.setImage(UIImage(systemName: icon, withConfiguration: bCfg), for: .normal)
            b.tintColor = .white
            b.addTarget(self, action: #selector(bioTap), for: .touchUpInside)
            view.addSubview(b)
            bioBtn = b
        }

        cancelBtn.setTitle("Отмена", for: .normal)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17)
        cancelBtn.addTarget(self, action: #selector(cancelTap), for: .touchUpInside)
        view.addSubview(cancelBtn)
    }

    // MARK: - Layout

    private func layout() {
        let w = view.bounds.width
        let top = min(view.bounds.height * 0.22, 200.0)

        lockIcon.frame = CGRect(x: (w - 32) / 2, y: top, width: 32, height: 32)
        titleLabel.frame = CGRect(x: 20, y: lockIcon.frame.maxY + 16, width: w - 40, height: 22)

        let dotsW = Self.dotSize * 4 + Self.dotGap * 3
        dotsContainer.frame = CGRect(x: (w - dotsW) / 2, y: titleLabel.frame.maxY + 24, width: dotsW, height: Self.dotSize)
        for (i, s) in dots.enumerated() {
            s.frame = CGRect(x: CGFloat(i) * (Self.dotSize + Self.dotGap), y: 0, width: Self.dotSize, height: Self.dotSize)
        }

        let kbW = Self.btnSize * 3 + Self.btnGapH * 2
        let kbX = (w - kbW) / 2
        let kbY = dotsContainer.frame.maxY + 36

        let positions: [(r: Int, c: Int)] = [(0,0),(0,1),(0,2),(1,0),(1,1),(1,2),(2,0),(2,1),(2,2),(3,1)]
        for (i, k) in keys.enumerated() {
            let p = positions[i]
            let x = kbX + CGFloat(p.c) * (Self.btnSize + Self.btnGapH)
            let y = kbY + CGFloat(p.r) * (Self.btnSize + Self.btnGapV)
            k.frame = CGRect(x: x, y: y, width: Self.btnSize, height: Self.btnSize)
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

    // MARK: - Dots

    private func refreshDots() {
        for (i, s) in dots.enumerated() {
            let filled = i < enteredPin.count
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            s.fillColor = filled ? UIColor.white.cgColor : UIColor.clear.cgColor
            CATransaction.commit()
            if i == enteredPin.count - 1 && !enteredPin.isEmpty {
                let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
                pulse.values = [1.0, 1.35, 1.0]
                pulse.keyTimes = [0, 0.4, 1.0]
                pulse.duration = 0.2
                s.add(pulse, forKey: "pulse")
            }
        }
        UIView.animate(withDuration: 0.15) {
            self.deleteBtn.alpha = self.enteredPin.isEmpty ? 0 : 1
        }
    }

    // MARK: - Input

    private func digitIn(_ d: String) {
        guard enteredPin.count < 4 else { return }
        enteredPin.append(d)
        refreshDots()
        if enteredPin.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.complete()
            }
        }
    }

    @objc private func delTap() {
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
                    shake()
                    titleLabel.text = "PIN не совпал"
                    confirmStep = false
                    firstPin = nil
                    enteredPin = ""
                    refreshDots()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.refreshTitle()
                    }
                }
            } else {
                firstPin = enteredPin
                confirmStep = true
                enteredPin = ""
                refreshDots()
                refreshTitle()
            }

        case .verify(let pid):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkPin(pid, pin: enteredPin) {
                unlockAnim { [weak self] in
                    LitegramChatLocks.shared.markUnlocked(pid)
                    self?.onPinVerified?()
                    self?.dismiss(animated: false)
                }
            } else { wrongPin() }

        case .verifyFolder(let fid):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkFolderPin(fid, pin: enteredPin) {
                unlockAnim { [weak self] in
                    LitegramChatLocks.shared.markFolderUnlocked(fid)
                    self?.onPinVerified?()
                    self?.dismiss(animated: false)
                }
            } else { wrongPin() }
        }
    }

    private func wrongPin() {
        shake()
        enteredPin = ""
        refreshDots()
    }

    // MARK: - Animations

    private func shake() {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values = [0, -12, 12, -10, 10, -6, 6, 0]
        anim.duration = 0.4
        dotsContainer.layer.add(anim, forKey: "shake")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func unlockAnim(done: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        for dot in dots {
            let glow = CAKeyframeAnimation(keyPath: "transform.scale")
            glow.values = [1.0, 1.5, 1.0]
            glow.keyTimes = [0, 0.5, 1.0]
            glow.duration = 0.3
            dot.add(glow, forKey: "glow")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .thin)
            self.lockIcon.image = UIImage(systemName: "lock.open.fill", withConfiguration: cfg)

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            self.gradient.opacity = 0
            CATransaction.commit()

            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
                self.lockIcon.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
                self.lockIcon.alpha = 0
                self.dotsContainer.alpha = 0
                self.titleLabel.alpha = 0
                for key in self.keys { key.alpha = 0 }
                self.deleteBtn.alpha = 0
                self.bioBtn?.alpha = 0
                self.cancelBtn.alpha = 0
            }) { _ in done() }
        }
    }

    @objc private func cancelTap() {
        onDismiss?()
        dismiss(animated: true)
    }

    // MARK: - Biometric

    private func detectBioType() -> LABiometryType {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return c.biometryType
    }

    private var biometricAvailable: Bool {
        guard LitegramChatLocks.shared.isBiometricEnabled else { return false }
        if case .set = mode { return false }
        let c = LAContext()
        return c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    @objc private func bioTap() { tryBiometric() }

    private func tryBiometric() {
        guard biometricAvailable else { return }
        let c = LAContext()
        c.localizedCancelTitle = "Ввести PIN"
        c.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Разблокировать чат") { [weak self] ok, _ in
            guard ok else { return }
            DispatchQueue.main.async {
                self?.enteredPin = "__bio__"
                self?.complete()
            }
        }
    }
}

// MARK: - PinKey

private final class PinKey: UIControl {
    var onTap: ((String) -> Void)?
    private let digit: String
    private let digitLbl = UILabel()
    private let lettersLbl = UILabel()
    private let circle = CAShapeLayer()
    private let btnColor: UIColor

    init(digit: String, letters: String, size: CGFloat, buttonColor: UIColor) {
        self.digit = digit
        self.btnColor = buttonColor
        super.init(frame: .zero)

        let r = size / 2
        circle.path = UIBezierPath(arcCenter: CGPoint(x: r, y: r), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        circle.fillColor = buttonColor.withAlphaComponent(0.8).cgColor
        layer.addSublayer(circle)

        digitLbl.text = digit
        digitLbl.font = .systemFont(ofSize: 36, weight: .thin)
        digitLbl.textColor = .white
        digitLbl.textAlignment = .center
        addSubview(digitLbl)

        if !letters.trimmingCharacters(in: .whitespaces).isEmpty {
            let attr = NSAttributedString(string: letters, attributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.white,
                .kern: 2.0
            ])
            lettersLbl.attributedText = attr
            lettersLbl.textAlignment = .center
            addSubview(lettersLbl)
        }

        addTarget(self, action: #selector(tap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        circle.frame = bounds
        let r = bounds.width / 2
        circle.path = UIBezierPath(arcCenter: CGPoint(x: r, y: r), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

        if lettersLbl.superview != nil {
            digitLbl.frame = CGRect(x: 0, y: bounds.height * 0.18, width: bounds.width, height: bounds.height * 0.46)
            lettersLbl.frame = CGRect(x: 0, y: digitLbl.frame.maxY - 2, width: bounds.width, height: 14)
        } else {
            digitLbl.frame = CGRect(x: 0, y: bounds.height * 0.22, width: bounds.width, height: bounds.height * 0.56)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.08)
            if isHighlighted {
                circle.fillColor = blend(base: btnColor.withAlphaComponent(0.8), overlay: UIColor(white: 1.0, alpha: 0.65)).cgColor
            } else {
                circle.fillColor = btnColor.withAlphaComponent(0.8).cgColor
            }
            CATransaction.commit()
        }
    }

    private func blend(base: UIColor, overlay: UIColor) -> UIColor {
        var bR: CGFloat = 0, bG: CGFloat = 0, bB: CGFloat = 0, bA: CGFloat = 0
        var oR: CGFloat = 0, oG: CGFloat = 0, oB: CGFloat = 0, oA: CGFloat = 0
        base.getRed(&bR, green: &bG, blue: &bB, alpha: &bA)
        overlay.getRed(&oR, green: &oG, blue: &oB, alpha: &oA)
        let a = oA + bA * (1 - oA)
        guard a > 0 else { return base }
        let r = (oR * oA + bR * bA * (1 - oA)) / a
        let g = (oG * oA + bG * bA * (1 - oA)) / a
        let b = (oB * oA + bB * bA * (1 - oA)) / a
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    @objc private func tap() { onTap?(digit) }
}
