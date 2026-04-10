import Foundation
import UIKit
import LocalAuthentication

public final class LitegramPinController: UIViewController {

    public enum Mode {
        case set
        case verify(dialogId: Int64)
        case verifyFolder(filterId: Int32)
        case verifyGroup(groupId: Int)
    }

    public typealias OnPinSet = (_ pin: String, _ hint: String?) -> Void
    public typealias OnPinVerified = () -> Void
    public typealias OnDismiss = () -> Void

    private let mode: Mode
    private var onPinSet: OnPinSet?
    private var onPinVerified: OnPinVerified?
    private var onDismiss: OnDismiss?

    private var enteredPin = ""
    private var firstPin: String?
    private var isConfirmStep = false

    private let gradientLayer = CAGradientLayer()
    private let lockImageView = UIImageView()
    private var dotLayers: [CAShapeLayer] = []
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private var keyButtons: [PinKeyButton] = []
    private let deleteButton = UIButton(type: .system)
    private var biometricButton: UIButton?
    private let cancelButton = UIButton(type: .system)
    private let hintButton = UIButton(type: .system)

    private let dotsContainer = UIView()
    private let keypadContainer = UIView()

    private static let dotDiameter: CGFloat = 13.0
    private static let dotSpacing: CGFloat = 24.0
    private static let buttonSize: CGFloat = 75.0
    private static let keypadHSpacing: CGFloat = 28.0
    private static let keypadVSpacing: CGFloat = 16.0

    private static let keyLetters: [String] = [
        " ", "A B C", "D E F",
        "G H I", "J K L", "M N O",
        "P Q R S", "T U V", "W X Y Z",
        "", "", ""
    ]

    public init(mode: Mode, onPinSet: OnPinSet? = nil, onPinVerified: OnPinVerified? = nil, onDismiss: OnDismiss? = nil) {
        self.mode = mode
        self.onPinSet = onPinSet
        self.onPinVerified = onPinVerified
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    public override var prefersHomeIndicatorAutoHidden: Bool { true }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupGradient()
        setupLockIcon()
        setupLabels()
        setupDots()
        setupKeypad()
        setupAccessoryButtons()
        updateTitle()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        switch mode {
        case .verify, .verifyFolder, .verifyGroup:
            attemptBiometric()
        default:
            break
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
        layoutAllElements()
    }

    // MARK: - Gradient

    private func setupGradient() {
        gradientLayer.colors = [
            UIColor(red: 0.275, green: 0.451, blue: 0.620, alpha: 1.0).cgColor,
            UIColor(red: 0.165, green: 0.349, blue: 0.510, alpha: 1.0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)
    }

    // MARK: - Lock icon

    private func setupLockIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .thin)
        lockImageView.image = UIImage(systemName: "lock.fill", withConfiguration: config)
        lockImageView.tintColor = .white
        lockImageView.contentMode = .scaleAspectFit
        view.addSubview(lockImageView)
    }

    // MARK: - Labels

    private func setupLabels() {
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        view.addSubview(subtitleLabel)
    }

    // MARK: - Dots

    private func setupDots() {
        dotsContainer.backgroundColor = .clear
        view.addSubview(dotsContainer)
        for _ in 0..<4 {
            let layer = CAShapeLayer()
            layer.strokeColor = UIColor.white.cgColor
            layer.lineWidth = 1.5
            layer.fillColor = UIColor.clear.cgColor
            let r = Self.dotDiameter / 2
            layer.path = UIBezierPath(arcCenter: CGPoint(x: r, y: r), radius: r - 0.75, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            dotsContainer.layer.addSublayer(layer)
            dotLayers.append(layer)
        }
    }

    // MARK: - Keypad

    private func setupKeypad() {
        keypadContainer.backgroundColor = .clear
        view.addSubview(keypadContainer)

        let digits = ["1","2","3","4","5","6","7","8","9","","0",""]
        for (i, digit) in digits.enumerated() {
            if i == 9 || i == 11 { continue }
            let letters = Self.keyLetters[i]
            let btn = PinKeyButton(digit: digit, letters: letters, size: Self.buttonSize)
            btn.onTap = { [weak self] d in self?.digitEntered(d) }
            keypadContainer.addSubview(btn)
            keyButtons.append(btn)
        }
    }

    // MARK: - Accessory buttons (delete, biometric, cancel, hint)

    private func setupAccessoryButtons() {
        let delConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: delConfig), for: .normal)
        deleteButton.tintColor = .white
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.alpha = 0
        view.addSubview(deleteButton)

