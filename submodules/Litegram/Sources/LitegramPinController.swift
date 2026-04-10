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
    private var dotViews: [UIView] = []
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var numpadButtons: [UIButton] = []
    private let backButton = UIButton(type: .system)
    private var biometricButton: UIButton?
    private let hintButton = UIButton(type: .system)

    private static let accentColor = UIColor(red: 0.67, green: 0.49, blue: 1.0, alpha: 1.0)
    private static let accentDimColor = UIColor(red: 0.48, green: 0.37, blue: 0.65, alpha: 1.0)

    public init(mode: Mode, onPinSet: OnPinSet? = nil, onPinVerified: OnPinVerified? = nil, onDismiss: OnDismiss? = nil) {
        self.mode = mode
        self.onPinSet = onPinSet
        self.onPinVerified = onPinVerified
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateTitle()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .verify = mode {
            attemptBiometric()
        } else if case .verifyFolder = mode {
            attemptBiometric()
        } else if case .verifyGroup = mode {
            attemptBiometric()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
        layoutElements()
    }

    // MARK: - UI Setup

    private func setupUI() {
        gradientLayer.colors = [Self.accentDimColor.cgColor, Self.accentColor.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)

        let lockConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        lockImageView.image = UIImage(systemName: "lock.fill", withConfiguration: lockConfig)
        lockImageView.tintColor = .white
        lockImageView.contentMode = .scaleAspectFit
        view.addSubview(lockImageView)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textAlignment = .center
        view.addSubview(subtitleLabel)

        for _ in 0..<4 {
            let dot = UIView()
            dot.layer.cornerRadius = 7
            dot.layer.borderWidth = 2
            dot.layer.borderColor = UIColor.white.cgColor
            dot.backgroundColor = .clear
            view.addSubview(dot)
            dotViews.append(dot)
        }

        for i in 0..<12 {
            let btn = UIButton(type: .system)
            btn.titleLabel?.font = .systemFont(ofSize: 32, weight: .light)
            btn.setTitleColor(.white, for: .normal)
            btn.tag = i

            if i < 9 {
                btn.setTitle("\(i + 1)", for: .normal)
            } else if i == 9 {
                if canUseBiometric {
                    let bioConfig = UIImage.SymbolConfiguration(pointSize: 24)
                    btn.setImage(UIImage(systemName: "touchid", withConfiguration: bioConfig), for: .normal)
                    btn.tintColor = .white
                    self.biometricButton = btn
                } else {
                    btn.isUserInteractionEnabled = false
                }
            } else if i == 10 {
                btn.setTitle("0", for: .normal)
            } else {
                let delConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                btn.setImage(UIImage(systemName: "delete.left", withConfiguration: delConfig), for: .normal)
                btn.tintColor = .white
            }

            btn.addTarget(self, action: #selector(numpadTapped(_:)), for: .touchUpInside)
            view.addSubview(btn)
            numpadButtons.append(btn)
        }

        backButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(backButton)

        hintButton.setTitle("Подсказка", for: .normal)
        hintButton.setTitleColor(UIColor.white.withAlphaComponent(0.7), for: .normal)
        hintButton.titleLabel?.font = .systemFont(ofSize: 14)
        hintButton.addTarget(self, action: #selector(hintTapped), for: .touchUpInside)
        hintButton.isHidden = true
        view.addSubview(hintButton)

        if case .verify(let dialogId) = mode, LitegramChatLocks.shared.getHint(dialogId) != nil {
            hintButton.isHidden = false
        } else if case .verifyFolder(let filterId) = mode, LitegramChatLocks.shared.getFolderHint(filterId) != nil {
            hintButton.isHidden = false
        } else if case .verifyGroup(let groupId) = mode, LitegramChatLocks.shared.getGroupHint(groupId) != nil {
            hintButton.isHidden = false
        }
    }

    private func layoutElements() {
        let w = view.bounds.width
        let safeTop = view.safeAreaInsets.top

        backButton.frame = CGRect(x: 16, y: safeTop + 12, width: 44, height: 44)

        let centerY = view.bounds.height * 0.28

        lockImageView.frame = CGRect(x: (w - 50) / 2, y: centerY - 60, width: 50, height: 50)
        titleLabel.frame = CGRect(x: 20, y: lockImageView.frame.maxY + 16, width: w - 40, height: 28)
        subtitleLabel.frame = CGRect(x: 20, y: titleLabel.frame.maxY + 4, width: w - 40, height: 20)

        let dotSize: CGFloat = 14
        let dotSpacing: CGFloat = 24
        let totalDotsWidth = dotSize * 4 + dotSpacing * 3
        let dotsStartX = (w - totalDotsWidth) / 2
        let dotsY = subtitleLabel.frame.maxY + 28

        for (i, dot) in dotViews.enumerated() {
            dot.frame = CGRect(x: dotsStartX + CGFloat(i) * (dotSize + dotSpacing), y: dotsY, width: dotSize, height: dotSize)
        }

        let numpadTop = dotsY + dotSize + 40
        let btnSize: CGFloat = 70
        let hSpacing: CGFloat = 28
        let vSpacing: CGFloat = 14
        let totalWidth = btnSize * 3 + hSpacing * 2
        let startX = (w - totalWidth) / 2

        for (i, btn) in numpadButtons.enumerated() {
            let row = i / 3
            let col = i % 3
            let x = startX + CGFloat(col) * (btnSize + hSpacing)
            let y = numpadTop + CGFloat(row) * (btnSize + vSpacing)
            btn.frame = CGRect(x: x, y: y, width: btnSize, height: btnSize)
            btn.layer.cornerRadius = btnSize / 2
        }

        hintButton.frame = CGRect(x: (w - 120) / 2, y: numpadTop + 4 * (btnSize + vSpacing) + 8, width: 120, height: 30)
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
            subtitleLabel.text = "Чат защищён PIN-кодом"
        }
    }

    // MARK: - Dots

    private func updateDots() {
        for (i, dot) in dotViews.enumerated() {
            UIView.animate(withDuration: 0.15) {
                dot.backgroundColor = i < self.enteredPin.count ? .white : .clear
            }
            if i == enteredPin.count - 1 && !enteredPin.isEmpty {
                dot.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: [], animations: {
                    dot.transform = .identity
                })
            }
        }
    }

    // MARK: - Numpad

    @objc private func numpadTapped(_ sender: UIButton) {
        let tag = sender.tag
        if tag == 11 {
            guard !enteredPin.isEmpty else { return }
            enteredPin.removeLast()
            updateDots()
            return
        }
        if tag == 9 {
            if sender === biometricButton {
                attemptBiometric()
            }
            return
        }
        let digit: String
        if tag == 10 {
            digit = "0"
        } else {
            digit = "\(tag + 1)"
        }

        guard enteredPin.count < 4 else { return }
        enteredPin.append(digit)
        updateDots()

        if enteredPin.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.handlePinComplete()
            }
        }
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
                    isConfirmStep = false
                    firstPin = nil
                    enteredPin = ""
                    updateDots()
                    updateTitle()
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
                shakeAnimation()
                enteredPin = ""
                updateDots()
            }

        case .verifyFolder(let filterId):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkFolderPin(filterId, pin: enteredPin) {
                playUnlockAnimation {
                    LitegramChatLocks.shared.markFolderUnlocked(filterId)
                    self.onPinVerified?()
                    self.dismissAnimated()
                }
            } else {
                shakeAnimation()
                enteredPin = ""
                updateDots()
            }

        case .verifyGroup(let groupId):
            if enteredPin == "__bio__" || LitegramChatLocks.shared.checkGroupPin(groupId, pin: enteredPin) {
                playUnlockAnimation {
                    self.onPinVerified?()
                    self.dismissAnimated()
                }
            } else {
                shakeAnimation()
                enteredPin = ""
                updateDots()
            }
        }
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
        default:
            break
        }
        guard let hint = hintText else { return }

        let toast = UILabel()
        toast.text = hint
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 16
        toast.clipsToBounds = true
        let size = toast.sizeThatFits(CGSize(width: view.bounds.width - 80, height: 40))
        toast.frame = CGRect(x: (view.bounds.width - size.width - 32) / 2, y: view.safeAreaInsets.top + 60, width: size.width + 32, height: 36)
        view.addSubview(toast)

        UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
            toast.alpha = 0
        }) { _ in
            toast.removeFromSuperview()
        }
    }

    private func askForHint(completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Подсказка к PIN", message: "Введите подсказку (необязательно)", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Подсказка"
        }
        alert.addAction(UIAlertAction(title: "Пропустить", style: .cancel) { _ in
            completion(nil)
        })
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
            completion(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    // MARK: - Animations

    private func shakeAnimation() {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values = [0, -10, 10, -8, 8, -4, 4, 0]
        anim.duration = 0.4
        for dot in dotViews {
            dot.layer.add(anim, forKey: "shake")
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    private func playUnlockAnimation(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.3, animations: {
            self.lockImageView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            self.lockImageView.alpha = 0
            for dot in self.dotViews {
                dot.alpha = 0
            }
        }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                completion()
            }
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

    private var canUseBiometric: Bool {
        guard LitegramChatLocks.shared.isBiometricEnabled else { return false }
        switch mode {
        case .set:
            return false
        default:
            break
        }
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private func attemptBiometric() {
        guard canUseBiometric else { return }
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Разблокировать чат") { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async {
                self?.enteredPin = "__bio__"
                self?.handlePinComplete()
            }
        }
    }
}
