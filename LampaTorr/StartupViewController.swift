import UIKit

final class StartupViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        startServer()
    }

    private func configureUI() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Запуск встроенного TorrServer…"
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Повторить", for: .normal)
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        view.addSubview(spinner)
        view.addSubview(statusLabel)
        view.addSubview(retryButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            retryButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func retryTapped() {
        retryButton.isHidden = true
        spinner.startAnimating()
        startServer()
    }

    private func startServer() {
        statusLabel.text = "Запуск встроенного TorrServer…"

        TorrServerManager.shared.start { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                self.showLampa()
            case .failure(let error):
                self.spinner.stopAnimating()
                self.statusLabel.text = error.localizedDescription
                self.retryButton.isHidden = false
            }
        }
    }

    private func showLampa() {
        guard let window = view.window else { return }

        UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
            window.rootViewController = LampaViewController()
        }
    }
}