        if canUseBiometric {
            let bioBtn = UIButton(type: .system)
            let biometryType = detectBiometryType()
            let iconName: String
            switch biometryType {
            case .faceID:
                iconName = "faceid"
            default:
                iconName = "touchid"
            }
            let bioConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .thin)
            bioBtn.setImage(UIImage(systemName: iconName, withConfiguration: bioConfig), for: .normal)
            bioBtn.tintColor = .white
            bioBtn.addTarget(self, action: #selector(biometricTapped), for: .touchUpInside)
            view.addSubview(bioBtn)
            biometricButton = bioBtn
        }

        cancelButton.setTitle("Отмена", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        hintButton.setTitle("Подсказка", for: .normal)
        hintButton.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .normal)
        hintButton.titleLabel?.font = .systemFont(ofSize: 14)
        hintButton.addTarget(self, action: #selector(hintTapped), for: .touchUpInside)
        hintButton.isHidden = true
        view.addSubview(hintButton)

        switch mode {
        case .verify(let dialogId):
            hintButton.isHidden = LitegramChatLocks.shared.getHint(dialogId) == nil
        case .verifyFolder(let filterId):
            hintButton.isHidden = LitegramChatLocks.shared.getFolderHint(filterId) == nil
        case .verifyGroup(let groupId):
            hintButton.isHidden = LitegramChatLocks.shared.getGroupHint(groupId) == nil
        default: break
        }
    }

    // MARK: - Layout

    private func layoutAllElements() {
        let w = view.bounds.width
        let h = view.bounds.height
        let safeTop = view.safeAreaInsets.top
        let isLandscape = w > h

        let kbTotalW = Self.buttonSize * 3 + Self.keypadHSpacing * 2
        let kbTotalH = Self.buttonSize * 4 + Self.keypadVSpacing * 3

        if isLandscape {
            layoutLandscape(w: w, h: h, safeTop: safeTop, kbW: kbTotalW, kbH: kbTotalH)
        } else {
            layoutPortrait(w: w, h: h, safeTop: safeTop, kbW: kbTotalW, kbH: kbTotalH)
        }

        layoutKeyButtons(in: keypadContainer.bounds, kbW: kbTotalW, kbH: kbTotalH)
    }

    private func layoutPortrait(w: CGFloat, h: CGFloat, safeTop: CGFloat, kbW: CGFloat, kbH: CGFloat) {
        let topSection = min(h * 0.32, 280.0)

        lockImageView.frame = CGRect(x: (w - 36) / 2, y: topSection - 110, width: 36, height: 36)
        titleLabel.frame = CGRect(x: 20, y: lockImageView.frame.maxY + 14, width: w - 40, height: 22)
        subtitleLabel.frame = CGRect(x: 20, y: titleLabel.frame.maxY + 4, width: w - 40, height: 20)

        let dotsW = Self.dotDiameter * 4 + Self.dotSpacing * 3
        dotsContainer.frame = CGRect(x: (w - dotsW) / 2, y: subtitleLabel.frame.maxY + 24, width: dotsW, height: Self.dotDiameter)
        layoutDots()

        let kbY = dotsContainer.frame.maxY + 30
        keypadContainer.frame = CGRect(x: (w - kbW) / 2, y: kbY, width: kbW, height: kbH)

        let bottomRowY = kbY + Self.buttonSize * 3 + Self.keypadVSpacing * 3
        let leftX = (w - kbW) / 2
        let rightX = leftX + kbW - Self.buttonSize

        if let bioBtn = biometricButton {
            bioBtn.frame = CGRect(x: leftX, y: bottomRowY, width: Self.buttonSize, height: Self.buttonSize)
        }
        deleteButton.frame = CGRect(x: rightX, y: bottomRowY, width: Self.buttonSize, height: Self.buttonSize)

        cancelButton.frame = CGRect(x: leftX, y: bottomRowY + Self.buttonSize + 10, width: 80, height: 30)
        hintButton.frame = CGRect(x: (w - 120) / 2, y: cancelButton.frame.minY, width: 120, height: 30)
    }

    private func layoutLandscape(w: CGFloat, h: CGFloat, safeTop: CGFloat, kbW: CGFloat, kbH: CGFloat) {
        let leftHalf = w * 0.35
        lockImageView.frame = CGRect(x: (leftHalf - 36) / 2, y: safeTop + 30, width: 36, height: 36)
        titleLabel.frame = CGRect(x: 10, y: lockImageView.frame.maxY + 10, width: leftHalf - 20, height: 22)
        subtitleLabel.frame = CGRect(x: 10, y: titleLabel.frame.maxY + 4, width: leftHalf - 20, height: 20)

        let dotsW = Self.dotDiameter * 4 + Self.dotSpacing * 3
        dotsContainer.frame = CGRect(x: (leftHalf - dotsW) / 2, y: subtitleLabel.frame.maxY + 20, width: dotsW, height: Self.dotDiameter)
        layoutDots()

        let scale: CGFloat = min(1.0, (h - safeTop - 20) / kbH)
        let scaledKbW = kbW * scale
        let scaledKbH = kbH * scale
        let kbX = leftHalf + (w - leftHalf - scaledKbW) / 2
        let kbY = (h - scaledKbH) / 2
        keypadContainer.frame = CGRect(x: kbX, y: kbY, width: scaledKbW, height: scaledKbH)

        cancelButton.frame = CGRect(x: 20, y: h - 50, width: 80, height: 30)
        hintButton.frame = CGRect(x: (leftHalf - 120) / 2, y: cancelButton.frame.minY, width: 120, height: 30)
        deleteButton.frame = CGRect(x: kbX + scaledKbW - Self.buttonSize * scale, y: kbY + 3 * (Self.buttonSize + Self.keypadVSpacing) * scale, width: Self.buttonSize * scale, height: Self.buttonSize * scale)
        if let bioBtn = biometricButton {
            bioBtn.frame = CGRect(x: kbX, y: deleteButton.frame.minY, width: Self.buttonSize * scale, height: Self.buttonSize * scale)
        }
    }

    private func layoutDots() {
        for (i, layer) in dotLayers.enumerated() {
            let x = CGFloat(i) * (Self.dotDiameter + Self.dotSpacing)
            layer.frame = CGRect(x: x, y: 0, width: Self.dotDiameter, height: Self.dotDiameter)
        }
    }

    private func layoutKeyButtons(in bounds: CGRect, kbW: CGFloat, kbH: CGFloat) {
        let positions: [(row: Int, col: Int, digit: String)] = [
            (0, 0, "1"), (0, 1, "2"), (0, 2, "3"),
            (1, 0, "4"), (1, 1, "5"), (1, 2, "6"),
            (2, 0, "7"), (2, 1, "8"), (2, 2, "9"),
            (3, 1, "0")
        ]
        var btnIndex = 0
        for pos in positions {
            guard btnIndex < keyButtons.count else { break }
            let btn = keyButtons[btnIndex]
            let x = CGFloat(pos.col) * (Self.buttonSize + Self.keypadHSpacing)
            let y = CGFloat(pos.row) * (Self.buttonSize + Self.keypadVSpacing)
            btn.frame = CGRect(x: x, y: y, width: Self.buttonSize, height: Self.buttonSize)
            btnIndex += 1
        }
    }

    // MARK: - Title

    private func updateTitle() {
        switch mode {
        case .set:
            if isConfirmStep {
                titleLabel.text = "Подтвердите PIN"
                subtitleLabel.text = "Введите PIN ещё раз"
            } else {
                titleLabel.text = "Установите PIN"
                subtitleLabel.text = "Введите 4-значный PIN"
            }
        case .verify, .verifyFolder, .verifyGroup:
            titleLabel.text = "Введите PIN"
            subtitleLabel.text = nil
        }
    }

    // MARK: - Dots update

    private func updateDots() {
        for (i, layer) in dotLayers.enumerated() {
            let filled = i < enteredPin.count
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            layer.fillColor = filled ? UIColor.white.cgColor : UIColor.clear.cgColor
            CATransaction.commit()

            if filled && i == enteredPin.count - 1 {
                let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
                pulse.values = [1.0, 1.4, 1.0]
                pulse.keyTimes = [0, 0.4, 1.0]
                pulse.duration = 0.2
                layer.add(pulse, forKey: "pulse")
            }
        }
        deleteButton.alpha = enteredPin.isEmpty ? 0 : 1
    }

    // MARK: - Input

    private func digitEntered(_ digit: String) {
        guard enteredPin.count < 4 else { return }
        enteredPin.append(digit)
        updateDots()
        if enteredPin.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.handlePinComplete()
            }
        }
    }

    @objc private func deleteTapped() {
        guard !enteredPin.isEmpty else { return }
        enteredPin.removeLast()
        updateDots()
    }

    @objc private func biometricTapped() {
        attemptBiometric()
    }

    private func handlePinComplete() {
        switch mode {
        case .set:
            if isConfirmStep {
                if enteredPin == firstPin {
                    askForHint { [weak self] hint in
                        self?.onPinSet?(self?.enteredPin ?? "", hint)
                        self?.dismissAnimated()
                    }
                } else {
                    shakeAnimation()
                    subtitleLabel.text = "PIN не совпал, попробуйте снова"
                    isConfirmStep = false
                    firstPin = nil
                    enteredPin = ""
                    updateDots()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.updateTitle()
                    }
                }
            } else {
                firstPin = enteredPin
                isConfirmStep = true
                enteredPin = ""
                updateDots()
                updateTitle()
            }

        case .verify(let dialogId):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkPin(dialogId, pin: enteredPin) {
                playUnlockAnimation {
                    LitegramChatLocks.shared.markUnlocked(dialogId)
                    self.onPinVerified?()
                    self.dismissAnimated()
                }
            } else {
                wrongPin()
            }

        case .verifyFolder(let filterId):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkFolderPin(filterId, pin: enteredPin) {
                playUnlockAnimation {
                    LitegramChatLocks.shared.markFolderUnlocked(filterId)
                    self.onPinVerified?()
                    self.dismissAnimated()
                }
            } else {
                wrongPin()
            }

        case .verifyGroup(let groupId):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkGroupPin(groupId, pin: enteredPin) {
                playUnlockAnimation {
                    self.onPinVerified?()
                    self.dismissAnimated()
                }
            } else {
                wrongPin()
            }
        }
    }

    private func wrongPin() {
        shakeAnimation()
        enteredPin = ""
        updateDots()
    }

    // MARK: - Hint

    @objc private func hintTapped() {
        var hintText: String?
        switch mode {
        case .verify(let dialogId):
            hintText = LitegramChatLocks.shared.getHint(dialogId)
        case .verifyFolder(let filterId):
            hintText = LitegramChatLocks.shared.getFolderHint(filterId)
        case .verifyGroup(let groupId):
            hintText = LitegramChatLocks.shared.getGroupHint(groupId)
        default: break
        }
        guard let hint = hintText else { return }

        let toast = UILabel()
        toast.text = "  \(hint)  "
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 18
        toast.clipsToBounds = true
        toast.sizeToFit()
        toast.frame.size.width += 32
        toast.frame.size.height = 36
        toast.center.x = view.bounds.midX
        toast.frame.origin.y = view.safeAreaInsets.top + 50
        view.addSubview(toast)

        UIView.animate(withDuration: 0.3, delay: 2.5, options: [], animations: { toast.alpha = 0 }) { _ in
            toast.removeFromSuperview()
        }
    }

    private func askForHint(completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Подсказка к PIN", message: "Введите подсказку (необязательно)", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Подсказка" }
        alert.addAction(UIAlertAction(title: "Пропустить", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
            completion(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    // MARK: - Animations

    private func shakeAnimation() {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values = [0, -12, 12, -10, 10, -6, 6, 0]
        anim.duration = 0.45
        dotsContainer.layer.add(anim, forKey: "shake")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func playUnlockAnimation(completion: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .thin)
        lockImageView.image = UIImage(systemName: "lock.open.fill", withConfiguration: config)

        UIView.animate(withDuration: 0.4, animations: {
            self.lockImageView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            self.lockImageView.alpha = 0
            self.dotsContainer.alpha = 0
            self.view.alpha = 0
        }) { _ in
            completion()
        }
    }

    private func dismissAnimated() {
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        onDismiss?()
        dismissAnimated()
    }

    // MARK: - Biometric

    private func detectBiometryType() -> LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    private var canUseBiometric: Bool {
        guard LitegramChatLocks.shared.isBiometricEnabled else { return false }
        switch mode {
        case .set: return false
        default: break
        }
        let ctx = LAContext()
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private func attemptBiometric() {
        guard canUseBiometric else { return }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Ввести PIN"
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Разблокировать чат") { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async {
                self?.enteredPin = "__bio__"
                self?.handlePinComplete()
            }
        }
    }
}

// MARK: - PinKeyButton (circular numpad key)

private final class PinKeyButton: UIControl {
    var onTap: ((String) -> Void)?
    private let digit: String
    private let digitLabel = UILabel()
    private let lettersLabel = UILabel()
    private let circleLayer = CAShapeLayer()

    init(digit: String, letters: String, size: CGFloat) {
        self.digit = digit
        super.init(frame: .zero)

        let r = size / 2
        circleLayer.path = UIBezierPath(arcCenter: CGPoint(x: r, y: r), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        circleLayer.fillColor = UIColor(white: 1.0, alpha: 0.12).cgColor
        layer.addSublayer(circleLayer)

        digitLabel.text = digit
        digitLabel.font = .systemFont(ofSize: 36, weight: .thin)
        digitLabel.textColor = .white
        digitLabel.textAlignment = .center
        addSubview(digitLabel)

        if !letters.trimmingCharacters(in: .whitespaces).isEmpty {
            lettersLabel.text = letters
            lettersLabel.font = .systemFont(ofSize: 9, weight: .medium)
            lettersLabel.textColor = .white
            lettersLabel.textAlignment = .center
            lettersLabel.tracking = 2.0
            addSubview(lettersLabel)
        }

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        circleLayer.frame = bounds
        let r = bounds.width / 2
        circleLayer.path = UIBezierPath(arcCenter: CGPoint(x: r, y: r), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

        if lettersLabel.superview != nil {
            digitLabel.frame = CGRect(x: 0, y: bounds.height * 0.18, width: bounds.width, height: bounds.height * 0.46)
            lettersLabel.frame = CGRect(x: 0, y: digitLabel.frame.maxY - 2, width: bounds.width, height: 14)
        } else {
            digitLabel.frame = CGRect(x: 0, y: bounds.height * 0.22, width: bounds.width, height: bounds.height * 0.56)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.circleLayer.fillColor = self.isHighlighted
                    ? UIColor(white: 1.0, alpha: 0.35).cgColor
                    : UIColor(white: 1.0, alpha: 0.12).cgColor
            }
        }
    }

    @objc private func handleTap() {
        onTap?(digit)
    }
}

private extension UILabel {
    var tracking: CGFloat {
        get { return 0 }
        set {
            guard let text = self.text else { return }
            let attr = NSMutableAttributedString(string: text)
            attr.addAttribute(.kern, value: newValue, range: NSRange(location: 0, length: text.count))
            if let font = self.font {
                attr.addAttribute(.font, value: font, range: NSRange(location: 0, length: text.count))
            }
            if let color = self.textColor {
                attr.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.count))
            }
            self.attributedText = attr
        }
    }
}
